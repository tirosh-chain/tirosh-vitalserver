from __future__ import annotations

import json
import zlib

from tests.support import FakeSocketIoClient
from tirosh_vitalserver.testkit.application.recorder_lifecycle import (
    MANAGEMENT_EVENTS,
    register_vrecorder_lifecycle,
)
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeState,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.stream_loop import (
    stream_realtime_payload,
)
from tirosh_vitalserver.testkit.domain.recorder import (
    RecorderFrameSource,
    RecorderFrameSourceKind,
)
from tirosh_vitalserver.testkit.types.json import JsonObject


def test_register_vrecorder_lifecycle_emits_join_and_records_events() -> None:
    client = FakeSocketIoClient()
    state = RecorderRuntimeState(
        vrcode="VR_TEST",
        base_url="http://example.test",
        local_ip="192.0.2.10",
    )

    register_vrecorder_lifecycle(client, state=state)
    client.handlers["dt"](1710000000)
    client.handlers["restart"]({"reason": "test"})

    snapshot = state.snapshot()

    assert client.emitted[0] == ("join_vr", "VR_TEST")
    assert snapshot.connected
    assert snapshot.join_sent
    assert snapshot.server_dt == 1710000000
    assert snapshot.management_events[0].name == "restart"
    assert snapshot.management_events[0].payload == ({"reason": "test"},)
    assert set(MANAGEMENT_EVENTS).issubset(client.handlers)


def test_register_vrecorder_lifecycle_rejoins_after_reconnect() -> None:
    client = FakeSocketIoClient()
    state = RecorderRuntimeState(
        vrcode="VR_TEST",
        base_url="http://example.test",
        local_ip="192.0.2.10",
    )

    register_vrecorder_lifecycle(client, state=state)
    client.connected = False
    client.handlers["disconnect"]()
    client.connected = True
    client.handlers["connect"]()

    snapshot = state.snapshot()

    assert client.emitted == [("join_vr", "VR_TEST"), ("join_vr", "VR_TEST")]
    assert snapshot.connected
    assert snapshot.join_sent


def test_stream_realtime_payload_records_join_and_send_data() -> None:
    client = FakeSocketIoClient()

    def connector(
        base_url: str,
        *,
        timeout: float = 30.0,
    ) -> FakeSocketIoClient:
        return client

    payload: JsonObject = {
        "vrcode": "VR_TEST",
        "ver": "testkit",
        "rooms": {
            "0": {
                "roomname": "BED01",
                "trks": [],
            }
        },
    }
    state = RecorderRuntimeState(
        vrcode="VR_TEST",
        base_url="http://example.test",
        local_ip="192.0.2.10",
    )

    result = stream_realtime_payload(
        "http://example.test",
        payload,
        max_messages=1,
        shift_time=False,
        runtime_state=state,
        connector=connector,
    )

    snapshot = state.snapshot()

    assert result.error is None
    assert [event for event, _ in client.emitted] == ["join_vr", "send_data"]
    assert snapshot.join_sent
    assert snapshot.messages_sent == 1
    assert snapshot.bytes_sent == result.bytes_sent
    assert not client.connected


def test_stream_realtime_payload_replays_recorded_frames_in_sequence() -> None:
    client = FakeSocketIoClient()

    def connector(
        base_url: str,
        *,
        timeout: float = 30.0,
    ) -> FakeSocketIoClient:
        return client

    payload: JsonObject = {
        "vrcode": "VR_TEST",
        "ver": "testkit",
        "rooms": {
            "OR-A": {
                "roomname": "OR-A",
                "dtstart": 100.0,
                "dtend": 100.03,
                "trks": [
                    {
                        "type": "num",
                        "montype": "HR",
                        "recs": [
                            {"dt": 100.0, "val": 80},
                            {"dt": 100.01, "val": 81},
                            {"dt": 100.02, "val": 82},
                        ],
                    }
                ],
            }
        },
    }

    result = stream_realtime_payload(
        "http://example.test",
        RecorderFrameSource(
            kind=RecorderFrameSourceKind.RECORDED,
            payload=payload,
        ),
        interval_seconds=0.01,
        max_messages=2,
        shift_time=True,
        connector=connector,
    )

    sent_payloads = [
        json.loads(zlib.decompress(data))
        for event, data in client.emitted
        if event == "send_data"
    ]
    first_record = sent_payloads[0]["rooms"]["OR-A"]["trks"][0]["recs"][0]
    second_record = sent_payloads[1]["rooms"]["OR-A"]["trks"][0]["recs"][0]

    assert result.error is None
    assert first_record["val"] == 80
    assert second_record["val"] == 81
    assert second_record["dt"] > first_record["dt"]


def test_stream_realtime_payload_does_not_count_disconnected_send() -> None:
    client = FakeSocketIoClient()

    def connector(
        base_url: str,
        *,
        timeout: float = 30.0,
    ) -> FakeSocketIoClient:
        return client

    def disconnect_after_join(event: str, data: object = None) -> None:
        client.emitted.append((event, data))
        if event == "join_vr":
            client.connected = False
            client.handlers["disconnect"]()

    client.emit = disconnect_after_join  # type: ignore[method-assign]

    payload: JsonObject = {
        "vrcode": "VR_TEST",
        "ver": "testkit",
        "rooms": {
            "0": {
                "roomname": "BED01",
                "trks": [],
            }
        },
    }
    state = RecorderRuntimeState(
        vrcode="VR_TEST",
        base_url="http://example.test",
        local_ip="192.0.2.10",
    )

    result = stream_realtime_payload(
        "http://example.test",
        payload,
        max_messages=1,
        shift_time=False,
        runtime_state=state,
        connector=connector,
        disconnected_timeout_seconds=0.01,
    )

    snapshot = state.snapshot()

    assert result.error == "Socket.IO disconnected before send_data"
    assert client.emitted == [("join_vr", "VR_TEST")]
    assert snapshot.messages_sent == 0
    assert result.messages_sent == 0
