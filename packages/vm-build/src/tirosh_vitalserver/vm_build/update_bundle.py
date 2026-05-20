from __future__ import annotations

import hashlib
import json
import shutil
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
    bundle_dir = output_dir / f"update-bundle-{args.version}"

    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True)
    (bundle_dir / "migrations").mkdir()

    artifacts = [
        ArtifactInput(args.rootfs_base, "rootfs-base.raw.gz", "rootfs-base"),
    ]

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
        "product": "TiroshVitalServer",
        "version": args.version,
        "runtimeVersion": args.runtime_version,
        "createdAt": datetime.now(UTC).replace(microsecond=0).isoformat(),
        "artifacts": artifact_entries,
        "migrations": migration_entries,
    }

    (bundle_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (bundle_dir / "checksums.txt").write_text("".join(checksum_lines), encoding="utf-8")
    (bundle_dir / "signature").write_text(
        "unsigned\n",
        encoding="utf-8",
    )

    print(f"update bundle is ready: {bundle_dir}")
    return 0


def run_verify_update_bundle(args: Any) -> int:
    bundle_dir = args.bundle_dir
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

    print(f"update bundle verified: {bundle_dir}")
    return 0


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


def validate_manifest(manifest: dict[str, Any]) -> None:
    required = {
        "schemaVersion": int,
        "product": str,
        "version": str,
        "runtimeVersion": str,
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
    if manifest["product"] != "TiroshVitalServer":
        raise SystemExit(f"unsupported product: {manifest['product']}")

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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
