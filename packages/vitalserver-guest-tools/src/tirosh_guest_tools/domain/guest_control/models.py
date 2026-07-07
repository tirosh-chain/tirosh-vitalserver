from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any

from tirosh_guest_tools.domain.runtime_state import RuntimeResourceUsage


class ServiceCommand(StrEnum):
    START = "start"
    STOP = "stop"
    RESTART = "restart"
    RECONCILE = "reconcile"
    LAB_CREATE_SESSION = "lab-create-session"
    LAB_START_SESSION = "lab-start-session"
    LAB_STOP_SESSION = "lab-stop-session"
    LAB_REPLAY_VITAL_FILE = "lab-replay-vital-file"
    LAB_UPLOAD_VITAL_FILE = "lab-upload-vital-file"
    LAB_CREATE_BEDS = "lab-create-beds"
    LAB_DELETE_BEDS = "lab-delete-beds"
    LAB_RESET_BEDS = "lab-reset-beds"
    LAB_CREATE_RECORDERS = "lab-create-recorders"
    LAB_DELETE_RECORDERS = "lab-delete-recorders"
    LAB_RESET_RECORDERS = "lab-reset-recorders"
    REDIS_BACKUP = "redis-backup"
    REDIS_RESTORE = "redis-restore"
    REPAIR_DATASTORE = "repair-datastore"
    UPDATE_ACTIVATION = "activate-update"
    UPDATE_SHUTDOWN = "prepare-update-shutdown"
    REQUEST_GUEST_POWEROFF = "request-guest-poweroff"


class GuestServiceDesiredState(StrEnum):
    RUNNING = "running"
    STOPPED = "stopped"


class GuestServiceSpecState(StrEnum):
    CONFIGURED = "configured"
    MISSING = "missing"


class GuestServiceStatusReadState(StrEnum):
    LOADED = "loaded"
    FAILED = "failed"


class GuestServiceObservedState(StrEnum):
    RUNNING = "running"
    STOPPED = "stopped"
    EXITED = "exited"
    ABSENT = "absent"
    UNKNOWN = "unknown"


class OperationState(StrEnum):
    ACCEPTED = "accepted"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


TERMINAL_OPERATION_STATES = {
    OperationState.COMPLETED,
    OperationState.FAILED,
    OperationState.CANCELLED,
}


@dataclass(frozen=True)
class ServiceStatus:
    service: str
    state: str
    health: str
    observed_at: datetime
    container: str = ""
    exit_code: int | None = None
    memory: RuntimeResourceUsage | None = None

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "service": self.service,
            "state": self.state,
            "health": self.health,
            "observedAt": self.observed_at.isoformat(),
        }
        if self.container:
            document["container"] = self.container
        if self.exit_code is not None:
            document["exitCode"] = self.exit_code
        if self.memory is not None:
            document["memory"] = self.memory.as_json()
        return document


@dataclass(frozen=True)
class GuestServiceSpec:
    state: GuestServiceSpecState
    desired_state: GuestServiceDesiredState | None = None
    updated_at: datetime | None = None

    @staticmethod
    def missing() -> GuestServiceSpec:
        return GuestServiceSpec(state=GuestServiceSpecState.MISSING)

    @staticmethod
    def configured(
        *,
        desired_state: GuestServiceDesiredState,
        updated_at: datetime,
    ) -> GuestServiceSpec:
        return GuestServiceSpec(
            state=GuestServiceSpecState.CONFIGURED,
            desired_state=desired_state,
            updated_at=updated_at,
        )

    def as_json(self) -> dict[str, Any]:
        return {
            "state": self.state.value,
            "desiredState": (
                self.desired_state.value if self.desired_state is not None else None
            ),
            "updatedAt": self.updated_at.isoformat()
            if self.updated_at is not None
            else None,
        }


@dataclass(frozen=True)
class GuestServiceStatusRead:
    state: GuestServiceStatusReadState
    observed_state: GuestServiceObservedState | None = None
    service_status: ServiceStatus | None = None
    failure: OperationFailure | None = None

    @staticmethod
    def loaded(
        service_status: ServiceStatus,
        *,
        observed_state: GuestServiceObservedState,
    ) -> GuestServiceStatusRead:
        return GuestServiceStatusRead(
            state=GuestServiceStatusReadState.LOADED,
            observed_state=observed_state,
            service_status=service_status,
        )

    @staticmethod
    def failed(failure: OperationFailure) -> GuestServiceStatusRead:
        return GuestServiceStatusRead(
            state=GuestServiceStatusReadState.FAILED,
            failure=failure,
        )

    def as_json(self) -> dict[str, Any]:
        return {
            "state": self.state.value,
            "observedState": self.observed_state.value
            if self.observed_state is not None
            else None,
            "observedAt": self.service_status.observed_at.isoformat()
            if self.service_status is not None
            else None,
            "serviceStatus": self.service_status.as_json()
            if self.service_status is not None
            else None,
            "readError": self.failure.as_json() if self.failure is not None else None,
        }


