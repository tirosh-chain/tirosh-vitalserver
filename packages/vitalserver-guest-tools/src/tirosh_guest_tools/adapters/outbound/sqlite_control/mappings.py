from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

from tirosh_guest_tools.adapters.outbound.sqlite_control.records import (
    GuestServiceResourceRecord,
    OperationEventRecord,
    ServiceOperationRecord,
)
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
    ServiceCommand,
    ServiceOperation,
    ServiceStatus,
)
from tirosh_guest_tools.domain.runtime_observation import RuntimeResourceUsage


def operation_record_from_domain(operation: ServiceOperation) -> ServiceOperationRecord:
    created_at, updated_at = operation_index_timestamps(operation)
    return ServiceOperationRecord(
        operation_id=operation.operation_id,
        service=operation.service,
        command=operation.command.value,
        state=operation.state.value,
        document=canonical_json(operation.as_json()),
        created_at=created_at,
        updated_at=updated_at,
    )


def update_operation_record(
    record: ServiceOperationRecord,
    operation: ServiceOperation,
) -> None:
    _, updated_at = operation_index_timestamps(operation)
    record.state = operation.state.value
    record.document = canonical_json(operation.as_json())
    record.updated_at = updated_at


def operation_from_record(record: ServiceOperationRecord) -> ServiceOperation:
    operation = operation_from_document(
        parse_document(record.document, kind="controlOperationDocumentInvalid")
    )
    if (
        operation.operation_id != record.operation_id
        or operation.service != record.service
        or operation.command.value != record.command
        or operation.state.value != record.state
        or not _sqlite_timestamp_matches_document(
            record.created_at,
            operation.created_at,
            kind="controlOperationDocumentInvalid",
            field="createdAt",
        )
        or not _sqlite_timestamp_matches_document(
            record.updated_at,
            operation.updated_at,
            kind="controlOperationDocumentInvalid",
            field="updatedAt",
        )
    ):
        raise GuestControlDependencyError(
            "control operation document does not match its indexed record",
            kind="controlOperationDocumentInvalid",
        )
    return operation


def _sqlite_timestamp_matches_document(
    indexed_timestamp: datetime,
    document_timestamp: datetime,
    *,
    kind: str,
    field: str,
) -> bool:
    """Compare SQLite's UTC-naive index representation to the public document."""
    return (
        isinstance(indexed_timestamp, datetime)
        and indexed_timestamp.tzinfo is None
        and indexed_timestamp
        == sqlite_utc_naive_timestamp(
            document_timestamp,
            kind=kind,
            field=field,
        )
    )


def operation_event_from_record(record: OperationEventRecord) -> OperationEvent:
    try:
        event = operation_event_from_document(
            parse_document(record.document, kind="runtimeEventHistoryInvalid")
        )
    except GuestControlDependencyError as error:
        if error.kind == "runtimeEventHistoryInvalid":
            raise
        raise GuestControlDependencyError(
            "control runtime event document is invalid",
            kind="runtimeEventHistoryInvalid",
        ) from error
    if (
        event.operation_id != record.operation_id
        or event.state.value != record.state
        or not _sqlite_timestamp_matches_document(
            record.observed_at,
            event.observed_at,
            kind="runtimeEventHistoryInvalid",
            field="observedAt",
        )
    ):
        raise GuestControlDependencyError(
            "control runtime event document does not match its indexed record",
            kind="runtimeEventHistoryInvalid",
        )
    return event


def guest_service_resource_record_document(resource: GuestServiceResource) -> str:
    return canonical_json(resource.as_json())


def guest_service_resource_from_record(
    record: GuestServiceResourceRecord,
) -> GuestServiceResource:
    resource = guest_service_resource_from_document(
        parse_document(record.document, kind="guestServiceResourceDocumentInvalid")
    )
    if resource.service != record.service:
        raise GuestControlDependencyError(
            "guest service resource document does not match its indexed record",
            kind="guestServiceResourceDocumentInvalid",
        )
    return resource


def canonical_json(document: dict[str, Any]) -> str:
    return json.dumps(document, sort_keys=True, separators=(",", ":"))


