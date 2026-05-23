from __future__ import annotations

import hashlib
import json
import shutil
import tarfile
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ArtifactInput:
    source: Path
    name: str
    kind: str


def run_build_update_bundle(args: Any) -> int:
    output_dir = args.output_dir
    bundle_name = f"update-bundle-{args.version}"
    bundle_archive = output_dir / f"{bundle_name}.tar.gz"
    helper_version = args.helper_version or args.version
    components = component_versions(args.component, helper_version)

    output_dir.mkdir(parents=True, exist_ok=True)
    if bundle_archive.exists():
        bundle_archive.unlink()

    with tempfile.TemporaryDirectory(prefix=f"{bundle_name}-") as staging:
        bundle_dir = Path(staging) / bundle_name
        bundle_dir.mkdir(parents=True)
        (bundle_dir / "migrations").mkdir()

        artifacts = []
        if args.rootfs_base is not None:
            artifacts.append(
                ArtifactInput(args.rootfs_base, "rootfs-base.raw.gz", "rootfs-base")
            )
        optional_artifacts = [
            (args.app_bundle, "app-bundle.tar.gz", "app-bundle"),
            (args.runtime_tools, "runtime-tools.tar.gz", "runtime-tools"),
            (args.nginx_bundle, "nginx-bundle.tar.gz", "nginx-bundle"),
            (args.guest_deploy, "guest-deploy.tar.gz", "guest-deploy"),
        ]
        for source, name, kind in optional_artifacts:
            if source is not None:
                artifacts.append(ArtifactInput(source, name, kind))

        artifact_entries = []
        checksum_lines = []
        for artifact in artifacts:
            if not artifact.source.is_file():
                raise SystemExit(f"missing artifact: {artifact.source}")

            destination = bundle_dir / artifact.name
            shutil.copy2(artifact.source, destination)
            digest = sha256_file(destination)
            size = destination.stat().st_size
            artifact_entries.append(
                {
                    "name": artifact.name,
                    "type": artifact.kind,
                    "sha256": digest,
                    "size": size,
                }
            )
            checksum_lines.append(f"{digest}  {artifact.name}\n")

        migration_entries = []
        seen_migrations: set[str] = set()
        for migration in args.migration:
            if not migration.is_file():
                raise SystemExit(f"missing migration: {migration}")
            if migration.name in seen_migrations:
                raise SystemExit(f"duplicate migration name: {migration.name}")
            if not is_safe_bundle_name(migration.name):
                raise SystemExit(f"invalid migration name: {migration.name}")
            seen_migrations.add(migration.name)

            destination = bundle_dir / "migrations" / migration.name
            shutil.copy2(migration, destination)
            digest = sha256_file(destination)
            size = destination.stat().st_size
            migration_entries.append(
                {
                    "name": migration.name,
                    "sha256": digest,
                    "size": size,
                }
            )
            checksum_lines.append(f"{digest}  migrations/{migration.name}\n")

        manifest = {
            "schemaVersion": 2,
            "product": "com.tirosh.vitalserver",
            "bundleKind": args.bundle_kind,
            "helperVersion": helper_version,
            "targetPlatforms": args.target_platform,
            "components": components,
            "minUpdaterVersion": (
                args.min_updater_version or args.runtime_version or helper_version
            ),
            "requiresGuestActivation": (
                args.requires_guest_activation
                if args.requires_guest_activation is not None
                else args.guest_deploy is not None
            ),
            "requiresTwoPhaseUpdate": args.requires_two_phase_update,
            "createdAt": datetime.now(UTC).replace(microsecond=0).isoformat(),
            "artifacts": artifact_entries,
            "migrations": migration_entries,
        }

        (bundle_dir / "manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (bundle_dir / "checksums.txt").write_text(
            "".join(checksum_lines),
            encoding="utf-8",
        )
        (bundle_dir / "signature").write_text(
            "unsigned\n",
            encoding="utf-8",
        )

        with tarfile.open(bundle_archive, "w:gz") as archive:
            archive.add(bundle_dir, arcname=bundle_name)

    print(f"update bundle is ready: {bundle_archive}")
    return 0


