from __future__ import annotations

import logging
import shutil
import tarfile
from pathlib import Path

from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.errors import GuestContractError, GuestDependencyError
from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    OperationName,
    OperationStatus,
)
from tirosh_guest_tools.infrastructure.common import (
    MOUNT_POINT,
    PROJECT_NAME,
    RUNTIME_DIR,
    compose_command,
    mount_runtime_share,
    output,
    read_json,
    run,
    utc_now,
    write_json,
)
from tirosh_guest_tools.infrastructure.bootstrap_operations import (
    default_bootstrap_context,
    sync_clock,
)

REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_RESTORE_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_RESTORE_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_RESTORE_LOG.value
REDIS_VOLUME = f"{PROJECT_NAME}_redis-data"
logger = logging.getLogger(__name__)


def run_redis_restore() -> None:
    mount_runtime_share()
    try:
        request = read_request()
    except Exception:
        write_result(
            "",
            OperationStatus.FAILED,
            "Redis restore request metadata is invalid.",
            None,
        )
        REQUEST_FILE.unlink(missing_ok=True)
        logger.exception("redis restore request metadata is invalid")
        raise
    archive = request.archive
    try:
        sync_clock(default_bootstrap_context())
        logger.info(
            "redis restore started",
            extra={
                "fields": {
                    "requestId": request.request_id,
                    "archive": str(archive),
                }
            },
        )
        write_result(
            request.request_id,
            OperationStatus.RUNNING,
            "Redis restore is running.",
            archive,
        )
        REQUEST_FILE.unlink(missing_ok=True)
        restore_archive(archive)
        write_result(
            request.request_id,
            OperationStatus.COMPLETED,
            "Redis restore completed.",
            archive,
        )
        logger.info(
            "redis restore completed",
            extra={"fields": {"archive": str(archive)}},
        )
    except Exception as error:
        write_result(
            request.request_id,
            OperationStatus.FAILED,
            f"Redis restore failed: {error}",
            archive,
        )
        logger.exception("redis restore failed")
        raise


class RedisRestoreRequest:
    def __init__(self, request_id: str, archive: Path) -> None:
        self.request_id = request_id
        self.archive = archive


def read_request() -> RedisRestoreRequest:
    document = read_json(REQUEST_FILE)
    request_id = document.get("requestId")
    if not isinstance(request_id, str) or not request_id:
        raise GuestContractError(
            f"requestId is missing: {REQUEST_FILE}",
            code="redis-restore-request-id-missing",
        )
    archive_value = document.get("archive")
    if not isinstance(archive_value, str) or not archive_value:
        raise GuestContractError(
            f"archive is missing: {REQUEST_FILE}",
            code="redis-restore-archive-missing",
        )
    archive = Path(archive_value)
    validate_archive_path(archive)
    return RedisRestoreRequest(request_id=request_id, archive=archive)


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


def write_result(
    request_id: str,
    status: OperationStatus,
    message: str,
    archive: Path | None,
) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation=OperationName.REDIS_RESTORE,
            request_id=request_id,
            schema_version=1,
            status=status,
            message=message,
            updated_at=utc_now(),
            restored_archive=str(archive) if archive is not None else "",
        ).as_json(),
    )
