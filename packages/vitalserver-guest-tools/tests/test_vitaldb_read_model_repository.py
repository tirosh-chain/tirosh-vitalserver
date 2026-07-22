from __future__ import annotations

import json
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

import pytest
from sqlalchemy import event

from tirosh_guest_tools.adapters.outbound.postgres import (
    PostgresVitalDBReadModelRepository,
)
from tirosh_guest_tools.adapters.outbound.postgres import (
    vitaldb_read_model_repository as repository_module,
)
from tirosh_guest_tools.domain.guest_control.models import (
    VitalDBReadModelDependencyError,
)


def repository(tmp_path: Path) -> PostgresVitalDBReadModelRepository:
    value = PostgresVitalDBReadModelRepository(
        f"sqlite:///{tmp_path / 'vitaldb.sqlite'}"
    )
    value.ensure_schema()
    return value


def observation(*, vrcode: str = "VR-001", bed_id: str = "bed-a") -> dict[str, object]:
    return {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [
            {"vrcode": vrcode, "bedID": bed_id, "online": True, "stale": False}
        ],
        "beds": [{"bedID": bed_id, "name": "OR-A", "online": True}],
        "activityBuckets": [
            {
                "vrcode": vrcode,
                "bucketStartedAt": "2026-07-01T00:00:00Z",
                "bucketSeconds": 60,
                "messageCount": 2,
                "byteCount": 20,
                "roomCount": 1,
                "firstObservedAt": "2026-07-01T00:00:01Z",
                "lastObservedAt": "2026-07-01T00:00:40Z",
            }
        ],
        "readIssues": [],
    }


def test_sqlalchemy_repository_round_trips_observation_on_sqlite(
    tmp_path: Path,
) -> None:
    store = repository(tmp_path)
    document = observation()
    store.save_latest_observation(document, observed_at=datetime.now(UTC))
    assert store.latest_observation() == {
        "state": "loaded",
        "observation": document,
        "readError": None,
    }
    assert store.recorders()["recorders"][0]["vrcode"] == "VR-001"
    assert store.beds()["beds"][0]["bedID"] == "bed-a"


def test_sqlalchemy_repository_applies_visibility_policy(tmp_path: Path) -> None:
    store = repository(tmp_path)
    store.save_latest_observation(observation(), observed_at=datetime.now(UTC))
    hidden = store.hide_recorders({"vrcodes": ["VR-001"]})
    assert hidden["recorders"][0]["visibility"] == "hidden"
    deleted = store.delete_recorders({"vrcodes": ["VR-001"]})
    assert deleted["recorders"] == []
    assert deleted["activityHistory"]["bucketCount"] == 0
    assert store.recorder_activity("VR-001")["buckets"] == []


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


def test_sqlalchemy_repository_rejects_missing_activity_contract(
    tmp_path: Path,
) -> None:
    store = repository(tmp_path)
    document = observation()
    del document["activityBuckets"]

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        store.save_latest_observation(document, observed_at=datetime.now(UTC))

    assert error.value.kind == "vitaldb-read-model-invalid"
    assert error.value.message == (
        "VitalDB recorder activity read model field is invalid."
    )


def test_sqlalchemy_repository_reads_activity_history_across_snapshots(
    tmp_path: Path,
) -> None:
    store = repository(tmp_path)
    first = observation()
    latest = observation()
    latest["observedAt"] = "2026-07-01T00:01:00+00:00"
    latest["activityBuckets"] = [
        {
            "vrcode": "VR-001",
            "bucketStartedAt": "2026-07-01T00:00:00Z",
            "bucketSeconds": 60,
            "messageCount": 5,
            "byteCount": 50,
            "roomCount": 2,
            "firstObservedAt": "2026-07-01T00:00:01Z",
            "lastObservedAt": "2026-07-01T00:00:55Z",
        },
        {
            "vrcode": "VR-001",
            "bucketStartedAt": "2026-07-01T00:01:00Z",
            "bucketSeconds": 60,
            "messageCount": 3,
            "byteCount": 30,
            "roomCount": 1,
            "firstObservedAt": "2026-07-01T00:01:01Z",
            "lastObservedAt": "2026-07-01T00:01:50Z",
        },
    ]
    store.save_latest_observation(
        first,
        observed_at=datetime.fromisoformat("2026-07-01T00:00:00+00:00"),
    )
    store.save_latest_observation(
        latest,
        observed_at=datetime.fromisoformat("2026-07-01T00:01:00+00:00"),
    )

    result = store.recorder_activity("VR-001")

    assert [bucket["bucketStartedAt"] for bucket in result["buckets"]] == [
        "2026-07-01T00:00:00Z",
        "2026-07-01T00:01:00Z",
    ]
    assert [bucket["messageCount"] for bucket in result["buckets"]] == [5, 3]


def test_sqlalchemy_repository_keeps_activity_beyond_observation_read_limit(
    tmp_path: Path,
) -> None:
    store = repository(tmp_path)
    for index in range(1001):
        document = observation()
        day = 1 + index // 1440
        hour = index % 1440 // 60
        minute = index % 60
        started_at = f"2026-07-{day:02d}T{hour:02d}:{minute:02d}:00Z"
        document["observedAt"] = started_at
        document["activityBuckets"][0]["bucketStartedAt"] = started_at
        store.save_latest_observation(
            document,
            observed_at=datetime.fromisoformat(started_at.replace("Z", "+00:00")),
        )

    result = store.recorder_activity("VR-001")

    assert len(result["buckets"]) == 1001
    assert result["buckets"][0]["bucketStartedAt"] == "2026-07-01T00:00:00Z"


