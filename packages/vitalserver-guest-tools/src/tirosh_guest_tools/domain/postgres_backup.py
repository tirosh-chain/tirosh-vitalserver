from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

POSTGRES_BACKUP_SCHEMA_VERSION = 1
POSTGRES_BACKUP_DATABASE_NAME = "vitalserver"
POSTGRES_BACKUP_DUMP_FORMAT = "custom"
POSTGRES_BACKUP_DUMP_FILE = "database.dump"
POSTGRES_BACKUP_MANIFEST_FILE = "manifest.json"
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class PostgresBackupManifestContractError(ValueError):
    def __init__(self, errors: tuple[str, ...]) -> None:
        super().__init__("; ".join(errors))
        self.errors = errors


@dataclass(frozen=True)
class PostgresBackupManifest:
    schema_version: int
    database_name: str
    created_at: str
    server_version: str
    dump_format: str
    dump_file: str
    dump_sha256: str
    dump_size_bytes: int
    alembic_revision: str

    def as_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "databaseName": self.database_name,
            "createdAt": self.created_at,
            "serverVersion": self.server_version,
            "dumpFormat": self.dump_format,
            "dumpFile": self.dump_file,
            "dumpSha256": self.dump_sha256,
            "dumpSizeBytes": self.dump_size_bytes,
            "alembicRevision": self.alembic_revision,
        }


def validated_postgres_backup_manifest(
    document: dict[str, Any],
) -> PostgresBackupManifest:
    errors: list[str] = []
    schema_version = _integer(document, "schemaVersion", errors)
    database_name = _string(document, "databaseName", errors)
    created_at = _string(document, "createdAt", errors)
    server_version = _string(document, "serverVersion", errors)
    dump_format = _string(document, "dumpFormat", errors)
    dump_file = _string(document, "dumpFile", errors)
    dump_sha256 = _string(document, "dumpSha256", errors)
    dump_size_bytes = _integer(document, "dumpSizeBytes", errors)
    alembic_revision = _string(document, "alembicRevision", errors)

    if schema_version is not None and schema_version != POSTGRES_BACKUP_SCHEMA_VERSION:
        errors.append(
            "schemaVersion is unsupported: "
            f"expected={POSTGRES_BACKUP_SCHEMA_VERSION} actual={schema_version}"
        )
    if database_name is not None and database_name != POSTGRES_BACKUP_DATABASE_NAME:
        errors.append(
            "databaseName is unsupported: "
            f"expected={POSTGRES_BACKUP_DATABASE_NAME} actual={database_name}"
        )
    if dump_format is not None and dump_format != POSTGRES_BACKUP_DUMP_FORMAT:
        errors.append(
            "dumpFormat is unsupported: "
            f"expected={POSTGRES_BACKUP_DUMP_FORMAT} actual={dump_format}"
        )
    if dump_file is not None and dump_file != POSTGRES_BACKUP_DUMP_FILE:
        errors.append(
            "dumpFile is unsupported: "
            f"expected={POSTGRES_BACKUP_DUMP_FILE} actual={dump_file}"
        )
    if dump_sha256 is not None and SHA256_PATTERN.fullmatch(dump_sha256) is None:
        errors.append("dumpSha256 must be a lowercase SHA-256 digest")
    if dump_size_bytes is not None and dump_size_bytes <= 0:
        errors.append("dumpSizeBytes must be greater than zero")

    if errors:
        raise PostgresBackupManifestContractError(tuple(errors))

    assert schema_version is not None
    assert database_name is not None
    assert created_at is not None
    assert server_version is not None
    assert dump_format is not None
    assert dump_file is not None
    assert dump_sha256 is not None
    assert dump_size_bytes is not None
    assert alembic_revision is not None
    return PostgresBackupManifest(
        schema_version=schema_version,
        database_name=database_name,
        created_at=created_at,
        server_version=server_version,
        dump_format=dump_format,
        dump_file=dump_file,
        dump_sha256=dump_sha256,
        dump_size_bytes=dump_size_bytes,
        alembic_revision=alembic_revision,
    )


def new_postgres_backup_manifest(
    *,
    created_at: str,
    server_version: str,
    dump_sha256: str,
    dump_size_bytes: int,
    alembic_revision: str,
) -> PostgresBackupManifest:
    return validated_postgres_backup_manifest(
        {
            "schemaVersion": POSTGRES_BACKUP_SCHEMA_VERSION,
            "databaseName": POSTGRES_BACKUP_DATABASE_NAME,
            "createdAt": created_at,
            "serverVersion": server_version,
            "dumpFormat": POSTGRES_BACKUP_DUMP_FORMAT,
            "dumpFile": POSTGRES_BACKUP_DUMP_FILE,
            "dumpSha256": dump_sha256,
            "dumpSizeBytes": dump_size_bytes,
            "alembicRevision": alembic_revision,
        }
    )


def _string(
    document: dict[str, Any],
    key: str,
    errors: list[str],
) -> str | None:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        errors.append(f"{key} must be a non-empty string")
        return None
    return value


def _integer(
    document: dict[str, Any],
    key: str,
    errors: list[str],
) -> int | None:
    value = document.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        errors.append(f"{key} must be an integer")
        return None
    return value
