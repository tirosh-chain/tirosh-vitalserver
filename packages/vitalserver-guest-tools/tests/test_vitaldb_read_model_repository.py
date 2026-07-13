from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.postgres import PostgresVitalDBReadModelRepository
from tirosh_guest_tools.domain.guest_control.models import VitalDBReadModelDependencyError


def repository(tmp_path: Path) -> PostgresVitalDBReadModelRepository:
    value = PostgresVitalDBReadModelRepository(f"sqlite:///{tmp_path / 'vitaldb.sqlite'}")
    value.ensure_schema()
    return value


def observation(*, vrcode: str = "VR-001", bed_id: str = "bed-a") -> dict[str, object]:
    return {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [{"vrcode": vrcode, "bedID": bed_id, "online": True, "stale": False}],
        "beds": [{"bedID": bed_id, "name": "OR-A", "online": True}],
        "activityBuckets": [{
            "vrcode": vrcode, "bucketStartedAt": "2026-07-01T00:00:00Z",
            "bucketSeconds": 60, "messageCount": 2, "byteCount": 20,
            "roomCount": 1, "firstObservedAt": "2026-07-01T00:00:01Z",
            "lastObservedAt": "2026-07-01T00:00:40Z",
        }],
        "readIssues": [],
    }


def test_sqlalchemy_repository_round_trips_observation_on_sqlite(tmp_path: Path) -> None:
    store = repository(tmp_path)
    document = observation()
    store.save_latest_observation(document, observed_at=datetime.now(UTC))
    assert store.latest_observation() == {"state": "loaded", "observation": document, "readError": None}
    assert store.recorders()["recorders"][0]["vrcode"] == "VR-001"
    assert store.beds()["beds"][0]["bedID"] == "bed-a"


def test_sqlalchemy_repository_applies_visibility_policy(tmp_path: Path) -> None:
    store = repository(tmp_path)
    store.save_latest_observation(observation(), observed_at=datetime.now(UTC))
    hidden = store.hide_recorders({"vrcodes": ["VR-001"]})
    assert hidden["recorders"][0]["visibility"] == "hidden"
    deleted = store.delete_recorders({"vrcodes": ["VR-001"]})
    assert deleted["recorders"] == []


def test_sqlalchemy_repository_requires_hidden_before_delete(tmp_path: Path) -> None:
    store = repository(tmp_path)
    store.save_latest_observation(observation(), observed_at=datetime.now(UTC))
    with pytest.raises(VitalDBReadModelDependencyError) as error:
        store.delete_recorders({"vrcodes": ["VR-001"]})
    assert error.value.kind == "vitaldb-read-model-delete-not-hidden"


def test_sqlalchemy_repository_reads_activity(tmp_path: Path) -> None:
    store = repository(tmp_path)
    store.save_latest_observation(observation(), observed_at=datetime.now(UTC))
    result = store.recorder_activity("VR-001")
    assert result["state"] == "loaded"
    assert result["buckets"][0]["messageCount"] == 2


def test_sqlalchemy_repository_round_trips_relationship_history(tmp_path: Path) -> None:
    store = repository(tmp_path)
    document = {"state": "loaded", "assignments": [], "events": [], "readError": None}
    store.save_relationship_history(document, observed_at=datetime.now(UTC))
    assert store.relationships() == document
    assert store.previous_relationship_history() == document


def test_sqlalchemy_repository_preserves_empty_as_unavailable(tmp_path: Path) -> None:
    store = repository(tmp_path)
    with pytest.raises(VitalDBReadModelDependencyError) as error:
        store.latest_observation()
    assert error.value.kind == "vitaldb-read-model-unavailable"
    assert error.value.message == "VitalDB observation read model is empty."


def test_sqlalchemy_repository_rejects_invalid_collection(tmp_path: Path) -> None:
    store = repository(tmp_path)
    document = observation()
    document["recorders"] = None
    store.save_latest_observation(document, observed_at=datetime.now(UTC))
    with pytest.raises(VitalDBReadModelDependencyError) as error:
        store.recorders()
    assert error.value.kind == "vitaldb-read-model-invalid"
