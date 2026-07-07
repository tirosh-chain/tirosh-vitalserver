from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime
from typing import Any

import pytest

from tirosh_guest_tools.adapters.outbound.postgres import (
    PostgresOperationRepository,
    PostgresVitalDBReadModelRepository,
)
from tirosh_guest_tools.application import compose as compose_app
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    GuestServiceCondition,
    GuestServiceDesiredState,
    GuestServiceObservedState,
    GuestServiceResource,
    GuestServiceSpec,
    GuestServiceStatusRead,
    OperationEvent,
    OperationState,
    ServiceCommand,
    ServiceOperation,
    ServiceStatus,
    VitalDBReadModelDependencyError,
)


def psql_commands(arguments: list[str]) -> list[str]:
    return [
        arguments[index + 1]
        for index, argument in enumerate(arguments)
        if argument == "-c"
    ]


def test_postgres_repository_runs_schema_migration(monkeypatch: Any) -> None:
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

    PostgresOperationRepository().ensure_schema()

    assert calls
    assert calls[0][:3] == ["exec", "-T", "postgres"]
    commands = psql_commands(calls[0])
    assert commands[0] == "SELECT pg_advisory_lock(66060002000);"
    assert "CREATE TABLE IF NOT EXISTS service_operations" in commands[1]
    assert "CREATE TABLE IF NOT EXISTS service_operation_events" in commands[1]
    assert "CREATE TABLE IF NOT EXISTS service_status_snapshots" in commands[1]
    assert "CREATE TABLE IF NOT EXISTS guest_service_resources" in commands[1]
    assert commands[2] == "SELECT pg_advisory_unlock(66060002000);"


def test_postgres_repository_persists_and_reads_operation(
    monkeypatch: Any,
) -> None:
    saved_sql: list[str] = []
    operation = ServiceOperation(
        operation_id="op_app_restart_1",
        service="app",
        command=ServiceCommand.RESTART,
        state=OperationState.COMPLETED,
        created_at=datetime(2026, 7, 1, tzinfo=UTC),
        updated_at=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
        result={"archive": "/mnt/tirosh-runtime/backups/redis/redis.tar.gz"},
    )

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
                stdout=json.dumps(operation.as_json(), sort_keys=True),
                stderr="",
            )
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    repository = PostgresOperationRepository()
    repository.save(operation)
    loaded = repository.get(operation.operation_id)

    assert loaded == operation
    assert loaded is not None
    assert loaded.result == {
        "archive": "/mnt/tirosh-runtime/backups/redis/redis.tar.gz"
    }
    assert "ON CONFLICT (operation_id) DO UPDATE" in saved_sql[0]
    assert "SELECT document::text FROM service_operations" in saved_sql[1]


def test_postgres_repository_appends_operation_event(monkeypatch: Any) -> None:
    saved_sql: list[str] = []
    event = OperationEvent(
        operation_id="op_app_restart_1",
        state=OperationState.RUNNING,
        observed_at=datetime(2026, 7, 1, tzinfo=UTC),
    )

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
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    PostgresOperationRepository().append_event(event)

    assert "INSERT INTO service_operation_events" in saved_sql[0]
    assert "'op_app_restart_1'" in saved_sql[0]
    assert "'running'" in saved_sql[0]


def test_postgres_repository_saves_service_status_snapshot(monkeypatch: Any) -> None:
    saved_sql: list[str] = []
    status = ServiceStatus(
        service="app",
        state="running",
        health="healthy",
        observed_at=datetime(2026, 7, 1, tzinfo=UTC),
        container="vitalserver-app-1",
        exit_code=0,
    )

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
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    PostgresOperationRepository().save_service_status_snapshot(status)

    assert "INSERT INTO service_status_snapshots" in saved_sql[0]
    assert "ON CONFLICT (service) DO UPDATE" in saved_sql[0]
    assert "'app'" in saved_sql[0]


