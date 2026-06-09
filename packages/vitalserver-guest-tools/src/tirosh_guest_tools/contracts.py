from __future__ import annotations

from enum import StrEnum


class RuntimeService(StrEnum):
    CONTAINER_LOGS = "tirosh-vitalserver-container-logs.service"
    RUNTIME_STATE = "tirosh-runtime-state.service"
    COMMAND_POLLER = "tirosh-vitalserver-command-poller.service"
    COMPOSE = "tirosh-vitalserver-compose.service"
    REDIS_BACKUP = "tirosh-vitalserver-redis-backup.service"
    REDIS_BACKUP_TIMER = "tirosh-vitalserver-redis-backup.timer"
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
    GUEST_TOOLS_INSTALL_CONFIG = "tirosh-guest-tools-install-config"


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
