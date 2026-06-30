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
from tirosh_vitalserver.testkit.application.bed_registry.store import (
    BED_REGISTRY_STORE_SCHEMA_VERSION,
)
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionState,
)
from tirosh_vitalserver.testkit.application.recorder_session.store import (
    SESSION_STORE_SCHEMA_VERSION,
    session_snapshot_to_record,
)

FIXTURES = Path(__file__).parents[2] / "fixtures" / "compat"


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
            bedroom_name="OR-A",
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
    assert restored.request.bedroom_name == "OR-A"
    payload = json.loads((tmp_path / "sessions.json").read_text(encoding="utf-8"))
    assert payload["schema_version"] == SESSION_STORE_SCHEMA_VERSION


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
            bedroom_name="OR-A",
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)
    restored = store.load_sessions()[0]
    record = session_snapshot_to_record(restored)
    del record["request"]["scenario"]
    path.write_text(
        json.dumps({
            "schema_version": SESSION_STORE_SCHEMA_VERSION,
            "sessions": [record],
        }),
        encoding="utf-8",
    )

    with pytest.raises(KeyError, match="scenario"):
        store.load_sessions()


def test_json_file_session_store_rejects_missing_vital_state(
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
            bedroom_name="OR-A",
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)
    restored = store.load_sessions()[0]
    record = session_snapshot_to_record(restored)
    del record["vital_state"]
    path.write_text(
        json.dumps({
            "schema_version": SESSION_STORE_SCHEMA_VERSION,
            "sessions": [record],
        }),
        encoding="utf-8",
    )

    with pytest.raises(KeyError, match="vital_state"):
        store.load_sessions()


def test_json_file_session_store_rejects_legacy_fixture_without_schema_version(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    path.write_text(
        (FIXTURES / "sessions-v1-no-vital-state.json").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    store = JsonFileVirtualRecorderSessionStore(path)

    with pytest.raises(ValueError, match="schema_version is required"):
        store.load_sessions()


def test_json_file_session_store_rejects_legacy_session_contract_values(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    legacy = json.loads(
        (FIXTURES / "sessions-v1-no-vital-state.json").read_text(encoding="utf-8")
    )
    legacy["schema_version"] = SESSION_STORE_SCHEMA_VERSION
    path.write_text(json.dumps(legacy), encoding="utf-8")
    store = JsonFileVirtualRecorderSessionStore(path)

    with pytest.raises(ValueError, match="'normal' is not a valid"):
        store.load_sessions()


def test_json_file_session_store_rejects_newer_schema(tmp_path: Path) -> None:
    path = tmp_path / "sessions.json"
    payload = json.loads(
        (FIXTURES / "sessions-v1-no-vital-state.json").read_text(encoding="utf-8")
    )
    payload["schema_version"] = SESSION_STORE_SCHEMA_VERSION + 1
    path.write_text(json.dumps(payload), encoding="utf-8")
    store = JsonFileVirtualRecorderSessionStore(path)

    with pytest.raises(ValueError, match="newer than supported"):
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
            bedroom_name="OR-A",
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)
    restored = store.load_sessions()[0]
    record = session_snapshot_to_record(restored)
    del record["recorders"][0]["messages_sent"]
    path.write_text(
        json.dumps({
            "schema_version": SESSION_STORE_SCHEMA_VERSION,
            "sessions": [record],
        }),
        encoding="utf-8",
    )

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
    payload = json.loads((tmp_path / "bed-registry.json").read_text(encoding="utf-8"))
    assert payload["schema_version"] == BED_REGISTRY_STORE_SCHEMA_VERSION

    restored.reset_beds()
    assert BedRegistry(store=store).list_beds() == ()


def test_json_file_bed_registry_store_loads_legacy_fixture(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    path.write_text(
        (FIXTURES / "bed-registry-v1-legacy.json").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    store = JsonFileBedRegistryStore(path)

    beds = store.load_beds()

    assert [(bed.room_name, bed.bed_id) for bed in beds] == [
        ("OR Legacy", "bed-legacy")
    ]


def test_json_file_bed_registry_store_rejects_corrupt_payload(tmp_path: Path) -> None:
    path = tmp_path / "bed-registry.json"
    path.write_text("{not-json", encoding="utf-8")
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(json.JSONDecodeError):
        store.load_beds()
