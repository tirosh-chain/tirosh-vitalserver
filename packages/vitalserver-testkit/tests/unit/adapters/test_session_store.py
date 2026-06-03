from __future__ import annotations

import json
from pathlib import Path

import pytest

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
from tirosh_vitalserver.testkit.application.recorder_session.store import (
    session_snapshot_to_record,
)


def test_json_file_session_store_round_trips_snapshots(tmp_path: Path) -> None:
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


def test_json_file_session_store_rejects_missing_session_contract_fields(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    store = JsonFileVirtualRecorderSessionStore(path)
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        session_store=store,
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_STORE",
            recorders=1,
            bed_room_names=("OR-A",),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)
    restored = store.load_sessions()[0]
    record = session_snapshot_to_record(restored)
    del record["request"]["scenario"]
    path.write_text(json.dumps({"sessions": [record]}), encoding="utf-8")

    with pytest.raises(KeyError, match="scenario"):
        store.load_sessions()


def test_json_file_session_store_rejects_missing_recorder_contract_fields(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    store = JsonFileVirtualRecorderSessionStore(path)
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        session_store=store,
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_STORE",
            recorders=1,
            bed_room_names=("OR-A",),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)
    restored = store.load_sessions()[0]
    record = session_snapshot_to_record(restored)
    del record["recorders"][0]["messages_sent"]
    path.write_text(json.dumps({"sessions": [record]}), encoding="utf-8")

    with pytest.raises(KeyError, match="messages_sent"):
        store.load_sessions()


def test_json_file_session_store_rejects_corrupt_payload(tmp_path: Path) -> None:
    path = tmp_path / "sessions.json"
    path.write_text("{not-json", encoding="utf-8")
    store = JsonFileVirtualRecorderSessionStore(path)

    with pytest.raises(json.JSONDecodeError):
        store.load_sessions()


def test_json_file_bed_registry_store_round_trips_beds(tmp_path: Path) -> None:
    store = JsonFileBedRegistryStore(tmp_path / "bed-registry.json")
    registry = BedRegistry(store=store)

    registry.create_beds(room_names=("OR-A", "OR-B"))

    restored = BedRegistry(store=store)
    assert [bed.room_name for bed in restored.list_beds()] == ["OR-A", "OR-B"]

    restored.reset_beds()
    assert BedRegistry(store=store).list_beds() == ()
