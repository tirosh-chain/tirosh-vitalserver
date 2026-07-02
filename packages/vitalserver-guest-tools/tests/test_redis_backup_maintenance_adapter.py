from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from tirosh_guest_tools.adapters.outbound.maintenance import (
    RedisBackupMaintenanceAdapter,
)
from tirosh_guest_tools.adapters.outbound.maintenance import redis_backup as adapter
from tirosh_guest_tools.application.contexts import (
    RedisBackupOutcome,
    RedisRestoreOutcome,
)
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.guest_control.models import (
    RedisBackupDependencyError,
    RedisRestoreDependencyError,
)


def test_redis_backup_maintenance_adapter_returns_archive_result(
    monkeypatch: Any,
) -> None:
    def fake_run_redis_backup() -> RedisBackupOutcome:
        return RedisBackupOutcome(
            archive=Path("/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"),
        )

    monkeypatch.setattr(adapter, "run_redis_backup", fake_run_redis_backup)

    result = RedisBackupMaintenanceAdapter().create_backup()

    assert result.as_json() == {
        "archive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    }


def test_redis_backup_maintenance_adapter_preserves_dependency_failure(
    monkeypatch: Any,
) -> None:
    def fake_run_redis_backup() -> RedisBackupOutcome:
        raise GuestDependencyError(
            "redis volume mount is missing",
            code="redis-volume-mount-missing",
        )

    monkeypatch.setattr(adapter, "run_redis_backup", fake_run_redis_backup)

    with pytest.raises(RedisBackupDependencyError) as error:
        RedisBackupMaintenanceAdapter().create_backup()

    assert error.value.kind == "redis-volume-mount-missing"
    assert error.value.message == "redis volume mount is missing"


def test_redis_backup_maintenance_adapter_restores_archive(
    monkeypatch: Any,
) -> None:
    restored: list[Path] = []

    def fake_restore_redis_archive(archive: Path) -> RedisRestoreOutcome:
        restored.append(archive)
        return RedisRestoreOutcome(restored_archive=archive)

    monkeypatch.setattr(adapter, "restore_redis_archive", fake_restore_redis_archive)

    result = RedisBackupMaintenanceAdapter().restore_backup(
        "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    )

    assert restored == [
        Path("/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz")
    ]
    assert result.as_json() == {
        "restoredArchive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    }


def test_redis_backup_maintenance_adapter_preserves_restore_dependency_failure(
    monkeypatch: Any,
) -> None:
    def fake_restore_redis_archive(archive: Path) -> RedisRestoreOutcome:
        raise GuestDependencyError(
            f"redis restore archive is missing: {archive}",
            code="redis-restore-archive-missing",
        )

    monkeypatch.setattr(adapter, "restore_redis_archive", fake_restore_redis_archive)

    with pytest.raises(RedisRestoreDependencyError) as error:
        RedisBackupMaintenanceAdapter().restore_backup(
            "/mnt/tirosh-runtime/backups/redis/missing.tar.gz"
        )

    assert error.value.kind == "redis-restore-archive-missing"