def test_postgres_repository_persists_and_reads_guest_service_resource(
    monkeypatch: Any,
) -> None:
    saved_sql: list[str] = []
    resource = GuestServiceResource(
        service="app",
        spec=GuestServiceSpec.configured(
            desired_state=GuestServiceDesiredState.RUNNING,
            updated_at=datetime(2026, 7, 1, tzinfo=UTC),
        ),
        status=GuestServiceStatusRead.loaded(
            ServiceStatus(
                service="app",
                state="running",
                health="healthy",
                observed_at=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
            ),
            observed_state=GuestServiceObservedState.RUNNING,
        ),
        conditions=[
            GuestServiceCondition(
                type="Reconciled",
                status="true",
                reason="DesiredStateObserved",
                message="Guest service already matches desired state.",
                observed_at=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
            )
        ],
        last_operation_id="op_app_start_1",
    )

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
                stdout=json.dumps(resource.as_json(), sort_keys=True),
                stderr="",
            )
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    repository = PostgresOperationRepository()
    repository.save_guest_service_resource(resource)
    loaded = repository.get_guest_service_resource("app")

    assert loaded == resource
    assert "INSERT INTO guest_service_resources" in saved_sql[0]
    assert "ON CONFLICT (service) DO UPDATE" in saved_sql[0]
    assert "SELECT document::text FROM guest_service_resources" in saved_sql[1]


def test_postgres_repository_rejects_invalid_guest_service_resource_document(
    monkeypatch: Any,
) -> None:
    document = {
        "service": "app",
        "spec": {
            "state": "configured",
            "desiredState": "running",
            "updatedAt": "2026-07-01T00:00:00+00:00",
        },
        "status": {
            "state": "loaded",
            "observedState": "paused",
            "serviceStatus": {
                "service": "app",
                "state": "running",
                "health": "healthy",
                "observedAt": "2026-07-01T00:00:00+00:00",
            },
            "readError": None,
        },
        "conditions": [],
        "lastOperationId": None,
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
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(document, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(GuestControlDependencyError) as error:
        PostgresOperationRepository().get_guest_service_resource("app")

    assert error.value.kind == "guestServiceResourceDocumentInvalid"


def test_postgres_repository_reports_psql_failure(monkeypatch: Any) -> None:
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
            stderr="relation does not exist",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(GuestControlDependencyError) as error:
        PostgresOperationRepository().ensure_schema()

    assert error.value.kind == "postgresCommandFailed"
    assert "relation does not exist" in error.value.message


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
                stdout=json.dumps(observation, sort_keys=True),
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
                "bedName": "OR-A",
                "status": "connected",
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
            stdout=json.dumps(observation, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().recorders()

    assert response == {
        "state": "loaded",
        "recorders": [{**observation["recorders"][0], "visibility": "visible"}],
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "readError": None,
    }


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
            stdout=json.dumps(observation, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().recorders()

    assert response["recorders"] == [
        {"vrcode": "VR-001", "online": True, "stale": False, "visibility": "hidden"},
        {"vrcode": "VR-003", "online": True, "stale": False, "visibility": "visible"},
    ]


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
        if "SELECT document::text FROM vitaldb_observation_snapshots" in arguments[-1]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout=json.dumps(observation),
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
            stdout=json.dumps(observation, sort_keys=True),
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
            stdout=json.dumps(observation, sort_keys=True),
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
                "recorderCount": 1,
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
            stdout=json.dumps(observation, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().beds()

    assert response == {
        "state": "loaded",
        "beds": [{**observation["beds"][0], "visibility": "visible"}],
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "readError": None,
    }


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
            stdout=json.dumps(observation, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().beds()

    assert response["beds"] == [
        {"bedID": "bed-a", "online": True, "visibility": "hidden"},
        {"bedID": "bed-c", "online": True, "visibility": "visible"},
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
        PostgresVitalDBReadModelRepository().delete_beds(
            {"bedIDs": ["bed-a", "bed-b"]}
        )

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
        error.value.message
        == "VitalDB relationship read model state field is invalid."
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
            stdout=json.dumps(observation, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    response = PostgresVitalDBReadModelRepository().recorders()

    assert response == {
        "state": "loaded",
        "recorders": [],
        "observedAt": "2026-07-01T00:00:00+00:00",
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "readError": None,
    }


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
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(observation, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().recorders()

    assert error.value.kind == "vitaldb-read-model-invalid"
    assert error.value.message == "VitalDB recorder read model field is invalid."


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
        return subprocess.CompletedProcess(
            arguments,
            0,
            stdout=json.dumps(observation, sort_keys=True),
            stderr="",
        )

    monkeypatch.setattr(compose_app, "compose", fake_compose)

    with pytest.raises(VitalDBReadModelDependencyError) as error:
        PostgresVitalDBReadModelRepository().beds()

    assert error.value.kind == "vitaldb-read-model-invalid"
    assert (
        error.value.message
        == "VitalDB observation read model observedAt field is invalid."
    )


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
