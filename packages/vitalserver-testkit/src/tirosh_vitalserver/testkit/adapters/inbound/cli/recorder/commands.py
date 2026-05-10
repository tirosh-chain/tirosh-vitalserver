"""Command handlers for Vital Recorder CLI workflows."""

from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.inbound.cli.output import (
    print_stream_summary,
    print_summary,
)
from tirosh_vitalserver.testkit.adapters.inbound.cli.recorder.scenarios import (
    parse_bed_signal_profiles,
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
from tirosh_vitalserver.testkit.application.results import StreamSummary
from tirosh_vitalserver.testkit.application.usecases import (
    assert_transfer_success,
    send_recorder_payloads,
    send_virtual_recorder_payloads,
    stream_virtual_recorder_payloads,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.visibility import (
    wait_for_recorder_visibility,
)
from tirosh_vitalserver.testkit.domain.recorder.payloads import (
    build_virtual_recorder_payloads,
    combine_virtual_recorder_rooms,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.templates import (
    build_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.signal import (
    RecorderSignalScenario,
    profile_for_scenario,
)
from tirosh_vitalserver.testkit.schemas.payloads import load_recorder_payload
from tirosh_vitalserver.testkit.types.json import JsonObject


def run_send_recorder(args: argparse.Namespace) -> int:
    """Send recorder payloads once or repeatedly and assert transfer success."""

    payload = load_recorder_payload_or_default(args.payload)

    if args.http:
        client = VitalServerClient(args.base_url, timeout=args.timeout)
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
            vrcode=args.vrcode,
            version=args.version,
        )
        summary = send_virtual_recorder_payloads(
            args.base_url,
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

    payload = load_recorder_payload_or_default(args.payload)
    virtual_payloads = build_virtual_recorder_payloads(
        payload,
        count=args.recorders,
        vrcode=args.vrcode,
        version=args.version,
    )
    duration_seconds = args.duration if args.duration > 0 else None

    try:
        summary = stream_virtual_recorder_payloads(
            args.base_url,
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
            connector=connect_socketio,
        )
    except KeyboardInterrupt:
        print("stream interrupted")
        return 130

    print_stream_summary(summary)
    assert_stream_success(summary)

    return 0


def run_verify_recorder(args: argparse.Namespace) -> int:
    """Send recorder data and poll VitalServer until rooms are visible."""

    payload = load_recorder_payload_or_default(args.payload)
    client = VitalServerClient(args.base_url, timeout=args.timeout)
    virtual_payloads = build_virtual_recorder_payloads(
        payload,
        count=args.recorders,
        vrcode=args.vrcode,
        version=args.version,
    )

    summary = send_virtual_recorder_payloads(
        args.base_url,
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


def assert_stream_success(summary: StreamSummary) -> None:
    """Raise when any recorder stream failed."""

    failed_streams = stream_failed_streams(summary)

    if failed_streams:
        raise AssertionError(
            f"{failed_streams}/{stream_total_streams(summary)} streams failed"
        )


def load_recorder_payload_or_default(path: Path | None) -> JsonObject:
    """Load a recorder payload file or build a simulated one when omitted."""

    if path is None:
        return build_simulated_recorder_payload()

    return load_recorder_payload(path)