def run_verify_update_bundle(args: Any) -> int:
    with materialized_bundle(args.bundle_path) as bundle_dir:
        verify_bundle_directory(bundle_dir)

    print(f"update bundle verified: {args.bundle_path}")
    return 0


def verify_bundle_directory(bundle_dir: Path) -> None:
    manifest_path = bundle_dir / "manifest.json"
    checksums_path = bundle_dir / "checksums.txt"
    signature_path = bundle_dir / "signature"

    if not manifest_path.is_file():
        raise SystemExit(f"missing manifest: {manifest_path}")
    if not checksums_path.is_file():
        raise SystemExit(f"missing checksums: {checksums_path}")
    if not signature_path.is_file():
        raise SystemExit(f"missing signature placeholder: {signature_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    validate_manifest(manifest)
    checksum_map = load_checksums(checksums_path)

    for artifact in manifest["artifacts"]:
        name = artifact["name"]
        artifact_path = bundle_dir / name
        if not artifact_path.is_file():
            raise SystemExit(f"missing artifact: {artifact_path}")

        verify_entry(
            path=artifact_path,
            checksum_key=name,
            expected_sha256=artifact["sha256"],
            expected_size=artifact["size"],
            checksum_map=checksum_map,
        )

    for migration in manifest["migrations"]:
        name = migration["name"]
        checksum_key = f"migrations/{name}"
        migration_path = bundle_dir / checksum_key
        if not migration_path.is_file():
            raise SystemExit(f"missing migration: {migration_path}")

        verify_entry(
            path=migration_path,
            checksum_key=checksum_key,
            expected_sha256=migration["sha256"],
            expected_size=migration["size"],
            checksum_map=checksum_map,
        )


def verify_entry(
    *,
    path: Path,
    checksum_key: str,
    expected_sha256: str,
    expected_size: int,
    checksum_map: dict[str, str],
) -> None:
    actual_sha256 = sha256_file(path)
    if actual_sha256 != expected_sha256:
        raise SystemExit(
            f"manifest checksum mismatch for {checksum_key}: "
            f"expected {expected_sha256}, got {actual_sha256}"
        )

    checksum_sha256 = checksum_map.get(checksum_key)
    if checksum_sha256 != actual_sha256:
        raise SystemExit(
            f"checksums.txt mismatch for {checksum_key}: "
            f"expected {checksum_sha256}, got {actual_sha256}"
        )

    actual_size = path.stat().st_size
    if actual_size != expected_size:
        raise SystemExit(
            f"size mismatch for {checksum_key}: "
            f"expected {expected_size}, got {actual_size}"
        )


class materialized_bundle:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._temporary: tempfile.TemporaryDirectory[str] | None = None

    def __enter__(self) -> Path:
        if self.path.is_dir():
            return self.path
        if not self.path.is_file():
            raise SystemExit(f"missing update bundle: {self.path}")
        if not is_update_bundle_archive(self.path):
            raise SystemExit(f"update bundle must be a .tar.gz archive: {self.path}")

        self._temporary = tempfile.TemporaryDirectory(prefix="update-bundle-verify-")
        temporary = Path(self._temporary.name)
        with tarfile.open(self.path, "r:gz") as archive:
            root_name = validated_archive_root(archive)
            archive.extractall(temporary)
        return temporary / root_name

    def __exit__(self, *args: object) -> None:
        if self._temporary is not None:
            self._temporary.cleanup()


def validated_archive_root(archive: tarfile.TarFile) -> str:
    root_name: str | None = None
    members = archive.getmembers()
    if not members:
        raise SystemExit("empty update bundle archive")
    for member in members:
        name = member.name
        if member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsafe archive entry type: {name}")
        if name.startswith("/") or "\\" in name:
            raise SystemExit(f"unsafe archive path: {name}")
        parts = [part for part in Path(name).parts if part not in {"", "."}]
        if not parts or any(part == ".." for part in parts):
            raise SystemExit(f"unsafe archive path: {name}")
        if root_name is None:
            root_name = parts[0]
        elif root_name != parts[0]:
            raise SystemExit(
                "update bundle archive must contain a single root directory"
            )
    if root_name is None:
        raise SystemExit("empty update bundle archive")
    return root_name


def is_update_bundle_archive(path: Path) -> bool:
    name = path.name
    return name.endswith(".tar.gz") or name.endswith(".tgz")


def validate_manifest(manifest: dict[str, Any]) -> None:
    required = {
        "schemaVersion": int,
        "product": str,
        "bundleKind": str,
        "helperVersion": str,
        "targetPlatforms": list,
        "components": dict,
        "minUpdaterVersion": str,
        "requiresGuestActivation": bool,
        "requiresTwoPhaseUpdate": bool,
        "createdAt": str,
        "artifacts": list,
        "migrations": list,
    }
    for key, expected_type in required.items():
        if key not in manifest:
            raise SystemExit(f"manifest missing key: {key}")
        if not isinstance(manifest[key], expected_type):
            raise SystemExit(f"manifest key has wrong type: {key}")

    if manifest["schemaVersion"] != 2:
        raise SystemExit(f"unsupported schemaVersion: {manifest['schemaVersion']}")
    if manifest["product"] != "com.tirosh.vitalserver":
        raise SystemExit(f"unsupported product: {manifest['product']}")
    if manifest["bundleKind"] not in {"product-update", "vm-image-update"}:
        raise SystemExit(f"unsupported bundleKind: {manifest['bundleKind']}")
    for platform in manifest["targetPlatforms"]:
        if not isinstance(platform, str) or not platform:
            raise SystemExit("targetPlatforms entries must be non-empty strings")
    for key, value in manifest["components"].items():
        if not isinstance(key, str) or not key:
            raise SystemExit("components keys must be non-empty strings")
        if not isinstance(value, str) or not value:
            raise SystemExit(f"component version must be a non-empty string: {key}")

    for artifact in manifest["artifacts"]:
        if not isinstance(artifact, dict):
            raise SystemExit("artifact entry must be an object")
        for key in ("name", "type", "sha256", "size"):
            if key not in artifact:
                raise SystemExit(f"artifact missing key: {key}")
        if not isinstance(artifact["name"], str) or not is_safe_bundle_name(
            artifact["name"]
        ):
            raise SystemExit(f"invalid artifact name: {artifact['name']}")
        if not isinstance(artifact["type"], str):
            raise SystemExit(f"invalid artifact type for {artifact['name']}")
        if not isinstance(artifact["sha256"], str) or len(artifact["sha256"]) != 64:
            raise SystemExit(f"invalid sha256 for {artifact['name']}")
        if not isinstance(artifact["size"], int) or artifact["size"] < 0:
            raise SystemExit(f"invalid size for {artifact['name']}")

    for migration in manifest["migrations"]:
        if not isinstance(migration, dict):
            raise SystemExit("migration entry must be an object")
        for key in ("name", "sha256", "size"):
            if key not in migration:
                raise SystemExit(f"migration missing key: {key}")
        if not isinstance(migration["name"], str) or not is_safe_bundle_name(
            migration["name"]
        ):
            raise SystemExit(f"invalid migration name: {migration['name']}")
        if not isinstance(migration["sha256"], str) or len(migration["sha256"]) != 64:
            raise SystemExit(f"invalid sha256 for migration {migration['name']}")
        if not isinstance(migration["size"], int) or migration["size"] < 0:
            raise SystemExit(f"invalid size for migration {migration['name']}")


def load_checksums(path: Path) -> dict[str, str]:
    checksums: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, name = line.split(maxsplit=1)
        checksums[name] = digest
    return checksums


def is_safe_bundle_name(name: str) -> bool:
    path = Path(name)
    return name not in {"", ".", ".."} and path.name == name


def component_versions(entries: list[str], helper_version: str) -> dict[str, str]:
    components = {
        "helperUI": helper_version,
        "updater": helper_version,
        "supervisor": helper_version,
        "vmDriver": helper_version,
    }
    for entry in entries:
        if "=" not in entry:
            raise SystemExit(f"component must be key=value: {entry}")
        key, value = entry.split("=", 1)
        if not key or not value:
            raise SystemExit(f"component must be key=value: {entry}")
        components[key] = value
    return components


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
