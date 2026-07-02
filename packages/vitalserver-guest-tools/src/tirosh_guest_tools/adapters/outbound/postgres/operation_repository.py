from __future__ import annotations

import json
import subprocess
from datetime import datetime
from typing import Any

from tirosh_guest_tools.application import compose as compose_app
from tirosh_guest_tools.contracts import ComposeService
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    OperationEvent,
    OperationFailure,
    OperationState,
    ServiceCommand,
    ServiceOperation,
    ServiceStatus,
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
"""


class PostgresOperationRepository:
    def ensure_schema(self) -> None:
        run_schema_migration(
            SCHEMA_SQL,
            stage="guest control operation schema migration",
        )

    def check_ready(self) -> None:
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


def string_or_empty(value: object) -> str:
    return value if isinstance(value, str) else ""
