from __future__ import annotations

import logging
import shutil
import tarfile
from pathlib import Path

from tirosh_guest_tools.application.contexts import RedisRestoreOutcome
from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.errors import GuestContractError, GuestDependencyError
from tirosh_guest_tools.infrastructure.bootstrap_operations import (
    default_bootstrap_context,
    sync_clock,
)
from tirosh_guest_tools.infrastructure.common import (
    MOUNT_POINT,
    PROJECT_NAME,
    RUNTIME_DIR,
    compose_command,
    mount_runtime_share,
    output,
    run,
)

LOG_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_RESTORE_LOG.value
REDIS_VOLUME = f"{PROJECT_NAME}_redis-data"
logger = logging.getLogger(__name__)


def restore_redis_archive(archive: Path) -> RedisRestoreOutcome:
    mount_runtime_share()
    validate_archive_path(archive)
    sync_clock(default_bootstrap_context())
    logger.info(
        "redis restore started",
        extra={
            "fields": {
                "archive": str(archive),
            }
        },
    )
    restore_archive(archive)
    logger.info(
        "redis restore completed",
        extra={"fields": {"archive": str(archive)}},
    )
    return RedisRestoreOutcome(restored_archive=archive)


def validate_archive_path(archive: Path) -> None:
    try:
        archive.relative_to(MOUNT_POINT)
    except ValueError as error:
        raise GuestContractError(
            f"redis restore archive must be under {MOUNT_POINT}: {archive}",
            code="redis-restore-archive-outside-runtime-share",
        ) from error
    if not archive.is_file():
        raise GuestDependencyError(
            f"redis restore archive is missing: {archive}",
            code="redis-restore-archive-missing",
        )


def restore_archive(archive: Path) -> None:
    validate_archive_members(archive)
    logger.info(
        "redis compose stop started",
        extra={"fields": {"step": "compose-stop"}},
    )
    run(compose_command(["stop"]))
    logger.info(
        "redis compose stop completed",
        extra={"fields": {"step": "compose-stop"}},
    )
    redis_volume_mount = output(
        ["docker", "volume", "inspect", "-f", "{{ .Mountpoint }}", REDIS_VOLUME]
    ).strip()
    target = Path(redis_volume_mount)
    if not target.is_dir():
        raise GuestDependencyError(
            f"redis volume mount is missing: {redis_volume_mount}",
            code="redis-volume-mount-missing",
        )
    clear_directory(target)
    with tarfile.open(archive, "r:gz") as tar:
        tar.extractall(target)
    logger.info("redis archive extracted", extra={"fields": {"archive": str(archive)}})
    run(compose_command(["up", "-d"]))


def validate_archive_members(archive: Path) -> None:
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            member_path = Path(member.name)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise GuestContractError(
                    f"redis restore archive member path is unsafe: {member.name}",
                    code="redis-restore-archive-member-path-unsafe",
                )
            if member.issym() or member.islnk():
                raise GuestContractError(
                    f"redis restore archive member link is unsupported: {member.name}",
                    code="redis-restore-archive-member-link-unsupported",
                )


def clear_directory(directory: Path) -> None:
    for entry in directory.iterdir():
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()
