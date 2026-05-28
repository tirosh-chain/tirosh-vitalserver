from __future__ import annotations

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.adapters.outbound.bed_registry_store import (
    JsonFileBedRegistryStore,
)
from tirosh_vitalserver.testkit.adapters.outbound.session_store import (
    JsonFileVirtualRecorderSessionStore,
)
from tirosh_vitalserver.testkit.application.bed_registry import BedRegistry
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionState,
)


def test_json_file_session_store_round_trips_snapshots(tmp_path) -> None:
    store = JsonFileVirtualRecorderSessionStore(tmp_path / "sessions.json")
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        session_store=store,
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_STORE",
            recorders=2,
            bed_room_names=("OR-A", "OR-B"),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )

    assert manager.wait_session(snapshot.session_id, timeout=5)

    restored = {
        snapshot.session_id: snapshot
        for snapshot in store.load_sessions()
    }[snapshot.session_id]

    assert restored.state == VirtualRecorderSessionState.STOPPED
    assert [recorder.vrcode for recorder in restored.recorders] == [
        "VR_STORE-001",
        "VR_STORE-002",
    ]
    assert restored.messages_sent == 2


def test_json_file_bed_registry_store_round_trips_beds(tmp_path) -> None:
    store = JsonFileBedRegistryStore(tmp_path / "bed-registry.json")
    registry = BedRegistry(store=store)

    registry.create_beds(room_names=("OR-A", "OR-B"))

    restored = BedRegistry(store=store)
    assert [bed.room_name for bed in restored.list_beds()] == ["OR-A", "OR-B"]

    restored.reset_beds()
    assert BedRegistry(store=store).list_beds() == ()
