from __future__ import annotations

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
