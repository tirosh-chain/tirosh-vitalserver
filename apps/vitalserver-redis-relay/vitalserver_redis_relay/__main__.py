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
    parser.add_argument(
        "--status-owner-socket",
        default=os.environ.get("REDIS_RELAY_STATUS_OWNER_SOCKET"),
    )
    args = parser.parse_args()
    status_owner_url = args.status_owner_url.strip() if args.status_owner_url else ""
    status_owner_socket = (
        Path(args.status_owner_socket)
        if args.status_owner_socket and args.status_owner_socket.strip()
        else None
    )
    if bool(status_owner_url) == (status_owner_socket is not None):
        parser.error(
            "exactly one status owner transport is required: "
            "--status-owner-url/REDIS_RELAY_STATUS_OWNER_URL or "
            "--status-owner-socket/REDIS_RELAY_STATUS_OWNER_SOCKET"
        )
    run_forever(
        config_path=Path(args.config_path),
        status_path=Path(args.status_path),
        status_owner_url=status_owner_url or None,
        status_owner_socket=status_owner_socket,
    )


if __name__ == "__main__":
    main()
