from __future__ import annotations

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionState,
    session_snapshot_to_document,
)


def test_virtual_recorder_session_runs_to_completion() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=2,
            interval_seconds=0.1,
            max_messages=2,
            shift_time=False,
        )
    )

    assert manager.wait_session(snapshot.session_id, timeout=5)

    completed = manager.get_session(snapshot.session_id)

    assert completed is not None
    assert completed.state == VirtualRecorderSessionState.STOPPED
    assert completed.error is None
    assert len(completed.recorders) == 2
    assert completed.messages_sent == 4
    assert completed.bytes_sent > 0

    document = session_snapshot_to_document(completed)

    assert document["id"] == completed.session_id
    assert document["state"] == "stopped"
    assert document["targetUrl"] == "http://example.test"
    assert document["recordersRequested"] == 2
    assert document["recorders"][0]["joinSent"] is True


def test_virtual_recorder_session_can_stop() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            interval_seconds=1,
            shift_time=False,
        )
    )

    stopping = manager.stop_session(snapshot.session_id)

    assert stopping is not None
    assert stopping.state in (
        VirtualRecorderSessionState.STOPPING,
        VirtualRecorderSessionState.STOPPED,
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)

    stopped = manager.get_session(snapshot.session_id)

    assert stopped is not None
    assert stopped.state == VirtualRecorderSessionState.STOPPED
