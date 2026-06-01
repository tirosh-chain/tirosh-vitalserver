from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Any


class OperationStatus(StrEnum):
    SKIPPED = "skipped"
    RUNNING = "running"
    READY = "ready"
    COMPLETED = "completed"
    FAILED = "failed"


class OperationName(StrEnum):
    ACTIVATE_UPDATE = "activate-update"
    PREPARE_UPDATE_SHUTDOWN = "prepare-update-shutdown"
    REDIS_BACKUP = "redis-backup"
    REPAIR_DATASTORE = "repair-datastore"


class ObservationPhase(StrEnum):
    ACTIVATION_PRE = "activation-pre"
    ACTIVATION_POST = "activation-post"
    ACTIVATION_FAILURE = "activation-failure"
    SHUTDOWN_PRE_STOP = "shutdown-pre-stop"
    SHUTDOWN_POST_SYNC = "shutdown-post-sync"
    SHUTDOWN_FAILURE = "shutdown-failure"
    REPAIR_PRE = "repair-pre"
    REPAIR_FAILURE = "repair-failure"
    MANUAL = "manual"


class ReasonCode(StrEnum):
    GUEST_UPDATE_SHUTDOWN_FAILED = "guest-update-shutdown-failed"


@dataclass(frozen=True)
class GuestOperationRequest:
    request_id: str
    version: str = ""


@dataclass(frozen=True)
class GuestOperationResult:
    operation: OperationName
    request_id: str
    schema_version: int
    status: OperationStatus
    message: str
    updated_at: str
    step: str = ""
    reason_codes: tuple[str, ...] = ()
    archive: str = ""
    redis_backup_path: str = ""

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "operation": self.operation.value,
            "requestId": self.request_id,
            "schemaVersion": self.schema_version,
            "message": self.message,
            "status": self.status.value,
            "updatedAt": self.updated_at,
        }
        if self.step:
            document["step"] = self.step
        if self.reason_codes:
            document["reasonCodes"] = list(self.reason_codes)
        if self.archive:
            document["archive"] = self.archive
        if self.redis_backup_path:
            document["redisBackupPath"] = self.redis_backup_path
        return document
