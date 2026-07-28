from __future__ import annotations

from typing import Protocol

from tirosh_guest_tools.application.guest_control.ports import Clock, OperationIdFactory
from tirosh_guest_tools.domain.container_image_set import (
    ContainerImageSet,
    ContainerImageSetCommand,
    ContainerImageSetContractError,
    ContainerImageSetDependencyError,
    ContainerImageSetFailure,
    ContainerImageSetOperation,
    ContainerImageSetOperationState,
    ContainerImageSetRead,
)


class ContainerImageSetStateOwner(Protocol):
    """Durable Guest owner for the current image-set and its mutations."""

    def read_current(self) -> ContainerImageSet:
        raise NotImplementedError

    def accept(self, operation: ContainerImageSetOperation) -> None:
        """Atomically compare current identity and persist a pending command."""
        raise NotImplementedError

    def get_operation(self, operation_id: str) -> ContainerImageSetOperation | None:
        raise NotImplementedError

    def record_container_image_set_transition(
        self, operation: ContainerImageSetOperation
    ) -> None:
        """Persist an executor-reported transition and activate succeeded target."""
        raise NotImplementedError


class ContainerImageSetUseCases:
    """Application boundary used by Host and a future Guest effect executor."""

    def __init__(
        self,
        *,
        state_owner: ContainerImageSetStateOwner | None,
        operation_ids: OperationIdFactory,
        clock: Clock,
    ) -> None:
        self._state_owner = state_owner
        self._operation_ids = operation_ids
        self._clock = clock

    def read_current(self) -> ContainerImageSetRead:
        observed_at = self._clock.now()
        if self._state_owner is None:
            return ContainerImageSetRead.unavailable(
                ContainerImageSetFailure(
                    kind="containerImageSetOwnerUnavailable",
                    message="Container image-set state owner is not configured.",
                ),
                observed_at=observed_at,
            )
        try:
            current = self._state_owner.read_current()
        except ContainerImageSetDependencyError as error:
            return ContainerImageSetRead.unavailable(
                ContainerImageSetFailure(kind=error.kind, message=error.message),
                observed_at=observed_at,
            )
        return ContainerImageSetRead.available(current, observed_at=observed_at)

    def apply(self, request: dict[str, object]) -> ContainerImageSetOperation:
        return self._accept(ContainerImageSetCommand.APPLY, request)

    def rollback(self, request: dict[str, object]) -> ContainerImageSetOperation:
        return self._accept(ContainerImageSetCommand.ROLLBACK, request)

    def operation(self, operation_id: str) -> ContainerImageSetOperation | None:
        if self._state_owner is None:
            raise ContainerImageSetDependencyError(
                "Container image-set state owner is not configured.",
                kind="containerImageSetOwnerUnavailable",
            )
        return self._state_owner.get_operation(operation_id)

    def _accept(
        self,
        command: ContainerImageSetCommand,
        request: dict[str, object],
    ) -> ContainerImageSetOperation:
        if self._state_owner is None:
            raise ContainerImageSetDependencyError(
                "Container image-set state owner is not configured.",
                kind="containerImageSetOwnerUnavailable",
            )
        expected = request.get("expectedCurrentIdentity")
        if not isinstance(expected, str) or not expected.strip():
            raise ContainerImageSetContractError(
                "expectedCurrentIdentity must be a non-empty string.",
                kind="containerImageSetExpectedIdentityInvalid",
            )
        target_document = request.get("target")
        if not isinstance(target_document, dict):
            raise ContainerImageSetContractError(
                "target must be an object.",
                kind="containerImageSetTargetInvalid",
            )
        target = ContainerImageSet.validated(
            target_document.get("identity"),
            target_document.get("digest"),
        )
        now = self._clock.now()
        operation = ContainerImageSetOperation(
            operation_id=self._operation_ids.new_operation_id(
                service="container-image-set",
                command=command.value,
            ),
            command=command,
            expected_current_identity=expected.strip(),
            target=target,
            state=ContainerImageSetOperationState.PENDING,
            created_at=now,
            updated_at=now,
        )
        self._state_owner.accept(operation)
        return operation