def parse_document(document: str, *, kind: str) -> dict[str, Any]:
    try:
        value = json.loads(document)
    except json.JSONDecodeError as error:
        raise GuestControlDependencyError(
            "control SQLite document is invalid JSON",
            kind=kind,
        ) from error
    if not isinstance(value, dict):
        raise GuestControlDependencyError(
            "control SQLite document is not an object",
            kind=kind,
        )
    return value


def operation_from_document(document: dict[str, Any]) -> ServiceOperation:
    result = document.get("result")
    if result is not None and not isinstance(result, dict):
        raise GuestControlDependencyError(
            "control operation document result is not an object",
            kind="controlOperationDocumentInvalid",
        )
    try:
        command = ServiceCommand(required_string(document, "command"))
        state = OperationState(required_string(document, "state"))
        created_at = required_aware_datetime(
            document,
            "createdAt",
            kind="controlOperationDocumentInvalid",
        )
        updated_at = required_aware_datetime(
            document,
            "updatedAt",
            kind="controlOperationDocumentInvalid",
        )
    except (ValueError, TypeError) as error:
        raise GuestControlDependencyError(
            "control operation document has an invalid enum or timestamp",
            kind="controlOperationDocumentInvalid",
        ) from error
    failure = optional_failure(document, "failure")
    if state in {OperationState.FAILED, OperationState.INTERRUPTED} and failure is None:
        raise GuestControlDependencyError(
            "failed control operation is missing its failure document",
            kind="controlOperationDocumentInvalid",
        )
    return ServiceOperation(
        operation_id=required_string(document, "operationId"),
        service=required_string(document, "service"),
        command=command,
        state=state,
        created_at=created_at,
        updated_at=updated_at,
        failure=failure,
        result=result,
    )


def operation_event_from_document(document: dict[str, Any]) -> OperationEvent:
    result = document.get("result")
    if result is not None and not isinstance(result, dict):
        raise GuestControlDependencyError(
            "control runtime event result is not an object",
            kind="runtimeEventHistoryInvalid",
        )
    try:
        state = OperationState(required_string(document, "state"))
        observed_at = required_aware_datetime(
            document,
            "observedAt",
            kind="runtimeEventHistoryInvalid",
        )
    except (ValueError, TypeError) as error:
        raise GuestControlDependencyError(
            "control runtime event has an invalid state or timestamp",
            kind="runtimeEventHistoryInvalid",
        ) from error
    failure = optional_failure(document, "failure")
    if state in {OperationState.FAILED, OperationState.INTERRUPTED} and failure is None:
        raise GuestControlDependencyError(
            "failed control runtime event is missing its failure document",
            kind="runtimeEventHistoryInvalid",
        )
    return OperationEvent(
        operation_id=required_string(document, "operationId"),
        state=state,
        observed_at=observed_at,
        failure=failure,
        result=result,
    )


def operation_index_timestamps(
    operation: ServiceOperation,
) -> tuple[datetime, datetime]:
    """Map public operation times to SQLite's UTC-naive index representation."""
    return (
        sqlite_utc_naive_timestamp(
            operation.created_at,
            kind="controlOperationDocumentInvalid",
            field="createdAt",
        ),
        sqlite_utc_naive_timestamp(
            operation.updated_at,
            kind="controlOperationDocumentInvalid",
            field="updatedAt",
        ),
    )


def sqlite_utc_naive_timestamp(
    timestamp: datetime,
    *,
    kind: str,
    field: str,
) -> datetime:
    """Return the one timestamp representation permitted in SQLite indexes."""
    return (
        _require_aware_timestamp(timestamp, kind=kind, field=field)
        .astimezone(UTC)
        .replace(tzinfo=None)
    )


def required_aware_datetime(
    document: dict[str, Any],
    field: str,
    *,
    kind: str,
) -> datetime:
    try:
        timestamp = datetime.fromisoformat(required_string(document, field))
    except (TypeError, ValueError) as error:
        raise GuestControlDependencyError(
            f"control document timestamp is invalid: {field}",
            kind=kind,
        ) from error
    return _require_aware_timestamp(timestamp, kind=kind, field=field)


