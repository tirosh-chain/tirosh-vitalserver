from __future__ import annotations

import shutil
import subprocess
from argparse import Namespace
from pathlib import Path

from .config import load_config, section


def run_nginx_bundle(args: Namespace) -> int:
    config = load_config(args.config)
    nginx_config = section(config, "nginx")

    binary = resolve_binary(args.binary or nginx_config.get("binary_path"))
    expected_version = args.expected_version or nginx_config.get("expected_version")
    bundle_dir = args.bundle_dir

    if expected_version:
        validate_version(binary, expected_version)

    bundle_sbin = bundle_dir / "sbin"
    bundle_lib = bundle_dir / "lib"
    bundled_nginx = bundle_sbin / "nginx"

    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)
    bundle_sbin.mkdir(parents=True)
    bundle_lib.mkdir(parents=True)
    (bundle_dir / "logs").mkdir()

    shutil.copy2(binary, bundled_nginx)
    bundled_nginx.chmod(0o755)

    source_dylibs = non_system_dylibs(binary)
    for dylib in source_dylibs:
        destination = bundle_lib / dylib.name
        shutil.copy2(dylib, destination)
        destination.chmod(0o644)

    rewrite_load_paths(
        bundled_nginx=bundled_nginx,
        bundle_lib=bundle_lib,
        source_dylibs=source_dylibs,
    )
    sign_bundle(bundled_nginx, bundle_lib)

    print("nginx bundle is ready:")
    print(f"  {bundle_dir}")
    print(otool_load_paths(bundled_nginx), end="")
    return 0


def resolve_binary(value: object) -> Path:
    if not isinstance(value, str) or not value:
        raise SystemExit("error: missing nginx binary path in [nginx].binary_path")
    path = Path(value).expanduser()
    if path.is_file() and path.stat().st_mode & 0o111:
        return path.resolve()
    resolved = shutil.which(value)
    if resolved:
        return Path(resolved).resolve()
    raise SystemExit(f"error: nginx binary not found: {value}")


def validate_version(binary: Path, expected_version: str) -> None:
    result = subprocess.run(
        [str(binary), "-v"],
        check=False,
        text=True,
        capture_output=True,
    )
    version_text = f"{result.stdout}{result.stderr}".strip()
    if expected_version not in version_text:
        raise SystemExit(
            "error: nginx version mismatch: "
            f"expected {expected_version!r}, got {version_text!r}"
        )


def non_system_dylibs(binary: Path) -> list[Path]:
    dylibs = []
    for line in otool_load_paths(binary).splitlines()[1:]:
        path = line.strip().split(maxsplit=1)[0]
        if path.startswith(("/opt/", "/usr/local/")):
            dylibs.append(Path(path))
    return sorted(set(dylibs))


def otool_load_paths(binary: Path) -> str:
    return subprocess.check_output(["otool", "-L", str(binary)], text=True)


def rewrite_load_paths(
    *,
    bundled_nginx: Path,
    bundle_lib: Path,
    source_dylibs: list[Path],
) -> None:
    for dylib in source_dylibs:
        name = dylib.name
        bundled_dylib = bundle_lib / name
        run(
            [
                "install_name_tool",
                "-id",
                f"@executable_path/../lib/{name}",
                str(bundled_dylib),
            ]
        )
        run(
            [
                "install_name_tool",
                "-change",
                str(dylib),
                f"@executable_path/../lib/{name}",
                str(bundled_nginx),
            ],
            allow_failure=True,
        )

        for nested in non_system_dylibs(bundled_dylib):
            run(
                [
                    "install_name_tool",
                    "-change",
                    str(nested),
                    f"@executable_path/../lib/{nested.name}",
                    str(bundled_dylib),
                ],
                allow_failure=True,
            )


def sign_bundle(bundled_nginx: Path, bundle_lib: Path) -> None:
    run(["codesign", "--force", "--sign", "-", str(bundled_nginx)])
    for dylib in sorted(bundle_lib.glob("*.dylib")):
        run(["codesign", "--force", "--sign", "-", str(dylib)])


def run(command: list[str], *, allow_failure: bool = False) -> None:
    result = subprocess.run(command, check=False, stdout=subprocess.DEVNULL)
    if result.returncode != 0 and not allow_failure:
        raise SystemExit(f"error: command failed: {' '.join(command)}")
