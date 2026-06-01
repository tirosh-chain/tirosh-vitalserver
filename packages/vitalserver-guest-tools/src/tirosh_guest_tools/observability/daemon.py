from __future__ import annotations

import argparse
import time
import traceback

from tirosh_guest_tools.observability.collectors import (
    OBSERVABILITY_DIR,
    collect_snapshot,
    utc_now,
)
from tirosh_guest_tools.observability.writer import append_jsonl, write_daemon_snapshot


def main() -> int:
    parser = argparse.ArgumentParser(description="Run guest observability daemon.")
    parser.add_argument("--interval", type=float, default=10.0)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    while True:
        try:
            write_daemon_snapshot(collect_snapshot(detail="daemon"))
        except Exception as error:
            OBSERVABILITY_DIR.mkdir(parents=True, exist_ok=True)
            message = {
                "schemaVersion": 1,
                "type": "daemon-error",
                "observedAt": utc_now(),
                "message": str(error),
                "traceback": traceback.format_exc(),
            }
            append_jsonl(OBSERVABILITY_DIR / "events.jsonl", message)
            daemon_log = OBSERVABILITY_DIR / "daemon.log"
            with daemon_log.open("a", encoding="utf-8") as handle:
                handle.write(f"{message['observedAt']} daemon-error {error}\n")
        if args.once:
            return 0
        time.sleep(max(args.interval, 1.0))


if __name__ == "__main__":
    raise SystemExit(main())
