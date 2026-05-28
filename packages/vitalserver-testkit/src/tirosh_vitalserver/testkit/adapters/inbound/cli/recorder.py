"""Vital Recorder command-line workflows."""

from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.inbound.cli.common import (
    add_common_server_args,
    add_load_args,
)
from tirosh_vitalserver.testkit.adapters.inbound.cli.output import (
    print_stream_summary,
    print_summary,
)
from tirosh_vitalserver.testkit.adapters.inbound.http.recorder_status import (
    RecorderStatusServer,
)
from tirosh_vitalserver.testkit.adapters.outbound.recorder import (
    connect_socketio,
    emit_send_data,
)
from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.metrics import (
    stream_failed_streams,
    stream_total_streams,
)
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeRegistry,
)
from tirosh_vitalserver.testkit.application.results import StreamSummary
from tirosh_vitalserver.testkit.application.usecases import (
    assert_transfer_success,
    send_recorder_payloads,
    send_virtual_recorder_payloads,
    stream_vrecorder_session,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.visibility import (
    wait_for_recorder_visibility,
)
from tirosh_vitalserver.testkit.domain.bed import beds_for_room_names
from tirosh_vitalserver.testkit.domain.recorder.payloads import (
    build_virtual_recorder_payloads,
    combine_virtual_recorder_rooms,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.templates import (
    build_simulated_recorder_payload,
    unique_testkit_vrcode,
)
from tirosh_vitalserver.testkit.domain.signal import (
    RecorderSignalScenario,
    SignalProfile,
    profile_for_scenario,
)
from tirosh_vitalserver.testkit.schemas.payloads import load_recorder_payload
from tirosh_vitalserver.testkit.types.json import JsonObject


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
        help="Send one-shot recorder payloads without join_vr lifecycle",
        description=(
            "Send finite one-shot recorder payloads. This command does not run "
            "the VRecorder join_vr lifecycle; use stream-recorder for lifecycle "
            "and management-event checks."
        ),
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
        help="Run VRecorder-style join_vr lifecycle and stream send_data",
        description=(
            "Run VRecorder-style lifecycle checks: connect to Socket.IO, emit "
            "join_vr, receive dt and management events, and stream send_data."
        ),
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
        type=parse_bed_signal_profile,
        metavar="INDEX=SCENARIO",
        help="Override one 1-based bed index with a signal scenario",
    )
    parser.add_argument(
        "--status-page",
        action="store_true",
        help="Serve a simple VRecorder status page for Network Settings checks",
    )
    parser.add_argument(
        "--status-host",
        default="0.0.0.0",
        help="Host/interface for the VRecorder status page",
    )
    parser.add_argument(
        "--status-port",
        type=int,
        default=80,
        help="Port for the VRecorder status page. Use 80 for Network Settings",
    )

    parser.set_defaults(command=run_stream_recorder)


def add_verify_recorder_parser(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register the command that verifies recorder data is UI-visible."""

    parser = subparsers.add_parser(
        "verify-recorder",
        help="Send one-shot recorder data and verify UI-visible metadata",
        description=(
            "Send one-shot recorder data and poll VitalServer metadata. This "
            "does not run the VRecorder join_vr lifecycle; use stream-recorder "
            "for lifecycle and Network Settings checks."
        ),
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


def run_send_recorder(args: argparse.Namespace) -> int:
    """Send recorder payloads once or repeatedly and assert transfer success."""

    payload = load_recorder_payload_or_default(
        args.payload,
        bed_room_names=tuple(args.bed_room_name),
    )
    vrcode = selected_vrcode(args.payload, args.vrcode)

    if args.http:
        client = VitalServerClient(args.vitalserver_url, timeout=args.timeout)
        summary = send_recorder_payloads(
            client,
            payload,
            concurrency=args.concurrency,
            repeat=args.repeat,
            endpoint=args.endpoint,
            shift_time=not args.no_shift_time,
        )
    else:
        virtual_payloads = build_virtual_recorder_payloads(
            payload,
            count=args.recorders,
            vrcode=vrcode,
            version=args.version,
        )
        summary = send_virtual_recorder_payloads(
            args.vitalserver_url,
            virtual_payloads,
            timeout=args.timeout,
            concurrency=args.concurrency,
            repeat=args.repeat,
            shift_time=not args.no_shift_time,
            emitter=emit_send_data,
        )

    print_summary(summary)
    assert_transfer_success(summary, max_failure_rate=args.max_failure_rate)

    return 0


def run_stream_recorder(args: argparse.Namespace) -> int:
    """Stream recorder payloads until duration, message limit, or interrupt."""

    payload = load_recorder_payload_or_default(
        args.payload,
        bed_room_names=tuple(args.bed_room_name),
    )
    vrcode = selected_vrcode(args.payload, args.vrcode)
    virtual_payloads = build_virtual_recorder_payloads(
        payload,
        count=args.recorders,
        vrcode=vrcode,
        version=args.version,
    )
    duration_seconds = args.duration if args.duration > 0 else None
    runtime_registry = RecorderRuntimeRegistry()
    status_server = build_optional_status_server(args, registry=runtime_registry)

    if status_server is not None:
        status_server.start()
        print(f"status_page: {status_server.url}")

    try:
        summary = stream_vrecorder_session(
            args.vitalserver_url,
            virtual_payloads,
            timeout=args.timeout,
            interval_seconds=args.interval,
            duration_seconds=duration_seconds,
            max_messages=args.max_messages,
            shift_time=not args.no_shift_time,
            generate_frames=not args.replay_sample,
            default_signal_profile=profile_for_scenario(
                RecorderSignalScenario(args.default_scenario),
            ),
            signal_profiles=parse_bed_signal_profiles(args.bed_scenario),
            runtime_registry=runtime_registry,
            connector=connect_socketio,
        )
    except KeyboardInterrupt:
        print("stream interrupted")
        return 130
    finally:
        if status_server is not None:
            status_server.stop()

    print_stream_summary(summary)
    assert_stream_success(summary)

    return 0


def run_verify_recorder(args: argparse.Namespace) -> int:
    """Send recorder data and poll VitalServer until rooms are visible."""

    payload = load_recorder_payload_or_default(
        args.payload,
        bed_room_names=tuple(args.bed_room_name),
    )
    vrcode = selected_vrcode(args.payload, args.vrcode)
    client = VitalServerClient(args.vitalserver_url, timeout=args.timeout)
    virtual_payloads = build_virtual_recorder_payloads(
        payload,
        count=args.recorders,
        vrcode=vrcode,
        version=args.version,
    )

    summary = send_virtual_recorder_payloads(
        args.vitalserver_url,
        virtual_payloads,
        timeout=args.timeout,
        concurrency=1,
        repeat=1,
        shift_time=not args.no_shift_time,
        emitter=emit_send_data,
    )
    assert_transfer_success(summary, max_failure_rate=0.0)

    visibility_payload = combine_virtual_recorder_rooms(
        virtual_payloads,
        version=args.version,
    )
    visibility_results = wait_for_recorder_visibility(
        client,
        visibility_payload,
        admin_user_id=args.admin_user_id,
        timeout_seconds=args.wait,
        interval_seconds=args.interval,
    )

    print_summary(summary)
    print(f"visible_rooms: {len(visibility_results)}")

    for result in visibility_results:
        print(
            "visible: "
            f"room={result.room.room_name} "
            f"bed_id={result.room.bed_id} "
            f"bytes={len(result.response.body)}"
        )

    return 0


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
    arg_parser.add_argument(
        "--bed-room-name",
        action="append",
        default=[],
        help="Existing bed room name to connect to. Repeat to connect multiple beds",
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


def assert_stream_success(summary: StreamSummary) -> None:
    """Raise when any recorder stream failed."""

    failed_streams = stream_failed_streams(summary)

    if failed_streams:
        raise AssertionError(
            f"{failed_streams}/{stream_total_streams(summary)} streams failed"
        )


def build_optional_status_server(
    args: argparse.Namespace,
    *,
    registry: RecorderRuntimeRegistry,
) -> RecorderStatusServer | None:
    """Build a recorder status server when requested."""

    if not args.status_page:
        return None

    return RecorderStatusServer(
        host=args.status_host,
        port=args.status_port,
        registry=registry,
    )


def parse_bed_signal_profiles(
    values: list[tuple[int, SignalProfile]],
) -> dict[int, SignalProfile]:
    """Convert parsed bed scenario options into a profile mapping."""

    return dict(values)


def parse_bed_signal_profile(value: str) -> tuple[int, SignalProfile]:
    """Parse one `INDEX=SCENARIO` CLI value."""

    index_text, separator, scenario_text = value.partition("=")
    if not separator:
        raise argparse.ArgumentTypeError(
            f"bed scenario must be INDEX=SCENARIO: {value}"
        )

    index = parse_bed_index(index_text)
    scenario = parse_recorder_signal_scenario(scenario_text)

    return index, profile_for_scenario(scenario)


def parse_bed_index(value: str) -> int:
    """Parse a 1-based bed index from CLI text."""

    try:
        index = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"bed scenario index must be an integer: {value}"
        ) from exc

    if index < 1:
        raise argparse.ArgumentTypeError(
            f"bed scenario index must be greater than 0: {index}"
        )

    return index


def parse_recorder_signal_scenario(value: str) -> RecorderSignalScenario:
    """Parse a signal scenario name from CLI text."""

    try:
        return RecorderSignalScenario(value)
    except ValueError as exc:
        allowed = ", ".join(scenario.value for scenario in RecorderSignalScenario)
        raise argparse.ArgumentTypeError(
            f"unknown signal scenario: {value}. allowed: {allowed}"
        ) from exc


def load_recorder_payload_or_default(
    path: Path | None,
    *,
    bed_room_names: tuple[str, ...] = (),
) -> JsonObject:
    """Load a recorder payload file or build a simulated one when omitted."""

    if path is None:
        if not bed_room_names:
            raise ValueError("bed room names are required when payload is omitted")

        bed_registry = beds_for_room_names(bed_room_names)
        return build_simulated_recorder_payload(
            room_names=tuple(bed.room_name for bed in bed_registry),
        )

    return load_recorder_payload(path)


def selected_vrcode(path: Path | None, requested_vrcode: str | None) -> str | None:
    """Return a fresh default vrcode only for generated testkit payloads."""

    if requested_vrcode is not None or path is not None:
        return requested_vrcode

    return unique_testkit_vrcode()
