from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from tirosh_vitalserver.devtools.application.inputs import NginxBundleInput
from tirosh_vitalserver.devtools.core.host_proxy import NginxBundleConfig


def run_nginx_bundle(input: NginxBundleInput, config: NginxBundleConfig) -> int:
    expected_version = input.expected_version or config.expected_version
    binary = resolve_bundle_binary(
        input_binary=input.binary,
        config=config,
        expected_version=expected_version,
    )
    dylib_prefixes = config.non_system_dylib_prefixes
    bundle_dir = input.bundle_dir

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

    source_dylibs = non_system_dylibs(binary, dylib_prefixes)
    for dylib in source_dylibs:
        destination = bundle_lib / dylib.name
        shutil.copy2(dylib, destination)
        destination.chmod(0o644)

    rewrite_load_paths(
        bundled_nginx=bundled_nginx,
        bundle_lib=bundle_lib,
        source_dylibs=source_dylibs,
        dylib_prefixes=dylib_prefixes,
    )
    sign_bundle(bundled_nginx, bundle_lib)

    print("nginx bundle is ready:")
    print(f"  {bundle_dir}")
    print(otool_load_paths(bundled_nginx), end="")
    return 0


def resolve_bundle_binary(
    *,
    input_binary: str | None,
    config: NginxBundleConfig,
    expected_version: str | None,
) -> Path:
    if input_binary:
        return resolve_binary(input_binary)
    if not expected_version or not config.source_binary_path:
        return resolve_binary(config.binary_path)

    binary = resolve_cached_binary(config.binary_path)
    if binary and version_matches(binary, expected_version):
        return binary

    source = resolve_binary(config.source_binary_path)
    validate_version(source, expected_version)
    config.binary_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, config.binary_path)
    config.binary_path.chmod(0o755)
    print(
        "refreshed nginx artifact cache: "
        f"{config.binary_path} ({expected_version})"
    )
    return config.binary_path.resolve()


def resolve_cached_binary(value: str | Path | None) -> Path | None:
    if value is None or value == "":
        return None
    path = Path(value).expanduser()
    if path.is_file() and path.stat().st_mode & 0o111:
        return path.resolve()
    return None


def resolve_binary(value: str | Path | None) -> Path:
    if value is None or value == "":
        raise SystemExit(
            "error: missing nginx binary path in "
            "[macos.host_proxy.nginx].binary_path"
        )
    path = Path(value).expanduser()
    if path.is_file() and path.stat().st_mode & 0o111:
        return path.resolve()
    resolved = shutil.which(value)
    if resolved:
        return Path(resolved).resolve()
    raise SystemExit(f"error: nginx binary not found: {value}")


def version_matches(binary: Path, expected_version: str) -> bool:
    return expected_version in nginx_version_text(binary)


def validate_version(binary: Path, expected_version: str) -> None:
    version_text = nginx_version_text(binary)
    if expected_version not in version_text:
        raise SystemExit(
            "error: nginx version mismatch: "
            f"expected {expected_version!r}, got {version_text!r}"
        )


def nginx_version_text(binary: Path) -> str:
    result = subprocess.run(
        [str(binary), "-v"],
        check=False,
        text=True,
        capture_output=True,
    )
    return f"{result.stdout}{result.stderr}".strip()


def non_system_dylibs(binary: Path, prefixes: tuple[str, ...]) -> list[Path]:
    dylibs = []
    for line in otool_load_paths(binary).splitlines()[1:]:
        path = line.strip().split(maxsplit=1)[0]
        if path.startswith(prefixes):
            dylibs.append(Path(path))
    return sorted(set(dylibs))


def otool_load_paths(binary: Path) -> str:
    return subprocess.check_output(["otool", "-L", str(binary)], text=True)


def rewrite_load_paths(
    *,
    bundled_nginx: Path,
    bundle_lib: Path,
    source_dylibs: list[Path],
    dylib_prefixes: tuple[str, ...],
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

        for nested in non_system_dylibs(bundled_dylib, dylib_prefixes):
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
