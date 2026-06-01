from __future__ import annotations

import tarfile
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

from tirosh_guest_tools.common import (
    DEPLOY_DIR,
    MOUNT_POINT,
    PROJECT_NAME,
    RUNTIME_DIR,
    mount_runtime_share,
    output,
    read_json,
    run,
    utc_now,
    write_json,
)
from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    OperationName,
    OperationStatus,
    RuntimeConfigKey,
    RuntimeFileName,
)
from tirosh_guest_tools.runtime.config import load_config

BACKUP_DIR = MOUNT_POINT / "backups" / "redis"
REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_LOG.value
REDIS_VOLUME = f"{PROJECT_NAME}_redis-data"


@dataclass(frozen=True)
class RedisBackupOutcome:
    archive: Path
    request_id: str


def run_redis_backup() -> RedisBackupOutcome:
    mount_runtime_share()
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as log:
        request_id = read_request_id()
        stamp = utc_now().replace(":", "").replace("-", "")
        archive = BACKUP_DIR / f"redis-{stamp}.tar.gz"
        try:
            log_line(log, f"status=started archive={archive}")
            BACKUP_DIR.mkdir(parents=True, exist_ok=True)
            retention = read_retention_count()
            log_line(
                log,
                f"request_id={request_id or 'none'} retention={retention} "
                f"project={PROJECT_NAME} volume={REDIS_VOLUME}",
            )
            if request_id:
                write_result(
                    request_id,
                    OperationStatus.RUNNING,
                    "Redis backup is running.",
                    archive,
                )
            create_backup(archive, log)
            prune_backups(retention)
            if request_id:
                write_result(
                    request_id,
                    OperationStatus.COMPLETED,
                    "Redis backup completed.",
                    archive,
                )
                REQUEST_FILE.unlink(missing_ok=True)
            log_line(log, "status=completed")
            return RedisBackupOutcome(archive=archive, request_id=request_id)
        except Exception as error:
            log_line(log, f"status=failed error={error}")
            if request_id:
                write_result(
                    request_id,
                    OperationStatus.FAILED,
                    f"Redis backup failed: {error}",
                    archive,
                )
                REQUEST_FILE.unlink(missing_ok=True)
            raise


def read_request_id() -> str:
    if not REQUEST_FILE.is_file():
        return ""
    value = read_json(REQUEST_FILE).get("requestId", "")
    return value if isinstance(value, str) else ""


def read_retention_count() -> int:
    value = load_config(DEPLOY_DIR / RuntimeFileName.RUNTIME_CONFIG.value)[
        RuntimeConfigKey.REDIS_BACKUP_RETENTION_COUNT.value
    ]
    if not isinstance(value, int):
        raise ValueError("redisBackupRetentionCount must be an integer")
    return min(max(value, 1), 30)


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


def create_backup(archive: Path, log: TextIO) -> None:
    log_line(log, "step=redis-save status=started")
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
    log_line(log, "step=redis-save status=completed")
    redis_volume_mount = output(
        ["docker", "volume", "inspect", "-f", "{{ .Mountpoint }}", REDIS_VOLUME]
    ).strip()
    log_line(log, f"redis_volume_mount={redis_volume_mount}")
    source = Path(redis_volume_mount)
    if not source.is_dir():
        raise FileNotFoundError(redis_volume_mount)
    log_line(log, "step=archive status=started")
    with tarfile.open(archive, "w:gz") as tar:
        for entry in source.iterdir():
            tar.add(entry, arcname=entry.name)
    if archive.stat().st_size <= 0:
        raise RuntimeError("backup archive is empty")
    with tarfile.open(archive, "r:gz") as tar:
        tar.getmembers()
    log_line(log, f"step=archive status=completed archive={archive}")


def prune_backups(retention_count: int) -> None:
    backups = sorted(BACKUP_DIR.glob("redis-*.tar.gz"))
    for backup in backups[: max(len(backups) - retention_count, 0)]:
        backup.unlink(missing_ok=True)


def log_line(log: TextIO, message: str) -> None:
    log.write(f"{utc_now()} {message}\n")
    log.flush()