def _require_aware_timestamp(
    timestamp: datetime,
    *,
    kind: str,
    field: str,
) -> datetime:
    if (
        not isinstance(timestamp, datetime)
        or timestamp.tzinfo is None
        or timestamp.utcoffset() is None
    ):
        raise GuestControlDependencyError(
            f"control timestamp must include a timezone: {field}",
            kind=kind,
        )
    return timestamp


def guest_service_resource_from_document(
    document: dict[str, Any],
) -> GuestServiceResource:
    service = required_string(document, "service")
    spec_document = required_object(document, "spec")
    status_document = required_object(document, "status")
    conditions_value = document.get("conditions")
    if not isinstance(conditions_value, list):
        raise GuestControlDependencyError(
            "guest service resource document field is invalid: conditions",
            kind="guestServiceResourceDocumentInvalid",
        )
    last_operation_id = document.get("lastOperationId")
    if last_operation_id is not None and not isinstance(last_operation_id, str):
        raise GuestControlDependencyError(
            "guest service resource document field is invalid: lastOperationId",
            kind="guestServiceResourceDocumentInvalid",
        )
    conditions: list[GuestServiceCondition] = []
    for condition in conditions_value:
        if not isinstance(condition, dict):
            raise GuestControlDependencyError(
                "guest service resource condition is invalid",
                kind="guestServiceResourceDocumentInvalid",
            )
        conditions.append(guest_service_condition_from_document(condition))
    return GuestServiceResource(
        service=service,
        spec=guest_service_spec_from_document(spec_document),
        status=guest_service_status_read_from_document(status_document),
        conditions=conditions,
        last_operation_id=last_operation_id,
    )


