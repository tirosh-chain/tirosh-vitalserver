from __future__ import annotations

import hashlib
import json
import tarfile
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.maintenance import (
    postgres_backup,
    postgres_restore,
)
from tirosh_guest_tools.domain.errors import GuestContractError, GuestDependencyError
from tirosh_guest_tools.domain.postgres_backup import (
    POSTGRES_BACKUP_DUMP_FILE,
    POSTGRES_BACKUP_MANIFEST_FILE,
    REQUIRED_RELATIONS,
    REQUIRED_SCHEMAS,
    PostgresBackupManifest,
    PostgresBackupManifestContractError,
    new_postgres_backup_manifest,
    validated_postgres_backup_manifest,
)


def test_postgres_backup_manifest_requires_the_managed_database_contract() -> None:
    document = _manifest().as_json()
    document["includedSchemas"] = ["public"]
    document["includedRelations"] = ["public.alembic_version"]

    with pytest.raises(PostgresBackupManifestContractError) as error:
        validated_postgres_backup_manifest(document)

    assert "includedSchemas is missing required schemas" in str(error.value)
    assert "includedRelations is missing required relations" in str(error.value)


def test_create_postgres_backup_writes_verified_archive(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    verified: list[Path] = []
    monkeypatch.setattr(postgres_backup, "BACKUP_DIR", tmp_path)
    monkeypatch.setattr(postgres_backup, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(
        postgres_backup,
        "utc_now",
        lambda: "2026-07-23T12:00:00Z",
    )

    def write_dump(destination: Path) -> None:
        destination.write_bytes(b"PGDMP-test")

    monkeypatch.setattr(postgres_backup, "_write_custom_dump", write_dump)
    monkeypatch.setattr(
        postgres_backup,
        "_verify_custom_dump",
        verified.append,
    )
    monkeypatch.setattr(
        postgres_backup,
        "_capture_manifest",
        lambda dump: _manifest(
            dump_sha256=hashlib.sha256(dump.read_bytes()).hexdigest(),
            dump_size_bytes=dump.stat().st_size,
        ),
    )

    outcome = postgres_backup.create_postgres_backup_archive()

    assert outcome.archive.is_file()
    assert outcome.database_id == "cluster:vitalserver"
    assert outcome.alembic_revisions == ("0002_recorder_observability_expectations",)
    assert len(verified) == 1
    with tarfile.open(outcome.archive, "r:gz") as archive:
        assert {member.name for member in archive.getmembers()} == {
            POSTGRES_BACKUP_DUMP_FILE,
            POSTGRES_BACKUP_MANIFEST_FILE,
        }


def test_postgres_restore_rejects_dump_checksum_mismatch_before_commands(
    tmp_path: Path,
) -> None:
    archive = tmp_path / "postgres.tar.gz"
    dump = tmp_path / POSTGRES_BACKUP_DUMP_FILE
    manifest = tmp_path / POSTGRES_BACKUP_MANIFEST_FILE
    dump.write_bytes(b"actual dump")
    document = _manifest(
        dump_sha256="0" * 64,
        dump_size_bytes=dump.stat().st_size,
    ).as_json()
    manifest.write_text(json.dumps(document), encoding="utf-8")
    with tarfile.open(archive, "w:gz") as destination:
        destination.add(dump, arcname=POSTGRES_BACKUP_DUMP_FILE)
        destination.add(manifest, arcname=POSTGRES_BACKUP_MANIFEST_FILE)
    staging = tmp_path / "staging"
    staging.mkdir()

    with pytest.raises(GuestContractError) as error:
        postgres_restore._load_archive(archive, staging)

    assert getattr(error.value, "code", None) == (
        "postgres-restore-dump-checksum-mismatch"
    )


def test_postgres_restore_validates_before_stopping_writers(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    archive = tmp_path / "postgres.tar.gz"
    archive.write_bytes(b"archive")
    dump = tmp_path / "database.dump"
    dump.write_bytes(b"dump")
    manifest = _manifest(
        dump_sha256=hashlib.sha256(dump.read_bytes()).hexdigest(),
        dump_size_bytes=dump.stat().st_size,
    )
    events: list[str] = []
    monkeypatch.setattr(postgres_restore, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(
        postgres_restore,
        "_validate_archive_path",
        lambda _archive: events.append("validate-path"),
    )
    monkeypatch.setattr(
        postgres_restore,
        "_load_archive",
        lambda _archive, _staging: events.append("load-archive") or (manifest, dump),
    )
    monkeypatch.setattr(
        postgres_restore,
        "_verify_custom_dump",
        lambda _dump: events.append("verify-dump"),
    )
    monkeypatch.setattr(
        postgres_restore,
        "_stop_database_writers",
        lambda: events.append("stop-writers"),
    )
    monkeypatch.setattr(
        postgres_restore,
        "_replace_database",
        lambda _dump: events.append("replace-database"),
    )
    monkeypatch.setattr(
        postgres_restore,
        "_verify_restored_database",
        lambda _manifest: events.append("verify-database"),
    )
    monkeypatch.setattr(
        postgres_restore,
        "_start_runtime",
        lambda: events.append("start-runtime"),
    )

    outcome = postgres_restore.restore_postgres_backup_archive(
        archive,
        restart_runtime=True,
    )

    assert outcome.restored_archive == archive
    assert outcome.runtime_restarted is True
    assert events == [
        "validate-path",
        "load-archive",
        "verify-dump",
        "stop-writers",
        "replace-database",
        "verify-database",
        "start-runtime",
    ]


def test_postgres_restore_does_not_report_start_after_replace_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    archive = tmp_path / "postgres.tar.gz"
    archive.write_bytes(b"archive")
    dump = tmp_path / "database.dump"
    dump.write_bytes(b"dump")
    started: list[bool] = []
    monkeypatch.setattr(postgres_restore, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(postgres_restore, "_validate_archive_path", lambda _: None)
    monkeypatch.setattr(
        postgres_restore,
        "_load_archive",
        lambda _archive, _staging: (_manifest(), dump),
    )
    monkeypatch.setattr(postgres_restore, "_verify_custom_dump", lambda _: None)
    monkeypatch.setattr(postgres_restore, "_stop_database_writers", lambda: None)

    def fail_replace(_dump: Path) -> None:
        raise GuestDependencyError(
            "restore failed",
            code="postgres-restore-pg-restore-failed",
        )

    monkeypatch.setattr(postgres_restore, "_replace_database", fail_replace)
    monkeypatch.setattr(
        postgres_restore,
        "_start_runtime",
        lambda: started.append(True),
    )

    with pytest.raises(GuestDependencyError):
        postgres_restore.restore_postgres_backup_archive(
            archive,
            restart_runtime=True,
        )

    assert started == []


def test_postgres_restore_can_leave_runtime_stopped_for_coordinated_restore(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    archive = tmp_path / "postgres.tar.gz"
    archive.write_bytes(b"archive")
    dump = tmp_path / "database.dump"
    dump.write_bytes(b"dump")
    started: list[bool] = []
    monkeypatch.setattr(postgres_restore, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(postgres_restore, "_validate_archive_path", lambda _: None)
    monkeypatch.setattr(
        postgres_restore,
        "_load_archive",
        lambda _archive, _staging: (_manifest(), dump),
    )
    monkeypatch.setattr(postgres_restore, "_verify_custom_dump", lambda _: None)
    monkeypatch.setattr(postgres_restore, "_stop_database_writers", lambda: None)
    monkeypatch.setattr(postgres_restore, "_replace_database", lambda _: None)
    monkeypatch.setattr(
        postgres_restore,
        "_verify_restored_database",
        lambda _: None,
    )
    monkeypatch.setattr(
        postgres_restore,
        "_start_runtime",
        lambda: started.append(True),
    )

    outcome = postgres_restore.restore_postgres_backup_archive(
        archive,
        restart_runtime=False,
    )

    assert outcome.runtime_restarted is False
    assert started == []


def _manifest(
    *,
    dump_sha256: str = "a" * 64,
    dump_size_bytes: int = 10,
) -> PostgresBackupManifest:
    return new_postgres_backup_manifest(
        database_id="cluster:vitalserver",
        created_at="2026-07-23T12:00:00Z",
        server_version="16.9",
        dump_sha256=dump_sha256,
        dump_size_bytes=dump_size_bytes,
        alembic_revisions=("0002_recorder_observability_expectations",),
        included_schemas=tuple(sorted(REQUIRED_SCHEMAS)),
        included_relations=tuple(sorted(REQUIRED_RELATIONS)),
    )