def test_schema_migration_backfills_activity_from_existing_observations(
    tmp_path: Path,
) -> None:
    database = tmp_path / "vitaldb.sqlite"
    with sqlite3.connect(database) as connection:
        connection.execute(
            """
            CREATE TABLE vitaldb_observation_snapshots(
              snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
              document JSON NOT NULL,
              observed_at DATETIME NOT NULL
            )
            """
        )
        connection.execute(
            """
            INSERT INTO vitaldb_observation_snapshots(document, observed_at)
            VALUES (?, ?)
            """,
            (json.dumps(observation()), "2026-07-01 00:00:00+00:00"),
        )

    store = PostgresVitalDBReadModelRepository(f"sqlite:///{database}")
    store.ensure_schema()

    assert store.recorder_activity("VR-001")["buckets"][0]["messageCount"] == 2


def test_schema_migration_reads_existing_observations_in_bounded_batches(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    database = tmp_path / "vitaldb.sqlite"
    documents: list[tuple[str, str]] = []
    for message_count in range(1, 6):
        document = observation()
        document["activityBuckets"][0]["messageCount"] = message_count
        documents.append((json.dumps(document), "2026-07-01 00:00:00+00:00"))
    with sqlite3.connect(database) as connection:
        connection.execute(
            """
            CREATE TABLE vitaldb_observation_snapshots(
              snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
              document JSON NOT NULL,
              observed_at DATETIME NOT NULL
            )
            """
        )
        connection.executemany(
            """
            INSERT INTO vitaldb_observation_snapshots(document, observed_at)
            VALUES (?, ?)
            """,
            documents,
        )

    monkeypatch.setattr(repository_module, "ACTIVITY_BUCKET_MIGRATION_BATCH_SIZE", 2)
    store = PostgresVitalDBReadModelRepository(f"sqlite:///{database}")
    statements: list[str] = []

    def record_statement(
        _connection: object,
        _cursor: object,
        statement: str,
        _parameters: object,
        _context: object,
        _executemany: bool,
    ) -> None:
        statements.append(statement)

    event.listen(store._engine, "before_cursor_execute", record_statement)

    store.ensure_schema()

    migration_reads = [
        statement
        for statement in statements
        if "FROM vitaldb_observation_snapshots" in statement
        and "ORDER BY vitaldb_observation_snapshots.snapshot_id" in statement
    ]
    assert len(migration_reads) == 4
    assert all("LIMIT" in statement for statement in migration_reads)
    assert store.recorder_activity("VR-001")["buckets"][0]["messageCount"] == 5
    output = capsys.readouterr().out
    assert (
        "activity bucket projection migration batch completed "
        "batch=3 rows=1 totalRows=5 lastSnapshotID=5"
    ) in output
    assert (
        "activity bucket projection migration completed batches=3 totalRows=5"
    ) in output


def test_sqlalchemy_repository_round_trips_relationship_history(tmp_path: Path) -> None:
    store = repository(tmp_path)
    document = {
        "projectionVersion": 2,
        "state": "loaded",
        "assignments": [],
        "events": [],
        "activeIssueIDs": ["issue:unlinkedBed:bed-a:-:Bed has no linked VRecorder."],
        "readError": None,
    }
    store.save_relationship_history(document, observed_at=datetime.now(UTC))
    assert store.relationships(event_limit=100) == {
        "state": "loaded",
        "assignments": [],
        "events": [],
        "eventTotalCount": 0,
        "eventLimit": 100,
        "readError": None,
    }
    assert store.previous_relationship_history() == document


def test_sqlalchemy_repository_excludes_deleted_entities_from_relationships(
    tmp_path: Path,
) -> None:
    store = repository(tmp_path)
    store.save_latest_observation(observation(), observed_at=datetime.now(UTC))
    store.save_relationship_history(
        {
            "state": "loaded",
            "assignments": [
                {
                    "assignmentID": "assignment-1",
                    "bedID": "bed-a",
                    "vrcode": "VR-001",
                }
            ],
            "events": [
                {
                    "eventID": "event-1",
                    "bedID": "bed-a",
                    "vrcode": "VR-001",
                    "previousBedID": None,
                    "previousVrcode": None,
                }
            ],
            "readError": None,
        },
        observed_at=datetime.now(UTC),
    )
    store.hide_recorders({"vrcodes": ["VR-001"]})
    store.delete_recorders({"vrcodes": ["VR-001"]})

    result = store.relationships(event_limit=100)

    assert result["assignments"] == []
    assert result["events"] == []


def test_sqlalchemy_repository_returns_recent_relationship_events_with_total(
    tmp_path: Path,
) -> None:
    store = repository(tmp_path)
    store.save_relationship_history(
        {
            "state": "loaded",
            "assignments": [],
            "events": [
                {"eventID": "event-1"},
                {"eventID": "event-2"},
                {"eventID": "event-3"},
            ],
            "readError": None,
        },
        observed_at=datetime.now(UTC),
    )

    result = store.relationships(event_limit=2)

    assert [event["eventID"] for event in result["events"]] == [
        "event-3",
        "event-2",
    ]
    assert result["eventTotalCount"] == 3
    assert result["eventLimit"] == 2


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
