from __future__ import annotations

from datetime import UTC, datetime

import pytest

from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlPolicyError,
    OperationFailure,
    OperationState,
    ServiceCommand,
)
from tirosh_guest_tools.domain.guest_control.operation_policy import (
    accept_service_operation,
    fail_operation,
    finish_operation,
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