@dataclass(frozen=True)
class GuestServiceCondition:
    type: str
    status: str
    reason: str
    message: str
    observed_at: datetime

    def as_json(self) -> dict[str, Any]:
        return {
            "type": self.type,
            "status": self.status,
            "reason": self.reason,
            "message": self.message,
            "observedAt": self.observed_at.isoformat(),
        }


@dataclass(frozen=True)
class GuestServiceResource:
    service: str
    spec: GuestServiceSpec
    status: GuestServiceStatusRead
    conditions: list[GuestServiceCondition]
    last_operation_id: str | None = None

    def as_json(self) -> dict[str, Any]:
        return {
            "service": self.service,
            "spec": self.spec.as_json(),
            "status": self.status.as_json(),
            "conditions": [
                condition.as_json() for condition in self.conditions
            ],
            "lastOperationId": self.last_operation_id,
        }


@dataclass(frozen=True)
class StackStatus:
    state: str
    services: list[ServiceStatus]
    observed_at: datetime
    cpu_usage_percent: float | None = None
    memory: RuntimeResourceUsage | None = None
    system_disk: RuntimeResourceUsage | None = None
    vital_files_disk: RuntimeResourceUsage | None = None

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "state": self.state,
            "observedAt": self.observed_at.isoformat(),
            "services": [service.as_json() for service in self.services],
        }
        if self.cpu_usage_percent is not None:
            document["cpuUsagePercent"] = self.cpu_usage_percent
        if self.memory is not None:
            document["memory"] = self.memory.as_json()
        if self.system_disk is not None:
            document["systemDisk"] = self.system_disk.as_json()
        if self.vital_files_disk is not None:
            document["vitalFilesDisk"] = self.vital_files_disk.as_json()
        return document


@dataclass(frozen=True)
class OperationFailure:
    kind: str
    message: str
    evidence_path: str = ""

    def as_json(self) -> dict[str, Any]:
        document = {
            "kind": self.kind,
            "message": self.message,
        }
        if self.evidence_path:
            document["evidencePath"] = self.evidence_path
        return document


@dataclass(frozen=True)
class ServiceOperation:
    operation_id: str
    service: str
    command: ServiceCommand
    state: OperationState
    created_at: datetime
    updated_at: datetime
    failure: OperationFailure | None = None
    result: dict[str, Any] | None = None

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "operationId": self.operation_id,
            "service": self.service,
            "command": self.command.value,
            "state": self.state.value,
            "createdAt": self.created_at.isoformat(),
            "updatedAt": self.updated_at.isoformat(),
        }
        if self.failure is not None:
            document["failure"] = self.failure.as_json()
        if self.result is not None:
            document["result"] = self.result
        return document


@dataclass(frozen=True)
class OperationEvent:
    operation_id: str
    state: OperationState
    observed_at: datetime
    failure: OperationFailure | None = None
    result: dict[str, Any] | None = None

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "operationId": self.operation_id,
            "state": self.state.value,
            "observedAt": self.observed_at.isoformat(),
        }
        if self.failure is not None:
            document["failure"] = self.failure.as_json()
        if self.result is not None:
            document["result"] = self.result
        return document


class GuestControlPolicyError(ValueError):
    pass


class GuestControlDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class ServiceNotFoundError(GuestControlDependencyError):
    def __init__(self, service: str, *, available_services: list[str]) -> None:
        super().__init__(
            f"compose service is not available: {service}",
            kind="serviceNotFound",
        )
        self.service = service
        self.available_services = available_services


class ProductLabDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class RecorderIngressDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class VitalDBReadModelDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass(frozen=True)
class ProductLabSessionResult:
    session: dict[str, Any]
    lab_operation_id: str | None = None


@dataclass(frozen=True)
class ProductLabReadModelResult:
    document: dict[str, Any]
    lab_operation_id: str | None = None


@dataclass(frozen=True)
class ProductLabUploadResult:
    document: dict[str, Any]
    lab_operation_id: str | None = None


class RedisBackupDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass(frozen=True)
class RedisBackupResult:
    archive: str

    def as_json(self) -> dict[str, Any]:
        return {
            "archive": self.archive,
        }


class RedisRestoreDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass(frozen=True)
class RedisRestoreResult:
    restored_archive: str

    def as_json(self) -> dict[str, Any]:
        return {
            "restoredArchive": self.restored_archive,
        }


class DatastoreRepairDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class UpdateActivationDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass(frozen=True)
class UpdateActivationResult:
    request_id: str
    version: str

    def as_json(self) -> dict[str, Any]:
        return {
            "requestId": self.request_id,
            "version": self.version,
        }


class UpdateShutdownDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass(frozen=True)
class UpdateShutdownResult:
    request_id: str
    version: str
    shutdown_phase: str
    redis_backup_path: str = ""

    def as_json(self) -> dict[str, Any]:
        document = {
            "requestId": self.request_id,
            "version": self.version,
            "shutdownPhase": self.shutdown_phase,
        }
        if self.redis_backup_path:
            document["redisBackupPath"] = self.redis_backup_path
        return document
