"""Run the VitalServer testkit CLI with `python -m`."""

from __future__ import annotations

import argparse

from tirosh_vitalserver.testkit.adapters.inbound.cli.recorder import (
    add_recorder_parsers,
)
from tirosh_vitalserver.testkit.adapters.inbound.cli.server import add_server_parsers
from tirosh_vitalserver.testkit.adapters.inbound.cli.vital_files import (
    add_vital_file_parsers,
)


def main(argv: list[str] | None = None) -> int:
    """Parse CLI arguments and dispatch to the selected command handler."""

    parser = build_parser()
    args = parser.parse_args(argv)

    return args.command(args)


def build_parser() -> argparse.ArgumentParser:
    """Build the top-level parser and register domain command groups."""

    parser = argparse.ArgumentParser(
        prog="vitalserver-testkit",
        description="Run VitalServer health, real-time collection, and upload tests.",
    )
    parser.set_defaults(command=print_help)

    subparsers = parser.add_subparsers(dest="command_name")
    add_server_parsers(subparsers)
    add_recorder_parsers(subparsers)
    add_vital_file_parsers(subparsers)

    return parser


def print_help(args: argparse.Namespace) -> int:
    """Print top-level help when no subcommand is selected."""

    del args

    parser = build_parser()
    parser.print_help()

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
