from __future__ import annotations

import argparse

from tirosh_guest_tools.application.redis_repair import run_repair_datastore


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair the Redis datastore.")
    parser.parse_args()
    run_repair_datastore()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
