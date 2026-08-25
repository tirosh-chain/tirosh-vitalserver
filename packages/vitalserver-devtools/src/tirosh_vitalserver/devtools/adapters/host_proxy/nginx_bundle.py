from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.application.inputs import NginxBundleInput
from tirosh_vitalserver.devtools.core.host_proxy import NginxBundleConfig


@dataclass(frozen=True)
class NginxDylibDependency:
    load_path: str
    source: Path


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
        destination = bundle_lib / dylib.source.name
        shutil.copy2(dylib.source, destination)
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
    print(f"refreshed nginx artifact cache: {config.binary_path} ({expected_version})")
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
            "error: missing nginx binary path in [macos.host_proxy.nginx].binary_path"
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


def non_system_dylibs(
    binary: Path,
    prefixes: tuple[str, ...],
) -> list[NginxDylibDependency]:
    dylibs: list[NginxDylibDependency] = []
    for line in otool_load_paths(binary).splitlines()[1:]:
        load_path = line.strip().split(maxsplit=1)[0]
        source = resolve_dylib_source(
            binary=binary,
            load_path=load_path,
            prefixes=prefixes,
        )
        if source is not None:
            dylibs.append(NginxDylibDependency(load_path=load_path, source=source))
    return sorted(
        set(dylibs),
        key=lambda dylib: (dylib.load_path, str(dylib.source)),
    )


def resolve_dylib_source(
    *,
    binary: Path,
    load_path: str,
    prefixes: tuple[str, ...],
) -> Path | None:
    if load_path.startswith(prefixes):
        return Path(load_path)
    executable_prefix = "@executable_path/"
    if not load_path.startswith(executable_prefix):
        return None
    source = (binary.parent / load_path.removeprefix(executable_prefix)).resolve()
    expected_lib = (binary.parent.parent / "lib").resolve()
    if source.parent != expected_lib:
        raise SystemExit(
            "error: nginx bundled dylib escapes sibling lib directory: "
            f"binary={binary} loadPath={load_path} resolved={source}"
        )
    if not source.is_file():
        raise SystemExit(
            "error: nginx bundled dylib is missing: "
            f"binary={binary} loadPath={load_path} resolved={source}"
        )
    return source


def otool_load_paths(binary: Path) -> str:
    return subprocess.check_output(["otool", "-L", str(binary)], text=True)


def rewrite_load_paths(
    *,
    bundled_nginx: Path,
    bundle_lib: Path,
    source_dylibs: list[NginxDylibDependency],
    dylib_prefixes: tuple[str, ...],
) -> None:
    for dylib in source_dylibs:
        name = dylib.source.name
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
                dylib.load_path,
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
                    nested.load_path,
                    f"@executable_path/../lib/{nested.source.name}",
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
