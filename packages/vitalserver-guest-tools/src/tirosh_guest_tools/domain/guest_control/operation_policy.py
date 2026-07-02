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


def ensure_not_terminal(operation: ServiceOperation) -> None:
    if operation.state in TERMINAL_OPERATION_STATES:
        raise GuestControlPolicyError(
            f"terminal operation cannot transition: {operation.state.value}"
        )
