from __future__ import annotations

from enum import StrEnum


class RuntimeService(StrEnum):
    CONTAINER_LOGS = "tirosh-vitalserver-container-logs.service"
    RUNTIME_STATE = "tirosh-runtime-state.service"
    COMMAND_POLLER = "tirosh-vitalserver-command-poller.service"
    COMPOSE = "tirosh-vitalserver-compose.service"
    SYNC_HOST_TIME = "tirosh-vitalserver-sync-host-time.service"
    REDIS_BACKUP = "tirosh-vitalserver-redis-backup.service"
    REDIS_RESTORE = "tirosh-vitalserver-redis-restore.service"
    RECONCILE_COMPOSE = "tirosh-vitalserver-reconcile-compose.service"
    REPAIR_DATASTORE = "tirosh-vitalserver-repair-datastore.service"
    ACTIVATE_UPDATE = "tirosh-vitalserver-activate-update.service"
    PREPARE_UPDATE_SHUTDOWN = "tirosh-vitalserver-prepare-update-shutdown.service"
    TESTKIT = "tirosh-vitalserver-testkit.service"


class RuntimeFileName(StrEnum):
    COMPOSE = "compose.yaml"
    COMPOSE_RUNTIME_LIMITS = "compose.runtime-limits.yaml"
    RUNTIME_STATE = "runtime-state.json"
    BOOTSTRAP_RESULT = "bootstrap-result.json"
    RUNTIME_CONFIG = "runtime-config.json"
    RUNTIME_SETTINGS = "runtime-settings.json"
    REDIS_BACKUP_REQUEST = "redis-backup.request"
    SERVICE_STACK_STATUS = "service-stack-status.json"
    REDIS_BACKUP_RESULT = "redis-backup-result.json"
    REDIS_BACKUP_LOG = "redis-backup.log"
    REDIS_RESTORE_REQUEST = "redis-restore.request"
    REDIS_RESTORE_RESULT = "redis-restore-result.json"
    REDIS_RESTORE_LOG = "redis-restore.log"
    RECONCILE_COMPOSE_REQUEST = "reconcile-compose.request"
    RECONCILE_COMPOSE_RESULT = "reconcile-compose-result.json"
    RECONCILE_COMPOSE_LOG = "reconcile-compose.log"
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
    RECORDER_RECOVERY = "recorder-recovery"
    RECORDER_INGRESS = "recorder-ingress"
    VITALDB_OBSERVER = "vitaldb-observer"
    REDIS_RELAY = "redis-relay"
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
    SERVICE_STACK_STATUS = "tirosh-vitalserver-service-stack-status"
    VITALSERVER_HEALTH = "tirosh-vitalserver-health"
    VITALSERVER_COMPOSE = "tirosh-vitalserver-compose"
    VITALSERVER_SYNC_HOST_TIME = "tirosh-vitalserver-sync-host-time"
    VITALSERVER_BOOTSTRAP = "tirosh-vitalserver-bootstrap"
    VITALSERVER_ROOTFS_SMOKE = "tirosh-vitalserver-rootfs-smoke"
    VITALSERVER_RUNTIME_BOOT_SMOKE = "tirosh-vitalserver-runtime-boot-smoke"
    VITALSERVER_RUNTIME_DATA_PREPARE = "tirosh-vitalserver-runtime-data-prepare"
    VITALSERVER_COMMAND_POLLER = "tirosh-vitalserver-command-poller"
    VITALSERVER_REDIS_BACKUP = "tirosh-vitalserver-redis-backup"
    VITALSERVER_REDIS_RESTORE = "tirosh-vitalserver-redis-restore"
    VITALSERVER_RECONCILE_COMPOSE = "tirosh-vitalserver-reconcile-compose"
    VITALSERVER_REPAIR_DATASTORE = "tirosh-vitalserver-repair-datastore"
    VITALSERVER_ACTIVATE_UPDATE = "tirosh-vitalserver-activate-update"
    VITALSERVER_PREPARE_UPDATE_SHUTDOWN = "tirosh-vitalserver-prepare-update-shutdown"
    VITALSERVER_CONTAINER_LOGS = "tirosh-vitalserver-container-logs"
    VITALSERVER_DIAGNOSTICS = "tirosh-vitalserver-diagnostics"
    GUEST_TOOLS_INSTALL_CONFIG = "tirosh-guest-tools-install-config"


class RootfsSmokeStatus(StrEnum):
    NOT_RUN = "not-run"
    RUNNING = "running"
    PASSED = "passed"
    FAILED = "failed"
    TIMEOUT = "timeout"
    CLEANUP_FAILED = "cleanup-failed"


class RuntimeConfigKey(StrEnum):
    ADMIN_PASSWORD = "adminPassword"
    PUBLIC_HOST = "publicHost"
    PUBLIC_PORT = "publicPort"
    REDIS_HOST = "redisHost"
    REDIS_PORT = "redisPort"
    TESTKIT_ENABLED = "testkitEnabled"
    TRUST_PROXY = "trustProxy"
    VITAL_FILES_DIRECTORY = "vitalFilesDirectory"
