from __future__ import annotations

import sqlite3
import stat
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from typing import Any, TypeVar

from sqlalchemy import Engine, Select, create_engine, event, select
from sqlalchemy.engine import Connection
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from tirosh_guest_tools.adapters.outbound.sqlite_control.mappings import (
    canonical_json,
    guest_service_resource_from_record,
    guest_service_resource_record_document,
    operation_event_from_record,
    operation_from_record,
    operation_index_timestamps,
    operation_record_from_domain,
    parse_document,
    sqlite_utc_naive_timestamp,
    update_operation_record,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control.migrations import (
    migrate_control_schema,
    validate_control_schema,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control.records import (
    ActiveOperationLeaseRecord,
    GuestServiceResourceRecord,
    OperationEventRecord,
    RedisRelayStatusRecord,
    ServiceOperationRecord,
    ServiceStatusSnapshotRecord,
)
from tirosh_guest_tools.domain.guest_control.models import (
    GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY,
    TERMINAL_OPERATION_STATES,
    GuestControlDependencyError,
    GuestControlPolicyError,
    GuestServiceResource,
    OperationEvent,
    OperationLease,
    OperationState,
    RedisRelayDependencyError,
    RedisRelayStatusContractError,
    ServiceOperation,
    ServiceStatus,
    operation_state_for_runtime_event_type,
    runtime_operation_event_type_for_state,
    validate_redis_relay_status_document,
)
from tirosh_guest_tools.domain.guest_control.operation_policy import (
    ensure_valid_operation_transition,
)

SQLITE_BUSY_TIMEOUT_MILLISECONDS = 5_000
T = TypeVar("T")


class SQLiteControlRepository:
    """The only writer for Guest Control's durable control state."""

    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path
        self._engine = build_sqlite_engine(database_path)

    def migrate_schema(self) -> None:
        try:
            self._database_path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
        except OSError as error:
            raise GuestControlDependencyError(
                "control SQLite data directory is unavailable: "
                f"{self._database_path.parent}: {error}",
                kind="controlStoreUnavailable",
            ) from error
        self._enable_wal_mode()
        self._write_connection(
            "control SQLite schema migration",
            migrate_control_schema,
        )

    def check_ready(self) -> None:
        try:
            file_mode = self._database_path.stat().st_mode
        except FileNotFoundError as error:
            raise GuestControlDependencyError(
                f"control SQLite database is missing: {self._database_path}",
                kind="controlStoreSchemaMissing",
            ) from error
        except OSError as error:
            raise GuestControlDependencyError(
                "control SQLite database is unavailable: "
                f"{self._database_path}: {error}",
                kind="controlStoreUnavailable",
            ) from error
        if not stat.S_ISREG(file_mode):
            raise GuestControlDependencyError(
                "control SQLite database is not a regular file: "
                f"{self._database_path}",
                kind="controlStoreUnavailable",
            )
        try:
            with self._engine.connect() as connection:
                validate_control_schema(connection)
                _require_wal_mode(connection)
        except GuestControlDependencyError:
            raise
        except SQLAlchemyError as error:
            raise control_store_error(
                error,
                stage="control SQLite readiness",
            ) from error

    def record_accepted(
        self,
        operation: ServiceOperation,
        *,
        lease: OperationLease,
    ) -> None:
        if operation.state != OperationState.ACCEPTED:
            raise GuestControlDependencyError(
                "control operation must be accepted before acquiring a lease: "
                f"operationId={operation.operation_id} state={operation.state.value}",
                kind="operationAcceptanceStateInvalid",
            )
        if lease.operation_id != operation.operation_id:
            raise GuestControlDependencyError(
                "control operation lease does not belong to the operation: "
                f"operationId={operation.operation_id} "
                f"leaseOperationId={lease.operation_id}",
                kind="operationLeaseInvalid",
            )
        if lease.resource_key != GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY:
            raise GuestControlDependencyError(
                "control operation lease must use the global Guest Control resource: "
                f"resource={lease.resource_key}",
                kind="operationLeaseResourceInvalid",
            )

        def write(session: Session) -> None:
            existing_operation = session.get(
                ServiceOperationRecord, operation.operation_id
            )
            if existing_operation is not None:
                raise GuestControlDependencyError(
                    "control operation already exists: "
                    f"operationId={operation.operation_id}",
                    kind="operationAlreadyExists",
                )
            existing_lease = session.get(ActiveOperationLeaseRecord, lease.resource_key)
            if existing_lease is not None:
                raise GuestControlDependencyError(
                    "a Guest Control operation already owns the command lease: "
                    f"resource={lease.resource_key} "
                    f"operationId={existing_lease.operation_id}",
                    kind="operationLeaseConflict",
                )
            session.add(operation_record_from_domain(operation))
            # Flush the parent inside the same transaction before inserting
            # dependent immutable event and lease records.
            session.flush()
            session.add(event_record_from_operation(operation))
            session.add(
                ActiveOperationLeaseRecord(
                    resource_key=lease.resource_key,
                    operation_id=lease.operation_id,
                    acquired_at=lease.acquired_at,
                )
            )

        self._write("control operation acceptance", write)

    def record_transition(
        self,
        operation: ServiceOperation,
    ) -> None:
        def write(session: Session) -> None:
            # Validate both public timestamps before transition policy compares
            # them to the persisted, explicitly-aware document values.
            operation_index_timestamps(operation)
            record = session.get(ServiceOperationRecord, operation.operation_id)
            if record is None:
                raise GuestControlDependencyError(
                    "control operation state is missing: "
                    f"operationId={operation.operation_id}",
                    kind="operationStateMissing",
                )
            persisted_operation = operation_from_record(record)
            try:
                ensure_valid_operation_transition(persisted_operation, operation)
            except GuestControlPolicyError as error:
                raise GuestControlDependencyError(
                    f"control operation transition is invalid: {error}",
                    kind="operationTransitionInvalid",
                ) from error
            lease = session.scalar(
                select(ActiveOperationLeaseRecord).where(
                    ActiveOperationLeaseRecord.operation_id == operation.operation_id
                )
            )
            if lease is None:
                raise GuestControlDependencyError(
                    "control operation lease is missing for transition: "
                    f"operationId={operation.operation_id}",
                    kind="operationLeaseMissing",
                )
            if lease.resource_key != GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY:
                raise GuestControlDependencyError(
                    "control operation lease does not use the global Guest Control "
                    f"resource: resource={lease.resource_key}",
                    kind="operationLeaseResourceInvalid",
                )
            update_operation_record(record, operation)
            session.add(event_record_from_operation(operation))
            if operation.state in TERMINAL_OPERATION_STATES:
                session.delete(lease)

        self._write("control operation transition", write)

    def list_unfinished_operations(self) -> list[ServiceOperation]:
        try:
            with Session(self._engine) as session:
                records = session.scalars(
                    select(ServiceOperationRecord)
                    # Do not turn an unknown persisted state into an absent
                    # operation. It must reach the strict record mapper and
                    # become an explicit corrupted-control-store failure.
                    .where(
                        ServiceOperationRecord.state.not_in(
                            tuple(state.value for state in TERMINAL_OPERATION_STATES)
                        )
                    )
                    .order_by(ServiceOperationRecord.created_at.asc())
                ).all()
                return [operation_from_record(record) for record in records]
        except SQLAlchemyError as error:
            raise control_store_error(
                error,
                stage="control unfinished operation read",
            ) from error

    def get(self, operation_id: str) -> ServiceOperation | None:
        try:
            with Session(self._engine) as session:
                record = session.get(ServiceOperationRecord, operation_id)
                return operation_from_record(record) if record is not None else None
        except SQLAlchemyError as error:
            raise control_store_error(
                error,
                stage="control operation read",
            ) from error

    def query_events(
        self,
        *,
        limit: int,
        event_type: str | None,
        since: datetime | None,
        cursor: str | None,
    ) -> dict[str, Any]:
        cursor_id = runtime_event_cursor_id(cursor)
        operation_state = _runtime_event_operation_state(event_type)
        if since is not None:
            since = sqlite_utc_naive_timestamp(
                since,
                kind="runtimeEventQueryInvalid",
                field="since",
            )
        statement: Select[tuple[OperationEventRecord, ServiceOperationRecord]] = (
            select(OperationEventRecord, ServiceOperationRecord)
            .join(
                ServiceOperationRecord,
                ServiceOperationRecord.operation_id
                == OperationEventRecord.operation_id,
            )
            .order_by(OperationEventRecord.event_id.desc())
            .limit(limit + 1)
        )
        if operation_state is not None:
            statement = statement.where(
                OperationEventRecord.state == operation_state.value
            )
        if since is not None:
            statement = statement.where(OperationEventRecord.observed_at >= since)
        if cursor_id is not None:
            statement = statement.where(OperationEventRecord.event_id < cursor_id)
        try:
            with Session(self._engine) as session:
                rows = session.execute(statement).all()
        except SQLAlchemyError as error:
            raise control_store_error(
                error,
                stage="control runtime event history read",
            ) from error

        has_next = len(rows) > limit
        events = [
            runtime_event_document(event, operation)
            for event, operation in rows[:limit]
        ]
        next_cursor = f"event:{rows[limit - 1][0].event_id}" if has_next else None
        return {
            "events": events,
            "nextCursor": next_cursor,
            "matchingCount": None,
        }

    def save_service_status_snapshot(self, status: ServiceStatus) -> None:
        def write(session: Session) -> None:
            record = session.get(ServiceStatusSnapshotRecord, status.service)
            if record is None:
                session.add(
                    ServiceStatusSnapshotRecord(
                        service=status.service,
                        document=canonical_json(status.as_json()),
                        observed_at=status.observed_at,
                    )
                )
                return
            record.document = canonical_json(status.as_json())
            record.observed_at = status.observed_at

        self._write("control service status snapshot save", write)

    def save_guest_service_resource(self, resource: GuestServiceResource) -> None:
        updated_at = resource_updated_at(resource)

        def write(session: Session) -> None:
            record = session.get(GuestServiceResourceRecord, resource.service)
            document = guest_service_resource_record_document(resource)
            if record is None:
                session.add(
                    GuestServiceResourceRecord(
                        service=resource.service,
                        document=document,
                        updated_at=updated_at,
                    )
                )
                return
            record.document = document
            record.updated_at = updated_at

        self._write("control guest service resource save", write)

    def get_guest_service_resource(self, service: str) -> GuestServiceResource | None:
        try:
            with Session(self._engine) as session:
                record = session.get(GuestServiceResourceRecord, service)
                return (
                    guest_service_resource_from_record(record)
                    if record is not None
                    else None
                )
        except SQLAlchemyError as error:
            raise control_store_error(
                error,
                stage="control guest service resource read",
            ) from error

    def save_status(self, document: dict[str, Any]) -> None:
        try:
            observed_at = validate_redis_relay_status_document(document)
        except RedisRelayStatusContractError as error:
            raise RedisRelayDependencyError(
                error.message,
                kind="redis-relay-contract-invalid",
            ) from error
        try:
            observed_at_datetime = datetime.fromisoformat(
                observed_at.replace("Z", "+00:00")
            )
        except ValueError as error:
            raise RedisRelayDependencyError(
                "Redis relay status observedAt is invalid.",
                kind="redis-relay-contract-invalid",
            ) from error

        def write(session: Session) -> None:
            record = session.get(RedisRelayStatusRecord, "current")
            if record is None:
                session.add(
                    RedisRelayStatusRecord(
                        snapshot_id="current",
                        document=canonical_json(document),
                        observed_at=observed_at_datetime,
                    )
                )
                return
            record.document = canonical_json(document)
            record.observed_at = observed_at_datetime

        try:
            self._write("control Redis relay status snapshot save", write)
        except GuestControlDependencyError as error:
            raise RedisRelayDependencyError(error.message, kind=error.kind) from error

    def status(self) -> dict[str, Any]:
        try:
            with Session(self._engine) as session:
                record = session.get(RedisRelayStatusRecord, "current")
                if record is None:
                    raise RedisRelayDependencyError(
                        "Redis relay status snapshot is missing.",
                        kind="redis-relay-status-missing",
                    )
                document = parse_document(
                    record.document,
                    kind="redis-relay-contract-invalid",
                )
        except RedisRelayDependencyError:
            raise
        except SQLAlchemyError as error:
            raise RedisRelayDependencyError(
                control_store_error(
                    error,
                    stage="control Redis relay status snapshot read",
                ).message,
                kind="redis-relay-status-unavailable",
            ) from error
        try:
            validate_redis_relay_status_document(document)
        except RedisRelayStatusContractError as error:
            raise RedisRelayDependencyError(
                error.message,
                kind="redis-relay-contract-invalid",
            ) from error
        return {
            "readState": "loaded",
            "document": document,
            "readError": None,
        }

    def _write(self, stage: str, action: Callable[[Session], T]) -> T:
        return self._write_connection(
            stage,
            lambda connection: _write_session(connection, action),
        )

    def _write_connection(
        self,
        stage: str,
        action: Callable[[Connection], T],
    ) -> T:
        try:
            with self._engine.connect() as connection:
                connection.exec_driver_sql("BEGIN IMMEDIATE")
                try:
                    result = action(connection)
                    connection.commit()
                    return result
                except Exception:
                    connection.rollback()
                    raise
        except GuestControlDependencyError:
            raise
        except SQLAlchemyError as error:
            raise control_store_error(error, stage=stage) from error

    def _enable_wal_mode(self) -> None:
        try:
            with self._engine.connect() as connection:
                journal_mode = connection.exec_driver_sql(
                    "PRAGMA journal_mode = WAL"
                ).scalar_one()
                if str(journal_mode).lower() != "wal":
                    raise GuestControlDependencyError(
                        "control SQLite WAL mode was not enabled: "
                        f"actual={journal_mode!r}",
                        kind="controlStoreJournalModeInvalid",
                    )
        except GuestControlDependencyError:
            raise
        except SQLAlchemyError as error:
            raise control_store_error(
                error,
                stage="control SQLite WAL mode migration",
            ) from error


def build_sqlite_engine(database_path: Path) -> Engine:
    engine = create_engine(
        f"sqlite+pysqlite:///{database_path}",
        future=True,
        connect_args={
            "check_same_thread": False,
            "timeout": SQLITE_BUSY_TIMEOUT_MILLISECONDS / 1000,
        },
    )

    @event.listens_for(engine, "connect")
    def configure_connection(
        connection: sqlite3.Connection,
        _: object,
    ) -> None:
        cursor = connection.cursor()
        try:
            cursor.execute("PRAGMA foreign_keys = ON")
            cursor.execute(f"PRAGMA busy_timeout = {SQLITE_BUSY_TIMEOUT_MILLISECONDS}")
        finally:
            cursor.close()

    return engine


def _write_session(  # noqa: UP047 -- Guest runtime supports Python 3.11.
    connection: Connection,
    action: Callable[[Session], T],
) -> T:
    session = Session(bind=connection, expire_on_commit=False)
    try:
        result = action(session)
        session.flush()
        return result
    finally:
        session.close()


def _require_wal_mode(connection: Connection) -> None:
    journal_mode = connection.exec_driver_sql("PRAGMA journal_mode").scalar_one()
    if str(journal_mode).lower() != "wal":
        raise GuestControlDependencyError(
            "control SQLite journal mode is not WAL: "
            f"actual={journal_mode!r}",
            kind="controlStoreJournalModeInvalid",
        )


def event_record_from_operation(operation: ServiceOperation) -> OperationEventRecord:
    event = OperationEvent(
        operation_id=operation.operation_id,
        state=operation.state,
        observed_at=operation.updated_at,
        failure=operation.failure,
        result=operation.result,
    )
    return OperationEventRecord(
        operation_id=event.operation_id,
        state=event.state.value,
        document=canonical_json(event.as_json()),
        observed_at=sqlite_utc_naive_timestamp(
            event.observed_at,
            kind="runtimeEventHistoryInvalid",
            field="observedAt",
        ),
    )


def runtime_event_document(
    event: OperationEventRecord,
    operation: ServiceOperationRecord,
) -> dict[str, Any]:
    event_document = operation_event_from_record(event)
    operation_document = operation_from_record(operation)
    try:
        event_type = runtime_operation_event_type_for_state(event_document.state)
    except GuestControlPolicyError as error:
        raise GuestControlDependencyError(
            f"control runtime event state is not public: {error}",
            kind="runtimeEventHistoryInvalid",
        ) from error
    return {
        "schemaVersion": 1,
        "id": f"runtime-operation-event-{event.event_id}",
        "source": "runtime-controller",
        "eventType": event_type,
        "timestamp": event_document.observed_at.isoformat(),
        "operationId": event_document.operation_id,
        "operationService": operation_document.service,
        "operationCommand": operation_document.command.value,
        "operationState": event_document.state.value,
        "message": (
            f"{operation_document.service} {operation_document.command.value} "
            f"{event_document.state.value}"
        ),
        "failure": (
            event_document.failure.as_json()
            if event_document.failure is not None
            else None
        ),
    }


def resource_updated_at(resource: GuestServiceResource) -> datetime:
    updated_at = resource.spec.updated_at
    for condition in resource.conditions:
        if updated_at is None or condition.observed_at > updated_at:
            updated_at = condition.observed_at
    if resource.status.service_status is not None and (
        updated_at is None or resource.status.service_status.observed_at > updated_at
    ):
        updated_at = resource.status.service_status.observed_at
    if updated_at is None:
        raise GuestControlDependencyError(
            "guest service resource is missing explicit update time",
            kind="guestServiceResourceInvalid",
        )
    return updated_at


def runtime_event_cursor_id(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    prefix = "event:"
    if not cursor.startswith(prefix):
        raise GuestControlDependencyError(
            "runtime event history cursor is invalid",
            kind="runtimeEventCursorInvalid",
        )
    try:
        value = int(cursor.removeprefix(prefix))
    except ValueError as error:
        raise GuestControlDependencyError(
            "runtime event history cursor is invalid",
            kind="runtimeEventCursorInvalid",
        ) from error
    if value < 1:
        raise GuestControlDependencyError(
            "runtime event history cursor is invalid",
            kind="runtimeEventCursorInvalid",
        )
    return value


def _runtime_event_operation_state(event_type: str | None) -> OperationState | None:
    if event_type is None:
        return None
    try:
        return operation_state_for_runtime_event_type(event_type)
    except GuestControlPolicyError as error:
        raise GuestControlDependencyError(
            f"runtime event history type is invalid: {error}",
            kind="runtimeEventQueryInvalid",
        ) from error


def control_store_error(
    error: SQLAlchemyError, *, stage: str
) -> GuestControlDependencyError:
    message = str(error).lower()
    if "database is locked" in message or "database is busy" in message:
        kind = "controlStoreBusy"
    elif "no such table" in message:
        kind = "controlStoreSchemaMissing"
    else:
        kind = "controlStoreUnavailable"
    return GuestControlDependencyError(
        f"{stage} failed: {error}",
        kind=kind,
    )
