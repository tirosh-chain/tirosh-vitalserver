from __future__ import annotations

import json
import subprocess
import tarfile
import tempfile
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.maintenance.postgres_backup import (
    POSTGRES_SERVICE,
    POSTGRES_USER,
    _postgres_lines,
    _sha256,
    _stderr,
    _verify_custom_dump,
)
from tirosh_guest_tools.application.compose import wait_for_postgres
from tirosh_guest_tools.application.contexts import PostgresRestoreOutcome
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.domain.errors import GuestContractError, GuestDependencyError
from tirosh_guest_tools.domain.postgres_backup import (
    POSTGRES_BACKUP_DATABASE_NAME,
    POSTGRES_BACKUP_DUMP_FILE,
    POSTGRES_BACKUP_MANIFEST_FILE,
    PostgresBackupManifest,
    PostgresBackupManifestContractError,
    validated_postgres_backup_manifest,
)
from tirosh_guest_tools.infrastructure.common import (
    MOUNT_POINT,
    compose_command,
    mount_runtime_share,
    run,
    systemctl,
)


def restore_postgres_backup_archive(
    archive: Path,
    *,
    restart_runtime: bool,
) -> PostgresRestoreOutcome:
    mount_runtime_share()
    _validate_archive_path(archive)
    with tempfile.TemporaryDirectory(prefix=".postgres-restore-") as temporary:
        staging = Path(temporary)
        manifest, dump = _load_archive(archive, staging)
        _verify_custom_dump(dump)
        _stop_database_writers()
        _replace_database(dump)
        _verify_restored_database(manifest)
        if restart_runtime:
            _start_runtime()
    return PostgresRestoreOutcome(
        restored_archive=archive,
        alembic_revision=manifest.alembic_revision,
        runtime_restarted=restart_runtime,
    )


def _validate_archive_path(archive: Path) -> None:
    try:
        archive.relative_to(MOUNT_POINT)
    except ValueError as error:
        raise GuestContractError(
            f"PostgreSQL restore archive must be under {MOUNT_POINT}: {archive}",
            code="postgres-restore-archive-outside-runtime-share",
        ) from error
    if not archive.is_file():
        raise GuestDependencyError(
            f"PostgreSQL restore archive is missing: {archive}",
            code="postgres-restore-archive-missing",
        )


def _load_archive(
    archive: Path,
    staging: Path,
) -> tuple[PostgresBackupManifest, Path]:
    try:
        with tarfile.open(archive, "r:gz") as source:
            members = source.getmembers()
            members_by_name = {member.name: member for member in members}
            expected = {
                POSTGRES_BACKUP_DUMP_FILE,
                POSTGRES_BACKUP_MANIFEST_FILE,
            }
            if set(members_by_name) != expected or any(
                not member.isfile() for member in members
            ):
                raise GuestContractError(
                    "PostgreSQL restore archive members are invalid",
                    code="postgres-restore-archive-members-invalid",
                )
            for name in expected:
                member_source = source.extractfile(members_by_name[name])
                if member_source is None:
                    raise GuestContractError(
                        f"PostgreSQL restore archive member is unreadable: {name}",
                        code="postgres-restore-archive-member-unreadable",
                    )
                with member_source, (staging / name).open("wb") as destination:
                    while chunk := member_source.read(1024 * 1024):
                        destination.write(chunk)
    except GuestContractError:
        raise
    except (OSError, tarfile.TarError) as error:
        raise GuestContractError(
            f"PostgreSQL restore archive could not be read: {error}",
            code="postgres-restore-archive-read-failed",
        ) from error

    manifest_path = staging / POSTGRES_BACKUP_MANIFEST_FILE
    try:
        document = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestContractError(
            f"PostgreSQL backup manifest could not be decoded: {error}",
            code="postgres-restore-manifest-decode-failed",
        ) from error
    if not isinstance(document, dict):
        raise GuestContractError(
            "PostgreSQL backup manifest must be a JSON object",
            code="postgres-restore-manifest-invalid",
        )
    try:
        manifest = validated_postgres_backup_manifest(document)
    except PostgresBackupManifestContractError as error:
        raise GuestContractError(
            "PostgreSQL backup manifest is invalid: " + "; ".join(error.errors),
            code="postgres-restore-manifest-invalid",
        ) from error

    dump = staging / POSTGRES_BACKUP_DUMP_FILE
    if dump.stat().st_size != manifest.dump_size_bytes:
        raise GuestContractError(
            "PostgreSQL backup dump size does not match its manifest",
            code="postgres-restore-dump-size-mismatch",
        )
    if _sha256(dump) != manifest.dump_sha256:
        raise GuestContractError(
            "PostgreSQL backup dump checksum does not match its manifest",
            code="postgres-restore-dump-checksum-mismatch",
        )
    return manifest, dump


def _stop_database_writers() -> None:
    systemctl("stop", RuntimeService.RUNTIME_OBSERVATION.value)
    run(compose_command(["stop"]))
    run(
        compose_command(["up", "--pull", "never", "--no-build", "-d", POSTGRES_SERVICE])
    )
    wait_for_postgres()


def _replace_database(dump: Path) -> None:
    _maintenance_command(
        [
            "psql",
            f"--username={POSTGRES_USER}",
            "--dbname=postgres",
            "--no-psqlrc",
            "--set=ON_ERROR_STOP=1",
            "--command",
            (
                "SELECT pg_terminate_backend(pid) "
                "FROM pg_stat_activity "
                f"WHERE datname = '{POSTGRES_BACKUP_DATABASE_NAME}' "
                "AND pid <> pg_backend_pid()"
            ),
        ],
        failure_code="postgres-restore-connection-termination-failed",
    )
    _maintenance_command(
        [
            "dropdb",
            "--if-exists",
            f"--username={POSTGRES_USER}",
            POSTGRES_BACKUP_DATABASE_NAME,
        ],
        failure_code="postgres-restore-drop-database-failed",
    )
    _maintenance_command(
        [
            "createdb",
            f"--username={POSTGRES_USER}",
            POSTGRES_BACKUP_DATABASE_NAME,
        ],
        failure_code="postgres-restore-create-database-failed",
    )
    command = compose_command(
        [
            "exec",
            "-T",
            POSTGRES_SERVICE,
            "pg_restore",
            "--exit-on-error",
            "--no-owner",
            "--no-privileges",
            f"--username={POSTGRES_USER}",
            f"--dbname={POSTGRES_BACKUP_DATABASE_NAME}",
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
            "PostgreSQL pg_restore failed: " + _stderr(completed),
            code="postgres-restore-pg-restore-failed",
        )


def _maintenance_command(arguments: list[str], *, failure_code: str) -> None:
    command = compose_command(["exec", "-T", POSTGRES_SERVICE, *arguments])
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise GuestDependencyError(
            "PostgreSQL restore command failed: " + (completed.stderr or "").strip(),
            code=failure_code,
        )


def _verify_restored_database(manifest: PostgresBackupManifest) -> None:
    revisions = _postgres_lines(
        "SELECT version_num FROM public.alembic_version ORDER BY version_num"
    )
    if revisions != (manifest.alembic_revision,):
        raise GuestDependencyError(
            "PostgreSQL restored database Alembic revision does not match "
            f"the backup manifest: expected={manifest.alembic_revision} "
            f"actual={list(revisions)}",
            code="postgres-restore-database-verification-failed",
        )


def _start_runtime() -> None:
    run(compose_command(["up", "--pull", "never", "--no-build", "-d"]))
    systemctl("start", RuntimeService.RUNTIME_OBSERVATION.value)
