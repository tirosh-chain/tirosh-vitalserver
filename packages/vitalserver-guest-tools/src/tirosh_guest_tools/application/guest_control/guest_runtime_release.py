from __future__ import annotations

from typing import Protocol

from tirosh_guest_tools.application.guest_control.ports import Clock, OperationIdFactory
from tirosh_guest_tools.domain.guest_runtime_release import (
    GuestRuntimeRelease,
    GuestRuntimeReleaseCommand,
    GuestRuntimeReleaseContractError,
    GuestRuntimeReleaseDependencyError,
    GuestRuntimeReleaseFailure,
    GuestRuntimeReleaseOperation,
    GuestRuntimeReleaseOperationState,
    GuestRuntimeReleaseRead,
)


class GuestRuntimeReleaseStateOwner(Protocol):
    def read_active_guest_runtime_release(self) -> GuestRuntimeRelease:
        raise NotImplementedError

    def accept_guest_runtime_release_operation(
        self,
        operation: GuestRuntimeReleaseOperation,
    ) -> None:
        raise NotImplementedError

    def get_guest_runtime_release_operation(
        self,
        operation_id: str,
    ) -> GuestRuntimeReleaseOperation | None:
        raise NotImplementedError

    def record_guest_runtime_release_transition(
        self,
        operation: GuestRuntimeReleaseOperation,
    ) -> None:
        raise NotImplementedError


class GuestRuntimeReleaseUseCases:
    def __init__(
        self,
        *,
        state_owner: GuestRuntimeReleaseStateOwner | None,
        operation_ids: OperationIdFactory,
        clock: Clock,
    ) -> None:
        self._state_owner = state_owner
        self._operation_ids = operation_ids
        self._clock = clock

    def read_active(self) -> GuestRuntimeReleaseRead:
        observed_at = self._clock.now()
        if self._state_owner is None:
            return GuestRuntimeReleaseRead.unavailable(
                GuestRuntimeReleaseFailure(
                    kind="guestRuntimeReleaseOwnerUnavailable",
                    message="Guest Runtime release state owner is not configured.",
                ),
                observed_at=observed_at,
            )
        try:
            active = self._state_owner.read_active_guest_runtime_release()
        except GuestRuntimeReleaseDependencyError as error:
            return GuestRuntimeReleaseRead.unavailable(
                GuestRuntimeReleaseFailure(kind=error.kind, message=error.message),
                observed_at=observed_at,
            )
        return GuestRuntimeReleaseRead.available(active, observed_at=observed_at)

    def apply(self, request: dict[str, object]) -> GuestRuntimeReleaseOperation:
        return self._accept(GuestRuntimeReleaseCommand.APPLY, request)

    def rollback(self, request: dict[str, object]) -> GuestRuntimeReleaseOperation:
        return self._accept(GuestRuntimeReleaseCommand.ROLLBACK, request)

    def operation(
        self,
        operation_id: str,
    ) -> GuestRuntimeReleaseOperation | None:
        owner = self._require_owner()
        return owner.get_guest_runtime_release_operation(operation_id)

    def _accept(
        self,
        command: GuestRuntimeReleaseCommand,
        request: dict[str, object],
    ) -> GuestRuntimeReleaseOperation:
        owner = self._require_owner()
        expected = request.get("expectedActiveIdentity")
        if not isinstance(expected, str) or not expected.strip():
            raise GuestRuntimeReleaseContractError(
                "expectedActiveIdentity must be a non-empty string.",
                kind="guestRuntimeReleaseExpectedIdentityInvalid",
            )
        target_document = request.get("target")
        if not isinstance(target_document, dict):
            raise GuestRuntimeReleaseContractError(
                "target must be an object.",
                kind="guestRuntimeReleaseTargetInvalid",
            )
        target = GuestRuntimeRelease.validated(
            target_document.get("identity"),
            target_document.get("archive"),
            target_document.get("digest"),
        )
        now = self._clock.now()
        operation = GuestRuntimeReleaseOperation(
            operation_id=self._operation_ids.new_operation_id(
                service="guest-runtime-release",
                command=command.value,
            ),
            command=command,
            expected_active_identity=expected.strip(),
            target=target,
            state=GuestRuntimeReleaseOperationState.PENDING,
            created_at=now,
            updated_at=now,
        )
        owner.accept_guest_runtime_release_operation(operation)
        return operation

    def _require_owner(self) -> GuestRuntimeReleaseStateOwner:
        if self._state_owner is None:
            raise GuestRuntimeReleaseDependencyError(
                "Guest Runtime release state owner is not configured.",
                kind="guestRuntimeReleaseOwnerUnavailable",
            )
        return self._state_owner
