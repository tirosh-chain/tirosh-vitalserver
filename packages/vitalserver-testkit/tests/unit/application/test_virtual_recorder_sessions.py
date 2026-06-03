from __future__ import annotations

import pytest

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionScenario,
    VirtualRecorderSessionSnapshot,
    VirtualRecorderSessionState,
    session_snapshot_to_document,
)
from tirosh_vitalserver.testkit.domain.bed import beds_for_room_names
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario


def test_virtual_recorder_session_runs_to_completion() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=2,
            bed_room_names=("OR-A", "OR-B"),
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
    assert document["bedsRequested"] == 2
    assert document["recorders"][0]["joinSent"] is True


def test_virtual_recorder_session_can_stop() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bed_room_names=("OR-A",),
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


def test_virtual_recorder_session_can_pause_and_resume() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bed_room_names=("OR-A",),
            interval_seconds=0.1,
            max_messages=2,
            shift_time=False,
        )
    )

    paused = manager.pause_session(snapshot.session_id)
    resumed = manager.resume_session(snapshot.session_id)

    assert paused is not None
    assert paused.state in (
        VirtualRecorderSessionState.PAUSED,
        VirtualRecorderSessionState.STOPPED,
    )
    assert resumed is not None
    assert resumed.state in (
        VirtualRecorderSessionState.RUNNING,
        VirtualRecorderSessionState.STOPPED,
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)


def test_stopped_virtual_recorder_session_can_restart_on_new_bed() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_REUSE",
            bed_room_names=("OR-A",),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)

    restarted = manager.restart_session(
        snapshot.session_id,
        bed_room_names=("OR-B",),
    )

    assert restarted is not None
    assert restarted.session_id != snapshot.session_id
    assert restarted.request.vrcode == "VR_REUSE"
    assert restarted.request.bed_room_names == ("OR-B",)
    assert manager.wait_session(restarted.session_id, timeout=5)


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
            bed_room_names=("OR-A", "OR-B"),
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


def test_virtual_recorder_can_delete_orphan_by_vrcode() -> None:
    recorder_management = FakeRecorderManagement()
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
    )

    result = manager.delete_vrecorder("http://example.test", " VR_ORPHAN ")

    assert result.deleted is True
    assert result.vrcode == "VR_ORPHAN"
    assert result.error is None
    assert recorder_management.deleted == [("http://example.test", "VR_ORPHAN")]


def test_virtual_recorder_manager_deletes_vitalserver_beds() -> None:
    recorder_management = FakeRecorderManagement()
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
    )
    beds = beds_for_room_names(("OR-A", "OR-B"))

    errors = manager.delete_vitalserver_beds("http://example.test", beds)

    assert errors == ()
    assert recorder_management.deleted_beds == [
        ("http://example.test", beds[0].bed_id, "OR-A"),
        ("http://example.test", beds[1].bed_id, "OR-B"),
    ]


def test_virtual_recorder_orphan_delete_reports_failure() -> None:
    recorder_management = FakeRecorderManagement(failing_vrcodes={"VR_ORPHAN"})
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
    )

    result = manager.delete_vrecorder("http://example.test", "VR_ORPHAN")

    assert result.deleted is False
    assert result.vrcode == "VR_ORPHAN"
    assert "delete failed" in (result.error or "")


def test_virtual_recorder_delete_keeps_session_when_cleanup_fails() -> None:
    recorder_management = FakeRecorderManagement(failing_vrcodes={"VR_FAIL-002"})
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_FAIL",
            recorders=2,
            bed_room_names=("OR-A", "OR-B"),
            interval_seconds=1,
            shift_time=False,
        )
    )

    deleted = manager.delete_session(snapshot.session_id)

    assert deleted is not None
    assert deleted.cleanup_errors[0].vrcode == "VR_FAIL-002"
    assert manager.get_session(snapshot.session_id) == deleted


