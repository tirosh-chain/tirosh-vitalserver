"""Persistent real-time streaming use case."""

from __future__ import annotations

import threading
import time
from collections.abc import Mapping

from tirosh_vitalserver.testkit.application.ports import SocketIoConnectorPort
from tirosh_vitalserver.testkit.application.recorder_lifecycle import (
    register_vrecorder_lifecycle,
)
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeState,
)
from tirosh_vitalserver.testkit.application.results import RealtimeStreamResult
from tirosh_vitalserver.testkit.application.usecases.recorder.sender import (
    encode_realtime_payload,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.frames import (
    generate_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event
from tirosh_vitalserver.testkit.types.json import JsonValue


def stream_realtime_payload(
    base_url: str,
    payload: Mapping[str, JsonValue],
    *,
    timeout: float = 30.0,
    interval_seconds: float = 1.0,
    duration_seconds: float | None = None,
    max_messages: int | None = None,
    shift_time: bool = True,
    generate_frames: bool = False,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    stop_event: threading.Event | None = None,
    runtime_state: RecorderRuntimeState | None = None,
    connector: SocketIoConnectorPort,
) -> RealtimeStreamResult:
    """Keep one Socket.IO connection open and emit `send_data` repeatedly."""

    validate_stream_options(
        interval_seconds=interval_seconds,
        duration_seconds=duration_seconds,
        max_messages=max_messages,
    )

    started = time.perf_counter()
    messages_sent = 0
    bytes_sent = 0
    vrcode = runtime_state.vrcode if runtime_state is not None else None

    try:
        emit_testkit_event(
            "stream.starting",
            target_url=base_url,
            vrcode=vrcode,
            interval_seconds=interval_seconds,
            duration_seconds=duration_seconds,
            max_messages=max_messages,
            generate_frames=generate_frames,
        )
        client = connector(base_url, timeout=timeout)
        if runtime_state is not None:
            register_vrecorder_lifecycle(client, state=runtime_state)
        emit_testkit_event(
            "stream.connected",
            target_url=base_url,
            vrcode=vrcode,
        )

        try:
            while should_continue_stream(
                started,
                messages_sent=messages_sent,
                duration_seconds=duration_seconds,
                max_messages=max_messages,
                stop_event=stop_event,
            ):
                frame_payload = next_frame_payload(
                    payload,
                    interval_seconds=interval_seconds,
                    messages_sent=messages_sent,
                    generate_frames=generate_frames,
                    signal_profile=signal_profile,
                )
                encoded = encode_realtime_payload(
                    frame_payload,
                    shift_time=shift_time and not generate_frames,
                )
                client.emit("send_data", encoded)
                if runtime_state is not None:
                    runtime_state.record_send_data(bytes_sent=len(encoded))
                client.sleep(0.05)

                messages_sent += 1
                bytes_sent += len(encoded)

                if should_continue_stream(
                    started,
                    messages_sent=messages_sent,
                    duration_seconds=duration_seconds,
                    max_messages=max_messages,
                    stop_event=stop_event,
                ):
                    client.sleep(interval_seconds)
        finally:
            if client.connected:
                client.disconnect()
    except Exception as exc:
        emit_testkit_event(
            "stream.failed",
            target_url=base_url,
            vrcode=vrcode,
            messages_sent=messages_sent,
            bytes_sent=bytes_sent,
            elapsed_seconds=round(time.perf_counter() - started, 3),
            error=str(exc),
        )
        return RealtimeStreamResult(
            messages_sent=messages_sent,
            bytes_sent=bytes_sent,
            elapsed_seconds=time.perf_counter() - started,
            error=str(exc),
        )

    emit_testkit_event(
        "stream.completed",
        target_url=base_url,
        vrcode=vrcode,
        messages_sent=messages_sent,
        bytes_sent=bytes_sent,
        elapsed_seconds=round(time.perf_counter() - started, 3),
    )
    return RealtimeStreamResult(
        messages_sent=messages_sent,
        bytes_sent=bytes_sent,
        elapsed_seconds=time.perf_counter() - started,
    )


def validate_stream_options(
    *,
    interval_seconds: float,
    duration_seconds: float | None,
    max_messages: int | None,
) -> None:
    """Validate real-time stream loop options."""

    if interval_seconds <= 0:
        raise ValueError("interval_seconds must be greater than 0")
    if duration_seconds is not None and duration_seconds < 0:
        raise ValueError("duration_seconds must be greater than or equal to 0")
    if max_messages is not None and max_messages < 1:
        raise ValueError("max_messages must be greater than 0")


def next_frame_payload(
    payload: Mapping[str, JsonValue],
    *,
    interval_seconds: float,
    messages_sent: int,
    generate_frames: bool,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
) -> Mapping[str, JsonValue]:
    """Return the payload for the next streaming message."""

    if not generate_frames:
        return payload

    return generate_simulated_recorder_payload(
        payload,
        now=time.time(),
        frame_seconds=interval_seconds,
        sequence=messages_sent,
        signal_profile=signal_profile,
    )


def should_continue_stream(
    started: float,
    *,
    messages_sent: int,
    duration_seconds: float | None,
    max_messages: int | None,
    stop_event: threading.Event | None,
) -> bool:
    """Return whether a stream loop should emit another message."""

    if stop_event is not None and stop_event.is_set():
        return False
    if max_messages is not None and messages_sent >= max_messages:
        return False
    return not (
        duration_seconds is not None
        and time.perf_counter() - started >= duration_seconds
    )
