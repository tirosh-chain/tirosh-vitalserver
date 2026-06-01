from __future__ import annotations

import argparse
import logging
import time
from pathlib import Path

from tirosh_guest_tools.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    service_is_running,
    systemctl,
)
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.operations import (
    OperationName,
)
from tirosh_guest_tools.logging import configure_logging
from tirosh_guest_tools.settings import SETTINGS

LOG_FILE = RUNTIME_DIR / "guest-command-poller.log"
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Dispatch guest command requests.")
    parser.parse_args()
    mount_runtime_share()
    configure_logging(SETTINGS.logging, log_file=LOG_FILE)
    interval = poll_interval()
    logger.info(
        "guest command poller started",
        extra={"fields": {"interval": interval}},
    )
    while True:
        for request_file, service, operation in REQUESTS:
            dispatch_request(request_file, service, operation)
        time.sleep(interval)


def poll_interval() -> int:
    return SETTINGS.intervals.command_poll_seconds


def dispatch_request(request_file: Path, service: str, operation: str) -> None:
    if not request_file.is_file() or service_is_running(service):
        return
    logger.info(
        "guest command request detected",
        extra={"fields": {"operation": operation, "service": service}},
    )
    systemctl("reset-failed", service, check=False)
    result = systemctl("start", "--no-block", service, check=False)
    status = (
        "service-scheduled"
        if result.returncode == 0
        else "service-schedule-failed"
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


if __name__ == "__main__":
    raise SystemExit(main())
