from __future__ import annotations

import time

from tirosh_guest_tools.adapters.outbound.observability.collectors import (
    OBSERVABILITY_DIR,
)
from tirosh_guest_tools.application.observability import (
    record_daemon_error,
    write_daemon_observability_snapshot,
)
from tirosh_guest_tools.infrastructure.logging import configure_logging
from tirosh_guest_tools.infrastructure.settings import SETTINGS


def run_observability_daemon(
    *,
    interval_seconds: float = SETTINGS.intervals.observability_seconds,
    once: bool = False,
) -> None:
    configure_logging(
        SETTINGS.logging,
        log_file=OBSERVABILITY_DIR / "daemon.log",
    )

    while True:
        try:
            write_daemon_observability_snapshot()
        except Exception as error:
            record_daemon_error(error)
        if once:
            return
        time.sleep(max(interval_seconds, 1.0))
