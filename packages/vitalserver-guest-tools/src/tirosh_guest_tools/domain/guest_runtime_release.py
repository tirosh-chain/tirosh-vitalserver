from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any

GUEST_RUNTIME_RELEASE_IDENTITY_PATTERN = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"
)


class GuestRuntimeReleaseCommand(StrEnum):
    APPLY = "apply"
    ROLLBACK = "rollback"


class GuestRuntimeReleaseOperationState(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    UNAVAILABLE = "unavailable"


TERMINAL_GUEST_RUNTIME_RELEASE_OPERATION_STATES = frozenset(
    {
        GuestRuntimeReleaseOperationState.SUCCEEDED,
        GuestRuntimeReleaseOperationState.FAILED,
        GuestRuntimeReleaseOperationState.UNAVAILABLE,
    }
)


class GuestRuntimeReleaseContractError(ValueError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class GuestRuntimeReleaseDependencyError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


class GuestRuntimeReleaseConflictError(RuntimeError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass(frozen=True)
class GuestRuntimeRelease:
    identity: str
    archive: str
    digest: str

    @staticmethod
    def validated(
        identity: object,
        archive: object,
        digest: object,
    ) -> GuestRuntimeRelease:
        if not isinstance(
            identity, str
        ) or not GUEST_RUNTIME_RELEASE_IDENTITY_PATTERN.fullmatch(identity):
            raise GuestRuntimeReleaseContractError(
                "Guest Runtime release identity must be a safe identifier.",
                kind="guestRuntimeReleaseIdentityInvalid",
            )
        if not isinstance(archive, str) or not archive.strip():
            raise GuestRuntimeReleaseContractError(
                "Guest Runtime release archive must be a non-empty owner reference.",
                kind="guestRuntimeReleaseArchiveInvalid",
            )
        if not isinstance(digest, str) or not digest.startswith("sha256:"):
            raise GuestRuntimeReleaseContractError(
                "Guest Runtime release digest must use the sha256:<hex> form.",
                kind="guestRuntimeReleaseDigestInvalid",
            )
        digest_hex = digest.removeprefix("sha256:")
        if len(digest_hex) != 64 or any(
            character not in "0123456789abcdef" for character in digest_hex
        ):
            raise GuestRuntimeReleaseContractError(
                "Guest Runtime release digest must contain "
                "64 lowercase hex characters.",
                kind="guestRuntimeReleaseDigestInvalid",
            )
        return GuestRuntimeRelease(
            identity=identity,
            archive=archive.strip(),
            digest=digest,
        )

    def as_json(self) -> dict[str, str]:
        return {
            "identity": self.identity,
            "archive": self.archive,
            "digest": self.digest,
        }


@dataclass(frozen=True)
class GuestRuntimeReleaseFailure:
    kind: str
    message: str

    def as_json(self) -> dict[str, str]:
        return {"kind": self.kind, "message": self.message}


@dataclass(frozen=True)
class GuestRuntimeReleaseRead:
    state: str
    release: GuestRuntimeRelease | None
    observed_at: datetime
    failure: GuestRuntimeReleaseFailure | None = None

    @staticmethod
    def available(
        release: GuestRuntimeRelease,
        *,
        observed_at: datetime,
    ) -> GuestRuntimeReleaseRead:
        return GuestRuntimeReleaseRead(
            state="available",
            release=release,
            observed_at=observed_at,
        )

    @staticmethod
    def unavailable(
        failure: GuestRuntimeReleaseFailure,
        *,
        observed_at: datetime,
    ) -> GuestRuntimeReleaseRead:
        return GuestRuntimeReleaseRead(
            state="unavailable",
            release=None,
            observed_at=observed_at,
            failure=failure,
        )

    def as_json(self) -> dict[str, Any]:
        return {
            "state": self.state,
            "release": self.release.as_json() if self.release else None,
            "observedAt": self.observed_at.isoformat(),
            "failure": self.failure.as_json() if self.failure else None,
        }


@dataclass(frozen=True)
class GuestRuntimeReleaseOperation:
    operation_id: str
    command: GuestRuntimeReleaseCommand
    expected_active_identity: str
    target: GuestRuntimeRelease
    state: GuestRuntimeReleaseOperationState
    created_at: datetime
    updated_at: datetime
    failure: GuestRuntimeReleaseFailure | None = None

    def as_json(self) -> dict[str, Any]:
        return {
            "operationId": self.operation_id,
            "command": self.command.value,
            "expectedActiveIdentity": self.expected_active_identity,
            "target": self.target.as_json(),
            "state": self.state.value,
            "createdAt": self.created_at.isoformat(),
            "updatedAt": self.updated_at.isoformat(),
            "failure": self.failure.as_json() if self.failure else None,
        }


def transition_guest_runtime_release_operation(
    current: GuestRuntimeReleaseOperation,
    *,
    state: GuestRuntimeReleaseOperationState,
    updated_at: datetime,
    failure: GuestRuntimeReleaseFailure | None = None,
) -> GuestRuntimeReleaseOperation:
    allowed = {
        GuestRuntimeReleaseOperationState.PENDING: {
            GuestRuntimeReleaseOperationState.RUNNING,
            GuestRuntimeReleaseOperationState.FAILED,
            GuestRuntimeReleaseOperationState.UNAVAILABLE,
        },
        GuestRuntimeReleaseOperationState.RUNNING: {
            GuestRuntimeReleaseOperationState.SUCCEEDED,
            GuestRuntimeReleaseOperationState.FAILED,
            GuestRuntimeReleaseOperationState.UNAVAILABLE,
        },
    }
    if state not in allowed.get(current.state, set()):
        raise GuestRuntimeReleaseContractError(
            "Guest Runtime release operation transition is invalid: "
            f"{current.state.value}->{state.value}.",
            kind="guestRuntimeReleaseOperationTransitionInvalid",
        )
    if updated_at < current.updated_at:
        raise GuestRuntimeReleaseContractError(
            "Guest Runtime release operation updatedAt cannot move backwards.",
            kind="guestRuntimeReleaseOperationTimestampInvalid",
        )
    failure_required = state in {
        GuestRuntimeReleaseOperationState.FAILED,
        GuestRuntimeReleaseOperationState.UNAVAILABLE,
    }
    if failure_required != (failure is not None):
        raise GuestRuntimeReleaseContractError(
            "Guest Runtime release operation state and failure disagree.",
            kind="guestRuntimeReleaseOperationFailureInvalid",
        )
    return GuestRuntimeReleaseOperation(
        operation_id=current.operation_id,
        command=current.command,
        expected_active_identity=current.expected_active_identity,
        target=current.target,
        state=state,
        created_at=current.created_at,
        updated_at=updated_at,
        failure=failure,
    )
