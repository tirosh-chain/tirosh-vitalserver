from __future__ import annotations

import logging
import time
from pathlib import Path

from tirosh_guest_tools.application.update_shutdown import (
    REQUEST_FILE as PREPARE_UPDATE_SHUTDOWN_REQUEST_FILE,
)
from tirosh_guest_tools.application.update_shutdown import write_dispatch_failure_result
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.operations import (
    OperationName,
    ReasonCode,
)
from tirosh_guest_tools.infrastructure.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    service_active_state,
    systemctl,
)
from tirosh_guest_tools.infrastructure.logging import configure_logging
from tirosh_guest_tools.infrastructure.settings import SETTINGS

LOG_FILE = RUNTIME_DIR / "guest-request-file-poller.log"
logger = logging.getLogger(__name__)
REQUESTS: list[tuple[Path, str, str]] = [
    (
        RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_REQUEST.value,
        RuntimeService.PREPARE_UPDATE_SHUTDOWN.value,
        OperationName.PREPARE_UPDATE_SHUTDOWN.value,
    ),
    (
        RUNTIME_DIR / RuntimeFileName.ACTIVATE_UPDATE_REQUEST.value,
        RuntimeService.ACTIVATE_UPDATE.value,
        OperationName.ACTIVATE_UPDATE.value,
    ),
    (
        RUNTIME_DIR / RuntimeFileName.REPAIR_DATASTORE_REQUEST.value,
        RuntimeService.REPAIR_DATASTORE.value,
        OperationName.REPAIR_DATASTORE.value,
    ),
    (
        RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_REQUEST.value,
        RuntimeService.REDIS_BACKUP.value,
        OperationName.REDIS_BACKUP.value,
    ),
]


def run_request_file_poller() -> None:
    mount_runtime_share()
    configure_logging(SETTINGS.logging, log_file=LOG_FILE)
    interval = SETTINGS.intervals.command_poll_seconds
    logger.info(
        "guest request file poller started",
        extra={"fields": {"interval": interval}},
    )
    while True:
        for request_file, service, operation in REQUESTS:
            dispatch_request(request_file, service, operation)
        time.sleep(interval)


def dispatch_request(request_file: Path, service: str, operation: str) -> None:
    if not request_file.is_file():
        return
    try:
        active_state = service_active_state(service)
    except Exception as error:
        logger.exception(
            "guest command service state read failed",
            extra={
                "fields": {
                    "operation": operation,
                    "service": service,
                    "error": str(error),
                }
            },
        )
        write_dispatch_failure(
            request_file=request_file,
            service=service,
            operation=operation,
            message=f"Guest command service state read failed: {service}",
            reason_code=ReasonCode.GUEST_COMMAND_DISPATCH_FAILED,
        )
        return
    if active_state in {"active", "activating"}:
        return
    if active_state == "failed":
        logger.error(
            "guest command service is failed",
            extra={"fields": {"operation": operation, "service": service}},
        )
        write_dispatch_failure(
            request_file=request_file,
            service=service,
            operation=operation,
            message=f"Guest command service failed before result: {service}",
            reason_code=ReasonCode.GUEST_COMMAND_UNIT_FAILED,
        )
        return
    logger.info(
        "guest command request detected",
        extra={"fields": {"operation": operation, "service": service}},
    )
    result = systemctl("start", "--no-block", service, check=False)
    status = (
        "service-scheduled"
        if result.returncode == 0
        else "service-schedule-failed"
    )
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        write_dispatch_failure(
            request_file=request_file,
            service=service,
            operation=operation,
            message=(
                f"Guest command service dispatch failed: {service} "
                f"error={stderr or result.returncode}"
            ),
            reason_code=ReasonCode.GUEST_COMMAND_DISPATCH_FAILED,
        )
    logger.info(
        "guest command service dispatch completed",
        extra={
            "fields": {
                "operation": operation,
                "service": service,
                "status": status,
            }
        },
    )


def write_dispatch_failure(
    *,
    request_file: Path,
    service: str,
    operation: str,
    message: str,
    reason_code: ReasonCode,
) -> None:
    if (
        request_file != PREPARE_UPDATE_SHUTDOWN_REQUEST_FILE
        or operation != OperationName.PREPARE_UPDATE_SHUTDOWN.value
        or service != RuntimeService.PREPARE_UPDATE_SHUTDOWN.value
    ):
        return
    try:
        write_dispatch_failure_result(
            message=message,
            reason_code=reason_code,
        )
    except Exception as error:
        logger.exception(
            "guest command dispatch failure result write failed",
            extra={
                "fields": {
                    "operation": operation,
                    "service": service,
                    "error": str(error),
                }
            },
        )