def guest_service_spec_from_document(document: dict[str, Any]) -> GuestServiceSpec:
    try:
        state = GuestServiceSpecState(required_string(document, "state"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "guest service resource spec state is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    desired_state_value = optional_nullable_string(document, "desiredState")
    updated_at_value = optional_nullable_string(document, "updatedAt")
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
            "guest service resource spec document is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    if state == GuestServiceSpecState.CONFIGURED and (
        desired_state is None or updated_at is None
    ):
        raise GuestControlDependencyError(
            "guest service resource configured spec is incomplete",
            kind="guestServiceResourceDocumentInvalid",
        )
    return GuestServiceSpec(
        state=state,
        desired_state=desired_state,
        updated_at=updated_at,
    )


def guest_service_status_read_from_document(
    document: dict[str, Any],
) -> GuestServiceStatusRead:
    try:
        state = GuestServiceStatusReadState(required_string(document, "state"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "guest service resource status state is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    observed_state_value = optional_nullable_string(document, "observedState")
    try:
        observed_state = (
            GuestServiceObservedState(observed_state_value)
            if isinstance(observed_state_value, str)
            else None
        )
    except ValueError as error:
        raise GuestControlDependencyError(
            "guest service resource observed state is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    failure = optional_failure(document, "readError", allow_null=True)
    service_status_document = optional_nullable_object(document, "serviceStatus")
    if state == GuestServiceStatusReadState.LOADED and (
        observed_state is None or not isinstance(service_status_document, dict)
    ):
        raise GuestControlDependencyError(
            "guest service resource loaded status is incomplete",
            kind="guestServiceResourceDocumentInvalid",
        )
    if state == GuestServiceStatusReadState.FAILED and failure is None:
        raise GuestControlDependencyError(
            "guest service resource failed status is incomplete",
            kind="guestServiceResourceDocumentInvalid",
        )
    return GuestServiceStatusRead(
        state=state,
        observed_state=observed_state,
        service_status=service_status_from_document(service_status_document)
        if service_status_document is not None
        else None,
        failure=failure,
    )


def guest_service_condition_from_document(
    document: dict[str, Any],
) -> GuestServiceCondition:
    try:
        observed_at = datetime.fromisoformat(required_string(document, "observedAt"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "guest service resource condition observedAt is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    return GuestServiceCondition(
        type=required_string(document, "type"),
        status=required_string(document, "status"),
        reason=required_string(document, "reason"),
        message=required_string(document, "message"),
        observed_at=observed_at,
    )


def service_status_from_document(document: dict[str, Any]) -> ServiceStatus:
    exit_code = document.get("exitCode")
    if exit_code is not None and (
        not isinstance(exit_code, int) or isinstance(exit_code, bool)
    ):
        raise GuestControlDependencyError(
            "guest service resource status exitCode is invalid",
            kind="guestServiceResourceDocumentInvalid",
        )
    try:
        observed_at = datetime.fromisoformat(required_string(document, "observedAt"))
    except ValueError as error:
        raise GuestControlDependencyError(
            "guest service resource status observedAt is invalid",
            kind="guestServiceResourceDocumentInvalid",
        ) from error
    return ServiceStatus(
        service=required_string(document, "service"),
        state=required_string(document, "state"),
        health=required_string(document, "health"),
        observed_at=observed_at,
        container=optional_string(document, "container"),
        exit_code=exit_code,
        memory=optional_resource_usage(document, "memory"),
    )


def optional_resource_usage(
    document: dict[str, Any],
    field: str,
) -> RuntimeResourceUsage | None:
    if field not in document:
        return None
    value = document[field]
    if not isinstance(value, dict):
        raise GuestControlDependencyError(
            f"guest service resource status {field} is invalid",
            kind="guestServiceResourceDocumentInvalid",
        )
    used_bytes = value.get("usedBytes")
    total_bytes = value.get("totalBytes")
    if (
        not isinstance(used_bytes, int)
        or isinstance(used_bytes, bool)
        or used_bytes < 0
        or not isinstance(total_bytes, int)
        or isinstance(total_bytes, bool)
        or total_bytes < 0
    ):
        raise GuestControlDependencyError(
            f"guest service resource status {field} is invalid",
            kind="guestServiceResourceDocumentInvalid",
        )
    return RuntimeResourceUsage(
        used_bytes=used_bytes,
        total_bytes=total_bytes,
    )


def operation_failure_from_document(document: dict[str, Any]) -> OperationFailure:
    return OperationFailure(
        kind=required_string(document, "kind"),
        message=required_string(document, "message"),
        evidence_path=optional_string(document, "evidencePath"),
    )


def required_string(document: dict[str, Any], field: str) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not value:
        raise GuestControlDependencyError(
            f"control document field is invalid: {field}",
            kind="controlDocumentInvalid",
        )
    return value


def required_object(document: dict[str, Any], field: str) -> dict[str, Any]:
    value = document.get(field)
    if not isinstance(value, dict):
        raise GuestControlDependencyError(
            f"control document field is invalid: {field}",
            kind="controlDocumentInvalid",
        )
    return value


def optional_failure(
    document: dict[str, Any],
    field: str,
    *,
    allow_null: bool = False,
) -> OperationFailure | None:
    if field not in document:
        return None
    value = document[field]
    if value is None and allow_null:
        return None
    if not isinstance(value, dict):
        raise GuestControlDependencyError(
            f"control document field is invalid: {field}",
            kind="controlDocumentInvalid",
        )
    return operation_failure_from_document(value)


def optional_nullable_object(
    document: dict[str, Any],
    field: str,
) -> dict[str, Any] | None:
    if field not in document or document[field] is None:
        return None
    value = document[field]
    if not isinstance(value, dict):
        raise GuestControlDependencyError(
            f"control document field is invalid: {field}",
            kind="controlDocumentInvalid",
        )
    return value


def optional_nullable_string(document: dict[str, Any], field: str) -> str | None:
    if field not in document or document[field] is None:
        return None
    value = document[field]
    if not isinstance(value, str):
        raise GuestControlDependencyError(
            f"control document field is invalid: {field}",
            kind="controlDocumentInvalid",
        )
    return value


def optional_string(document: dict[str, Any], field: str) -> str:
    if field not in document:
        return ""
    value = document[field]
    if not isinstance(value, str):
        raise GuestControlDependencyError(
            f"control document field is invalid: {field}",
            kind="controlDocumentInvalid",
        )
    return value
