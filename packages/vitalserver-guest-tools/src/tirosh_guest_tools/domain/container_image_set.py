from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any


class ContainerImageSetCommand(StrEnum):
    APPLY = "apply"
    ROLLBACK = "rollback"


class ContainerImageSetOperationState(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    UNAVAILABLE = "unavailable"


TERMINAL_CONTAINER_IMAGE_SET_OPERATION_STATES = frozenset(
    {
        ContainerImageSetOperationState.SUCCEEDED,
        ContainerImageSetOperationState.FAILED,
        ContainerImageSetOperationState.UNAVAILABLE,
    }
)


class ContainerImageSetContractError(ValueError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class ContainerImageSetDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class ContainerImageSetConflictError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass(frozen=True)
class ContainerImageSet:
    identity: str
    digest: str

    @staticmethod
    def validated(identity: object, digest: object) -> ContainerImageSet:
        if not isinstance(identity, str) or not identity.strip():
            raise ContainerImageSetContractError(
                "Container image-set identity must be a non-empty string.",
                kind="containerImageSetIdentityInvalid",
            )
        if not isinstance(digest, str) or not digest.startswith("sha256:"):
            raise ContainerImageSetContractError(
                "Container image-set digest must use the sha256:<hex> form.",
                kind="containerImageSetDigestInvalid",
            )
        digest_hex = digest.removeprefix("sha256:")
        if len(digest_hex) != 64 or any(
            character not in "0123456789abcdef" for character in digest_hex
        ):
            raise ContainerImageSetContractError(
                "Container image-set digest must contain 64 lowercase hex characters.",
                kind="containerImageSetDigestInvalid",
            )
        return ContainerImageSet(identity=identity.strip(), digest=digest)

    def as_json(self) -> dict[str, str]:
        return {"identity": self.identity, "digest": self.digest}


@dataclass(frozen=True)
class ContainerImageSetFailure:
    kind: str
    message: str

    def as_json(self) -> dict[str, str]:
        return {"kind": self.kind, "message": self.message}


@dataclass(frozen=True)
class ContainerImageSetRead:
    state: str
    image_set: ContainerImageSet | None
    observed_at: datetime
    failure: ContainerImageSetFailure | None = None

    @staticmethod
    def available(
        image_set: ContainerImageSet, *, observed_at: datetime
    ) -> ContainerImageSetRead:
        return ContainerImageSetRead(
            state="available",
            image_set=image_set,
            observed_at=observed_at,
        )

    @staticmethod
    def unavailable(
        failure: ContainerImageSetFailure, *, observed_at: datetime
    ) -> ContainerImageSetRead:
        return ContainerImageSetRead(
            state="unavailable",
            image_set=None,
            observed_at=observed_at,
            failure=failure,
        )

    def as_json(self) -> dict[str, Any]:
        return {
            "state": self.state,
            "imageSet": self.image_set.as_json() if self.image_set else None,
            "observedAt": self.observed_at.isoformat(),
            "failure": self.failure.as_json() if self.failure else None,
        }


@dataclass(frozen=True)
class ContainerImageSetOperation:
    operation_id: str
    command: ContainerImageSetCommand
    expected_current_identity: str
    target: ContainerImageSet
    state: ContainerImageSetOperationState
    created_at: datetime
    updated_at: datetime
    failure: ContainerImageSetFailure | None = None

    def as_json(self) -> dict[str, Any]:
        return {
            "operationId": self.operation_id,
            "command": self.command.value,
            "expectedCurrentIdentity": self.expected_current_identity,
            "target": self.target.as_json(),
            "state": self.state.value,
            "createdAt": self.created_at.isoformat(),
            "updatedAt": self.updated_at.isoformat(),
            "failure": self.failure.as_json() if self.failure else None,
        }


def transition_container_image_set_operation(
    current: ContainerImageSetOperation,
    *,
    state: ContainerImageSetOperationState,
    updated_at: datetime,
    failure: ContainerImageSetFailure | None = None,
) -> ContainerImageSetOperation:
    allowed = {
        ContainerImageSetOperationState.PENDING: {
            ContainerImageSetOperationState.RUNNING,
            ContainerImageSetOperationState.FAILED,
            ContainerImageSetOperationState.UNAVAILABLE,
        },
        ContainerImageSetOperationState.RUNNING: {
            ContainerImageSetOperationState.SUCCEEDED,
            ContainerImageSetOperationState.FAILED,
            ContainerImageSetOperationState.UNAVAILABLE,
        },
    }
    if state not in allowed.get(current.state, set()):
        raise ContainerImageSetContractError(
            "Container image-set operation transition is invalid: "
            f"{current.state.value}->{state.value}.",
            kind="containerImageSetOperationTransitionInvalid",
        )
    if updated_at < current.updated_at:
        raise ContainerImageSetContractError(
            "Container image-set operation updatedAt cannot move backwards.",
            kind="containerImageSetOperationTimestampInvalid",
        )
    if state in {
        ContainerImageSetOperationState.FAILED,
        ContainerImageSetOperationState.UNAVAILABLE,
    }:
        if failure is None:
            raise ContainerImageSetContractError(
                "Failed and unavailable container image-set operations "
                "require failure.",
                kind="containerImageSetOperationFailureMissing",
            )
    elif failure is not None:
        raise ContainerImageSetContractError(
            "Non-failure container image-set operations cannot contain failure.",
            kind="containerImageSetOperationFailureUnexpected",
        )
    return ContainerImageSetOperation(
        operation_id=current.operation_id,
        command=current.command,
        expected_current_identity=current.expected_current_identity,
        target=current.target,
        state=state,
        created_at=current.created_at,
        updated_at=updated_at,
        failure=failure,
    )
