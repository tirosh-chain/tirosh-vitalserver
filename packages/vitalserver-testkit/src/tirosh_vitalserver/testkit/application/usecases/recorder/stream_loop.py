"""Persistent real-time streaming use case."""

from __future__ import annotations

import threading
import time
from collections.abc import Mapping

from tirosh_vitalserver.testkit.application.ports import (
    SocketIoClientPort,
    SocketIoConnectorPort,
)
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
from tirosh_vitalserver.testkit.domain.recorder import (
    DEFAULT_RECORDER_FRAME_POST_POLICY,
    RecorderFramePostPolicy,
    RecorderFrameRequest,
    RecorderFrameSource,
    RecorderFrameSourceKind,
    apply_recorder_frame_post_policy,
    materialize_recorder_frame,
    recorder_frame_source_uses_current_time,
)
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
    SignalQualityProfile,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event
from tirosh_vitalserver.testkit.types.json import JsonValue


def stream_realtime_payload(
    base_url: str,
    frame_source: RecorderFrameSource | Mapping[str, JsonValue],
    *,
    timeout: float = 30.0,
    interval_seconds: float = 1.0,
    duration_seconds: float | None = None,
    max_messages: int | None = None,
    shift_time: bool = True,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
    frame_post_policy: RecorderFramePostPolicy = DEFAULT_RECORDER_FRAME_POST_POLICY,
    stop_event: threading.Event | None = None,
    pause_event: threading.Event | None = None,
    runtime_state: RecorderRuntimeState | None = None,
    connector: SocketIoConnectorPort,
    disconnected_timeout_seconds: float = 5.0,
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
    source = normalize_frame_source(
        frame_source,
        signal_profile=signal_profile,
        signal_quality=signal_quality,
    )

    try:
        emit_testkit_event(
            "stream.starting",
            target_url=base_url,
            vrcode=vrcode,
            interval_seconds=interval_seconds,
            duration_seconds=duration_seconds,
            max_messages=max_messages,
            frame_source=source.kind.value,
        )
        client = connector(base_url, timeout=timeout)
        if runtime_state is not None:
            register_vrecorder_lifecycle(client, state=runtime_state)
        emit_testkit_event(
            "stream.connected",
            target_url=base_url,
            vrcode=vrcode,
        )
        frame_started_at = time.time()

        try:
            while should_continue_stream(
                started,
                messages_sent=messages_sent,
                duration_seconds=duration_seconds,
                max_messages=max_messages,
                stop_event=stop_event,
            ):
                while stream_is_paused(pause_event) and should_continue_stream(
                    started,
                    messages_sent=messages_sent,
                    duration_seconds=duration_seconds,
                    max_messages=max_messages,
                    stop_event=stop_event,
                ):
                    time.sleep(0.2)

                if not should_continue_stream(
                    started,
                    messages_sent=messages_sent,
                    duration_seconds=duration_seconds,
                    max_messages=max_messages,
                    stop_event=stop_event,
                ):
                    break

                frame_payload = next_frame_payload(
                    source,
                    interval_seconds=interval_seconds,
                    messages_sent=messages_sent,
                    now=frame_started_at + messages_sent * interval_seconds,
                    frame_post_policy=frame_post_policy,
                )
                encoded = encode_realtime_payload(
                    frame_payload,
                    shift_time=shift_time
                    and not recorder_frame_source_uses_current_time(source),
                )
                wait_until_stream_connected(
                    client,
                    timeout_seconds=disconnected_timeout_seconds,
                    stop_event=stop_event,
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
    frame_source: RecorderFrameSource,
    *,
    interval_seconds: float,
    messages_sent: int,
    now: float | None = None,
    frame_post_policy: RecorderFramePostPolicy = DEFAULT_RECORDER_FRAME_POST_POLICY,
) -> Mapping[str, JsonValue]:
    """Return the payload for the next streaming message."""

    frame_now = time.time() if now is None else now
    frame = materialize_recorder_frame(
        frame_source,
        RecorderFrameRequest(
            sequence=messages_sent,
            now=frame_now,
            frame_seconds=interval_seconds,
        ),
    )
    return apply_recorder_frame_post_policy(frame, frame_post_policy)


def normalize_frame_source(
    frame_source: RecorderFrameSource | Mapping[str, JsonValue],
    *,
    signal_profile: SignalProfile,
    signal_quality: SignalQualityProfile,
) -> RecorderFrameSource:
    """Return an explicit frame source for legacy static payload callers."""

    if isinstance(frame_source, RecorderFrameSource):
        return frame_source

    return RecorderFrameSource(
        kind=RecorderFrameSourceKind.STATIC,
        payload=frame_source,
        signal_profile=signal_profile,
        signal_quality=signal_quality,
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


def stream_is_paused(pause_event: threading.Event | None) -> bool:
    """Return whether the stream loop should keep the connection idle."""

    return pause_event is not None and pause_event.is_set()


def wait_until_stream_connected(
    client: SocketIoClientPort,
    *,
    timeout_seconds: float,
    stop_event: threading.Event | None,
) -> None:
    """Wait for a reconnect-capable Socket.IO client before sending data."""

    if client.connected:
        return
    if timeout_seconds < 0:
        raise ValueError("timeout_seconds must be greater than or equal to 0")

    started = time.perf_counter()
    while not client.connected:
        if stop_event is not None and stop_event.is_set():
            raise RuntimeError("stream stopped while Socket.IO was disconnected")
        if time.perf_counter() - started >= timeout_seconds:
            raise RuntimeError("Socket.IO disconnected before send_data")
        client.sleep(min(0.2, max(timeout_seconds, 0.01)))
