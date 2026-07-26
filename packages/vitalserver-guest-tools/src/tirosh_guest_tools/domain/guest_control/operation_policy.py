from __future__ import annotations

from datetime import datetime
from typing import Any

from tirosh_guest_tools.domain.guest_control.models import (
    TERMINAL_OPERATION_STATES,
    GuestControlPolicyError,
    OperationFailure,
    OperationState,
    ServiceCommand,
    ServiceOperation,
)

_ALLOWED_OPERATION_TRANSITIONS: dict[OperationState, frozenset[OperationState]] = {
    OperationState.ACCEPTED: frozenset(
        {
            OperationState.RUNNING,
            OperationState.FAILED,
            OperationState.CANCELLED,
            OperationState.INTERRUPTED,
        }
    ),
    OperationState.RUNNING: frozenset(
        {
            OperationState.COMPLETED,
            OperationState.FAILED,
            OperationState.CANCELLED,
            OperationState.INTERRUPTED,
        }
    ),
}


def accept_service_operation(
    *,
    operation_id: str,
    service: str,
    command: ServiceCommand,
    now: datetime,
) -> ServiceOperation:
    return ServiceOperation(
        operation_id=operation_id,
        service=service,
        command=command,
        state=OperationState.ACCEPTED,
        created_at=now,
        updated_at=now,
    )


def start_operation(operation: ServiceOperation, *, now: datetime) -> ServiceOperation:
    ensure_not_terminal(operation)
    if operation.state != OperationState.ACCEPTED:
        raise GuestControlPolicyError(
            f"operation cannot start from state: {operation.state.value}"
        )
    return ServiceOperation(
        operation_id=operation.operation_id,
        service=operation.service,
        command=operation.command,
        state=OperationState.RUNNING,
        created_at=operation.created_at,
        updated_at=now,
    )


def finish_operation(
    operation: ServiceOperation,
    *,
    now: datetime,
    result: dict[str, Any] | None = None,
) -> ServiceOperation:
    ensure_not_terminal(operation)
    if operation.state != OperationState.RUNNING:
        raise GuestControlPolicyError(
            f"operation cannot complete from state: {operation.state.value}"
        )
    return ServiceOperation(
        operation_id=operation.operation_id,
        service=operation.service,
        command=operation.command,
        state=OperationState.COMPLETED,
        created_at=operation.created_at,
        updated_at=now,
        result=result,
    )


def fail_operation(
    operation: ServiceOperation,
    *,
    failure: OperationFailure,
    now: datetime,
) -> ServiceOperation:
    ensure_not_terminal(operation)
    if operation.state not in {OperationState.ACCEPTED, OperationState.RUNNING}:
        raise GuestControlPolicyError(
            f"operation cannot fail from state: {operation.state.value}"
        )
    return ServiceOperation(
        operation_id=operation.operation_id,
        service=operation.service,
        command=operation.command,
        state=OperationState.FAILED,
        created_at=operation.created_at,
        updated_at=now,
        failure=failure,
    )


def interrupt_operation(
    operation: ServiceOperation,
    *,
    failure: OperationFailure,
    now: datetime,
) -> ServiceOperation:
    ensure_not_terminal(operation)
    if operation.state not in {OperationState.ACCEPTED, OperationState.RUNNING}:
        raise GuestControlPolicyError(
            f"operation cannot be interrupted from state: {operation.state.value}"
        )
    return ServiceOperation(
        operation_id=operation.operation_id,
        service=operation.service,
        command=operation.command,
        state=OperationState.INTERRUPTED,
        created_at=operation.created_at,
        updated_at=now,
        failure=failure,
    )


def ensure_valid_operation_transition(
    persisted: ServiceOperation,
    transition: ServiceOperation,
) -> None:
    """Validate a transition against the operation state already made durable."""
    _ensure_operation_identity_is_unchanged(persisted, transition)
    if transition.updated_at <= persisted.updated_at:
        raise GuestControlPolicyError(
            "operation transition updatedAt must be later than its persisted value"
        )
    allowed_states = _ALLOWED_OPERATION_TRANSITIONS.get(persisted.state)
    if allowed_states is None:
        raise GuestControlPolicyError(
            f"terminal operation cannot transition: {persisted.state.value}"
        )
    if transition.state not in allowed_states:
        raise GuestControlPolicyError(
            "operation cannot transition from state: "
            f"{persisted.state.value} to {transition.state.value}"
        )


def _ensure_operation_identity_is_unchanged(
    persisted: ServiceOperation,
    transition: ServiceOperation,
) -> None:
    immutable_fields = (
        ("operationId", persisted.operation_id, transition.operation_id),
        ("service", persisted.service, transition.service),
        ("command", persisted.command, transition.command),
        ("createdAt", persisted.created_at, transition.created_at),
    )
    for field, persisted_value, transition_value in immutable_fields:
        if persisted_value != transition_value:
            raise GuestControlPolicyError(
                f"operation transition changes immutable field: {field}"
            )


def ensure_not_terminal(operation: ServiceOperation) -> None:
    if operation.state in TERMINAL_OPERATION_STATES:
        raise GuestControlPolicyError(
            f"terminal operation cannot transition: {operation.state.value}"
        )
