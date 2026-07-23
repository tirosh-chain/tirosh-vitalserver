from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tarfile
import tempfile
from pathlib import Path

from tirosh_guest_tools.application.contexts import PostgresBackupOutcome
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.postgres_backup import (
    POSTGRES_BACKUP_DATABASE_NAME,
    POSTGRES_BACKUP_DUMP_FILE,
    POSTGRES_BACKUP_MANIFEST_FILE,
    PostgresBackupManifest,
    new_postgres_backup_manifest,
)
from tirosh_guest_tools.infrastructure.common import (
    MOUNT_POINT,
    compose_command,
    mount_runtime_share,
    utc_now,
    write_json,
)

BACKUP_DIR = MOUNT_POINT / "backups" / "postgres"
POSTGRES_SERVICE = "postgres"
POSTGRES_USER = "vitalserver"


def create_postgres_backup_archive() -> PostgresBackupOutcome:
    mount_runtime_share()
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = utc_now().replace(":", "").replace("-", "")
    archive = BACKUP_DIR / f"postgres-{stamp}.tar.gz"
    if archive.exists():
        raise GuestDependencyError(
            f"PostgreSQL backup destination already exists: {archive}",
            code="postgres-backup-destination-exists",
        )

    with tempfile.TemporaryDirectory(
        prefix=".postgres-backup-",
        dir=BACKUP_DIR,
    ) as temporary_directory:
        staging = Path(temporary_directory)
        dump = staging / POSTGRES_BACKUP_DUMP_FILE
        manifest_path = staging / POSTGRES_BACKUP_MANIFEST_FILE
        _write_custom_dump(dump)
        _verify_custom_dump(dump)
        manifest = _capture_manifest(dump)
        write_json(manifest_path, manifest.as_json())
        temporary_archive = staging / "postgres-backup.tar.gz"
        _write_archive(
            temporary_archive,
            dump=dump,
            manifest=manifest_path,
        )
        _verify_archive_members(temporary_archive)
        os.replace(temporary_archive, archive)

    return PostgresBackupOutcome(
        archive=archive,
        database_id=manifest.database_id,
        alembic_revisions=manifest.alembic_revisions,
    )


def _capture_manifest(dump: Path) -> PostgresBackupManifest:
    system_identifier = _postgres_lines(
        "SELECT system_identifier::text FROM pg_control_system()"
    )
    server_version = _postgres_lines("SHOW server_version")
    revisions = _postgres_lines(
        "SELECT version_num FROM public.alembic_version ORDER BY version_num"
    )
    schemas = _postgres_lines(
        """
        SELECT nspname
          FROM pg_namespace
         WHERE nspname <> 'information_schema'
           AND nspname !~ '^pg_'
         ORDER BY nspname
        """
    )
    relations = _postgres_lines(
        """
        SELECT namespace.nspname || '.' || relation.relname
          FROM pg_class AS relation
          JOIN pg_namespace AS namespace
            ON namespace.oid = relation.relnamespace
         WHERE namespace.nspname <> 'information_schema'
           AND namespace.nspname !~ '^pg_'
           AND relation.relkind IN ('r', 'p')
         ORDER BY namespace.nspname, relation.relname
        """
    )
    if len(system_identifier) != 1:
        raise GuestDependencyError(
            "PostgreSQL returned an invalid system identifier",
            code="postgres-backup-database-identity-invalid",
        )
    if len(server_version) != 1:
        raise GuestDependencyError(
            "PostgreSQL returned an invalid server version",
            code="postgres-backup-server-version-invalid",
        )
    return new_postgres_backup_manifest(
        database_id=f"{system_identifier[0]}:{POSTGRES_BACKUP_DATABASE_NAME}",
        created_at=utc_now(),
        server_version=server_version[0],
        dump_sha256=_sha256(dump),
        dump_size_bytes=dump.stat().st_size,
        alembic_revisions=revisions,
        included_schemas=schemas,
        included_relations=relations,
    )


def _write_custom_dump(destination: Path) -> None:
    command = compose_command(
        [
            "exec",
            "-T",
            POSTGRES_SERVICE,
            "pg_dump",
            "--format=custom",
            "--no-owner",
            "--no-privileges",
            f"--username={POSTGRES_USER}",
            f"--dbname={POSTGRES_BACKUP_DATABASE_NAME}",
        ]
    )
    with destination.open("wb") as output:
        completed = subprocess.run(
            command,
            check=False,
            stdout=output,
            stderr=subprocess.PIPE,
        )
    if completed.returncode != 0:
        raise GuestDependencyError(
            "PostgreSQL pg_dump failed: " + _stderr(completed),
            code="postgres-backup-pg-dump-failed",
        )
    if destination.stat().st_size <= 0:
        raise GuestDependencyError(
            "PostgreSQL pg_dump produced an empty dump",
            code="postgres-backup-dump-empty",
        )


def _verify_custom_dump(dump: Path) -> None:
    command = compose_command(
        [
            "exec",
            "-T",
            POSTGRES_SERVICE,
            "pg_restore",
            "--list",
        ]
    )
    with dump.open("rb") as source:
        completed = subprocess.run(
            command,
            check=False,
            stdin=source,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    if completed.returncode != 0:
        raise GuestDependencyError(
            "PostgreSQL dump verification failed: " + _stderr(completed),
            code="postgres-backup-dump-verification-failed",
        )


def _postgres_lines(statement: str) -> tuple[str, ...]:
    command = compose_command(
        [
            "exec",
            "-T",
            POSTGRES_SERVICE,
            "psql",
            f"--username={POSTGRES_USER}",
            f"--dbname={POSTGRES_BACKUP_DATABASE_NAME}",
            "--no-psqlrc",
            "--tuples-only",
            "--no-align",
            "--set=ON_ERROR_STOP=1",
            "--command",
            statement,
        ]
    )
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise GuestDependencyError(
            "PostgreSQL metadata read failed: " + (completed.stderr or "").strip(),
            code="postgres-backup-metadata-read-failed",
        )
    return tuple(line.strip() for line in completed.stdout.splitlines() if line.strip())


def _write_archive(
    destination: Path,
    *,
    dump: Path,
    manifest: Path,
) -> None:
    with tarfile.open(destination, "w:gz") as archive:
        archive.add(dump, arcname=POSTGRES_BACKUP_DUMP_FILE)
        archive.add(manifest, arcname=POSTGRES_BACKUP_MANIFEST_FILE)
    if destination.stat().st_size <= 0:
        raise GuestDependencyError(
            "PostgreSQL backup archive is empty",
            code="postgres-backup-archive-empty",
        )


def _verify_archive_members(archive: Path) -> None:
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
    member_names = {member.name for member in members if member.isfile()}
    expected = {
        POSTGRES_BACKUP_DUMP_FILE,
        POSTGRES_BACKUP_MANIFEST_FILE,
    }
    if member_names != expected:
        raise GuestDependencyError(
            "PostgreSQL backup archive members are invalid: "
            + json.dumps(sorted(member_names)),
            code="postgres-backup-archive-members-invalid",
        )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _stderr(completed: subprocess.CompletedProcess[bytes]) -> str:
    return (completed.stderr or b"").decode("utf-8", errors="replace").strip()
