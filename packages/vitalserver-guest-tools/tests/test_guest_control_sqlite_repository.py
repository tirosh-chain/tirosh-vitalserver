from __future__ import annotations

import json
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.sqlite_control import (
    SQLiteControlRepository,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control import (
    repository as sqlite_repository,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control.mappings import (
    operation_from_document,
    service_status_from_document,
)
from tirosh_guest_tools.application.guest_control.usecases import GuestControlUseCases
from tirosh_guest_tools.domain.guest_control.models import (
    GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY,
    GuestControlDependencyError,
    OperationFailure,
    OperationLease,
    OperationState,
    ServiceCommand,
    ServiceOperation,
    ServiceStatus,
)
from tirosh_guest_tools.domain.guest_control.operation_policy import (
    fail_operation,
    finish_operation,
    start_operation,
)
from tirosh_guest_tools.domain.runtime_observation import RuntimeResourceUsage


def operation(
    operation_id: str = "op_app_restart_1",
) -> ServiceOperation:
    return ServiceOperation(
        operation_id=operation_id,
        service="app",
        command=ServiceCommand.RESTART,
        state=OperationState.ACCEPTED,
        created_at=datetime(2026, 7, 1, tzinfo=UTC),
        updated_at=datetime(2026, 7, 1, tzinfo=UTC),
    )


def lease_for(value: ServiceOperation) -> OperationLease:
    return OperationLease(
        resource_key=GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY,
        operation_id=value.operation_id,
        acquired_at=value.created_at,
    )


def test_sqlite_control_store_requires_explicit_schema_migration(
    tmp_path: Path,
) -> None:
    control_dir = tmp_path / "control"
    control_dir.mkdir()
    repository = SQLiteControlRepository(control_dir / "control.sqlite")

    with pytest.raises(GuestControlDependencyError) as error:
        repository.check_ready()

    assert error.value.kind == "controlStoreSchemaMissing"
    assert not (control_dir / "control.sqlite").exists()

    repository.migrate_schema()
    repository.check_ready()
    assert journal_mode(control_dir / "control.sqlite") == "wal"


def test_sqlite_control_store_rejects_unexpected_schema_history(
    tmp_path: Path,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    with sqlite3.connect(database) as connection:
        connection.execute(
            "INSERT INTO control_schema_migrations (version, checksum, applied_at) "
            "VALUES (?, ?, ?)",
            ("9999", "unexpected", "2026-07-01T00:00:01+00:00"),
        )

    with pytest.raises(GuestControlDependencyError) as error:
        repository.check_ready()

    assert error.value.kind == "controlStoreSchemaMismatch"


def test_sqlite_control_store_rejects_missing_required_table(tmp_path: Path) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    with sqlite3.connect(database) as connection:
        connection.execute("DROP TABLE service_status_snapshots")

    with pytest.raises(GuestControlDependencyError) as error:
        repository.migrate_schema()

    assert error.value.kind == "controlStoreSchemaMismatch"


def test_sqlite_control_store_records_operation_event_and_lease_atomically(
    tmp_path: Path,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()

    repository.record_accepted(accepted, lease=lease_for(accepted))

    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    repository.record_transition(running)
    completed = finish_operation(
        running,
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
        result={"result": "done"},
    )
    repository.record_transition(completed)

    assert repository.get(completed.operation_id) == completed
    events = repository.query_events(
        limit=10,
        event_type=None,
        since=None,
        cursor=None,
    )
    assert [event["operationState"] for event in events["events"]] == [
        "completed",
        "running",
        "accepted",
    ]
    assert table_count(database, "active_operation_leases") == 0


def test_sqlite_control_store_rolls_back_operation_event_and_lease_together(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()

    def fail_event(_: ServiceOperation) -> object:
        raise GuestControlDependencyError("injected event failure", kind="injected")

    monkeypatch.setattr(sqlite_repository, "event_record_from_operation", fail_event)

    with pytest.raises(GuestControlDependencyError) as error:
        repository.record_accepted(accepted, lease=lease_for(accepted))

    assert error.value.kind == "injected"
    assert repository.get(accepted.operation_id) is None
    assert table_count(database, "service_operations") == 0
    assert table_count(database, "service_operation_events") == 0
    assert table_count(database, "active_operation_leases") == 0


def test_sqlite_control_store_rolls_back_terminal_transition_and_lease_together(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    repository.record_transition(running)
    completed = finish_operation(
        running,
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
    )

    def event_with_missing_parent(
        value: ServiceOperation,
    ) -> sqlite_repository.OperationEventRecord:
        return sqlite_repository.OperationEventRecord(
            operation_id="missing-operation",
            state=value.state.value,
            document="{}",
            observed_at=value.updated_at,
        )

    monkeypatch.setattr(
        sqlite_repository,
        "event_record_from_operation",
        event_with_missing_parent,
    )

    with pytest.raises(GuestControlDependencyError) as error:
        repository.record_transition(completed)

    assert error.value.kind == "controlStoreUnavailable"
    assert repository.get(running.operation_id) == running
    assert table_count(database, "service_operation_events") == 2
    assert table_count(database, "active_operation_leases") == 1


def test_sqlite_control_store_rejects_concurrent_active_operation_lease(
    tmp_path: Path,
) -> None:
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    first = operation("op_first")
    second = operation("op_second")
    repository.record_accepted(first, lease=lease_for(first))

    with pytest.raises(GuestControlDependencyError) as error:
        repository.record_accepted(second, lease=lease_for(second))

    assert error.value.kind == "operationLeaseConflict"
    assert repository.get(second.operation_id) is None


@pytest.mark.parametrize(
    ("invalid_operation", "invalid_lease", "expected_kind"),
    [
        (
            ServiceOperation(
                operation_id="op_completed",
                service="app",
                command=ServiceCommand.RESTART,
                state=OperationState.COMPLETED,
                created_at=datetime(2026, 7, 1, tzinfo=UTC),
                updated_at=datetime(2026, 7, 1, tzinfo=UTC),
            ),
            None,
            "operationAcceptanceStateInvalid",
        ),
        (
            operation("op_other_resource"),
            OperationLease(
                resource_key="app-only",
                operation_id="op_other_resource",
                acquired_at=datetime(2026, 7, 1, tzinfo=UTC),
            ),
            "operationLeaseResourceInvalid",
        ),
    ],
)
def test_sqlite_control_store_rejects_invalid_operation_acceptance_contract(
    tmp_path: Path,
    invalid_operation: ServiceOperation,
    invalid_lease: OperationLease | None,
    expected_kind: str,
) -> None:
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    lease = invalid_lease or lease_for(invalid_operation)

    with pytest.raises(GuestControlDependencyError) as error:
        repository.record_accepted(invalid_operation, lease=lease)

    assert error.value.kind == expected_kind
    assert repository.get(invalid_operation.operation_id) is None
    assert table_count(tmp_path / "control.sqlite", "active_operation_leases") == 0


def test_sqlite_control_store_rejects_transition_without_matching_lease(
    tmp_path: Path,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))
    with sqlite3.connect(database) as connection:
        connection.execute(
            "DELETE FROM active_operation_leases WHERE operation_id = ?",
            (accepted.operation_id,),
        )
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )

    with pytest.raises(GuestControlDependencyError) as error:
        repository.record_transition(running)

    assert error.value.kind == "operationLeaseMissing"
    persisted = repository.get(accepted.operation_id)
    assert persisted is not None
    assert persisted.state == OperationState.ACCEPTED


def test_sqlite_control_store_lists_only_unfinished_operations(tmp_path: Path) -> None:
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))

    assert repository.list_unfinished_operations() == [accepted]

    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    repository.record_transition(running)
    completed = finish_operation(
        running,
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
    )
    repository.record_transition(completed)

    assert repository.list_unfinished_operations() == []


def test_sqlite_control_store_does_not_hide_unknown_operation_state(
    tmp_path: Path,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))
    with sqlite3.connect(database) as connection:
        connection.execute(
            "UPDATE service_operations SET state = ? WHERE operation_id = ?",
            ("unknown-future-state", accepted.operation_id),
        )

    with pytest.raises(GuestControlDependencyError) as error:
        repository.list_unfinished_operations()

    assert error.value.kind == "controlOperationDocumentInvalid"


def test_controller_restart_interrupts_unfinished_operation_and_releases_lease(
    tmp_path: Path,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    repository.record_transition(running)
    usecases = GuestControlUseCases(
        service_control=UnusedServiceControl(),
        operations=repository,
        service_status_snapshots=repository,
        guest_service_resources=repository,
        operation_ids=UnusedOperationIds(),
        clock=RestartClock(),
    )

    usecases.recover_interrupted_operations()

    interrupted = repository.get(accepted.operation_id)
    assert interrupted is not None
    assert interrupted.state == OperationState.INTERRUPTED
    assert interrupted.failure is not None
    assert interrupted.failure.kind == "controllerRestarted"
    events = repository.query_events(
        limit=10,
        event_type=None,
        since=None,
        cursor=None,
    )
    assert [event["operationState"] for event in events["events"]] == [
        "interrupted",
        "running",
        "accepted",
    ]
    assert table_count(database, "active_operation_leases") == 0
    assert repository.list_unfinished_operations() == []


def test_sqlite_control_store_rejects_failed_operation_without_failure_document(
    tmp_path: Path,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    repository.record_transition(running)
    failed = fail_operation(
        running,
        failure=OperationFailure(kind="composeFailed", message="compose failed"),
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
    )
    repository.record_transition(failed)

    with sqlite3.connect(database) as connection:
        row = connection.execute(
            "SELECT document FROM service_operations WHERE operation_id = ?",
            (failed.operation_id,),
        ).fetchone()
        assert row is not None
        document = json.loads(str(row[0]))
        document.pop("failure")
        connection.execute(
            "UPDATE service_operations SET document = ? WHERE operation_id = ?",
            (json.dumps(document), failed.operation_id),
        )

    with pytest.raises(GuestControlDependencyError) as error:
        repository.get(failed.operation_id)

    assert error.value.kind == "controlOperationDocumentInvalid"


def test_sqlite_control_store_rejects_index_and_document_state_mismatch(
    tmp_path: Path,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))

    with sqlite3.connect(database) as connection:
        connection.execute(
            "UPDATE service_operations SET state = ? WHERE operation_id = ?",
            ("running", accepted.operation_id),
        )

    with pytest.raises(GuestControlDependencyError) as error:
        repository.get(accepted.operation_id)

    assert error.value.kind == "controlOperationDocumentInvalid"


@pytest.mark.parametrize(
    ("event_column", "event_value", "document_update"),
    [
        ("state", "running", None),
        ("document", None, {"failure": "not-a-failure-document"}),
    ],
)
def test_sqlite_control_store_rejects_invalid_runtime_event_history(
    tmp_path: Path,
    event_column: str,
    event_value: str | None,
    document_update: dict[str, object] | None,
) -> None:
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    accepted = operation()
    repository.record_accepted(accepted, lease=lease_for(accepted))
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    repository.record_transition(running)
    failed = fail_operation(
        running,
        failure=OperationFailure(kind="composeFailed", message="compose failed"),
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
    )
    repository.record_transition(failed)
    with sqlite3.connect(database) as connection:
        if document_update is not None:
            row = connection.execute(
                "SELECT document FROM service_operation_events "
                "WHERE operation_id = ? ORDER BY event_id DESC LIMIT 1",
                (failed.operation_id,),
            ).fetchone()
            assert row is not None
            document = json.loads(str(row[0]))
            document.update(document_update)
            event_value = json.dumps(document)
        connection.execute(
            f"UPDATE service_operation_events SET {event_column} = ? "
            "WHERE operation_id = ? AND state = ?",
            (event_value, failed.operation_id, "failed"),
        )

    with pytest.raises(GuestControlDependencyError) as error:
        repository.query_events(limit=10, event_type=None, since=None, cursor=None)

    assert error.value.kind == "runtimeEventHistoryInvalid"


def test_sqlite_control_mapping_rejects_invalid_optional_failure_field() -> None:
    document = operation().as_json()
    document["failure"] = {
        "kind": "composeFailed",
        "message": "compose failed",
        "evidencePath": ["not", "a", "path"],
    }

    with pytest.raises(GuestControlDependencyError) as error:
        operation_from_document(document)

    assert error.value.kind == "controlDocumentInvalid"


def test_sqlite_control_mapping_round_trips_service_status_memory() -> None:
    status = ServiceStatus(
        service="app",
        state="running",
        health="healthy",
        observed_at=datetime(2026, 7, 1, tzinfo=UTC),
        memory=RuntimeResourceUsage(used_bytes=128, total_bytes=256),
    )

    assert service_status_from_document(status.as_json()) == status


def test_sqlite_control_mapping_rejects_invalid_service_status_memory() -> None:
    document = ServiceStatus(
        service="app",
        state="running",
        health="healthy",
        observed_at=datetime(2026, 7, 1, tzinfo=UTC),
    ).as_json()
    document["memory"] = {"usedBytes": "128", "totalBytes": 256}

    with pytest.raises(GuestControlDependencyError) as error:
        service_status_from_document(document)

    assert error.value.kind == "guestServiceResourceDocumentInvalid"


class RestartClock:
    def now(self) -> datetime:
        return datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC)


class UnusedOperationIds:
    def new_operation_id(self, *, service: str, command: str) -> str:
        raise AssertionError(f"unexpected operation id request: {service} {command}")


class UnusedServiceControl:
    pass


def table_count(database: Path, table: str) -> int:
    with sqlite3.connect(database) as connection:
        row = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()
    assert row is not None
    return int(row[0])


def journal_mode(database: Path) -> str:
    with sqlite3.connect(database) as connection:
        row = connection.execute("PRAGMA journal_mode").fetchone()
    assert row is not None
    return str(row[0])
