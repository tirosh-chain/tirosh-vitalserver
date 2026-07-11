from __future__ import annotations

import logging
import tarfile
from pathlib import Path

from tirosh_guest_tools.application.contexts import RedisBackupOutcome
from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.infrastructure.common import (
    COMPOSE_ENVIRONMENT_FILE,
    COMPOSE_FILE,
    MOUNT_POINT,
    PROJECT_NAME,
    RUNTIME_DIR,
    mount_runtime_share,
    output,
    run,
    utc_now,
)

BACKUP_DIR = MOUNT_POINT / "backups" / "redis"
LOG_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_LOG.value
REDIS_VOLUME = f"{PROJECT_NAME}_redis-data"
logger = logging.getLogger(__name__)


def run_redis_backup() -> RedisBackupOutcome:
    mount_runtime_share()
    stamp = utc_now().replace(":", "").replace("-", "")
    archive = BACKUP_DIR / f"redis-{stamp}.tar.gz"
    try:
        logger.info("redis backup started")
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        logger.info(
            "redis backup context loaded",
            extra={
                "fields": {
                    "project": PROJECT_NAME,
                    "volume": REDIS_VOLUME,
                }
            },
        )
        create_backup(archive)
        logger.info(
            "redis backup completed",
            extra={"fields": {"archive": str(archive)}},
        )
        return RedisBackupOutcome(archive=archive)
    except Exception:
        logger.exception("redis backup failed")
        raise


def create_backup(archive: Path) -> None:
    logger.info("redis save started", extra={"fields": {"step": "redis-save"}})
    run(
        [
            "docker",
            "compose",
            "--env-file",
            str(COMPOSE_ENVIRONMENT_FILE),
            "--project-name",
            PROJECT_NAME,
            "-f",
            str(COMPOSE_FILE),
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
