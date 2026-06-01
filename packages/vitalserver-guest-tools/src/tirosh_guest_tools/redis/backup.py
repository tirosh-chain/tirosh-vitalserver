from __future__ import annotations

import argparse

from tirosh_guest_tools.application.redis_backup import run_redis_backup


def main() -> int:
    parser = argparse.ArgumentParser(description="Back up the Redis Docker volume.")
    parser.parse_args()
    run_redis_backup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
