from __future__ import annotations

from pathlib import Path

from tirosh_guest_tools.adapters.outbound.maintenance.postgres_backup import (
    create_postgres_backup_archive,
)
from tirosh_guest_tools.adapters.outbound.maintenance.postgres_restore import (
    restore_postgres_backup_archive,
)
from tirosh_guest_tools.domain.errors import GuestToolsDomainError
from tirosh_guest_tools.domain.guest_control.models import (
    PostgresBackupDependencyError,
    PostgresBackupResult,
    PostgresRestoreDependencyError,
    PostgresRestoreResult,
)


class PostgresDatabaseMaintenanceAdapter:
    def create_backup(self) -> PostgresBackupResult:
        try:
            outcome = create_postgres_backup_archive()
        except GuestToolsDomainError as error:
            raise PostgresBackupDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise PostgresBackupDependencyError(
                f"PostgreSQL backup failed: {error}",
                kind="postgres-backup-failed",
            ) from error
        return PostgresBackupResult(
            archive=str(outcome.archive),
            alembic_revision=outcome.alembic_revision,
        )

    def restore_backup(
        self,
        archive: str,
        *,
        restart_runtime: bool,
    ) -> PostgresRestoreResult:
        try:
            outcome = restore_postgres_backup_archive(
                Path(archive),
                restart_runtime=restart_runtime,
            )
        except GuestToolsDomainError as error:
            raise PostgresRestoreDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise PostgresRestoreDependencyError(
                f"PostgreSQL restore failed: {error}",
                kind="postgres-restore-failed",
            ) from error
        return PostgresRestoreResult(
            restored_archive=str(outcome.restored_archive),
            alembic_revision=outcome.alembic_revision,
            runtime_restarted=outcome.runtime_restarted,
        )
