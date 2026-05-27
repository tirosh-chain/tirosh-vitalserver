from __future__ import annotations

import hashlib
import json
import shutil
import tarfile
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from tirosh_vitalserver.devtools.core.update_bundle import (
    build_manifest,
    is_safe_bundle_name,
    is_update_bundle_archive,
    resolve_bundle_name,
    validate_manifest,
    validated_archive_root,
)
from tirosh_vitalserver.devtools.core.update_bundle_models import (
    ArchiveMember,
    ArtifactInput,
    BuildUpdateBundleInput,
    BuildUpdateBundleResult,
)


def build_bundle(spec: BuildUpdateBundleInput) -> BuildUpdateBundleResult:
    output_dir = spec.output_dir
    bundle_name = resolve_bundle_name(spec)
    bundle_archive = output_dir / f"{bundle_name}.tar.gz"

    output_dir.mkdir(parents=True, exist_ok=True)
    if bundle_archive.exists():
        bundle_archive.unlink()

    with tempfile.TemporaryDirectory(prefix=f"{bundle_name}-") as staging:
        bundle_dir = Path(staging) / bundle_name
        bundle_dir.mkdir(parents=True)
        (bundle_dir / "migrations").mkdir()

        artifacts: list[ArtifactInput] = []
        artifact_entries = []
        checksum_lines = []
        if spec.rootfs_base is not None:
            artifacts.append(
                ArtifactInput(spec.rootfs_base, "rootfs-base.raw.gz", "rootfs-base")
            )
        optional_artifacts = [
            (spec.app_bundle, "app-bundle.tar.gz", "app-bundle"),
            (spec.runtime_tools, "runtime-tools.tar.gz", "runtime-tools"),
            (spec.nginx_bundle, "nginx-bundle.tar.gz", "nginx-bundle"),
            (spec.guest_deploy, "guest-deploy.tar.gz", "guest-deploy"),
        ]
        for source, name, kind in optional_artifacts:
            if source is not None:
                artifacts.append(ArtifactInput(source, name, kind))

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
        for migration in spec.migration:
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

        manifest = build_manifest(
            spec=spec,
            artifact_entries=artifact_entries,
            migration_entries=migration_entries,
            created_at=datetime.now(UTC),
        )

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

    return BuildUpdateBundleResult(archive=bundle_archive)


def verify_bundle(bundle_path: Path) -> None:
    with materialized_bundle(bundle_path) as bundle_dir:
        verify_bundle_directory(bundle_dir)


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
            root_name = validated_archive_root(
                [
                    ArchiveMember(
                        name=member.name,
                        is_file=member.isfile(),
                        is_dir=member.isdir(),
                        is_symlink=member.issym(),
                        is_hardlink=member.islnk(),
                    )
                    for member in archive.getmembers()
                ]
            )
            archive.extractall(temporary)
        return temporary / root_name

    def __exit__(self, *args: object) -> None:
        if self._temporary is not None:
            self._temporary.cleanup()


def load_checksums(path: Path) -> dict[str, str]:
    checksums: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, name = line.split(maxsplit=1)
        checksums[name] = digest
    return checksums


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
