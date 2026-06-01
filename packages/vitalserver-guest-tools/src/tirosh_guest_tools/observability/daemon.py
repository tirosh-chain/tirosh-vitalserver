from __future__ import annotations

import argparse
import time

from tirosh_guest_tools.application.observability import (
    record_daemon_error,
    write_daemon_observability_snapshot,
)
from tirosh_guest_tools.logging import configure_logging
from tirosh_guest_tools.observability.collectors import OBSERVABILITY_DIR
from tirosh_guest_tools.settings import SETTINGS


def main() -> int:
    parser = argparse.ArgumentParser(description="Run guest observability daemon.")
    parser.add_argument(
        "--interval",
        type=float,
        default=SETTINGS.intervals.observability_seconds,
    )
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    configure_logging(
        SETTINGS.logging,
        log_file=OBSERVABILITY_DIR / "daemon.log",
    )

    while True:
        try:
            write_daemon_observability_snapshot()
        except Exception as error:
            record_daemon_error(error)
        if args.once:
            return 0
        time.sleep(max(args.interval, 1.0))


if __name__ == "__main__":
    raise SystemExit(main())