def test_virtual_recorder_delete_reports_missing_cleanup_provider() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_NO_PROVIDER",
            recorders=1,
            bed_room_names=("OR-A",),
            interval_seconds=1,
            shift_time=False,
        )
    )

    deleted = manager.delete_session(snapshot.session_id)

    assert deleted is not None
    assert deleted.cleanup_errors[0].vrcode == "VR_NO_PROVIDER"
    assert "recorder management is not configured" in deleted.cleanup_errors[0].error
    assert manager.get_session(snapshot.session_id) == deleted


def test_virtual_recorder_bed_cleanup_reports_missing_provider() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    beds = beds_for_room_names(("OR-A",))

    errors = manager.delete_vitalserver_beds("http://example.test", beds)

    assert errors == (
        f"OR-A({beds[0].bed_id}): recorder management is not configured",
    )


def test_virtual_recorder_session_save_failure_is_not_event_only() -> None:
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        session_store=FailingSessionStore(save_error=RuntimeError("save denied")),
    )

    with pytest.raises(RuntimeError, match="save denied"):
        manager.start_session(
            VirtualRecorderSessionRequest(
                target_url="http://example.test",
                bed_room_names=("OR-A",),
                interval_seconds=1,
                shift_time=False,
            )
        )


def test_virtual_recorder_session_delete_failure_is_not_event_only() -> None:
    recorder_management = FakeRecorderManagement()
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
        session_store=FailingSessionStore(delete_error=RuntimeError("delete denied")),
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_STORE_DELETE",
            bed_room_names=("OR-A",),
            interval_seconds=1,
            shift_time=False,
        )
    )

    with pytest.raises(RuntimeError, match="delete denied"):
        manager.delete_session(snapshot.session_id)

    assert manager.get_session(snapshot.session_id) is not None


def test_virtual_recorder_session_applies_session_scenario_defaults() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bed_room_names=("OR-A",),
            scenario=VirtualRecorderSessionScenario.SIGNAL_ANOMALY,
            interval_seconds=1,
            max_messages=1,
            shift_time=False,
        )
    )

    assert snapshot.request.scenario == VirtualRecorderSessionScenario.SIGNAL_ANOMALY
    assert snapshot.request.default_scenario == RecorderSignalScenario.ARTIFACT


def test_multiple_recorder_scenario_requires_enough_explicit_beds() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)

    try:
        manager.start_session(
            VirtualRecorderSessionRequest(
                target_url="http://example.test",
                bed_room_names=("OR-A", "OR-B"),
                scenario=VirtualRecorderSessionScenario.MULTIPLE_RECORDERS,
                interval_seconds=1,
                max_messages=1,
                shift_time=False,
            )
        )
    except ValueError as exc:
        assert str(exc) == "bed count must be greater than or equal to recorder count"
    else:
        raise AssertionError("expected multiple recorder bed validation")


def test_virtual_recorder_session_requires_explicit_bed_room_names() -> None:
    try:
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=2,
        )
    except ValueError as exc:
        assert str(exc) == "bed_room_names is required"
    else:
        raise AssertionError("expected missing bed validation")


def test_virtual_recorder_session_requires_a_bed_per_recorder() -> None:
    try:
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=2,
            bed_room_names=("OR-A",),
        )
    except ValueError as exc:
        assert str(exc) == "bed count must be greater than or equal to recorder count"
    else:
        raise AssertionError("expected bed count validation")


def test_virtual_recorder_session_rejects_duplicate_bed_room_names() -> None:
    try:
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=1,
            bed_room_names=("OR-A", " OR-A "),
        )
    except ValueError as exc:
        assert str(exc) == "bed_room_names must not include duplicate values"
    else:
        raise AssertionError("expected duplicate bed validation")


def test_virtual_recorder_session_rejects_active_bed_reuse() -> None:
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=FakeRecorderManagement(),
    )
    first = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=1,
            bed_room_names=("OR-A",),
            interval_seconds=1,
            shift_time=False,
        )
    )

    try:
        try:
            manager.start_session(
                VirtualRecorderSessionRequest(
                    target_url="http://example.test",
                    recorders=1,
                    bed_room_names=("OR-A",),
                    interval_seconds=1,
                    shift_time=False,
                )
            )
        except ValueError as exc:
            assert str(exc) == "bed room names are already assigned: OR-A"
        else:
            raise AssertionError("expected active bed assignment validation")
    finally:
        manager.delete_session(first.session_id)


