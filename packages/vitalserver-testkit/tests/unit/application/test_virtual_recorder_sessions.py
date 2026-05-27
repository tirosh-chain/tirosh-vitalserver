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


def test_virtual_recorder_session_can_be_deleted() -> None:
    recorder_management = FakeRecorderManagement()
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_TEST",
            recorders=2,
            interval_seconds=1,
            shift_time=False,
        )
    )

    deleted = manager.delete_session(snapshot.session_id)

    assert deleted is not None
    assert deleted.session_id == snapshot.session_id
    assert manager.get_session(snapshot.session_id) is None
    assert recorder_management.deleted == [
        ("http://example.test", "VR_TEST-001"),
        ("http://example.test", "VR_TEST-002"),
    ]


def test_virtual_recorder_sessions_can_be_reset() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    first = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            interval_seconds=1,
            shift_time=False,
        )
    )
    second = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            interval_seconds=1,
            shift_time=False,
        )
    )

    deleted = manager.delete_all_sessions()

    assert {snapshot.session_id for snapshot in deleted} == {
        first.session_id,
        second.session_id,
    }
    assert manager.list_sessions() == ()


class FakeRecorderManagement:
    def __init__(self) -> None:
        self.deleted: list[tuple[str, str]] = []

    def delete_vrecorder(
        self,
        base_url: str,
        vrcode: str,
        *,
        timeout: float = 5.0,
    ) -> None:
        self.deleted.append((base_url, vrcode))
