from __future__ import annotations

import logging
import tarfile
from dataclasses import dataclass
from pathlib import Path

from tirosh_guest_tools.common import (
    DEPLOY_DIR,
    MOUNT_POINT,
    PROJECT_NAME,
    RUNTIME_DIR,
    mount_runtime_share,
    output,
    request_id_from,
    run,
    utc_now,
    write_json,
)
from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    OperationName,
    OperationStatus,
)
from tirosh_guest_tools.runtime.config import load_config

BACKUP_DIR = MOUNT_POINT / "backups" / "redis"
REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_LOG.value
REDIS_VOLUME = f"{PROJECT_NAME}_redis-data"
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class RedisBackupOutcome:
    archive: Path
    request_id: str


def run_redis_backup() -> RedisBackupOutcome:
    mount_runtime_share()
    request_id = read_request_id()
    stamp = utc_now().replace(":", "").replace("-", "")
    archive = BACKUP_DIR / f"redis-{stamp}.tar.gz"
    try:
        logger.info(
            "redis backup started",
            extra={"fields": {"requestId": request_id or None}},
        )
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        retention = read_retention_count()
        logger.info(
            "redis backup context loaded",
            extra={
                "fields": {
                    "requestId": request_id or None,
                    "retention": retention,
                    "project": PROJECT_NAME,
                    "volume": REDIS_VOLUME,
                }
            },
        )
        if request_id:
            write_result(
                request_id,
                OperationStatus.RUNNING,
                "Redis backup is running.",
                archive,
            )
        create_backup(archive)
        prune_backups(retention)
        if request_id:
            write_result(
                request_id,
                OperationStatus.COMPLETED,
                "Redis backup completed.",
                archive,
            )
            REQUEST_FILE.unlink(missing_ok=True)
        logger.info(
            "redis backup completed",
            extra={"fields": {"archive": str(archive)}},
        )
        return RedisBackupOutcome(archive=archive, request_id=request_id)
    except Exception as error:
        if request_id:
            write_result(
                request_id,
                OperationStatus.FAILED,
                f"Redis backup failed: {error}",
                archive,
            )
            REQUEST_FILE.unlink(missing_ok=True)
        logger.exception(
            "redis backup failed",
            extra={"fields": {"requestId": request_id or None}},
        )
        raise


def read_request_id() -> str:
    if not REQUEST_FILE.is_file():
        return ""
    return request_id_from(REQUEST_FILE)


def read_retention_count() -> int:
    return load_config(
        DEPLOY_DIR / RuntimeFileName.RUNTIME_CONFIG.value
    ).redis_backup_retention_count


def write_result(
    request_id: str,
    status: OperationStatus,
    message: str,
    archive: Path,
) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation=OperationName.REDIS_BACKUP,
            request_id=request_id,
            schema_version=1,
            status=status,
            message=message,
            updated_at=utc_now(),
            archive=str(archive),
        ).as_json(),
    )


def create_backup(archive: Path) -> None:
    logger.info("redis save started", extra={"fields": {"step": "redis-save"}})
    run(
        [
            "docker",
            "compose",
            "--project-name",
            PROJECT_NAME,
            "-f",
            str(DEPLOY_DIR / RuntimeFileName.COMPOSE.value),
            "exec",
            "-T",
            "redis",
            "redis-cli",
            "SAVE",
        ]
    )
    logger.info("redis save completed", extra={"fields": {"step": "redis-save"}})
    redis_volume_mount = output(
        ["docker", "volume", "inspect", "-f", "{{ .Mountpoint }}", REDIS_VOLUME]
    ).strip()
    logger.info(
        "redis volume mount resolved",
        extra={"fields": {"volumeMount": redis_volume_mount}},
    )
    source = Path(redis_volume_mount)
    if not source.is_dir():
        raise GuestDependencyError(
            f"redis volume mount is missing: {redis_volume_mount}",
            code="redis-volume-mount-missing",
        )
    logger.info(
        "redis archive started",
        extra={"fields": {"step": "archive", "archive": str(archive)}},
    )
    with tarfile.open(archive, "w:gz") as tar:
        for entry in source.iterdir():
            tar.add(entry, arcname=entry.name)
    if archive.stat().st_size <= 0:
        raise GuestDependencyError(
            "backup archive is empty",
            code="redis-backup-archive-empty",
        )
    with tarfile.open(archive, "r:gz") as tar:
        tar.getmembers()
    logger.info(
        "redis archive completed",
        extra={"fields": {"step": "archive", "archive": str(archive)}},
    )


def prune_backups(retention_count: int) -> None:
    backups = sorted(BACKUP_DIR.glob("redis-*.tar.gz"))
    for backup in backups[: max(len(backups) - retention_count, 0)]:
        backup.unlink(missing_ok=True)
