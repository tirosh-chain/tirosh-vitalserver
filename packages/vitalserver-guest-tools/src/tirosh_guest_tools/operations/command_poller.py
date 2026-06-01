from __future__ import annotations

import argparse
import time
from pathlib import Path

from tirosh_guest_tools.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    service_is_running,
    systemctl,
    utc_now,
)
from tirosh_guest_tools.settings import SETTINGS

LOG_FILE = RUNTIME_DIR / "guest-command-poller.log"
REQUESTS: list[tuple[Path, str, str]] = [
    (
        RUNTIME_DIR / "prepare-update-shutdown.request",
        "tirosh-vitalserver-prepare-update-shutdown.service",
        "prepare-update-shutdown",
    ),
    (
        RUNTIME_DIR / "activate-update.request",
        "tirosh-vitalserver-activate-update.service",
        "activate-update",
    ),
    (
        RUNTIME_DIR / "repair-datastore.request",
        "tirosh-vitalserver-repair-datastore.service",
        "repair-datastore",
    ),
    (
        RUNTIME_DIR / "redis-backup.request",
        "tirosh-vitalserver-redis-backup.service",
        "redis-backup",
    ),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Dispatch guest command requests.")
    parser.parse_args()
    mount_runtime_share()
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    interval = poll_interval()
    append_log(f"status=started intervalSeconds={interval}")
    while True:
        for request_file, service, operation in REQUESTS:
            dispatch_request(request_file, service, operation)
        time.sleep(interval)


def poll_interval() -> int:
    return SETTINGS.intervals.command_poll_seconds


def append_log(message: str) -> None:
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(f"{utc_now()} {message}\n")


def dispatch_request(request_file: Path, service: str, operation: str) -> None:
    if not request_file.is_file() or service_is_running(service):
        return
    append_log(f"operation={operation} status=request-detected service={service}")
    systemctl("reset-failed", service, check=False)
    result = systemctl("start", "--no-block", service, check=False)
    status = (
        "service-scheduled"
        if result.returncode == 0
        else "service-schedule-failed"
    )
    append_log(f"operation={operation} status={status} service={service}")


if __name__ == "__main__":
    raise SystemExit(main())
