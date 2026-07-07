from __future__ import annotations

from datetime import UTC, datetime

from tirosh_guest_tools.domain.guest_control.models import (
    GuestServiceDesiredState,
    GuestServiceSpec,
    GuestServiceStatusRead,
    OperationFailure,
    ServiceCommand,
    ServiceStatus,
)
from tirosh_guest_tools.domain.guest_control.service_reconcile_policy import (
    GuestServiceReconcileEffect,
    reconcile_guest_service,
)

NOW = datetime(2026, 7, 1, tzinfo=UTC)


def test_reconcile_blocks_missing_spec() -> None:
    decision = reconcile_guest_service(
        spec=GuestServiceSpec.missing(),
        status=GuestServiceStatusRead.loaded(_service_status("running")),
        requested_command=None,
        now=NOW,
    )

    assert decision.effect == GuestServiceReconcileEffect.BLOCKED
    assert decision.conditions[0].reason == "SpecMissing"


def test_reconcile_blocks_failed_status_read() -> None:
    decision = reconcile_guest_service(
        spec=GuestServiceSpec.configured(
            desired_state=GuestServiceDesiredState.RUNNING,
            updated_at=NOW,
        ),
        status=GuestServiceStatusRead.failed(
            OperationFailure(kind="statusReadFailed", message="status failed")
        ),
        requested_command=None,
        now=NOW,
    )

    assert decision.effect == GuestServiceReconcileEffect.BLOCKED
    assert decision.reason == "StatusReadFailed"


def test_reconcile_noops_when_desired_running_is_observed() -> None:
    decision = reconcile_guest_service(
        spec=GuestServiceSpec.configured(
            desired_state=GuestServiceDesiredState.RUNNING,
            updated_at=NOW,
        ),
        status=GuestServiceStatusRead.loaded(_service_status("running")),
        requested_command=ServiceCommand.START,
        now=NOW,
    )

    assert decision.effect == GuestServiceReconcileEffect.NONE
    assert decision.command is None
    assert decision.reason == "DesiredStateObserved"


def test_reconcile_starts_when_desired_running_is_not_observed() -> None:
    decision = reconcile_guest_service(
        spec=GuestServiceSpec.configured(
            desired_state=GuestServiceDesiredState.RUNNING,
            updated_at=NOW,
        ),
        status=GuestServiceStatusRead.loaded(_service_status("exited")),
        requested_command=None,
        now=NOW,
    )

    assert decision.effect == GuestServiceReconcileEffect.START
    assert decision.command == ServiceCommand.START


def test_reconcile_stops_when_desired_stopped_is_not_observed() -> None:
    decision = reconcile_guest_service(
        spec=GuestServiceSpec.configured(
            desired_state=GuestServiceDesiredState.STOPPED,
            updated_at=NOW,
        ),
        status=GuestServiceStatusRead.loaded(_service_status("running")),
        requested_command=ServiceCommand.STOP,
        now=NOW,
    )

    assert decision.effect == GuestServiceReconcileEffect.STOP
    assert decision.command == ServiceCommand.STOP


def test_reconcile_restarts_when_restart_is_requested() -> None:
    decision = reconcile_guest_service(
        spec=GuestServiceSpec.configured(
            desired_state=GuestServiceDesiredState.RUNNING,
            updated_at=NOW,
        ),
        status=GuestServiceStatusRead.loaded(_service_status("running")),
        requested_command=ServiceCommand.RESTART,
        now=NOW,
    )

    assert decision.effect == GuestServiceReconcileEffect.RESTART
    assert decision.command == ServiceCommand.RESTART


def _service_status(state: str) -> ServiceStatus:
    return ServiceStatus(
        service="app",
        state=state,
        health="healthy",
        observed_at=NOW,
    )
