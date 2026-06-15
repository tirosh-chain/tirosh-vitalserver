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
    REDIS_RESTORE = "redis-restore"
    REPAIR_DATASTORE = "repair-datastore"


class ComposeAction(StrEnum):
    UP = "up"
    TESTKIT_UP = "testkit-up"
    TESTKIT_UP_LOGGED = "testkit-up-logged"
    STOP = "stop"


class RuntimeStateAction(StrEnum):
    WATCH = "watch"
    ONCE = "once"


class ContainerLogAction(StrEnum):
    WATCH = "watch"
    ONCE = "once"


class ObservationPhase(StrEnum):
    ACTIVATION_PRE = "activation-pre"
    ACTIVATION_POST = "activation-post"
    ACTIVATION_FAILURE = "activation-failure"
    SHUTDOWN_PRE_STOP = "shutdown-pre-stop"
    SHUTDOWN_POST_SYNC = "shutdown-post-sync"
    SHUTDOWN_POWEROFF_REQUESTED = "shutdown-poweroff-requested"
    SHUTDOWN_FAILURE = "shutdown-failure"
    REPAIR_PRE = "repair-pre"
    REPAIR_FAILURE = "repair-failure"
    MANUAL = "manual"


class ShutdownPhase(StrEnum):
    PREPARING = "preparing"
    PREPARED = "prepared"
    POWEROFF_READY = "poweroff-ready"
    POWEROFF_REQUESTED = "poweroff-requested"
    POWEROFF_FAILED = "poweroff-failed"


class ReasonCode(StrEnum):
    GUEST_UPDATE_SHUTDOWN_FAILED = "guest-update-shutdown-failed"
    GUEST_COMMAND_DISPATCH_FAILED = "guest-command-dispatch-failed"
    GUEST_COMMAND_UNIT_FAILED = "guest-command-unit-failed"
    GUEST_BOOTSTRAP_DOCKER_RUNTIME_FAILED = "guest-bootstrap-docker-runtime-failed"


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
    restored_archive: str = ""
    redis_backup_path: str = ""
    shutdown_phase: ShutdownPhase | None = None
    details: dict[str, Any] | None = None

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
        if self.restored_archive:
            document["restoredArchive"] = self.restored_archive
        if self.redis_backup_path:
            document["redisBackupPath"] = self.redis_backup_path
        if self.shutdown_phase is not None:
            document["shutdownPhase"] = self.shutdown_phase.value
        if self.details is not None:
            document["details"] = self.details
        return document
