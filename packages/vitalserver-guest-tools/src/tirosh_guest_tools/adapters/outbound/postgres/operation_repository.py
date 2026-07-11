from __future__ import annotations

import json
import subprocess
from datetime import datetime
from typing import Any

from tirosh_guest_tools.application import compose as compose_app
from tirosh_guest_tools.contracts import ComposeService
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    GuestServiceCondition,
    GuestServiceDesiredState,
    GuestServiceObservedState,
    GuestServiceResource,
    GuestServiceSpec,
    GuestServiceSpecState,
    GuestServiceStatusRead,
    GuestServiceStatusReadState,
    OperationEvent,
    OperationFailure,
    OperationState,
    RedisRelayDependencyError,
    RedisRelayStatusContractError,
    ServiceCommand,
    ServiceOperation,
    ServiceStatus,
    validate_redis_relay_status_document,
)

GUEST_SCHEMA_ADVISORY_LOCK = "66060002000"

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS service_operations (
    operation_id text PRIMARY KEY,
    document jsonb NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS service_operations_updated_at_idx
    ON service_operations (updated_at);
CREATE TABLE IF NOT EXISTS service_operation_events (
    event_id bigserial PRIMARY KEY,
    operation_id text NOT NULL,
    state text NOT NULL,
    document jsonb NOT NULL,
    observed_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS service_operation_events_operation_id_idx
    ON service_operation_events (operation_id);
CREATE INDEX IF NOT EXISTS service_operation_events_observed_at_idx
    ON service_operation_events (observed_at);
CREATE TABLE IF NOT EXISTS service_status_snapshots (
    service text PRIMARY KEY,
    document jsonb NOT NULL,
    observed_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS service_status_snapshots_observed_at_idx
    ON service_status_snapshots (observed_at);
CREATE TABLE IF NOT EXISTS guest_service_resources (
    service text PRIMARY KEY,
    document jsonb NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS guest_service_resources_updated_at_idx
    ON guest_service_resources (updated_at);
CREATE TABLE IF NOT EXISTS redis_relay_status_snapshots (
    snapshot_id text PRIMARY KEY,
    document jsonb NOT NULL,
    observed_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS redis_relay_status_snapshots_observed_at_idx
    ON redis_relay_status_snapshots (observed_at);

UPDATE guest_service_resources
SET document = jsonb_set(
        document,
        '{status,serviceStatus,health}',
        '"not_reported"'::jsonb,
        true
    ),
    updated_at = now()
WHERE document #>> '{status,state}' = 'loaded'
  AND (
      document #>> '{status,serviceStatus,health}' IS NULL
      OR document #>> '{status,serviceStatus,health}' = ''
  );

UPDATE service_status_snapshots
SET document = jsonb_set(
        document,
        '{health}',
        '"not_reported"'::jsonb,
        true
    )
WHERE document ->> 'health' IS NULL
   OR document ->> 'health' = '';
"""


class PostgresOperationRepository:
    def ensure_schema(self) -> None:
        run_schema_migration(
            SCHEMA_SQL,
            stage="guest control operation schema migration",
        )

    def check_ready(self) -> None:
        self.ensure_schema()
        run_psql("SELECT 1;", stage="guest control operation repository readiness")

    def create(self, operation: ServiceOperation) -> None:
        document = operation.as_json()
        sql = (
            "INSERT INTO service_operations "
            "(operation_id, document, created_at, updated_at) VALUES ("
            f"{sql_literal(operation.operation_id)}, "
            f"{jsonb_literal(document)}, "
            f"{sql_literal(operation.created_at.isoformat())}::timestamptz, "
            f"{sql_literal(operation.updated_at.isoformat())}::timestamptz"
            ");"
        )
        run_psql(sql, stage="guest control operation create")

    def save(self, operation: ServiceOperation) -> None:
        document = operation.as_json()
        sql = (
            "INSERT INTO service_operations "
            "(operation_id, document, created_at, updated_at) VALUES ("
            f"{sql_literal(operation.operation_id)}, "
            f"{jsonb_literal(document)}, "
            f"{sql_literal(operation.created_at.isoformat())}::timestamptz, "
            f"{sql_literal(operation.updated_at.isoformat())}::timestamptz"
            ") ON CONFLICT (operation_id) DO UPDATE SET "
            "document = EXCLUDED.document, "
            "created_at = EXCLUDED.created_at, "
            "updated_at = EXCLUDED.updated_at;"
        )
        run_psql(sql, stage="guest control operation save")

    def append_event(self, event: OperationEvent) -> None:
        document = event.as_json()
        sql = (
            "INSERT INTO service_operation_events "
            "(operation_id, state, document, observed_at) VALUES ("
            f"{sql_literal(event.operation_id)}, "
            f"{sql_literal(event.state.value)}, "
            f"{jsonb_literal(document)}, "
            f"{sql_literal(event.observed_at.isoformat())}::timestamptz"
            ");"
        )
        run_psql(sql, stage="guest control operation event append")

    def save_service_status_snapshot(self, status: ServiceStatus) -> None:
        document = status.as_json()
        sql = (
            "INSERT INTO service_status_snapshots "
            "(service, document, observed_at) VALUES ("
            f"{sql_literal(status.service)}, "
            f"{jsonb_literal(document)}, "
            f"{sql_literal(status.observed_at.isoformat())}::timestamptz"
            ") ON CONFLICT (service) DO UPDATE SET "
            "document = EXCLUDED.document, "
            "observed_at = EXCLUDED.observed_at;"
        )
        run_psql(sql, stage="guest control service status snapshot save")

    def save_guest_service_resource(self, resource: GuestServiceResource) -> None:
        document = resource.as_json()
        updated_at = resource.spec.updated_at
        for condition in resource.conditions:
            if updated_at is None or condition.observed_at > updated_at:
                updated_at = condition.observed_at
        if resource.status.service_status is not None and (
            updated_at is None
            or resource.status.service_status.observed_at > updated_at
        ):
            updated_at = resource.status.service_status.observed_at
        if updated_at is None:
            raise GuestControlDependencyError(
                "guest service resource is missing explicit update time",
                kind="guestServiceResourceInvalid",
            )
        sql = (
            "INSERT INTO guest_service_resources "
            "(service, document, updated_at) VALUES ("
            f"{sql_literal(resource.service)}, "
            f"{jsonb_literal(document)}, "
            f"{sql_literal(updated_at.isoformat())}::timestamptz"
            ") ON CONFLICT (service) DO UPDATE SET "
            "document = EXCLUDED.document, "
            "updated_at = EXCLUDED.updated_at;"
        )
        run_psql(sql, stage="guest service resource save")

    def get_guest_service_resource(self, service: str) -> GuestServiceResource | None:
        sql = (
            "SELECT document::text FROM guest_service_resources "
            f"WHERE service = {sql_literal(service)};"
        )
        completed = run_psql(sql, stage="guest service resource read")
        stdout = completed.stdout or ""
        text = stdout.strip()
        if not text:
            return None
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise GuestControlDependencyError(
                "postgres guest service resource document is invalid JSON",
                kind="guestServiceResourceDocumentInvalid",
            ) from error
        if not isinstance(document, dict):
            raise GuestControlDependencyError(
                "postgres guest service resource document is not an object",
                kind="guestServiceResourceDocumentInvalid",
            )
        return guest_service_resource_from_json(document)

    def get(self, operation_id: str) -> ServiceOperation | None:
        sql = (
            "SELECT document::text FROM service_operations "
            f"WHERE operation_id = {sql_literal(operation_id)};"
        )
        completed = run_psql(sql, stage="guest control operation read")
        stdout = completed.stdout or ""
        text = stdout.strip()
        if not text:
            return None
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise GuestControlDependencyError(
                "postgres service operation document is invalid JSON",
                kind="postgresOperationDocumentInvalid",
            ) from error
        if not isinstance(document, dict):
            raise GuestControlDependencyError(
                "postgres service operation document is not an object",
                kind="postgresOperationDocumentInvalid",
            )
        return operation_from_json(document)

    def query_events(
        self,
        *,
        limit: int,
        event_type: str | None,
        since: datetime | None,
        cursor: str | None,
    ) -> dict[str, Any]:
        cursor_id = _runtime_event_cursor_id(cursor)
        conditions: list[str] = []
        if event_type is not None:
            state = event_type.removeprefix("operation-")
            conditions.append(f"e.state = {sql_literal(state)}")
        if since is not None:
            conditions.append(
                f"e.observed_at >= {sql_literal(since.isoformat())}::timestamptz"
            )
        if cursor_id is not None:
            conditions.append(f"e.event_id < {cursor_id}")
        where = " WHERE " + " AND ".join(conditions) if conditions else ""
        sql = (
            "SELECT COALESCE(jsonb_agg(item ORDER BY event_id DESC), '[]'::jsonb)::text "
            "FROM (SELECT e.event_id, jsonb_build_object("
            "'_eventId', e.event_id, "
            "'schemaVersion', 1, "
            "'id', 'runtime-operation-event-' || e.event_id::text, "
            "'source', 'runtime-controller', "
            "'eventType', 'operation-' || e.state, "
            "'timestamp', e.observed_at, "
            "'operationId', e.operation_id, "
            "'operationService', o.document ->> 'service', "
            "'operationCommand', o.document ->> 'command', "
            "'operationState', e.state, "
            "'message', concat_ws(' ', o.document ->> 'service', "
            "o.document ->> 'command', e.state), "
            "'failure', e.document -> 'failure'"
            ") AS item FROM service_operation_events e "
            "JOIN service_operations o ON o.operation_id = e.operation_id"
            f"{where} ORDER BY e.event_id DESC LIMIT {limit + 1}) AS page;"
        )
        completed = run_psql(sql, stage="guest control runtime event history read")
        text = (completed.stdout or "").strip()
        if not text:
            raise GuestControlDependencyError(
                "runtime event history read returned no document",
                kind="runtimeEventHistoryUnavailable",
            )
        try:
            values = json.loads(text)
        except json.JSONDecodeError as error:
            raise GuestControlDependencyError(
                "runtime event history document is invalid JSON",
                kind="runtimeEventHistoryInvalid",
            ) from error
        if not isinstance(values, list) or not all(isinstance(value, dict) for value in values):
            raise GuestControlDependencyError(
                "runtime event history document is not an event list",
                kind="runtimeEventHistoryInvalid",
            )
        has_next = len(values) > limit
        events = values[:limit]
        next_cursor: str | None = None
        if has_next and events:
            event_id = events[-1].get("_eventId")
            if not isinstance(event_id, int):
                raise GuestControlDependencyError(
                    "runtime event history cursor evidence is invalid",
                    kind="runtimeEventHistoryInvalid",
                )
            next_cursor = f"event:{event_id}"
        for event in events:
            event.pop("_eventId", None)
        return {
            "events": events,
            "nextCursor": next_cursor,
            "matchingCount": None,
        }

    def save_status(self, document: dict[str, Any]) -> None:
        try:
            observed_at = validate_redis_relay_status_document(document)
        except RedisRelayStatusContractError as error:
            raise RedisRelayDependencyError(
                error.message,
                kind="redis-relay-contract-invalid",
            ) from error
        sql = (
            "INSERT INTO redis_relay_status_snapshots "
            "(snapshot_id, document, observed_at) VALUES ("
            "'current', "
            f"{jsonb_literal(document)}, "
            f"{sql_literal(observed_at)}::timestamptz"
            ") ON CONFLICT (snapshot_id) DO UPDATE SET "
            "document = EXCLUDED.document, "
            "observed_at = EXCLUDED.observed_at;"
        )
        run_psql(sql, stage="redis relay status snapshot save")

    def status(self) -> dict[str, Any]:
        completed = run_psql(
            "SELECT document::text FROM redis_relay_status_snapshots "
            "WHERE snapshot_id = 'current';",
            stage="redis relay status snapshot read",
        )
        stdout = completed.stdout or ""
        text = stdout.strip()
        if not text:
            raise RedisRelayDependencyError(
                "Redis relay status snapshot is missing.",
                kind="redis-relay-status-missing",
            )
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise RedisRelayDependencyError(
                "postgres redis relay status snapshot is invalid JSON.",
                kind="redis-relay-contract-invalid",
            ) from error
        if not isinstance(document, dict):
            raise RedisRelayDependencyError(
                "postgres redis relay status snapshot is not an object.",
                kind="redis-relay-contract-invalid",
            )
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


def run_psql(
    sql: str,
    *,
    stage: str,
) -> subprocess.CompletedProcess[str]:
    return run_psql_commands([sql], stage=stage)


def run_schema_migration(
    sql: str,
    *,
    stage: str,
) -> subprocess.CompletedProcess[str]:
    return run_psql_commands(
        [
            f"SELECT pg_advisory_lock({GUEST_SCHEMA_ADVISORY_LOCK});",
            sql,
            f"SELECT pg_advisory_unlock({GUEST_SCHEMA_ADVISORY_LOCK});",
        ],
        stage=stage,
    )


def run_psql_commands(
    commands: list[str],
    *,
    stage: str,
) -> subprocess.CompletedProcess[str]:
    psql_arguments: list[str] = [
        "exec",
        "-T",
        ComposeService.POSTGRES.value,
        "psql",
        "-U",
        "vitalserver",
        "-d",
        "vitalserver",
        "-v",
        "ON_ERROR_STOP=1",
        "-qAt",
    ]
    for command in commands:
        psql_arguments.extend(["-c", command])

    try:
        return compose_app.compose(psql_arguments, capture_output=True)
    except subprocess.CalledProcessError as error:
        message = (
            f"postgres command failed during {stage}: exitCode={error.returncode}"
        )
        output = compact_process_output(error)
        if output:
            message += "\n" + output
        raise GuestControlDependencyError(
            message,
            kind="postgresCommandFailed",
        ) from error


def compact_process_output(error: subprocess.CalledProcessError) -> str:
    sections: list[str] = []
    if error.stdout:
        sections.append(f"stdout:\n{error.stdout}")
    if error.stderr:
        sections.append(f"stderr:\n{error.stderr}")
    return "\n".join(sections)


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def jsonb_literal(document: dict[str, Any]) -> str:
    return sql_literal(json.dumps(document, sort_keys=True)) + "::jsonb"


def operation_from_json(document: dict[str, Any]) -> ServiceOperation:
    failure = document.get("failure")
    result = document.get("result")
    if result is not None and not isinstance(result, dict):
        raise GuestControlDependencyError(
            "postgres service operation document result is not an object",
            kind="postgresOperationDocumentInvalid",
        )
    return ServiceOperation(
        operation_id=required_string(document, "operationId"),
        service=required_string(document, "service"),
        command=ServiceCommand(required_string(document, "command")),
        state=OperationState(required_string(document, "state")),
        created_at=datetime.fromisoformat(required_string(document, "createdAt")),
        updated_at=datetime.fromisoformat(required_string(document, "updatedAt")),
        failure=operation_failure_from_json(failure)
        if isinstance(failure, dict)
        else None,
        result=result,
    )


def guest_service_resource_from_json(document: dict[str, Any]) -> GuestServiceResource:
    service = required_string(document, "service")
    spec_document = required_object(document, "spec")
    status_document = required_object(document, "status")
    conditions_value = document.get("conditions")
    if not isinstance(conditions_value, list):
        raise GuestControlDependencyError(
            "postgres guest service resource document field is invalid: conditions",
            kind="guestServiceResourceDocumentInvalid",
        )
    last_operation_id = document.get("lastOperationId")
    if last_operation_id is not None and not isinstance(last_operation_id, str):
        raise GuestControlDependencyError(
            "postgres guest service resource document field is invalid: "
            "lastOperationId",
            kind="guestServiceResourceDocumentInvalid",
        )
    conditions: list[GuestServiceCondition] = []
    for condition in conditions_value:
        if not isinstance(condition, dict):
            raise GuestControlDependencyError(
                "postgres guest service resource condition is invalid",
                kind="guestServiceResourceDocumentInvalid",
            )
        conditions.append(guest_service_condition_from_json(condition))
    return GuestServiceResource(
        service=service,
        spec=guest_service_spec_from_json(spec_document),
        status=guest_service_status_read_from_json(status_document),
        conditions=conditions,
        last_operation_id=last_operation_id,
    )


def guest_service_spec_from_json(document: dict[str, Any]) -> GuestServiceSpec:
    try:
        state = GuestServiceSpecState(required_string(document, "state"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "postgres guest service resource spec state is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    desired_state_value = document.get("desiredState")
    updated_at_value = document.get("updatedAt")
    try:
        desired_state = (
            GuestServiceDesiredState(desired_state_value)
            if isinstance(desired_state_value, str)
            else None
        )
        updated_at = (
            datetime.fromisoformat(updated_at_value)
            if isinstance(updated_at_value, str)
            else None
        )
    except (ValueError, TypeError) as error:
        raise GuestControlDependencyError(
            "postgres guest service resource spec document is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    if state == GuestServiceSpecState.CONFIGURED and (
        desired_state is None or updated_at is None
    ):
        raise GuestControlDependencyError(
            "postgres guest service resource configured spec is incomplete",
            kind="guestServiceResourceDocumentInvalid",
        )
    return GuestServiceSpec(
        state=state,
        desired_state=desired_state,
        updated_at=updated_at,
    )


def guest_service_status_read_from_json(
    document: dict[str, Any],
) -> GuestServiceStatusRead:
    try:
        state = GuestServiceStatusReadState(required_string(document, "state"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "postgres guest service resource status state is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    observed_state_value = document.get("observedState")
    try:
        observed_state = (
            GuestServiceObservedState(observed_state_value)
            if isinstance(observed_state_value, str)
            else None
        )
    except ValueError as error:
        raise GuestControlDependencyError(
            "postgres guest service resource observed state is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    failure = document.get("readError")
    service_status_document = document.get("serviceStatus")
    if state == GuestServiceStatusReadState.LOADED and (
        observed_state is None or not isinstance(service_status_document, dict)
    ):
        raise GuestControlDependencyError(
            "postgres guest service resource loaded status is incomplete",
            kind="guestServiceResourceDocumentInvalid",
        )
    if state == GuestServiceStatusReadState.FAILED and not isinstance(failure, dict):
        raise GuestControlDependencyError(
            "postgres guest service resource failed status is incomplete",
            kind="guestServiceResourceDocumentInvalid",
        )
    return GuestServiceStatusRead(
        state=state,
        observed_state=observed_state,
        service_status=service_status_from_json(service_status_document)
        if isinstance(service_status_document, dict)
        else None,
        failure=operation_failure_from_json(failure)
        if isinstance(failure, dict)
        else None,
    )


def guest_service_condition_from_json(
    document: dict[str, Any],
) -> GuestServiceCondition:
    try:
        observed_at = datetime.fromisoformat(required_string(document, "observedAt"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "postgres guest service resource condition observedAt is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    return GuestServiceCondition(
        type=required_string(document, "type"),
        status=required_string(document, "status"),
        reason=required_string(document, "reason"),
        message=required_string(document, "message"),
        observed_at=observed_at,
    )


def service_status_from_json(document: dict[str, Any]) -> ServiceStatus:
    exit_code = document.get("exitCode")
    if exit_code is not None and not isinstance(exit_code, int):
        raise GuestControlDependencyError(
            "postgres guest service resource status exitCode is invalid",
            kind="guestServiceResourceDocumentInvalid",
        )
    try:
        observed_at = datetime.fromisoformat(required_string(document, "observedAt"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "postgres guest service resource status observedAt is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    return ServiceStatus(
        service=required_string(document, "service"),
        state=required_string(document, "state"),
        health=required_string(document, "health"),
        observed_at=observed_at,
        container=string_or_empty(document.get("container")),
        exit_code=exit_code,
    )


def operation_failure_from_json(document: dict[str, Any]) -> OperationFailure:
    return OperationFailure(
        kind=required_string(document, "kind"),
        message=required_string(document, "message"),
        evidence_path=string_or_empty(document.get("evidencePath")),
    )


def required_string(document: dict[str, Any], field: str) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not value:
        raise GuestControlDependencyError(
            f"postgres service operation document field is invalid: {field}",
            kind="postgresOperationDocumentInvalid",
        )
    return value


def required_object(document: dict[str, Any], field: str) -> dict[str, Any]:
    value = document.get(field)
    if not isinstance(value, dict):
        raise GuestControlDependencyError(
            f"postgres document field is invalid: {field}",
            kind="postgresDocumentInvalid",
        )
    return value


def string_or_empty(value: object) -> str:
    return value if isinstance(value, str) else ""


def _runtime_event_cursor_id(cursor: str | None) -> int | None:
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
