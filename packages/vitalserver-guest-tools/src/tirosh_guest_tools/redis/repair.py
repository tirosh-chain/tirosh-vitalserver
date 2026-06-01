from __future__ import annotations

import argparse

from tirosh_guest_tools.application.redis_repair import LOG_FILE, run_repair_datastore
from tirosh_guest_tools.logging import configure_logging
from tirosh_guest_tools.settings import SETTINGS


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair the Redis datastore.")
    parser.parse_args()
    configure_logging(
        SETTINGS.logging,
        log_file=LOG_FILE,
    )
    run_repair_datastore()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
