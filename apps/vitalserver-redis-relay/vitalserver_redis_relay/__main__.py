from __future__ import annotations

import argparse
import os
from pathlib import Path

from .relay_loop import run_forever


def main() -> None:
    parser = argparse.ArgumentParser(description="VitalServer Redis relay")
    parser.add_argument(
        "--config-path",
        default=os.environ.get(
            "REDIS_RELAY_CONFIG_PATH",
            "/run/tirosh/config/redis-relay.toml",
        ),
    )
    parser.add_argument(
        "--status-path",
        default=os.environ.get(
            "REDIS_RELAY_STATUS_PATH",
            "/run/tirosh/status/redis-relay-status.json",
        ),
    )
    parser.add_argument(
        "--status-owner-url",
        default=os.environ.get("REDIS_RELAY_STATUS_OWNER_URL"),
    )
    args = parser.parse_args()
    run_forever(
        config_path=Path(args.config_path),
        status_path=Path(args.status_path),
        status_owner_url=args.status_owner_url,
    )


if __name__ == "__main__":
    main()