def test_virtual_recorder_session_allows_reuse_after_session_delete() -> None:
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=FakeRecorderManagement(),
    )
    first = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=1,
            bed_room_names=("OR-A",),
            interval_seconds=1,
            shift_time=False,
        )
    )
    manager.delete_session(first.session_id)

    second = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=1,
            bed_room_names=("OR-A",),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )

    assert manager.wait_session(second.session_id, timeout=5)


def test_virtual_recorder_session_can_use_existing_bed_room_names() -> None:
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            recorders=2,
            bed_room_names=("OR-A", "OR-B"),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )

    assert manager.wait_session(snapshot.session_id, timeout=5)

    completed = manager.get_session(snapshot.session_id)
    assert completed is not None

    document = session_snapshot_to_document(completed)

    assert document["bedsRequested"] == 2
    assert document["bedRoomNames"] == ("OR-A", "OR-B")


def test_stored_virtual_recorder_session_can_be_deleted_after_restart() -> None:
    session_store = InMemorySessionStore()
    recorder_management = FakeRecorderManagement()
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
        session_store=session_store,
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_RESTART",
            recorders=2,
            bed_room_names=("OR-A", "OR-B"),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )

    assert manager.wait_session(snapshot.session_id, timeout=5)

    restarted_manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=recorder_management,
        session_store=session_store,
    )
    stored = restarted_manager.get_session(snapshot.session_id)

    assert stored is not None
    assert [recorder.vrcode for recorder in stored.recorders] == [
        "VR_RESTART-001",
        "VR_RESTART-002",
    ]

    deleted = restarted_manager.delete_session(snapshot.session_id)

    assert deleted is not None
    assert restarted_manager.get_session(snapshot.session_id) is None
    assert recorder_management.deleted == [
        ("http://example.test", "VR_RESTART-001"),
        ("http://example.test", "VR_RESTART-002"),
    ]


def test_virtual_recorder_sessions_can_be_reset() -> None:
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        recorder_management=FakeRecorderManagement(),
    )
    first = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bed_room_names=("OR-A",),
            interval_seconds=1,
            shift_time=False,
        )
    )
    second = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bed_room_names=("OR-B",),
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
    def __init__(self, failing_vrcodes: set[str] | None = None) -> None:
        self.deleted: list[tuple[str, str]] = []
        self.deleted_beds: list[tuple[str, str, str]] = []
        self.failing_vrcodes = failing_vrcodes or set()

    def delete_vrecorder(
        self,
        base_url: str,
        vrcode: str,
        *,
        timeout: float = 5.0,
    ) -> None:
        if vrcode in self.failing_vrcodes:
            raise RuntimeError(f"delete failed: {vrcode}")
        self.deleted.append((base_url, vrcode))

    def delete_bed(
        self,
        base_url: str,
        *,
        bed_id: str,
        bed_name: str,
        timeout: float = 5.0,
    ) -> None:
        self.deleted_beds.append((base_url, bed_id, bed_name))


class InMemorySessionStore:
    def __init__(self) -> None:
        self.sessions: dict[str, VirtualRecorderSessionSnapshot] = {}

    def load_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]:
        return tuple(self.sessions.values())

    def save_session(self, snapshot: VirtualRecorderSessionSnapshot) -> None:
        self.sessions[snapshot.session_id] = snapshot

    def delete_session(self, session_id: str) -> None:
        self.sessions.pop(session_id, None)

    def delete_all_sessions(self) -> None:
        self.sessions.clear()


class FailingSessionStore(InMemorySessionStore):
    def __init__(
        self,
        *,
        save_error: Exception | None = None,
        delete_error: Exception | None = None,
    ) -> None:
        super().__init__()
        self.save_error = save_error
        self.delete_error = delete_error

    def save_session(self, snapshot: VirtualRecorderSessionSnapshot) -> None:
        if self.save_error is not None:
            raise self.save_error
        super().save_session(snapshot)

    def delete_session(self, session_id: str) -> None:
        if self.delete_error is not None:
            raise self.delete_error
        super().delete_session(session_id)
