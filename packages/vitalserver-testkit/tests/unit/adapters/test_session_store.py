from __future__ import annotations

import json
from pathlib import Path
from typing import cast
from unittest.mock import patch

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
from tirosh_vitalserver.testkit.domain.bed import Bed

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
            bed_room_names=("OR-A", "OR-B"),
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )

    assert manager.wait_session(snapshot.session_id, timeout=5)

    restored = {snapshot.session_id: snapshot for snapshot in store.load_sessions()}[
        snapshot.session_id
    ]

    assert restored.state == VirtualRecorderSessionState.STOPPED
    assert [recorder.vrcode for recorder in restored.recorders] == [
        "VR_STORE-001",
        "VR_STORE-002",
    ]
    assert restored.messages_sent == 2
    assert restored.request.bedroom_name == "OR-A"
    payload = json.loads((tmp_path / "sessions.json").read_text(encoding="utf-8"))
    assert payload["schema_version"] == SESSION_STORE_SCHEMA_VERSION


def test_json_file_session_store_treats_an_absent_file_as_first_run_state(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    store = JsonFileVirtualRecorderSessionStore(path)

    assert store.load_sessions() == ()
    assert not path.exists()


def test_json_file_session_store_does_not_treat_a_dangling_symlink_as_absent(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    path.symlink_to(tmp_path / "missing-sessions.json")
    store = JsonFileVirtualRecorderSessionStore(path)

    with pytest.raises(FileNotFoundError):
        store.load_sessions()


def test_json_file_session_store_surfaces_an_unreadable_existing_file(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    path.write_text("{}", encoding="utf-8")
    store = JsonFileVirtualRecorderSessionStore(path)

    with (
        patch.object(Path, "open", side_effect=PermissionError("read denied")),
        pytest.raises(PermissionError, match="read denied"),
    ):
        store.load_sessions()


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
        json.dumps(
            {
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [record],
            }
        ),
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
        json.dumps(
            {
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [record],
            }
        ),
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
        json.dumps(
            {
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [record],
            }
        ),
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


def test_json_file_session_store_does_not_overwrite_invalid_state_on_delete_all(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    original = json.dumps(
        {
            "schema_version": SESSION_STORE_SCHEMA_VERSION,
            "sessions": [{"session_id": 42}],
        }
    )
    path.write_text(original, encoding="utf-8")
    store = JsonFileVirtualRecorderSessionStore(path)

    with pytest.raises(ValueError, match="session_id must be a string"):
        store.delete_all_sessions()

    assert path.read_text(encoding="utf-8") == original


def test_json_file_session_store_rejects_persisted_scalar_type_coercion(
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
    record = session_snapshot_to_record(store.load_sessions()[0])
    record["session_id"] = 101
    path.write_text(
        json.dumps(
            {
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [record],
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="session_id must be a string"):
        store.load_sessions()

    record["session_id"] = snapshot.session_id
    record["recorders"][0]["connected"] = "false"
    path.write_text(
        json.dumps(
            {
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [record],
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="connected must be a boolean"):
        store.load_sessions()


def test_json_file_session_store_does_not_publish_over_invalid_existing_records(
    tmp_path: Path,
) -> None:
    path = tmp_path / "sessions.json"
    invalid_payload = {
        "schema_version": SESSION_STORE_SCHEMA_VERSION,
        "sessions": [{"session_id": 101}],
    }
    path.write_text(json.dumps(invalid_payload), encoding="utf-8")
    store = JsonFileVirtualRecorderSessionStore(path)
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bedroom_name="OR-A",
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)

    with pytest.raises(ValueError, match="session_id must be a string"):
        store.save_session(snapshot)

    assert json.loads(path.read_text(encoding="utf-8")) == invalid_payload


def test_json_file_session_store_rejects_duplicate_session_ids(
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
            bedroom_name="OR-A",
            interval_seconds=0.1,
            max_messages=1,
            shift_time=False,
        )
    )
    assert manager.wait_session(snapshot.session_id, timeout=5)
    record = session_snapshot_to_record(store.load_sessions()[0])
    path.write_text(
        json.dumps(
            {
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [record, record],
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="duplicate session_id"):
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


def test_json_file_bed_registry_store_treats_an_absent_file_as_first_run_state(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    store = JsonFileBedRegistryStore(path)

    assert store.load_beds() == ()
    assert not path.exists()


def test_json_file_bed_registry_store_does_not_treat_a_dangling_symlink_as_absent(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    path.symlink_to(tmp_path / "missing-bed-registry.json")
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(FileNotFoundError):
        store.load_beds()


def test_json_file_bed_registry_store_surfaces_an_unreadable_existing_file(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    path.write_text("{}", encoding="utf-8")
    store = JsonFileBedRegistryStore(path)

    with (
        patch.object(Path, "open", side_effect=PermissionError("read denied")),
        pytest.raises(PermissionError, match="read denied"),
    ):
        store.load_beds()


def test_json_file_bed_registry_store_rejects_legacy_fixture_without_schema_version(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    path.write_text(
        (FIXTURES / "bed-registry-v1-legacy.json").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(ValueError, match="schema_version is required"):
        store.load_beds()


def test_json_file_bed_registry_store_rejects_corrupt_payload(tmp_path: Path) -> None:
    path = tmp_path / "bed-registry.json"
    path.write_text("{not-json", encoding="utf-8")
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(json.JSONDecodeError):
        store.load_beds()


def test_json_file_bed_registry_store_rejects_invalid_record_types(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    path.write_text(
        json.dumps(
            {
                "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                "bed_registry": [{"room_name": 101, "bed_id": "bed-101"}],
            }
        ),
        encoding="utf-8",
    )
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(ValueError, match="room_name must be a string"):
        store.load_beds()


def test_json_file_bed_registry_store_rejects_duplicate_room_names(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    path.write_text(
        json.dumps(
            {
                "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                "bed_registry": [
                    {"room_name": "OR-A", "bed_id": "bed-a"},
                    {"room_name": "OR-A", "bed_id": "bed-b"},
                ],
            }
        ),
        encoding="utf-8",
    )
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(ValueError, match="duplicate room_name"):
        store.load_beds()


def test_json_file_bed_registry_store_validates_existing_state_before_overwrite(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    invalid_payload = {
        "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
        "bed_registry": [{"room_name": 101, "bed_id": "bed-101"}],
    }
    path.write_text(json.dumps(invalid_payload), encoding="utf-8")
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(ValueError, match="room_name must be a string"):
        store.save_beds((Bed(room_name="OR-A", bed_id="bed-a"),))
    assert json.loads(path.read_text(encoding="utf-8")) == invalid_payload

    with pytest.raises(ValueError, match="room_name must be a string"):
        store.delete_beds()
    assert json.loads(path.read_text(encoding="utf-8")) == invalid_payload


def test_json_file_bed_registry_store_rejects_invalid_or_duplicate_outgoing_beds(
    tmp_path: Path,
) -> None:
    path = tmp_path / "bed-registry.json"
    store = JsonFileBedRegistryStore(path)

    with pytest.raises(ValueError, match="duplicate room_name"):
        store.save_beds(
            (
                Bed(room_name="OR-A", bed_id="bed-a"),
                Bed(room_name="OR-A", bed_id="bed-b"),
            )
        )
    assert not path.exists()

    with pytest.raises(ValueError, match="room_name must be a string"):
        store.save_beds((Bed(room_name=cast(str, 101), bed_id="bed-101"),))
    assert not path.exists()


def test_bed_registry_does_not_publish_unpersisted_beds() -> None:
    store = FailingBedRegistryStore(save_error=RuntimeError("save denied"))
    registry = BedRegistry(store=store)

    with pytest.raises(RuntimeError, match="save denied"):
        registry.create_beds(room_names=("OR-A",))

    assert registry.list_beds() == ()


def test_bed_registry_keeps_published_beds_when_persistence_removal_fails() -> None:
    store = FailingBedRegistryStore()
    registry = BedRegistry(store=store)
    registry.create_beds(room_names=("OR-A",))
    store.save_error = RuntimeError("save denied")

    with pytest.raises(RuntimeError, match="save denied"):
        registry.delete_beds(("OR-A",))

    assert [bed.room_name for bed in registry.list_beds()] == ["OR-A"]

    store.save_error = None
    store.delete_error = RuntimeError("delete denied")
    with pytest.raises(RuntimeError, match="delete denied"):
        registry.reset_beds()

    assert [bed.room_name for bed in registry.list_beds()] == ["OR-A"]


class FailingBedRegistryStore:
    def __init__(
        self,
        *,
        save_error: Exception | None = None,
        delete_error: Exception | None = None,
    ) -> None:
        self._beds: tuple[Bed, ...] = ()
        self.save_error = save_error
        self.delete_error = delete_error

    def load_beds(self) -> tuple[Bed, ...]:
        return self._beds

    def save_beds(self, beds: tuple[Bed, ...]) -> None:
        if self.save_error is not None:
            raise self.save_error
        self._beds = beds

    def delete_beds(self) -> None:
        if self.delete_error is not None:
            raise self.delete_error
        self._beds = ()
