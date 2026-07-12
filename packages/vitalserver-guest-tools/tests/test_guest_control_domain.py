from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime

import pytest

from tirosh_guest_tools.domain.guest_control.models import (
    RUNTIME_OPERATION_EVENT_TYPES,
    GuestControlPolicyError,
    OperationFailure,
    OperationState,
    ServiceCommand,
    runtime_operation_event_type_for_state,
)
from tirosh_guest_tools.domain.guest_control.operation_policy import (
    accept_service_operation,
    ensure_valid_operation_transition,
    fail_operation,
    finish_operation,
    interrupt_operation,
    start_operation,
)


def test_service_operation_transitions_to_completed() -> None:
    accepted = accept_service_operation(
        operation_id="op_1",
        service="app",
        command=ServiceCommand.RESTART,
        now=datetime(2026, 7, 1, tzinfo=UTC),
    )

    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    completed = finish_operation(
        running,
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
    )

    assert accepted.state == OperationState.ACCEPTED
    assert running.state == OperationState.RUNNING
    assert completed.state == OperationState.COMPLETED


def test_terminal_operation_cannot_transition_again() -> None:
    accepted = accept_service_operation(
        operation_id="op_1",
        service="app",
        command=ServiceCommand.RESTART,
        now=datetime(2026, 7, 1, tzinfo=UTC),
    )
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )
    completed = finish_operation(
        running,
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
    )

    with pytest.raises(GuestControlPolicyError):
        fail_operation(
            completed,
            failure=OperationFailure(
                kind="composeCommandFailed",
                message="compose failed",
            ),
            now=datetime(2026, 7, 1, 0, 0, 3, tzinfo=UTC),
        )


def test_running_operation_can_be_explicitly_interrupted() -> None:
    accepted = accept_service_operation(
        operation_id="op_1",
        service="app",
        command=ServiceCommand.RESTART,
        now=datetime(2026, 7, 1, tzinfo=UTC),
    )
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )

    interrupted = interrupt_operation(
        running,
        failure=OperationFailure(
            kind="controllerRestarted",
            message=(
                "Runtime Controller restarted before the operation outcome was known."
            ),
        ),
        now=datetime(2026, 7, 1, 0, 0, 2, tzinfo=UTC),
    )

    assert interrupted.state == OperationState.INTERRUPTED
    assert interrupted.failure is not None
    assert interrupted.failure.kind == "controllerRestarted"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("operation_id", "op_other"),
        ("service", "redis"),
        ("command", ServiceCommand.START),
        ("created_at", datetime(2026, 7, 2, tzinfo=UTC)),
    ],
)
def test_persisted_operation_transition_keeps_immutable_identity(
    field: str,
    value: str | ServiceCommand | datetime,
) -> None:
    accepted = accept_service_operation(
        operation_id="op_1",
        service="app",
        command=ServiceCommand.RESTART,
        now=datetime(2026, 7, 1, tzinfo=UTC),
    )
    running = start_operation(
        accepted,
        now=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )

    with pytest.raises(GuestControlPolicyError, match="immutable field"):
        ensure_valid_operation_transition(accepted, replace(running, **{field: value}))


def test_persisted_operation_transition_rejects_skipped_state() -> None:
    accepted = accept_service_operation(
        operation_id="op_1",
        service="app",
        command=ServiceCommand.RESTART,
        now=datetime(2026, 7, 1, tzinfo=UTC),
    )
    completed = replace(
        accepted,
        state=OperationState.COMPLETED,
        updated_at=datetime(2026, 7, 1, 0, 0, 1, tzinfo=UTC),
    )

    with pytest.raises(GuestControlPolicyError, match="accepted to completed"):
        ensure_valid_operation_transition(accepted, completed)


def test_persisted_operation_transition_rejects_stale_updated_at() -> None:
    accepted = accept_service_operation(
        operation_id="op_1",
        service="app",
        command=ServiceCommand.RESTART,
        now=datetime(2026, 7, 1, tzinfo=UTC),
    )
    running = start_operation(accepted, now=accepted.updated_at)

    with pytest.raises(GuestControlPolicyError, match="updatedAt"):
        ensure_valid_operation_transition(accepted, running)


def test_runtime_event_contract_maps_explicit_operation_states() -> None:
    assert (
        frozenset(
            {
                "operation-accepted",
                "operation-running",
                "operation-completed",
                "operation-failed",
                "operation-cancelled",
                "operation-interrupted",
            }
        )
        == RUNTIME_OPERATION_EVENT_TYPES
    )
    assert {
        runtime_operation_event_type_for_state(state) for state in OperationState
    } == RUNTIME_OPERATION_EVENT_TYPES
