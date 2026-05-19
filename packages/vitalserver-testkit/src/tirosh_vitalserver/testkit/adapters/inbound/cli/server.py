"""VitalServer lifecycle CLI commands."""

from __future__ import annotations

import argparse

from tirosh_vitalserver.testkit.adapters.inbound.cli.common import (
    add_common_server_args,
)
from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.usecases import wait_for_server


def add_server_parsers(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register VitalServer lifecycle and readiness commands."""

    parser = subparsers.add_parser(
        "health",
        help="Wait for VitalServer health endpoint",
    )

    add_common_server_args(parser)

    parser.add_argument("--path", default="/check", help="Health endpoint path")
    parser.add_argument("--wait", type=float, default=60.0, help="Max seconds to wait")
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Polling interval seconds",
    )

    parser.set_defaults(command=run_health)


def run_health(args: argparse.Namespace) -> int:
    """Wait until the configured VitalServer health endpoint responds."""

    client = VitalServerClient(args.vitalserver_url, timeout=args.timeout)

    wait_for_server(
        client,
        path=args.path,
        timeout_seconds=args.wait,
        interval_seconds=args.interval,
    )

    print(f"VitalServer is ready: {args.vitalserver_url}{args.path}")

    return 0
