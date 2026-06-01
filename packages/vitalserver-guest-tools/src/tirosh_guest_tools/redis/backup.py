from __future__ import annotations

import argparse

from tirosh_guest_tools.application.redis_backup import LOG_FILE, run_redis_backup
from tirosh_guest_tools.logging import configure_logging
from tirosh_guest_tools.settings import SETTINGS


def main() -> int:
    parser = argparse.ArgumentParser(description="Back up the Redis Docker volume.")
    parser.parse_args()
    configure_logging(
        SETTINGS.logging,
        log_file=LOG_FILE,
    )
    run_redis_backup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
