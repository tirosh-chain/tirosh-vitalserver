"""PostgreSQL VitalDB read-model adapter tests."""

from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime
from typing import Any

import pytest

from tirosh_guest_tools.adapters.outbound.postgres import (
    PostgresVitalDBReadModelRepository,
)
from tirosh_guest_tools.application import compose as compose_app
from tirosh_guest_tools.domain.guest_control.models import (
    VitalDBReadModelDependencyError,
)


def psql_commands(arguments: list[str]) -> list[str]:
    return [
        arguments[index + 1]
        for index, argument in enumerate(arguments)
        if argument == "-c"
    ]


def test_vitaldb_read_model_repository_runs_schema_migration(
    monkeypatch: Any,
) -> None:
    calls: list[list[str]] = []

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        calls.append(arguments)
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    PostgresVitalDBReadModelRepository().ensure_schema()

    assert calls
    assert calls[0][:3] == ["exec", "-T", "postgres"]
    commands = psql_commands(calls[0])
    assert commands[0] == "SELECT pg_advisory_lock(66060002000);"
    assert "CREATE TABLE IF NOT EXISTS vitaldb_observation_snapshots" in commands[1]
    assert (
        "CREATE TABLE IF NOT EXISTS vitaldb_relationship_history_snapshots"
        in commands[1]
    )
    assert "CREATE TABLE IF NOT EXISTS vitaldb_entity_visibility" in commands[1]
    assert commands[2] == "SELECT pg_advisory_unlock(66060002000);"


def test_vitaldb_read_model_repository_persists_and_reads_latest_observation(
    monkeypatch: Any,
) -> None:
    saved_sql: list[str] = []
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "recorders": [],
        "beds": [],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        saved_sql.append(arguments[-1])
        if arguments[-1].startswith("SELECT"):
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps(
                    [observation] if "jsonb_agg" in arguments[-1] else observation,
                    sort_keys=True,
                ),
                stderr="",
            )
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    repository = PostgresVitalDBReadModelRepository()
    repository.save_latest_observation(
        observation,
        observed_at=datetime(2026, 7, 1, tzinfo=UTC),
    )
    response = repository.latest_observation()

    assert response == {
        "state": "loaded",
        "observation": observation,
        "readError": None,
    }
    assert "INSERT INTO vitaldb_observation_snapshots" in saved_sql[0]
    assert "SELECT document::text FROM vitaldb_observation_snapshots" in saved_sql[1]


def test_vitaldb_read_model_repository_reads_recorders_from_latest_observation(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [
            {
                "vrcode": "VR-001",
                "ip": "10.0.0.2",
                "lastSeenAt": "2026-07-01T00:00:00+00:00",
                "version": "1.0",
                "online": True,
                "stale": False,
            }
        ],
        "beds": [],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().recorders()

    assert response["state"] == "loaded"
    assert response["updatedAt"] == "2026-07-01T00:00:00+00:00"
    assert response["recorders"][0]["vrcode"] == "VR-001"
    assert response["recorders"][0]["status"] == "online"
    assert response["recorders"][0]["visibility"] == "visible"
    assert response["summary"]["knownRecorders"] == 1


def test_vitaldb_read_model_repository_applies_recorder_visibility(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [
            {"vrcode": "VR-001", "online": True, "stale": False},
            {"vrcode": "VR-002", "online": True, "stale": False},
            {"vrcode": "VR-003", "online": True, "stale": False},
        ],
        "beds": [],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps({"VR-001": "hidden", "VR-002": "deleted"}),
                stderr="",
            )
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().recorders()

    assert [
        (record["vrcode"], record["visibility"]) for record in response["recorders"]
    ] == [("VR-001", "hidden"), ("VR-003", "visible")]


def test_vitaldb_read_model_repository_requires_hidden_before_recorder_delete(
    monkeypatch: Any,
) -> None:
    calls: list[str] = []

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        calls.append(arguments[-1])
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps({"VR-001": "hidden"}),
                stderr="",
            )
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().delete_recorders(
            {"vrcodes": ["VR-001", "VR-002"]}
        )

    assert error.value.kind == "vitaldb-read-model-delete-not-hidden"
    assert "VR-002" in error.value.message
    assert not any("visibility = EXCLUDED.visibility" in sql for sql in calls)


