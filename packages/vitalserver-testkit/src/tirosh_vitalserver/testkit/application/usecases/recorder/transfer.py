"""Use cases for sending Vital Recorder data to VitalServer."""

from __future__ import annotations

import time
from collections.abc import Iterable, Mapping
from concurrent.futures import (
    FIRST_COMPLETED,
    Future,
    ThreadPoolExecutor,
    as_completed,
    wait,
)
from threading import Event

from tirosh_vitalserver.testkit.application.ports import (
    SendDataEmitterPort,
    SocketIoConnectorPort,
    VitalServerPort,
)
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeRegistry,
)
from tirosh_vitalserver.testkit.application.results import (
    RealtimeSendResult,
    RealtimeStreamResult,
    RecorderSendResult,
    StreamSummary,
    TransferSummary,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.sender import (
    send_realtime_payload,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.stream_loop import (
    stream_realtime_payload,
)
from tirosh_vitalserver.testkit.domain.recorder.models import VirtualRecorderPayload
from tirosh_vitalserver.testkit.domain.recorder.payloads import (
    recorder_payload_size_bytes,
    shift_recorder_payload_time,
)
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
)
from tirosh_vitalserver.testkit.schemas.http import HttpResponse
from tirosh_vitalserver.testkit.types.json import JsonValue


def send_realtime_payloads(
    base_url: str,
    payload: Mapping[str, JsonValue],
    *,
    timeout: float = 30.0,
    concurrency: int = 1,
    repeat: int = 1,
    vrcode: str | None = None,
    version: str = "testkit",
    shift_time: bool = True,
    emitter: SendDataEmitterPort,
) -> TransferSummary:
    """Send Vital Recorder real-time payloads through Socket.IO."""

    if concurrency < 1:
        raise ValueError("concurrency must be greater than 0")
    if repeat < 1:
        raise ValueError("repeat must be greater than 0")

    started = time.perf_counter()

    results: list[RealtimeSendResult] = []

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [
            executor.submit(
                send_realtime_payload,
                base_url,
                payload,
                attempt=attempt,
                timeout=timeout,
                vrcode=vrcode,
                version=version,
                shift_time=shift_time,
                emitter=emitter,
            )
            for attempt in range(repeat)
        ]

        for future in as_completed(futures):
            results.append(future.result())

    elapsed = time.perf_counter() - started

    return TransferSummary(results=tuple(results), elapsed_seconds=elapsed)


def send_virtual_recorder_payloads(
    base_url: str,
    payloads: Iterable[VirtualRecorderPayload],
    *,
    timeout: float = 30.0,
    concurrency: int = 1,
    repeat: int = 1,
    shift_time: bool = True,
    emitter: SendDataEmitterPort,
) -> TransferSummary:
    """Send distinct virtual recorder payloads through Socket.IO."""

    payload_list = tuple(payloads)
    if not payload_list:
        raise ValueError("at least one recorder payload is required")
    if concurrency < 1:
        raise ValueError("concurrency must be greater than 0")
    if repeat < 1:
        raise ValueError("repeat must be greater than 0")

    started = time.perf_counter()

    results: list[RealtimeSendResult] = []
    jobs = [
        (payload, attempt)
        for attempt in range(repeat)
        for payload in payload_list
    ]

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [
            executor.submit(
                send_realtime_payload,
                base_url,
                payload.payload,
                attempt=attempt,
                timeout=timeout,
                shift_time=shift_time,
                emitter=emitter,
            )
            for payload, attempt in jobs
        ]

        for future in as_completed(futures):
            results.append(future.result())

    elapsed = time.perf_counter() - started

    return TransferSummary(results=tuple(results), elapsed_seconds=elapsed)


def stream_virtual_recorder_payloads(
    base_url: str,
    payloads: Iterable[VirtualRecorderPayload],
    *,
    timeout: float = 30.0,
    interval_seconds: float = 1.0,
    duration_seconds: float | None = None,
    max_messages: int | None = None,
    shift_time: bool = True,
    generate_frames: bool = True,
    default_signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_profiles: Mapping[int, SignalProfile] | None = None,
    runtime_registry: RecorderRuntimeRegistry | None = None,
    connector: SocketIoConnectorPort,
) -> StreamSummary:
    """Stream distinct virtual recorder payloads through persistent Socket.IO."""

    payload_list = tuple(payloads)
    if not payload_list:
        raise ValueError("at least one recorder payload is required")

    started = time.perf_counter()
    stop_event = Event()

    with ThreadPoolExecutor(max_workers=len(payload_list)) as executor:
        futures = [
            executor.submit(
                stream_realtime_payload,
                base_url,
                payload.payload,
                timeout=timeout,
                interval_seconds=interval_seconds,
                duration_seconds=duration_seconds,
                max_messages=max_messages,
                shift_time=shift_time,
                generate_frames=generate_frames,
                signal_profile=signal_profile_for_index(
                    index,
                    default_signal_profile=default_signal_profile,
                    signal_profiles=signal_profiles,
                ),
                stop_event=stop_event,
                runtime_state=(
                    runtime_registry.state_for(
                        vrcode=payload.vrcode,
                        base_url=base_url,
                    )
                    if runtime_registry is not None
                    else None
                ),
                connector=connector,
            )
            for index, payload in enumerate(payload_list, start=1)
        ]

        try:
            results = collect_stream_results(futures, stop_event=stop_event)
        except KeyboardInterrupt:
            stop_event.set()
            results = [future.result() for future in futures]

    elapsed = time.perf_counter() - started

    return StreamSummary(results=tuple(results), elapsed_seconds=elapsed)


def collect_stream_results(
    futures: Iterable[Future[RealtimeStreamResult]],
    *,
    stop_event: Event,
) -> list[RealtimeStreamResult]:
    """Collect stream results and stop peer streams after the first failure."""

    pending = set(futures)
    results: list[RealtimeStreamResult] = []

    while pending:
        done, pending = wait(pending, return_when=FIRST_COMPLETED)

        for future in done:
            result = future.result()
            results.append(result)

            if result.error:
                stop_event.set()

    return results


def signal_profile_for_index(
    index: int,
    *,
    default_signal_profile: SignalProfile,
    signal_profiles: Mapping[int, SignalProfile] | None,
) -> SignalProfile:
    """Return the signal profile for a 1-based virtual recorder index."""

    if signal_profiles is None:
        return default_signal_profile

    return signal_profiles.get(index, default_signal_profile)


def send_recorder_payloads(
    client: VitalServerPort,
    payload: Mapping[str, JsonValue],
    *,
    concurrency: int = 1,
    repeat: int = 1,
    endpoint: str = "/api/send",
    shift_time: bool = True,
) -> TransferSummary:
    """Send a JSON payload over HTTP.

    This is kept for probing HTTP endpoints. Upstream VitalServer real-time
    collection uses Socket.IO `send_data`; use `send_realtime_payloads()` for
    recorder-style load tests.
    """

    if concurrency < 1:
        raise ValueError("concurrency must be greater than 0")
    if repeat < 1:
        raise ValueError("repeat must be greater than 0")

    started = time.perf_counter()

    results: list[RecorderSendResult] = []

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [
            executor.submit(
                _send_recorder_one, client, payload, endpoint, attempt, shift_time
            )
            for attempt in range(repeat)
        ]

        for future in as_completed(futures):
            results.append(future.result())

    elapsed = time.perf_counter() - started

    return TransferSummary(results=tuple(results), elapsed_seconds=elapsed)


def _send_recorder_one(
    client: VitalServerPort,
    payload: Mapping[str, JsonValue],
    endpoint: str,
    attempt: int,
    shift_time: bool,
) -> RecorderSendResult:
    request_payload = (
        shift_recorder_payload_time(payload) if shift_time else dict(payload)
    )
    bytes_sent = recorder_payload_size_bytes(request_payload)

    try:
        response = client.send_recorder_payload(request_payload, endpoint=endpoint)

        return RecorderSendResult(
            bytes_sent=bytes_sent, response=response, attempt=attempt
        )
    except Exception as exc:
        response = HttpResponse(
            status_code=0, headers={}, body=b"", elapsed_seconds=0.0
        )

        return RecorderSendResult(
            bytes_sent=bytes_sent,
            response=response,
            attempt=attempt,
            error=str(exc),
        )
