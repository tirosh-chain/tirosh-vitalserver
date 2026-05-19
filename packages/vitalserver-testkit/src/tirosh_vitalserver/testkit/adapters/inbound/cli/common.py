"""Shared CLI argument groups."""

from __future__ import annotations

import argparse


def add_common_server_args(parser: argparse.ArgumentParser) -> None:
    """Add VitalServer connection options shared by every command."""

    parser.add_argument(
        "--vitalserver-url",
        default="http://localhost",
        help="VitalServer base URL",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=60.0,
        help="HTTP timeout seconds",
    )


def add_load_args(parser: argparse.ArgumentParser) -> None:
    """Add request volume and failure-threshold options for load commands."""

    parser.add_argument(
        "--concurrency",
        type=int,
        default=1,
        help="Concurrent requests",
    )
    parser.add_argument("--repeat", type=int, default=1, help="Total requests to send")
    parser.add_argument(
        "--max-failure-rate",
        type=float,
        default=0.0,
        help="Allowed failure rate between 0 and 1",
    )
