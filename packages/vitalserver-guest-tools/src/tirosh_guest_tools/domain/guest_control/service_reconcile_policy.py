from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum

from tirosh_guest_tools.domain.guest_control.models import (
    GuestServiceCondition,
    GuestServiceDesiredState,
    GuestServiceObservedState,
    GuestServiceSpec,
    GuestServiceSpecState,
    GuestServiceStatusRead,
    GuestServiceStatusReadState,
    ServiceCommand,
)


class GuestServiceReconcileEffect(StrEnum):
    NONE = "none"
    START = "start"
    STOP = "stop"
    RESTART = "restart"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class GuestServiceReconcileDecision:
    effect: GuestServiceReconcileEffect
    command: ServiceCommand | None
    conditions: list[GuestServiceCondition]
    reason: str
    message: str

    @property
    def blocked(self) -> bool:
        return self.effect == GuestServiceReconcileEffect.BLOCKED

    def result_json(self) -> dict[str, object]:
        return {
            "effect": self.effect.value,
            "command": self.command.value if self.command is not None else None,
            "reason": self.reason,
            "message": self.message,
        }


def reconcile_guest_service(
    *,
    spec: GuestServiceSpec,
    status: GuestServiceStatusRead,
    requested_command: ServiceCommand | None,
    now: datetime,
) -> GuestServiceReconcileDecision:
    if spec.state == GuestServiceSpecState.MISSING:
        return _blocked(
            reason="SpecMissing",
            message="Guest service desired state is not configured.",
            now=now,
        )

    if status.state == GuestServiceStatusReadState.FAILED:
        failure = status.failure
        return _blocked(
            reason="StatusReadFailed",
            message=failure.message
            if failure is not None
            else "Guest service status read failed.",
            now=now,
        )

    if spec.desired_state is None:
        return _blocked(
            reason="DesiredStateMissing",
            message="Guest service desired state is missing.",
            now=now,
        )

    if requested_command == ServiceCommand.RESTART:
        return _effect(
            effect=GuestServiceReconcileEffect.RESTART,
            command=ServiceCommand.RESTART,
            reason="RestartRequested",
            message="Guest service restart was explicitly requested.",
            now=now,
        )

    observed_state = status.observed_state or GuestServiceObservedState.UNKNOWN
    if spec.desired_state == GuestServiceDesiredState.RUNNING:
        if observed_state == GuestServiceObservedState.RUNNING:
            return _noop(
                reason="DesiredStateObserved",
                message="Guest service already matches desired running state.",
                now=now,
            )
        return _effect(
            effect=GuestServiceReconcileEffect.START,
            command=ServiceCommand.START,
            reason="StartRequired",
            message="Guest service must be started to match desired state.",
            now=now,
        )

    if observed_state in {
        GuestServiceObservedState.EXITED,
        GuestServiceObservedState.STOPPED,
    }:
        return _noop(
            reason="DesiredStateObserved",
            message="Guest service already matches desired stopped state.",
            now=now,
        )
    return _effect(
        effect=GuestServiceReconcileEffect.STOP,
        command=ServiceCommand.STOP,
        reason="StopRequired",
        message="Guest service must be stopped to match desired state.",
        now=now,
    )


def _noop(
    *,
    reason: str,
    message: str,
    now: datetime,
) -> GuestServiceReconcileDecision:
    return GuestServiceReconcileDecision(
        effect=GuestServiceReconcileEffect.NONE,
        command=None,
        conditions=[
            GuestServiceCondition(
                type="Reconciled",
                status="true",
                reason=reason,
                message=message,
                observed_at=now,
            )
        ],
        reason=reason,
        message=message,
    )


def _effect(
    *,
    effect: GuestServiceReconcileEffect,
    command: ServiceCommand,
    reason: str,
    message: str,
    now: datetime,
) -> GuestServiceReconcileDecision:
    return GuestServiceReconcileDecision(
        effect=effect,
        command=command,
        conditions=[
            GuestServiceCondition(
                type="Reconciled",
                status="true",
                reason=reason,
                message=message,
                observed_at=now,
            )
        ],
        reason=reason,
        message=message,
    )


def _blocked(
    *,
    reason: str,
    message: str,
    now: datetime,
) -> GuestServiceReconcileDecision:
    return GuestServiceReconcileDecision(
        effect=GuestServiceReconcileEffect.BLOCKED,
        command=None,
        conditions=[
            GuestServiceCondition(
                type="ReconcileBlocked",
                status="true",
                reason=reason,
                message=message,
                observed_at=now,
            )
        ],
        reason=reason,
        message=message,
    )
