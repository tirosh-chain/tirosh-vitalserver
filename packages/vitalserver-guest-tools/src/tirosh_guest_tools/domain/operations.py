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


class RuntimeService(StrEnum):
    CONTAINER_LOGS = "tirosh-vitalserver-container-logs.service"
    RUNTIME_STATE = "tirosh-runtime-state.service"
    COMPOSE = "tirosh-vitalserver-compose.service"
    REDIS_BACKUP = "tirosh-vitalserver-redis-backup.service"
    REPAIR_DATASTORE = "tirosh-vitalserver-repair-datastore.service"
    ACTIVATE_UPDATE = "tirosh-vitalserver-activate-update.service"
    PREPARE_UPDATE_SHUTDOWN = "tirosh-vitalserver-prepare-update-shutdown.service"
    TESTKIT = "tirosh-vitalserver-testkit.service"


class RuntimeFileName(StrEnum):
    COMPOSE = "compose.yaml"
    RUNTIME_STATE = "runtime-state.json"
    BOOTSTRAP_RESULT = "bootstrap-result.json"
    RUNTIME_CONFIG = "runtime-config.json"
    REDIS_BACKUP_REQUEST = "redis-backup.request"
    REDIS_BACKUP_RESULT = "redis-backup-result.json"
    REDIS_BACKUP_LOG = "redis-backup.log"
    REPAIR_DATASTORE_REQUEST = "repair-datastore.request"
    REPAIR_DATASTORE_RESULT = "repair-datastore-result.json"
    REPAIR_DATASTORE_LOG = "repair-datastore.log"
    ACTIVATE_UPDATE_REQUEST = "activate-update.request"
    ACTIVATE_UPDATE_RESULT = "activate-update-result.json"
    ACTIVATE_UPDATE_LOG = "activate-update.log"
    PREPARE_UPDATE_SHUTDOWN_REQUEST = "prepare-update-shutdown.request"
    PREPARE_UPDATE_SHUTDOWN_RESULT = "prepare-update-shutdown-result.json"
    PREPARE_UPDATE_SHUTDOWN_LOG = "prepare-update-shutdown.log"


class ComposeService(StrEnum):
    REDIS = "redis"
    APP = "app"
    AUDIT_PROXY = "audit-proxy"
    VITALDB_OBSERVER = "vitaldb-observer"
    REDIS_UI = "redis-ui"
    SWAGGER_UI = "swagger-ui"
    EDGE = "edge"
    TESTKIT = "testkit"


class RuntimeCommand(StrEnum):
    GUEST_OBSERVED = "tirosh-guest-observed"
    GUEST_OBSERVE = "tirosh-guest-observe"
    GUEST_CONTAINER_LOGS = "tirosh-guest-container-logs"
    GUEST_DIAGNOSTICS = "tirosh-guest-diagnostics"
    RUNTIME_ENV = "tirosh-runtime-env"
    WRITE_RUNTIME_STATE = "tirosh-write-runtime-state"
    RUNTIME_STATE = "tirosh-runtime-state"
    VITALSERVER_HEALTH = "tirosh-vitalserver-health"
    VITALSERVER_COMPOSE = "tirosh-vitalserver-compose"
    VITALSERVER_COMMAND_POLLER = "tirosh-vitalserver-command-poller"
    VITALSERVER_REDIS_BACKUP = "tirosh-vitalserver-redis-backup"
    VITALSERVER_REPAIR_DATASTORE = "tirosh-vitalserver-repair-datastore"
    VITALSERVER_ACTIVATE_UPDATE = "tirosh-vitalserver-activate-update"
    VITALSERVER_PREPARE_UPDATE_SHUTDOWN = "tirosh-vitalserver-prepare-update-shutdown"
    VITALSERVER_CONTAINER_LOGS = "tirosh-vitalserver-container-logs"
    VITALSERVER_DIAGNOSTICS = "tirosh-vitalserver-diagnostics"


class RuntimeConfigKey(StrEnum):
    ADMIN_PASSWORD = "adminPassword"
    PUBLIC_HOST = "publicHost"
    PUBLIC_PORT = "publicPort"
    REDIS_BACKUP_RETENTION_COUNT = "redisBackupRetentionCount"
    REDIS_HOST = "redisHost"
    REDIS_PORT = "redisPort"
    TESTKIT_ENABLED = "testkitEnabled"
    TRUST_PROXY = "trustProxy"
    VITAL_FILES_DIRECTORY = "vitalFilesDirectory"


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
