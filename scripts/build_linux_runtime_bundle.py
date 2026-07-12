#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import shutil
import struct
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "apps/vitalserver-platform-agent/packaging/linux"
GUEST_TOOLS_RUNTIME_INSTALLER = (
    ROOT / "apps/vitalserver-macos-runtime/Support/Guest/install-guest-tools-runtime.py"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a deterministic offline Linux Runtime v2 bundle."
    )
    parser.add_argument("--platform-version", required=True)
    parser.add_argument("--runtime-bundle-version", required=True)
    parser.add_argument("--agent-binary", type=Path, required=True)
    parser.add_argument("--provider-binary", type=Path, required=True)
    parser.add_argument("--runtime-controller-wheelhouse", type=Path, required=True)
    parser.add_argument("--pwa-directory", type=Path, required=True)
    parser.add_argument("--runtime-bundle-directory", type=Path, required=True)
    parser.add_argument("--images-archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    _validate_version(args.platform_version, "platform version")
    _validate_version(args.runtime_bundle_version, "Runtime Bundle version")
    _require_linux_amd64_elf(args.agent_binary, "Platform Agent")
    _require_linux_amd64_elf(args.provider_binary, "Native Runtime Provider")
    _require_control_wheelhouse(args.runtime_controller_wheelhouse)
    _require_file(GUEST_TOOLS_RUNTIME_INSTALLER, "Guest Tools runtime installer")
    _require_file(args.pwa_directory / "index.html", "PWA index")
    _require_file(args.runtime_bundle_directory / "compose.yaml", "Runtime Compose")
    _require_docker_image_archive(args.images_archive)
    _require_tree_without_symlinks(args.pwa_directory, "PWA")
    _require_tree_without_symlinks(args.runtime_bundle_directory, "Runtime Bundle")
    _require_tree_without_symlinks(
        args.runtime_controller_wheelhouse,
        "Runtime Controller wheelhouse",
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".vitalserver-linux-bundle-", dir=args.output.parent
    ) as temporary:
        stage = Path(temporary) / "VitalServer-Linux"
        (stage / "bin").mkdir(parents=True)
        (stage / "images").mkdir()
        (stage / "packaging").mkdir()
        shutil.copy2(args.agent_binary, stage / "bin/vitalserver-platform-agent")
        shutil.copy2(args.provider_binary, stage / "bin/vitalserver-runtime-provider")
        runtime_controller = stage / "runtime-controller"
        runtime_controller.mkdir()
        shutil.copytree(
            args.runtime_controller_wheelhouse,
            runtime_controller / "python-wheels",
        )
        shutil.copy2(
            GUEST_TOOLS_RUNTIME_INSTALLER,
            runtime_controller / "install-guest-tools-runtime.py",
        )
        shutil.copytree(args.pwa_directory, stage / "pwa")
        shutil.copytree(args.runtime_bundle_directory, stage / "runtime-bundle")
        shutil.copy2(args.images_archive, stage / "images/runtime-images.tar")
        for name in (
            "runtime.env",
            "runtime-controller.toml",
            "runtime-settings.json",
            "redis-relay.toml",
            "migrate-runtime-env.py",
            "vitalserver-platform-agent.service",
            "vitalserver-runtime-controller.service",
            "vitalserver-runtime-provider.service",
            "acceptance-linux.py",
            "acceptance-reboot-linux.py",
            "acceptance-update-rollback-linux.py",
            "acceptance-uninstall-reinstall-linux.py",
            "rollback-linux.sh",
            "rollback-linux.py",
            "update-linux.py",
            "uninstall-linux.py",
            "support-export-linux.py",
            "trust-update-linux.py",
        ):
            shutil.copy2(PACKAGING / name, stage / "packaging" / name)
        (stage / "packaging/acceptance-linux.py").chmod(0o755)
        (stage / "packaging/acceptance-reboot-linux.py").chmod(0o755)
        (stage / "packaging/acceptance-update-rollback-linux.py").chmod(0o755)
        (stage / "packaging/acceptance-uninstall-reinstall-linux.py").chmod(0o755)
        (stage / "packaging/rollback-linux.sh").chmod(0o755)
        (stage / "packaging/rollback-linux.py").chmod(0o755)
        (stage / "packaging/update-linux.py").chmod(0o755)
        (stage / "packaging/uninstall-linux.py").chmod(0o755)
        (stage / "packaging/support-export-linux.py").chmod(0o755)
        (stage / "packaging/trust-update-linux.py").chmod(0o755)
        shutil.copy2(PACKAGING / "install.sh", stage / "install.sh")
        (stage / "install.sh").chmod(0o755)
        (stage / "VERSION").write_text(args.platform_version + "\n", encoding="utf-8")
        (stage / "RUNTIME_BUNDLE_VERSION").write_text(
            args.runtime_bundle_version + "\n", encoding="utf-8"
        )

        release = {
            "schemaVersion": 1,
            "platformVersion": args.platform_version,
            "runtimeBundleVersion": args.runtime_bundle_version,
            "target": {"os": "linux", "architecture": "amd64"},
            "inputs": {
                "platformAgentSHA256": _sha256(args.agent_binary),
                "runtimeProviderSHA256": _sha256(args.provider_binary),
                "runtimeControllerWheelhouseSHA256": _tree_sha256(
                    args.runtime_controller_wheelhouse
                ),
                "runtimeImagesSHA256": _sha256(args.images_archive),
                "pwaTreeSHA256": _tree_sha256(args.pwa_directory),
                "runtimeBundleTreeSHA256": _tree_sha256(args.runtime_bundle_directory),
            },
        }
        (stage / "release.json").write_text(
            json.dumps(release, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        _write_checksums(stage)
        _write_deterministic_tar_gz(stage, args.output)
    print(f"Linux Runtime v2 offline bundle: {args.output}")
    return 0


def _validate_version(value: str, label: str) -> None:
    if not value or any(
        not (character.isalnum() or character in "._+-") for character in value
    ):
        raise SystemExit(f"{label} is invalid: {value!r}")


def _require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise SystemExit(f"{label} is missing: {path}")


def _require_linux_amd64_elf(path: Path, label: str) -> None:
    _require_file(path, label)
    data = path.read_bytes()[:20]
    if len(data) < 20 or data[:4] != b"\x7fELF":
        raise SystemExit(f"{label} is not an ELF executable: {path}")
    if data[4] != 2 or data[5] != 1:
        raise SystemExit(f"{label} must be 64-bit little-endian ELF: {path}")
    machine = struct.unpack("<H", data[18:20])[0]
    if machine != 62:
        raise SystemExit(
            f"{label} must target linux/amd64 machine=62 actual={machine}: {path}"
        )


def _require_docker_image_archive(path: Path) -> None:
    _require_file(path, "Runtime image archive")
    try:
        with tarfile.open(path, "r:*") as archive:
            names = set(archive.getnames())
            if "manifest.json" in names:
                manifest = _read_archive_json(archive, "manifest.json", path)
                if not isinstance(manifest, list) or not manifest:
                    raise SystemExit(
                        "Runtime image archive Docker manifest is empty or invalid: "
                        f"{path}"
                    )
                for image in manifest:
                    if not isinstance(image, dict) or not isinstance(
                        image.get("Config"), str
                    ):
                        raise SystemExit(
                            "Runtime image archive Docker manifest entry is invalid: "
                            f"{path}"
                        )
                    config_name = image["Config"]
                    if config_name not in names:
                        raise SystemExit(
                            "Runtime image archive config is missing: "
                            f"archive={path} config={config_name}"
                        )
                    config = _read_archive_json(archive, config_name, path)
                    _require_linux_amd64_image(
                        config,
                        path,
                        ",".join(image.get("RepoTags") or []) or config_name,
                    )
            elif "index.json" in names:
                index = _read_archive_json(archive, "index.json", path)
                manifests = index.get("manifests") if isinstance(index, dict) else None
                if not isinstance(manifests, list) or not manifests:
                    raise SystemExit(
                        f"Runtime image archive OCI index is empty or invalid: {path}"
                    )
                for descriptor in manifests:
                    if not isinstance(descriptor, dict):
                        raise SystemExit(
                            f"Runtime image archive OCI descriptor is invalid: {path}"
                        )
                    _require_linux_amd64_image(
                        descriptor.get("platform"),
                        path,
                        str(descriptor.get("digest", "unknown")),
                    )
            else:
                raise SystemExit(
                    "Runtime image archive has no Docker manifest.json or OCI "
                    f"index.json: {path}"
                )
    except tarfile.TarError as error:
        raise SystemExit(
            f"Runtime image archive is not a readable tar archive: {path}: {error}"
        ) from error


def _read_archive_json(archive: tarfile.TarFile, name: str, path: Path) -> object:
    source = archive.extractfile(name)
    if source is None:
        raise SystemExit(
            f"Runtime image archive member is unreadable: archive={path} member={name}"
        )
    try:
        return json.load(source)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(
            "Runtime image archive JSON is invalid: "
            f"archive={path} member={name}: {error}"
        ) from error


def _require_linux_amd64_image(config: object, path: Path, identity: str) -> None:
    architecture = config.get("architecture") if isinstance(config, dict) else None
    operating_system = config.get("os") if isinstance(config, dict) else None
    if architecture != "amd64" or operating_system != "linux":
        raise SystemExit(
            "Runtime image must target linux/amd64: "
            f"archive={path} image={identity} os={operating_system!r} "
            f"architecture={architecture!r}"
        )


def _require_tree_without_symlinks(path: Path, label: str) -> None:
    if not path.is_dir():
        raise SystemExit(f"{label} directory is missing: {path}")
    for item in path.rglob("*"):
        if item.is_symlink():
            raise SystemExit(f"{label} contains unsupported symlink: {item}")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(bytes.fromhex(_sha256(path)))
    return digest.hexdigest()


def _write_checksums(stage: Path) -> None:
    lines = []
    for path in sorted(item for item in stage.rglob("*") if item.is_file()):
        relative = path.relative_to(stage).as_posix()
        if relative == "checksums.sha256":
            continue
        lines.append(f"{_sha256(path)}  {relative}")
    (stage / "checksums.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def _require_control_wheelhouse(path: Path) -> None:
    _require_file(path / "manifest.json", "Runtime Controller wheelhouse manifest")
    _require_file(
        path / "linux-amd64/requirements.txt",
        "Runtime Controller linux-amd64 requirements",
    )
    _require_nonempty_wheel_directory(
        path / "guest-tools",
        "Runtime Controller Guest Tools wheel directory",
    )
    _require_nonempty_wheel_directory(
        path / "linux-amd64",
        "Runtime Controller linux-amd64 wheel directory",
    )


def _require_nonempty_wheel_directory(path: Path, label: str) -> None:
    if not path.is_dir():
        raise SystemExit(f"{label} is missing: {path}")
    if not list(path.glob("*.whl")):
        raise SystemExit(f"{label} has no wheels: {path}")


def _write_deterministic_tar_gz(stage: Path, output: Path) -> None:
    temporary = output.with_name(output.name + ".tmp")
    with (
        temporary.open("wb") as raw,
        gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed,
        tarfile.open(
            fileobj=compressed,
            mode="w",
            format=tarfile.PAX_FORMAT,
        ) as archive,
    ):
        for path in [stage, *sorted(stage.rglob("*"))]:
            relative = Path(stage.name) / path.relative_to(stage)
            info = archive.gettarinfo(str(path), arcname=relative.as_posix())
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = 0
            if path.is_file():
                with path.open("rb") as source:
                    archive.addfile(info, source)
            else:
                archive.addfile(info)
    os.replace(temporary, output)


if __name__ == "__main__":
    raise SystemExit(main())
