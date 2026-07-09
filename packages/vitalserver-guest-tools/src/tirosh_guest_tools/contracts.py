from __future__ import annotations

from enum import StrEnum


class RuntimeService(StrEnum):
    CONTAINER_LOGS = "tirosh-vitalserver-container-logs.service"
    RUNTIME_OBSERVATION = "tirosh-runtime-observation.service"
    GUEST_CONTROL_API = "tirosh-vitalserver-guest-control-api.service"
    COMPOSE = "tirosh-vitalserver-compose.service"
    SYNC_HOST_TIME = "tirosh-vitalserver-sync-host-time.service"


class RuntimeFileName(StrEnum):
    COMPOSE = "compose.yaml"
    COMPOSE_RUNTIME_LIMITS = "compose.runtime-limits.yaml"
    RUNTIME_CONFIG = "runtime-config.json"
    RUNTIME_SETTINGS = "runtime-settings.json"
    REDIS_BACKUP_LOG = "redis-backup.log"
    REDIS_RESTORE_LOG = "redis-restore.log"
    REPAIR_DATASTORE_LOG = "repair-datastore.log"
    ACTIVATE_UPDATE_LOG = "activate-update.log"
    PREPARE_UPDATE_SHUTDOWN_LOG = "prepare-update-shutdown.log"


class RuntimeBootstrapEvidenceFileName(StrEnum):
    VM_IP = "vm-ip"


class RuntimeDiagnosticsArtifactFileName(StrEnum):
    RUNTIME_OBSERVATION = "runtime-observation.json"
    BOOTSTRAP_RESULT = "bootstrap-result.json"


class ComposeService(StrEnum):
    POSTGRES = "postgres"
    REDIS = "redis"
    APP = "app"
    RECORDER_RECOVERY = "recorder-recovery"
    RECORDER_INGRESS = "recorder-ingress"
    VITALDB_OBSERVER = "vitaldb-observer"
    REDIS_RELAY = "redis-relay"
    LAB = "lab"
    REDIS_UI = "redis-ui"
    SWAGGER_UI = "swagger-ui"
    EDGE = "edge"


class RuntimeCommand(StrEnum):
    GUEST_OBSERVED = "tirosh-guest-observed"
    GUEST_OBSERVE = "tirosh-guest-observe"
    GUEST_CONTAINER_LOGS = "tirosh-guest-container-logs"
    GUEST_DIAGNOSTICS = "tirosh-guest-diagnostics"
    RUNTIME_ENV = "tirosh-runtime-env"
    WRITE_RUNTIME_OBSERVATION = "tirosh-write-runtime-observation"
    RUNTIME_OBSERVATION = "tirosh-runtime-observation"
    VITALSERVER_HEALTH = "tirosh-vitalserver-health"
    VITALSERVER_COMPOSE = "tirosh-vitalserver-compose"
    VITALSERVER_SYNC_HOST_TIME = "tirosh-vitalserver-sync-host-time"
    VITALSERVER_BOOTSTRAP = "tirosh-vitalserver-bootstrap"
    VITALSERVER_ROOTFS_SMOKE = "tirosh-vitalserver-rootfs-smoke"
    VITALSERVER_RUNTIME_BOOT_SMOKE = "tirosh-vitalserver-runtime-boot-smoke"
    VITALSERVER_RUNTIME_DATA_PREPARE = "tirosh-vitalserver-runtime-data-prepare"
    VITALSERVER_GUEST_CONTROL_API = "tirosh-vitalserver-guest-control-api"
    VITALSERVER_REDIS_BACKUP = "tirosh-vitalserver-redis-backup"
    VITALSERVER_REDIS_RESTORE = "tirosh-vitalserver-redis-restore"
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
    TRUST_PROXY = "trustProxy"
    VITAL_FILES_DIRECTORY = "vitalFilesDirectory"
