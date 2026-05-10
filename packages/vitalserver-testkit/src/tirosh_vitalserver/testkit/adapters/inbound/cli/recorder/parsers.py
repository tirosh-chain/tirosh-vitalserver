"""Argument parser registration for Vital Recorder CLI workflows."""

from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.inbound.cli.common import (
    add_common_server_args,
    add_load_args,
)
from tirosh_vitalserver.testkit.adapters.inbound.cli.recorder.commands import (
    run_send_recorder,
    run_stream_recorder,
    run_verify_recorder,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario


def add_recorder_parsers(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register all Vital Recorder real-time collection commands."""

    add_send_recorder_parser(subparsers)
    add_stream_recorder_parser(subparsers)
    add_verify_recorder_parser(subparsers)


def add_send_recorder_parser(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register the command that sends finite recorder payload batches."""

    parser = subparsers.add_parser(
        "send-recorder",
        help="Send Vital Recorder-style payloads through Socket.IO send_data",
    )

    add_common_server_args(parser)
    add_load_args(parser)

    add_optional_recorder_payload_arg(parser)
    add_common_recorder_args(parser)
    parser.add_argument(
        "--http",
        action="store_true",
        help="Use legacy HTTP JSON probing instead of Socket.IO send_data",
    )
    parser.add_argument(
        "--endpoint",
        default="/api/send",
        help="HTTP endpoint used only with --http",
    )
    parser.add_argument(
        "--no-shift-time",
        action="store_true",
        help="Do not shift dt* timestamp fields before each request",
    )

    parser.set_defaults(command=run_send_recorder)


def add_stream_recorder_parser(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register the command that continuously streams recorder payloads."""

    parser = subparsers.add_parser(
        "stream-recorder",
        help="Continuously stream recorder payloads through Socket.IO send_data",
    )

    add_common_server_args(parser)

    add_optional_recorder_payload_arg(parser)
    add_common_recorder_args(parser)
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Seconds between send_data events per recorder",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=0.0,
        help="Seconds to stream. Use 0 to stream until interrupted",
    )
    parser.add_argument(
        "--max-messages",
        type=int,
        default=None,
        help="Max messages per recorder before stopping",
    )
    parser.add_argument(
        "--no-shift-time",
        action="store_true",
        help="Do not shift dt* timestamp fields before each send",
    )
    parser.add_argument(
        "--replay-sample",
        action="store_true",
        help="Replay the sample payload instead of generating live frames",
    )
    parser.add_argument(
        "--default-scenario",
        choices=[scenario.value for scenario in RecorderSignalScenario],
        default=RecorderSignalScenario.NORMAL.value,
        help="Default simulated signal scenario for all beds",
    )
    parser.add_argument(
        "--bed-scenario",
        action="append",
        default=[],
        metavar="INDEX=SCENARIO",
        help="Override one 1-based bed index with a signal scenario",
    )

    parser.set_defaults(command=run_stream_recorder)


def add_verify_recorder_parser(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register the command that verifies recorder data is UI-visible."""

    parser = subparsers.add_parser(
        "verify-recorder",
        help="Send one recorder payload and verify it is visible to VitalServer",
    )

    add_common_server_args(parser)

    add_optional_recorder_payload_arg(parser)
    add_common_recorder_args(parser)
    parser.add_argument(
        "--admin-user-id",
        default="admin",
        help="Admin user id used by VitalServer to derive bed ids",
    )
    parser.add_argument(
        "--wait",
        type=float,
        default=10.0,
        help="Max seconds to wait for UI-visible device metadata",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=0.5,
        help="Visibility polling interval seconds",
    )
    parser.add_argument(
        "--no-shift-time",
        action="store_true",
        help="Do not shift dt* timestamp fields before sending",
    )

    parser.set_defaults(command=run_verify_recorder)


def add_common_recorder_args(arg_parser: argparse.ArgumentParser) -> None:
    """Add recorder identity and fan-out arguments."""

    arg_parser.add_argument(
        "--vrcode",
        default=None,
        help="Recorder code. Defaults to the only top-level key in the payload.",
    )
    arg_parser.add_argument(
        "--version",
        default="testkit",
        help="Recorder version value sent as `ver`",
    )
    arg_parser.add_argument(
        "--recorders",
        type=int,
        default=1,
        help="Number of virtual recorder machines",
    )


def add_optional_recorder_payload_arg(arg_parser: argparse.ArgumentParser) -> None:
    """Add the optional external recorder payload argument to a command parser."""

    arg_parser.add_argument(
        "payload",
        nargs="?",
        type=Path,
        default=None,
        help="Recorder JSON payload path. Omit to generate simulated recorder data.",
    )
