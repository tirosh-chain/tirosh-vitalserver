"""Single-message real-time send use case."""

from __future__ import annotations

import json
import time
import zlib
from collections.abc import Mapping

from tirosh_vitalserver.testkit.application.ports import SendDataEmitterPort
from tirosh_vitalserver.testkit.application.results import RealtimeSendResult
from tirosh_vitalserver.testkit.domain.recorder.payloads import (
    build_realtime_message,
    shift_recorder_payload_time,
)
from tirosh_vitalserver.testkit.types.json import JsonValue


def encode_realtime_payload(
    payload: Mapping[str, JsonValue],
    *,
    vrcode: str | None = None,
    version: str = "testkit",
    shift_time: bool = True,
) -> bytes:
    """Return zlib-compressed bytes for Socket.IO `send_data`."""

    request_payload = (
        shift_recorder_payload_time(payload) if shift_time else dict(payload)
    )
    message = build_realtime_message(
        request_payload,
        vrcode=vrcode,
        version=version,
    )
    body = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )

    return zlib.compress(body)


def send_realtime_payload(
    base_url: str,
    payload: Mapping[str, JsonValue],
    *,
    attempt: int = 0,
    timeout: float = 30.0,
    vrcode: str | None = None,
    version: str = "testkit",
    shift_time: bool = True,
    emitter: SendDataEmitterPort,
) -> RealtimeSendResult:
    """Connect to VitalServer Socket.IO and emit one `send_data` event."""

    started = time.perf_counter()
    encoded = encode_realtime_payload(
        payload,
        vrcode=vrcode,
        version=version,
        shift_time=shift_time,
    )

    try:
        emitter(base_url, encoded, timeout=timeout)
    except Exception as exc:
        return RealtimeSendResult(
            bytes_sent=len(encoded),
            attempt=attempt,
            elapsed_seconds=time.perf_counter() - started,
            error=str(exc),
        )

    return RealtimeSendResult(
        bytes_sent=len(encoded),
        attempt=attempt,
        elapsed_seconds=time.perf_counter() - started,
    )
