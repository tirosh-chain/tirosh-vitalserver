from __future__ import annotations

from tirosh_guest_tools.application.redis_repair import restart_runtime_compose
from tirosh_guest_tools.domain.guest_control.models import (
    DatastoreRepairDependencyError,
)


class DatastoreRepairMaintenanceAdapter:
    def repair_datastore(self) -> None:
        try:
            restart_runtime_compose()
        except Exception as error:
            raise DatastoreRepairDependencyError(
                f"Datastore repair failed: {error}",
                kind="datastore-repair-failed",
            ) from error
