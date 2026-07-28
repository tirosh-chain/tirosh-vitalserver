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
    ActiveGuestRuntimeReleaseRecord,
    ActiveOperationLeaseRecord,
    ContainerImageSetOperationRecord,
    ContainerImageSetRecord,
    CurrentContainerImageSetRecord,
    GuestRuntimeReleaseOperationRecord,
    GuestRuntimeReleaseRecord,
    GuestServiceResourceRecord,
    InitialUpdateOwnerProvisioningRecord,
    OperationEventRecord,
    RedisRelayStatusRecord,
    ServiceOperationRecord,
    ServiceStatusSnapshotRecord,
)
from tirosh_guest_tools.domain.container_image_set import (
    TERMINAL_CONTAINER_IMAGE_SET_OPERATION_STATES,
    ContainerImageSet,
    ContainerImageSetCommand,
    ContainerImageSetConflictError,
    ContainerImageSetContractError,
    ContainerImageSetDependencyError,
    ContainerImageSetFailure,
    ContainerImageSetOperation,
    ContainerImageSetOperationState,
    transition_container_image_set_operation,
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
from tirosh_guest_tools.domain.guest_runtime_release import (
    TERMINAL_GUEST_RUNTIME_RELEASE_OPERATION_STATES,
    GuestRuntimeRelease,
    GuestRuntimeReleaseCommand,
    GuestRuntimeReleaseConflictError,
    GuestRuntimeReleaseContractError,
    GuestRuntimeReleaseDependencyError,
    GuestRuntimeReleaseFailure,
    GuestRuntimeReleaseOperation,
    GuestRuntimeReleaseOperationState,
    transition_guest_runtime_release_operation,
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
                f"control SQLite database is not a regular file: {self._database_path}",
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

    def provision_current_container_image_set(
        self,
        image_set: ContainerImageSet,
        *,
        observed_at: datetime,
    ) -> None:
        """Persist an installer-observed initial current image-set explicitly."""

        def write(session: Session) -> None:
            self._require_immutable_image_set(session, image_set, observed_at)
            current = session.get(CurrentContainerImageSetRecord, "current")
            if current is not None:
                raise ContainerImageSetConflictError(
                    "Current container image-set is already provisioned: "
                    f"identity={current.identity}.",
                    kind="containerImageSetAlreadyProvisioned",
                )
            session.add(
                CurrentContainerImageSetRecord(
                    owner_key="current",
                    identity=image_set.identity,
                    updated_at=observed_at,
                )
            )

        self._container_image_set_write("container image-set provision", write)

    def provision_initial_update_owner_state(
        self,
        *,
        container_image_set: ContainerImageSet,
        contract_digest: str,
        container_archive: str,
        guest_runtime_release: GuestRuntimeRelease,
        observed_at: datetime,
    ) -> None:
        """Persist both fresh-install update owners in one transaction."""

        def write(session: Session) -> None:
            receipt = session.get(
                InitialUpdateOwnerProvisioningRecord,
                "initial",
            )
            expected_receipt = (
                contract_digest,
                container_image_set.identity,
                container_image_set.digest,
                container_archive,
                guest_runtime_release.identity,
                guest_runtime_release.digest,
                guest_runtime_release.archive,
            )
            if receipt is not None:
                actual_receipt = (
                    receipt.contract_digest,
                    receipt.container_identity,
                    receipt.container_digest,
                    receipt.container_archive,
                    receipt.guest_runtime_identity,
                    receipt.guest_runtime_digest,
                    receipt.guest_runtime_archive,
                )
                if actual_receipt == expected_receipt:
                    return
                raise ContainerImageSetConflictError(
                    "Initial update owner provisioning receipt disagrees with "
                    "the installed release contract.",
                    kind="initialUpdateOwnerProvisioningReceiptMismatch",
                )
            current = session.get(CurrentContainerImageSetRecord, "current")
            active = session.get(ActiveGuestRuntimeReleaseRecord, "active")
            if current is not None or active is not None:
                raise ContainerImageSetConflictError(
                    "Initial update owner state exists without its provisioning "
                    "receipt: "
                    f"container={current.identity if current else 'missing'} "
                    f"guestRuntime={active.identity if active else 'missing'}.",
                    kind="initialUpdateOwnerProvisioningPartialState",
                )
            self._require_immutable_image_set(
                session,
                container_image_set,
                observed_at,
            )
            self._require_immutable_guest_runtime_release(
                session,
                guest_runtime_release,
                observed_at,
            )
            session.add(
                CurrentContainerImageSetRecord(
                    owner_key="current",
                    identity=container_image_set.identity,
                    updated_at=observed_at,
                )
            )
            session.add(
                ActiveGuestRuntimeReleaseRecord(
                    owner_key="active",
                    identity=guest_runtime_release.identity,
                    updated_at=observed_at,
                )
            )
            session.add(
                InitialUpdateOwnerProvisioningRecord(
                    owner_key="initial",
                    contract_digest=contract_digest,
                    container_identity=container_image_set.identity,
                    container_digest=container_image_set.digest,
                    container_archive=container_archive,
                    guest_runtime_identity=guest_runtime_release.identity,
                    guest_runtime_digest=guest_runtime_release.digest,
                    guest_runtime_archive=guest_runtime_release.archive,
                    completed_at=observed_at,
                )
            )

        try:
            self._write("initial update owner state provision", write)
        except (
            ContainerImageSetConflictError,
            ContainerImageSetContractError,
            GuestRuntimeReleaseConflictError,
            GuestRuntimeReleaseContractError,
        ):
            raise
        except GuestControlDependencyError as error:
            raise GuestRuntimeReleaseDependencyError(
                error.message,
                kind="initialUpdateOwnerStateUnavailable",
            ) from error

    def initial_update_owner_state_is_provisioned(
        self,
        *,
        contract_digest: str,
        container_image_set: ContainerImageSet,
        container_archive: str,
        guest_runtime_release: GuestRuntimeRelease,
    ) -> bool:
        """Read the explicit installer receipt without consulting filesystem state."""

        def read(session: Session) -> bool:
            receipt = session.get(
                InitialUpdateOwnerProvisioningRecord,
                "initial",
            )
            if receipt is not None:
                actual = (
                    receipt.contract_digest,
                    receipt.container_identity,
                    receipt.container_digest,
                    receipt.container_archive,
                    receipt.guest_runtime_identity,
                    receipt.guest_runtime_digest,
                    receipt.guest_runtime_archive,
                )
                expected = (
                    contract_digest,
                    container_image_set.identity,
                    container_image_set.digest,
                    container_archive,
                    guest_runtime_release.identity,
                    guest_runtime_release.digest,
                    guest_runtime_release.archive,
                )
                if actual == expected:
                    current = session.get(
                        CurrentContainerImageSetRecord,
                        "current",
                    )
                    active = session.get(
                        ActiveGuestRuntimeReleaseRecord,
                        "active",
                    )
                    if current is None or active is None:
                        raise ContainerImageSetDependencyError(
                            "Initial update owner receipt exists but current "
                            "owner pointers are missing.",
                            kind="initialUpdateOwnerCurrentStateInvalid",
                        )
                    current_value = session.get(
                        ContainerImageSetRecord,
                        current.identity,
                    )
                    active_value = session.get(
                        GuestRuntimeReleaseRecord,
                        active.identity,
                    )
                    if current_value is None or active_value is None:
                        raise ContainerImageSetDependencyError(
                            "Initial update owner receipt exists but an owner "
                            "pointer has no immutable record.",
                            kind="initialUpdateOwnerCurrentStateInvalid",
                        )
                    ContainerImageSet.validated(
                        current_value.identity,
                        current_value.digest,
                    )
                    GuestRuntimeRelease.validated(
                        active_value.identity,
                        active_value.archive,
                        active_value.digest,
                    )
                    return True
                raise ContainerImageSetConflictError(
                    "Initial update owner provisioning receipt disagrees with "
                    "the installed release contract.",
                    kind="initialUpdateOwnerProvisioningReceiptMismatch",
                )
            current = session.get(CurrentContainerImageSetRecord, "current")
            active = session.get(ActiveGuestRuntimeReleaseRecord, "active")
            if current is None and active is None:
                return False
            raise ContainerImageSetConflictError(
                "Initial update owner state exists without its provisioning "
                "receipt.",
                kind="initialUpdateOwnerProvisioningPartialState",
            )

        try:
            with Session(self._engine) as session:
                return read(session)
        except (
            ContainerImageSetConflictError,
            ContainerImageSetContractError,
            GuestRuntimeReleaseConflictError,
            GuestRuntimeReleaseContractError,
        ):
            raise
        except SQLAlchemyError as error:
            raise GuestRuntimeReleaseDependencyError(
                control_store_error(
                    error,
                    stage="initial update owner provisioning receipt read",
                ).message,
                kind="initialUpdateOwnerStateUnavailable",
            ) from error

    def read_current(self) -> ContainerImageSet:
        try:
            with Session(self._engine) as session:
                current = session.get(CurrentContainerImageSetRecord, "current")
                if current is None:
                    raise ContainerImageSetDependencyError(
                        "Current container image-set state is not provisioned.",
                        kind="containerImageSetCurrentMissing",
                    )
                image_set = session.get(ContainerImageSetRecord, current.identity)
                if image_set is None:
                    raise ContainerImageSetDependencyError(
                        "Current container image-set identity has no immutable digest: "
                        f"identity={current.identity}.",
                        kind="containerImageSetStateInvalid",
                    )
                return ContainerImageSet.validated(
                    image_set.identity,
                    image_set.digest,
                )
        except (ContainerImageSetDependencyError, ContainerImageSetContractError):
            raise
        except SQLAlchemyError as error:
            raise ContainerImageSetDependencyError(
                f"Container image-set current-state read failed: {error}",
                kind="containerImageSetStateUnavailable",
            ) from error

    def accept(self, operation: ContainerImageSetOperation) -> None:
        if operation.state != ContainerImageSetOperationState.PENDING:
            raise ContainerImageSetDependencyError(
                "Container image-set command must enter the owner as pending.",
                kind="containerImageSetOperationAcceptanceInvalid",
            )

        def write(session: Session) -> None:
            current = session.get(CurrentContainerImageSetRecord, "current")
            if current is None:
                raise ContainerImageSetDependencyError(
                    "Current container image-set state is not provisioned.",
                    kind="containerImageSetCurrentMissing",
                )
            if current.identity != operation.expected_current_identity:
                raise ContainerImageSetConflictError(
                    "Container image-set compare-and-swap rejected the command: "
                    f"expected={operation.expected_current_identity} "
                    f"actual={current.identity}.",
                    kind="containerImageSetRevisionConflict",
                )
            existing_operation = session.get(
                ContainerImageSetOperationRecord,
                operation.operation_id,
            )
            if existing_operation is not None:
                raise ContainerImageSetConflictError(
                    "Container image-set operation already exists: "
                    f"operationId={operation.operation_id}.",
                    kind="containerImageSetOperationAlreadyExists",
                )
            active = session.scalar(
                select(ContainerImageSetOperationRecord).where(
                    ContainerImageSetOperationRecord.state.not_in(
                        tuple(
                            state.value
                            for state in TERMINAL_CONTAINER_IMAGE_SET_OPERATION_STATES
                        )
                    )
                )
            )
            if active is not None:
                raise ContainerImageSetConflictError(
                    "A container image-set operation is already active: "
                    f"operationId={active.operation_id}.",
                    kind="containerImageSetOperationInProgress",
                )
            self._require_immutable_image_set(
                session,
                operation.target,
                operation.created_at,
            )
            session.add(_container_image_set_operation_record(operation))

        self._container_image_set_write("container image-set acceptance", write)

    def get_operation(
        self,
        operation_id: str,
    ) -> ContainerImageSetOperation | None:
        try:
            with Session(self._engine) as session:
                record = session.get(ContainerImageSetOperationRecord, operation_id)
                if record is None:
                    return None
                target = session.get(ContainerImageSetRecord, record.target_identity)
                if target is None:
                    raise ContainerImageSetDependencyError(
                        "Container image-set operation target is missing: "
                        f"operationId={record.operation_id}.",
                        kind="containerImageSetOperationInvalid",
                    )
                return _container_image_set_operation_from_record(
                    record,
                    target_digest=target.digest,
                )
        except (ContainerImageSetDependencyError, ContainerImageSetContractError):
            raise
        except SQLAlchemyError as error:
            raise ContainerImageSetDependencyError(
                f"Container image-set operation read failed: {error}",
                kind="containerImageSetOperationUnavailable",
            ) from error

    def list_container_image_set_operations(
        self,
        states: frozenset[ContainerImageSetOperationState],
    ) -> list[ContainerImageSetOperation]:
        if not states:
            return []
        try:
            with Session(self._engine) as session:
                records = session.scalars(
                    select(ContainerImageSetOperationRecord)
                    .where(
                        ContainerImageSetOperationRecord.state.in_(
                            tuple(state.value for state in states)
                        )
                    )
                    .order_by(
                        ContainerImageSetOperationRecord.created_at,
                        ContainerImageSetOperationRecord.operation_id,
                    )
                ).all()
                operations: list[ContainerImageSetOperation] = []
                for record in records:
                    target = session.get(
                        ContainerImageSetRecord,
                        record.target_identity,
                    )
                    if target is None:
                        raise ContainerImageSetDependencyError(
                            "Container image-set operation target is missing: "
                            f"operationId={record.operation_id}.",
                            kind="containerImageSetOperationInvalid",
                        )
                    operations.append(
                        _container_image_set_operation_from_record(
                            record,
                            target_digest=target.digest,
                        )
                    )
                return operations
        except (ContainerImageSetDependencyError, ContainerImageSetContractError):
            raise
        except SQLAlchemyError as error:
            raise ContainerImageSetDependencyError(
                f"Container image-set operation list failed: {error}",
                kind="containerImageSetOperationUnavailable",
            ) from error

    def record_container_image_set_transition(
        self,
        operation: ContainerImageSetOperation,
    ) -> None:
        def write(session: Session) -> None:
            record = session.get(
                ContainerImageSetOperationRecord,
                operation.operation_id,
            )
            if record is None:
                raise ContainerImageSetDependencyError(
                    "Container image-set operation is missing: "
                    f"operationId={operation.operation_id}.",
                    kind="containerImageSetOperationMissing",
                )
            target = session.get(ContainerImageSetRecord, record.target_identity)
            if target is None:
                raise ContainerImageSetDependencyError(
                    "Container image-set operation target is missing: "
                    f"operationId={record.operation_id}.",
                    kind="containerImageSetOperationInvalid",
                )
            persisted = _container_image_set_operation_from_record(
                record,
                target_digest=target.digest,
            )
            expected = transition_container_image_set_operation(
                persisted,
                state=operation.state,
                updated_at=operation.updated_at,
                failure=operation.failure,
            )
            if expected != operation:
                raise ContainerImageSetDependencyError(
                    "Container image-set operation immutable fields changed.",
                    kind="containerImageSetOperationInvalid",
                )
            if operation.state == ContainerImageSetOperationState.SUCCEEDED:
                current = session.get(CurrentContainerImageSetRecord, "current")
                if current is None:
                    raise ContainerImageSetDependencyError(
                        "Current container image-set state is not provisioned.",
                        kind="containerImageSetCurrentMissing",
                    )
                if current.identity != operation.expected_current_identity:
                    raise ContainerImageSetConflictError(
                        "Container image-set changed before operation settlement: "
                        f"expected={operation.expected_current_identity} "
                        f"actual={current.identity}.",
                        kind="containerImageSetRevisionConflict",
                    )
                current.identity = operation.target.identity
                current.updated_at = operation.updated_at
            record.state = operation.state.value
            record.document = canonical_json(operation.as_json())
            record.updated_at = sqlite_utc_naive_timestamp(
                operation.updated_at,
                kind="containerImageSetOperationInvalid",
                field="updatedAt",
            )

        self._container_image_set_write("container image-set transition", write)

    def _require_immutable_image_set(
        self,
        session: Session,
        image_set: ContainerImageSet,
        observed_at: datetime,
    ) -> None:
        existing = session.get(ContainerImageSetRecord, image_set.identity)
        if existing is not None:
            if existing.digest != image_set.digest:
                raise ContainerImageSetConflictError(
                    "Container image-set identity already has a different digest: "
                    f"identity={image_set.identity}.",
                    kind="containerImageSetIdentityDigestConflict",
                )
            return
        session.add(
            ContainerImageSetRecord(
                identity=image_set.identity,
                digest=image_set.digest,
                created_at=observed_at,
            )
        )
        session.flush()

    def _container_image_set_write(
        self,
        stage: str,
        action: Callable[[Session], T],
    ) -> T:
        try:
            return self._write(stage, action)
        except (
            ContainerImageSetConflictError,
            ContainerImageSetContractError,
            ContainerImageSetDependencyError,
        ):
            raise
        except GuestControlDependencyError as error:
            raise ContainerImageSetDependencyError(
                error.message,
                kind="containerImageSetStateUnavailable",
            ) from error

    def provision_active_guest_runtime_release(
        self,
        release: GuestRuntimeRelease,
        *,
        observed_at: datetime,
    ) -> None:
        """Persist installer-authored initial active Guest Runtime release."""

        def write(session: Session) -> None:
            self._require_immutable_guest_runtime_release(
                session,
                release,
                observed_at,
            )
            active = session.get(ActiveGuestRuntimeReleaseRecord, "active")
            if active is not None:
                raise GuestRuntimeReleaseConflictError(
                    "Active Guest Runtime release is already provisioned: "
                    f"identity={active.identity}.",
                    kind="guestRuntimeReleaseAlreadyProvisioned",
                )
            session.add(
                ActiveGuestRuntimeReleaseRecord(
                    owner_key="active",
                    identity=release.identity,
                    updated_at=observed_at,
                )
            )

        self._guest_runtime_release_write("Guest Runtime release provision", write)

    def read_active_guest_runtime_release(self) -> GuestRuntimeRelease:
        try:
            with Session(self._engine) as session:
                active = session.get(ActiveGuestRuntimeReleaseRecord, "active")
                if active is None:
                    raise GuestRuntimeReleaseDependencyError(
                        "Active Guest Runtime release is not provisioned.",
                        kind="guestRuntimeReleaseActiveMissing",
                    )
                release = session.get(GuestRuntimeReleaseRecord, active.identity)
                if release is None:
                    raise GuestRuntimeReleaseDependencyError(
                        "Active Guest Runtime release has no immutable archive: "
                        f"identity={active.identity}.",
                        kind="guestRuntimeReleaseStateInvalid",
                    )
                return GuestRuntimeRelease.validated(
                    release.identity,
                    release.archive,
                    release.digest,
                )
        except (GuestRuntimeReleaseDependencyError, GuestRuntimeReleaseContractError):
            raise
        except SQLAlchemyError as error:
            raise GuestRuntimeReleaseDependencyError(
                f"Active Guest Runtime release read failed: {error}",
                kind="guestRuntimeReleaseStateUnavailable",
            ) from error

    def accept_guest_runtime_release_operation(
        self,
        operation: GuestRuntimeReleaseOperation,
    ) -> None:
        if operation.state != GuestRuntimeReleaseOperationState.PENDING:
            raise GuestRuntimeReleaseDependencyError(
                "Guest Runtime release command must enter the owner as pending.",
                kind="guestRuntimeReleaseOperationAcceptanceInvalid",
            )

        def write(session: Session) -> None:
            active = session.get(ActiveGuestRuntimeReleaseRecord, "active")
            if active is None:
                raise GuestRuntimeReleaseDependencyError(
                    "Active Guest Runtime release is not provisioned.",
                    kind="guestRuntimeReleaseActiveMissing",
                )
            if active.identity != operation.expected_active_identity:
                raise GuestRuntimeReleaseConflictError(
                    "Guest Runtime release compare-and-swap rejected the command: "
                    f"expected={operation.expected_active_identity} "
                    f"actual={active.identity}.",
                    kind="guestRuntimeReleaseRevisionConflict",
                )
            if (
                session.get(
                    GuestRuntimeReleaseOperationRecord,
                    operation.operation_id,
                )
                is not None
            ):
                raise GuestRuntimeReleaseConflictError(
                    "Guest Runtime release operation already exists: "
                    f"operationId={operation.operation_id}.",
                    kind="guestRuntimeReleaseOperationAlreadyExists",
                )
            active_operation = session.scalar(
                select(GuestRuntimeReleaseOperationRecord).where(
                    GuestRuntimeReleaseOperationRecord.state.not_in(
                        tuple(
                            state.value
                            for state in (
                                TERMINAL_GUEST_RUNTIME_RELEASE_OPERATION_STATES
                            )
                        )
                    )
                )
            )
            if active_operation is not None:
                raise GuestRuntimeReleaseConflictError(
                    "A Guest Runtime release operation is already active: "
                    f"operationId={active_operation.operation_id}.",
                    kind="guestRuntimeReleaseOperationInProgress",
                )
            self._require_immutable_guest_runtime_release(
                session,
                operation.target,
                operation.created_at,
            )
            session.add(_guest_runtime_release_operation_record(operation))

        self._guest_runtime_release_write(
            "Guest Runtime release acceptance",
            write,
        )

    def get_guest_runtime_release_operation(
        self,
        operation_id: str,
    ) -> GuestRuntimeReleaseOperation | None:
        try:
            with Session(self._engine) as session:
                record = session.get(
                    GuestRuntimeReleaseOperationRecord,
                    operation_id,
                )
                if record is None:
                    return None
                target = session.get(
                    GuestRuntimeReleaseRecord,
                    record.target_identity,
                )
                if target is None:
                    raise GuestRuntimeReleaseDependencyError(
                        "Guest Runtime release operation target is missing: "
                        f"operationId={record.operation_id}.",
                        kind="guestRuntimeReleaseOperationInvalid",
                    )
                return _guest_runtime_release_operation_from_record(
                    record,
                    target_archive=target.archive,
                    target_digest=target.digest,
                )
        except (GuestRuntimeReleaseDependencyError, GuestRuntimeReleaseContractError):
            raise
        except SQLAlchemyError as error:
            raise GuestRuntimeReleaseDependencyError(
                f"Guest Runtime release operation read failed: {error}",
                kind="guestRuntimeReleaseOperationUnavailable",
            ) from error

    def list_guest_runtime_release_operations(
        self,
        states: frozenset[GuestRuntimeReleaseOperationState],
    ) -> list[GuestRuntimeReleaseOperation]:
        if not states:
            return []
        try:
            with Session(self._engine) as session:
                records = session.scalars(
                    select(GuestRuntimeReleaseOperationRecord)
                    .where(
                        GuestRuntimeReleaseOperationRecord.state.in_(
                            tuple(state.value for state in states)
                        )
                    )
                    .order_by(
                        GuestRuntimeReleaseOperationRecord.created_at,
                        GuestRuntimeReleaseOperationRecord.operation_id,
                    )
                ).all()
                operations: list[GuestRuntimeReleaseOperation] = []
                for record in records:
                    target = session.get(
                        GuestRuntimeReleaseRecord,
                        record.target_identity,
                    )
                    if target is None:
                        raise GuestRuntimeReleaseDependencyError(
                            "Guest Runtime release operation target is missing: "
                            f"operationId={record.operation_id}.",
                            kind="guestRuntimeReleaseOperationInvalid",
                        )
                    operations.append(
                        _guest_runtime_release_operation_from_record(
                            record,
                            target_archive=target.archive,
                            target_digest=target.digest,
                        )
                    )
                return operations
        except (GuestRuntimeReleaseDependencyError, GuestRuntimeReleaseContractError):
            raise
        except SQLAlchemyError as error:
            raise GuestRuntimeReleaseDependencyError(
                f"Guest Runtime release operation list failed: {error}",
                kind="guestRuntimeReleaseOperationUnavailable",
            ) from error

    def record_guest_runtime_release_transition(
        self,
        operation: GuestRuntimeReleaseOperation,
    ) -> None:
        def write(session: Session) -> None:
            record = session.get(
                GuestRuntimeReleaseOperationRecord,
                operation.operation_id,
            )
            if record is None:
                raise GuestRuntimeReleaseDependencyError(
                    "Guest Runtime release operation is missing: "
                    f"operationId={operation.operation_id}.",
                    kind="guestRuntimeReleaseOperationMissing",
                )
            target = session.get(
                GuestRuntimeReleaseRecord,
                record.target_identity,
            )
            if target is None:
                raise GuestRuntimeReleaseDependencyError(
                    "Guest Runtime release operation target is missing: "
                    f"operationId={record.operation_id}.",
                    kind="guestRuntimeReleaseOperationInvalid",
                )
            persisted = _guest_runtime_release_operation_from_record(
                record,
                target_archive=target.archive,
                target_digest=target.digest,
            )
            expected = transition_guest_runtime_release_operation(
                persisted,
                state=operation.state,
                updated_at=operation.updated_at,
                failure=operation.failure,
            )
            if expected != operation:
                raise GuestRuntimeReleaseDependencyError(
                    "Guest Runtime release operation immutable fields changed.",
                    kind="guestRuntimeReleaseOperationInvalid",
                )
            if operation.state == GuestRuntimeReleaseOperationState.SUCCEEDED:
                active = session.get(ActiveGuestRuntimeReleaseRecord, "active")
                if active is None:
                    raise GuestRuntimeReleaseDependencyError(
                        "Active Guest Runtime release is not provisioned.",
                        kind="guestRuntimeReleaseActiveMissing",
                    )
                if active.identity != operation.expected_active_identity:
                    raise GuestRuntimeReleaseConflictError(
                        "Guest Runtime release changed before operation settlement: "
                        f"expected={operation.expected_active_identity} "
                        f"actual={active.identity}.",
                        kind="guestRuntimeReleaseRevisionConflict",
                    )
                active.identity = operation.target.identity
                active.updated_at = operation.updated_at
            record.state = operation.state.value
            record.document = canonical_json(operation.as_json())
            record.updated_at = sqlite_utc_naive_timestamp(
                operation.updated_at,
                kind="guestRuntimeReleaseOperationInvalid",
                field="updatedAt",
            )

        self._guest_runtime_release_write(
            "Guest Runtime release transition",
            write,
        )

    def _require_immutable_guest_runtime_release(
        self,
        session: Session,
        release: GuestRuntimeRelease,
        observed_at: datetime,
    ) -> None:
        existing = session.get(GuestRuntimeReleaseRecord, release.identity)
        if existing is not None:
            if existing.archive != release.archive or existing.digest != release.digest:
                raise GuestRuntimeReleaseConflictError(
                    "Guest Runtime release identity already names another archive: "
                    f"identity={release.identity}.",
                    kind="guestRuntimeReleaseIdentityConflict",
                )
            return
        archive_owner = session.scalar(
            select(GuestRuntimeReleaseRecord).where(
                GuestRuntimeReleaseRecord.archive == release.archive
            )
        )
        if archive_owner is not None:
            raise GuestRuntimeReleaseConflictError(
                "Guest Runtime release archive already belongs to another identity: "
                f"archive={release.archive}.",
                kind="guestRuntimeReleaseArchiveConflict",
            )
        session.add(
            GuestRuntimeReleaseRecord(
                identity=release.identity,
                archive=release.archive,
                digest=release.digest,
                created_at=observed_at,
            )
        )
        session.flush()

    def _guest_runtime_release_write(
        self,
        stage: str,
        action: Callable[[Session], T],
    ) -> T:
        try:
            return self._write(stage, action)
        except (
            GuestRuntimeReleaseConflictError,
            GuestRuntimeReleaseContractError,
            GuestRuntimeReleaseDependencyError,
        ):
            raise
        except GuestControlDependencyError as error:
            raise GuestRuntimeReleaseDependencyError(
                error.message,
                kind="guestRuntimeReleaseStateUnavailable",
            ) from error

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
            f"control SQLite journal mode is not WAL: actual={journal_mode!r}",
            kind="controlStoreJournalModeInvalid",
        )


def _container_image_set_operation_record(
    operation: ContainerImageSetOperation,
) -> ContainerImageSetOperationRecord:
    return ContainerImageSetOperationRecord(
        operation_id=operation.operation_id,
        command=operation.command.value,
        expected_current_identity=operation.expected_current_identity,
        target_identity=operation.target.identity,
        state=operation.state.value,
        document=canonical_json(operation.as_json()),
        created_at=sqlite_utc_naive_timestamp(
            operation.created_at,
            kind="containerImageSetOperationInvalid",
            field="createdAt",
        ),
        updated_at=sqlite_utc_naive_timestamp(
            operation.updated_at,
            kind="containerImageSetOperationInvalid",
            field="updatedAt",
        ),
    )


def _container_image_set_operation_from_record(
    record: ContainerImageSetOperationRecord,
    *,
    target_digest: str,
) -> ContainerImageSetOperation:
    document = parse_document(
        record.document,
        kind="containerImageSetOperationInvalid",
    )
    try:
        target = document["target"]
        failure_document = document.get("failure")
        operation = ContainerImageSetOperation(
            operation_id=str(document["operationId"]),
            command=ContainerImageSetCommand(str(document["command"])),
            expected_current_identity=str(document["expectedCurrentIdentity"]),
            target=ContainerImageSet.validated(
                target["identity"],
                target["digest"],
            ),
            state=ContainerImageSetOperationState(str(document["state"])),
            created_at=datetime.fromisoformat(str(document["createdAt"])),
            updated_at=datetime.fromisoformat(str(document["updatedAt"])),
            failure=(
                ContainerImageSetFailure(
                    kind=str(failure_document["kind"]),
                    message=str(failure_document["message"]),
                )
                if isinstance(failure_document, dict)
                else None
            ),
        )
    except (KeyError, TypeError, ValueError) as error:
        raise ContainerImageSetDependencyError(
            "Container image-set operation document is invalid: "
            f"operationId={record.operation_id}.",
            kind="containerImageSetOperationInvalid",
        ) from error
    if (
        operation.operation_id != record.operation_id
        or operation.command.value != record.command
        or operation.expected_current_identity != record.expected_current_identity
        or operation.target.identity != record.target_identity
        or operation.target.digest != target_digest
        or operation.state.value != record.state
        or record.created_at
        != sqlite_utc_naive_timestamp(
            operation.created_at,
            kind="containerImageSetOperationInvalid",
            field="createdAt",
        )
        or record.updated_at
        != sqlite_utc_naive_timestamp(
            operation.updated_at,
            kind="containerImageSetOperationInvalid",
            field="updatedAt",
        )
    ):
        raise ContainerImageSetDependencyError(
            "Container image-set operation index and document disagree: "
            f"operationId={record.operation_id}.",
            kind="containerImageSetOperationInvalid",
        )
    failure_required = operation.state in {
        ContainerImageSetOperationState.FAILED,
        ContainerImageSetOperationState.UNAVAILABLE,
    }
    if failure_required != (operation.failure is not None):
        raise ContainerImageSetDependencyError(
            "Container image-set operation state and failure disagree: "
            f"operationId={record.operation_id}.",
            kind="containerImageSetOperationInvalid",
        )
    return operation


def _guest_runtime_release_operation_record(
    operation: GuestRuntimeReleaseOperation,
) -> GuestRuntimeReleaseOperationRecord:
    return GuestRuntimeReleaseOperationRecord(
        operation_id=operation.operation_id,
        command=operation.command.value,
        expected_active_identity=operation.expected_active_identity,
        target_identity=operation.target.identity,
        state=operation.state.value,
        document=canonical_json(operation.as_json()),
        created_at=sqlite_utc_naive_timestamp(
            operation.created_at,
            kind="guestRuntimeReleaseOperationInvalid",
            field="createdAt",
        ),
        updated_at=sqlite_utc_naive_timestamp(
            operation.updated_at,
            kind="guestRuntimeReleaseOperationInvalid",
            field="updatedAt",
        ),
    )


def _guest_runtime_release_operation_from_record(
    record: GuestRuntimeReleaseOperationRecord,
    *,
    target_archive: str,
    target_digest: str,
) -> GuestRuntimeReleaseOperation:
    document = parse_document(
        record.document,
        kind="guestRuntimeReleaseOperationInvalid",
    )
    try:
        target = document["target"]
        failure_document = document.get("failure")
        operation = GuestRuntimeReleaseOperation(
            operation_id=str(document["operationId"]),
            command=GuestRuntimeReleaseCommand(str(document["command"])),
            expected_active_identity=str(document["expectedActiveIdentity"]),
            target=GuestRuntimeRelease.validated(
                target["identity"],
                target["archive"],
                target["digest"],
            ),
            state=GuestRuntimeReleaseOperationState(str(document["state"])),
            created_at=datetime.fromisoformat(str(document["createdAt"])),
            updated_at=datetime.fromisoformat(str(document["updatedAt"])),
            failure=(
                GuestRuntimeReleaseFailure(
                    kind=str(failure_document["kind"]),
                    message=str(failure_document["message"]),
                )
                if isinstance(failure_document, dict)
                else None
            ),
        )
    except (KeyError, TypeError, ValueError) as error:
        raise GuestRuntimeReleaseDependencyError(
            "Guest Runtime release operation document is invalid: "
            f"operationId={record.operation_id}.",
            kind="guestRuntimeReleaseOperationInvalid",
        ) from error
    if (
        operation.operation_id != record.operation_id
        or operation.command.value != record.command
        or operation.expected_active_identity != record.expected_active_identity
        or operation.target.identity != record.target_identity
        or operation.target.archive != target_archive
        or operation.target.digest != target_digest
        or operation.state.value != record.state
        or record.created_at
        != sqlite_utc_naive_timestamp(
            operation.created_at,
            kind="guestRuntimeReleaseOperationInvalid",
            field="createdAt",
        )
        or record.updated_at
        != sqlite_utc_naive_timestamp(
            operation.updated_at,
            kind="guestRuntimeReleaseOperationInvalid",
            field="updatedAt",
        )
    ):
        raise GuestRuntimeReleaseDependencyError(
            "Guest Runtime release operation index and document disagree: "
            f"operationId={record.operation_id}.",
            kind="guestRuntimeReleaseOperationInvalid",
        )
    failure_required = operation.state in {
        GuestRuntimeReleaseOperationState.FAILED,
        GuestRuntimeReleaseOperationState.UNAVAILABLE,
    }
    if failure_required != (operation.failure is not None):
        raise GuestRuntimeReleaseDependencyError(
            "Guest Runtime release operation state and failure disagree: "
            f"operationId={record.operation_id}.",
            kind="guestRuntimeReleaseOperationInvalid",
        )
    return operation


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
