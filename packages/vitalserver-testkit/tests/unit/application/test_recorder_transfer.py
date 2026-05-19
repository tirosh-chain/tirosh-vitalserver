from __future__ import annotations

import threading
from collections.abc import Mapping

import pytest

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.application.metrics import (
    stream_failed_streams,
    stream_total_messages_sent,
    stream_total_streams,
)
from tirosh_vitalserver.testkit.application.ports import SocketIoConnectorPort
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeState,
)
from tirosh_vitalserver.testkit.application.results import RealtimeStreamResult
from tirosh_vitalserver.testkit.application.usecases.recorder import (
    transfer as recorder_transfer_module,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.stream_vrecorder import (
    stream_vrecorder_session,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.transfer import (
    stream_virtual_recorder_payloads,
)
from tirosh_vitalserver.testkit.domain.recorder import (
    build_virtual_recorder_payloads,
    iter_recorder_rooms,
)
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    RecorderSignalScenario,
    SignalProfile,
)
from tirosh_vitalserver.testkit.types.json import JsonObject, JsonValue


def test_stream_virtual_recorder_payloads_streams_each_recorder(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "BED01",
            "trks": [],
        }
    }
    virtual_payloads = build_virtual_recorder_payloads(recorder_payload, count=2)
    streamed_rooms: list[str] = []
    streamed_scenarios: list[RecorderSignalScenario] = []

    def fake_stream_realtime_payload(
        base_url: str,
        payload: Mapping[str, JsonValue],
        *,
        timeout: float = 30.0,
        interval_seconds: float = 1.0,
        duration_seconds: float | None = None,
        max_messages: int | None = None,
        shift_time: bool = True,
        generate_frames: bool = True,
        signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
        stop_event: threading.Event | None = None,
        runtime_state: RecorderRuntimeState | None = None,
        connector: SocketIoConnectorPort,
    ) -> RealtimeStreamResult:
        rooms = iter_recorder_rooms(payload)
        streamed_rooms.extend(room.room_name for room in rooms)
        streamed_scenarios.append(signal_profile.scenario)

        return RealtimeStreamResult(
            messages_sent=max_messages or 1,
            bytes_sent=123,
            elapsed_seconds=0.01,
        )

    monkeypatch.setattr(
        recorder_transfer_module,
        "stream_realtime_payload",
        fake_stream_realtime_payload,
    )

    summary = stream_virtual_recorder_payloads(
        "http://example.test",
        virtual_payloads,
        max_messages=3,
        default_signal_profile=SignalProfile(
            scenario=RecorderSignalScenario.NORMAL,
        ),
        signal_profiles={
            2: SignalProfile(
                scenario=RecorderSignalScenario.TACHYCARDIA,
                heart_rate_bpm=128.0,
            )
        },
        connector=fake_socketio_connector,
    )

    assert stream_total_streams(summary) == 2
    assert stream_total_messages_sent(summary) == 6
    assert streamed_rooms == ["BED01-001", "BED01-002"]
    assert streamed_scenarios == [
        RecorderSignalScenario.NORMAL,
        RecorderSignalScenario.TACHYCARDIA,
    ]


def test_stream_virtual_recorder_payloads_stops_peers_after_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "BED01",
            "trks": [],
        }
    }
    virtual_payloads = build_virtual_recorder_payloads(recorder_payload, count=2)
    peer_observed_stop = False

    def fake_stream_realtime_payload(
        base_url: str,
        payload: Mapping[str, JsonValue],
        *,
        timeout: float = 30.0,
        interval_seconds: float = 1.0,
        duration_seconds: float | None = None,
        max_messages: int | None = None,
        shift_time: bool = True,
        generate_frames: bool = True,
        signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
        stop_event: threading.Event | None = None,
        runtime_state: RecorderRuntimeState | None = None,
        connector: SocketIoConnectorPort,
    ) -> RealtimeStreamResult:
        nonlocal peer_observed_stop

        room_name = iter_recorder_rooms(payload)[0].room_name
        if room_name == "BED01-001":
            return RealtimeStreamResult(
                messages_sent=0,
                bytes_sent=0,
                elapsed_seconds=0.01,
                error="boom",
            )

        assert stop_event is not None
        peer_observed_stop = stop_event.wait(timeout=1)

        return RealtimeStreamResult(
            messages_sent=1,
            bytes_sent=10,
            elapsed_seconds=0.01,
        )

    monkeypatch.setattr(
        recorder_transfer_module,
        "stream_realtime_payload",
        fake_stream_realtime_payload,
    )

    summary = stream_virtual_recorder_payloads(
        "http://example.test",
        virtual_payloads,
        connector=fake_socketio_connector,
    )

    assert stream_total_streams(summary) == 2
    assert stream_failed_streams(summary) == 1
    assert peer_observed_stop


def test_stream_vrecorder_session_registers_lifecycle_by_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "BED01",
            "trks": [],
        }
    }
    virtual_payloads = build_virtual_recorder_payloads(recorder_payload, count=1)
    runtime_states: list[RecorderRuntimeState | None] = []

    def fake_stream_realtime_payload(
        base_url: str,
        payload: Mapping[str, JsonValue],
        *,
        timeout: float = 30.0,
        interval_seconds: float = 1.0,
        duration_seconds: float | None = None,
        max_messages: int | None = None,
        shift_time: bool = True,
        generate_frames: bool = True,
        signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
        stop_event: threading.Event | None = None,
        runtime_state: RecorderRuntimeState | None = None,
        connector: SocketIoConnectorPort,
    ) -> RealtimeStreamResult:
        runtime_states.append(runtime_state)

        return RealtimeStreamResult(
            messages_sent=1,
            bytes_sent=10,
            elapsed_seconds=0.01,
        )

    monkeypatch.setattr(
        recorder_transfer_module,
        "stream_realtime_payload",
        fake_stream_realtime_payload,
    )

    summary = stream_vrecorder_session(
        "http://example.test",
        virtual_payloads,
        connector=fake_socketio_connector,
    )

    assert stream_total_streams(summary) == 1
    assert runtime_states
    assert runtime_states[0] is not None
