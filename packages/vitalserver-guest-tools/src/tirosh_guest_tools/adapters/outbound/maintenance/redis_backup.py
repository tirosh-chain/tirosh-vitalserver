from __future__ import annotations

from pathlib import Path

from tirosh_guest_tools.application.redis_backup import run_redis_backup
from tirosh_guest_tools.application.redis_restore import restore_redis_archive
from tirosh_guest_tools.domain.errors import GuestToolsDomainError
from tirosh_guest_tools.domain.guest_control.models import (
    RedisBackupDependencyError,
    RedisBackupResult,
    RedisRestoreDependencyError,
    RedisRestoreResult,
)


class RedisBackupMaintenanceAdapter:
    def create_backup(self) -> RedisBackupResult:
        try:
            outcome = run_redis_backup()
        except GuestToolsDomainError as error:
            raise RedisBackupDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise RedisBackupDependencyError(
                f"Redis backup failed: {error}",
                kind="redis-backup-failed",
            ) from error
        return RedisBackupResult(
            archive=str(outcome.archive),
        )

    def restore_backup(self, archive: str) -> RedisRestoreResult:
        try:
            outcome = restore_redis_archive(Path(archive))
        except GuestToolsDomainError as error:
            raise RedisRestoreDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise RedisRestoreDependencyError(
                f"Redis restore failed: {error}",
                kind="redis-restore-failed",
            ) from error
        return RedisRestoreResult(
            restored_archive=str(outcome.restored_archive),
        )