def test_vitaldb_read_model_repository_marks_hidden_recorders_deleted(
    monkeypatch: Any,
) -> None:
    calls: list[str] = []
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [{"vrcode": "VR-001", "online": True, "stale": False}],
        "beds": [],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        calls.append(arguments[-1])
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps({"VR-001": "hidden"}),
                stderr="",
            )
        if "jsonb_agg" in arguments[-1]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps([observation]),
                stderr="",
            )
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    PostgresVitalDBReadModelRepository().delete_recorders({"vrcodes": ["VR-001"]})

    assert any("'deleted'" in sql for sql in calls)


def test_vitaldb_read_model_repository_reads_recorder_activity_from_latest_observation(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [],
        "beds": [],
        "activityBuckets": [
            {
                "vrcode": "VR-001",
                "bucketStartedAt": "2026-07-01T00:00:00+00:00",
                "bucketSeconds": 60,
                "messageCount": 2,
                "byteCount": 128,
                "roomCount": 1,
                "firstObservedAt": "2026-07-01T00:00:00+00:00",
                "lastObservedAt": "2026-07-01T00:00:59+00:00",
            },
            {
                "vrcode": "VR-002",
                "bucketStartedAt": "2026-07-01T00:00:00+00:00",
                "bucketSeconds": 60,
                "messageCount": 1,
                "byteCount": 64,
                "roomCount": 1,
                "firstObservedAt": "2026-07-01T00:00:00+00:00",
                "lastObservedAt": "2026-07-01T00:00:59+00:00",
            },
        ],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().recorder_activity("VR-001")

    assert response == {
        "state": "loaded",
        "vrcode": "VR-001",
        "buckets": [observation["activityBuckets"][0]],
        "readError": None,
    }


def test_vitaldb_read_model_repository_reports_invalid_recorder_activity(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [],
        "beds": [],
        "activityBuckets": [
            {
                "vrcode": "VR-001",
                "bucketStartedAt": "2026-07-01T00:00:00+00:00",
                "bucketSeconds": "60",
                "messageCount": 2,
                "byteCount": 128,
                "roomCount": 1,
                "firstObservedAt": "2026-07-01T00:00:00+00:00",
                "lastObservedAt": "2026-07-01T00:00:59+00:00",
            },
        ],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().recorder_activity("VR-001")

    assert error.value.kind == "vitaldb-read-model-invalid"
    assert "bucketSeconds" in error.value.message


def test_vitaldb_read_model_repository_reads_beds_from_latest_observation(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [],
        "beds": [
            {
                "bedID": "bed-a",
                "name": "OR-A",
                "vrcode": None,
                "lastSeenAt": "2026-07-01T00:00:00+00:00",
                "patientConnected": False,
                "online": True,
            }
        ],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().beds()

    assert response["state"] == "loaded"
    assert response["updatedAt"] == "2026-07-01T00:00:00+00:00"
    assert response["beds"][0]["bedID"] == "bed-a"
    assert response["beds"][0]["status"] == "online"
    assert response["beds"][0]["visibility"] == "visible"
    assert response["summary"]["knownBeds"] == 1


def test_vitaldb_read_model_repository_applies_bed_visibility(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [],
        "beds": [
            {"bedID": "bed-a", "online": True},
            {"bedID": "bed-b", "online": True},
            {"bedID": "bed-c", "online": True},
        ],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps({"bed-a": "hidden", "bed-b": "deleted"}),
                stderr="",
            )
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().beds()

    assert [(record["bedID"], record["visibility"]) for record in response["beds"]] == [
        ("bed-a", "hidden"),
        ("bed-c", "visible"),
    ]


def test_vitaldb_read_model_repository_requires_hidden_before_bed_delete(
    monkeypatch: Any,
) -> None:
    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps({"bed-a": "hidden"}),
                stderr="",
            )
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().delete_beds({"bedIDs": ["bed-a", "bed-b"]})

    assert error.value.kind == "vitaldb-read-model-delete-not-hidden"
    assert "bed-b" in error.value.message


def test_vitaldb_read_model_repository_persists_and_reads_relationships(
    monkeypatch: Any,
) -> None:
    saved_sql: list[str] = []
    relationship_history = {
        "state": "loaded",
        "assignments": [
            {
                "assignmentID": "assignment-1",
                "bedID": "bed-a",
                "bedName": "OR-A",
                "vrcode": "VR-001",
                "startedAt": "2026-07-01T00:00:00+00:00",
                "endedAt": None,
                "lastSeenAt": "2026-07-01T00:00:05+00:00",
                "lastObservedAt": "2026-07-01T00:00:05+00:00",
                "status": "online",
                "patientConnected": True,
                "observationCount": 2,
            }
        ],
        "events": [],
        "readError": None,
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        saved_sql.append(arguments[-1])
        if arguments[-1].startswith("SELECT"):
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps(relationship_history, sort_keys=True),
                stderr="",
            )
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    repository = PostgresVitalDBReadModelRepository()
    repository.save_relationship_history(
        relationship_history,
        observed_at=datetime(2026, 7, 1, tzinfo=UTC),
    )
    response = repository.relationships()

    assert response == relationship_history
    assert "INSERT INTO vitaldb_relationship_history_snapshots" in saved_sql[0]
    assert (
        "SELECT document::text FROM vitaldb_relationship_history_snapshots"
        in saved_sql[1]
    )


def test_vitaldb_read_model_repository_reports_empty_relationship_model(
    monkeypatch: Any,
) -> None:
    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().relationships()

    assert error.value.kind == "vitaldb-read-model-unavailable"
    assert error.value.message == "VitalDB relationship read model is empty."


def test_vitaldb_read_model_repository_reports_no_previous_relationship_history(
    monkeypatch: Any,
) -> None:
    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    previous = PostgresVitalDBReadModelRepository().previous_relationship_history()

    assert previous is None


def test_vitaldb_read_model_repository_reports_invalid_relationship_state(
    monkeypatch: Any,
) -> None:
    relationship_history = {
        "state": "unknown",
        "assignments": [],
        "events": [],
        "readError": None,
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(relationship_history, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().relationships()

    assert error.value.kind == "vitaldb-read-model-invalid"
    assert (
        error.value.message == "VitalDB relationship read model state field is invalid."
    )


def test_vitaldb_read_model_repository_preserves_loaded_empty_collection(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [],
        "beds": [],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().recorders()

    assert response["state"] == "loaded"
    assert response["updatedAt"] == "2026-07-01T00:00:00+00:00"
    assert response["recorders"] == []
    assert response["beds"] == []
    assert response["summary"]["knownRecorders"] == 0


def test_vitaldb_read_model_repository_reports_invalid_collection(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": None,
        "beds": [],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().recorders()

    assert error.value.kind == "vitaldb-read-model-invalid"
    assert error.value.message == "VitalDB observation recorders is invalid."


def test_vitaldb_read_model_repository_reports_invalid_observed_at(
    monkeypatch: Any,
) -> None:
    observation = {
        "observedAt": None,
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": [],
        "beds": [],
        "readIssues": [],
    }

    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        if "FROM vitaldb_entity_visibility" in arguments[-1]:
            return subprocess.CompletedProcess(arguments, 0, stdout="{}", stderr="")
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(
                [observation] if "jsonb_agg" in arguments[-1] else observation,
                sort_keys=True,
            ),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().beds()

    assert error.value.kind == "vitaldb-read-model-invalid"
    assert error.value.message == "VitalDB observation observedAt is invalid."


def test_vitaldb_read_model_repository_preserves_empty_read_model(
    monkeypatch: Any,
) -> None:
    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        assert capture_output is True
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().latest_observation()

    assert error.value.kind == "vitaldb-read-model-unavailable"
    assert error.value.message == "VitalDB observation read model is empty."


def test_vitaldb_read_model_repository_reports_psql_failure(
    monkeypatch: Any,
) -> None:
    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del timeout_seconds
        del capture_output
        raise subprocess.CalledProcessError(
            2,
            arguments,
            output="",
            stderr="postgres is unavailable",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().latest_observation()

    assert error.value.kind == "vitaldb-read-model-unavailable"
    assert "postgres is unavailable" in error.value.message
