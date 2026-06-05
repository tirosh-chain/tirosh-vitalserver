"""Bed domain exceptions."""

from __future__ import annotations

from tirosh_vitalserver.testkit.errors.base import DomainError


class BedDomainError(DomainError):
    """Base error for invalid bed domain operations."""


class BedCountInvalidError(BedDomainError):
    """Raised when a generated bed count is invalid."""

    def __init__(self) -> None:
        super().__init__("count must be greater than 0")


class BedRoomNameRequiredError(BedDomainError):
    """Raised when a bed room name list is missing."""

    def __init__(self, message: str = "room_names must not be empty") -> None:
        super().__init__(message)


class BedRoomNameEmptyError(BedDomainError):
    """Raised when one bed room name is empty."""

    def __init__(self) -> None:
        super().__init__("room_name must not be empty")


class DuplicateBedRoomNameError(BedDomainError):
    """Raised when one bed is selected more than once."""

    def __init__(self) -> None:
        super().__init__("room_names must not include duplicate values")


class InsufficientBedsForRecordersError(BedDomainError):
    """Raised when multiple VRecorders would compete for one active bed."""

    def __init__(self) -> None:
        super().__init__("bed count must be greater than or equal to recorder count")


class BedNotRegisteredError(BedDomainError):
    """Raised when a recorder references a bed outside the registry."""

    def __init__(self, room_names: tuple[str, ...]) -> None:
        joined = ", ".join(room_names)
        super().__init__(f"bed room names are not registered: {joined}")


class BedAlreadyAssignedError(BedDomainError):
    """Raised when a recorder tries to reuse an active bed."""

    def __init__(self, room_names: tuple[str, ...]) -> None:
        joined = ", ".join(room_names)
        super().__init__(f"bed room names are already assigned: {joined}")


class ActiveBedAssignmentsExistError(BedDomainError):
    """Raised when deleting beds would orphan active recorder assignments."""

    def __init__(
        self,
        room_names: tuple[str, ...],
        *,
        operation: str = "reset",
    ) -> None:
        joined = ", ".join(room_names)
        message = f"active bed assignments must be stopped before {operation}: {joined}"
        super().__init__(message)


__all__ = [
    "ActiveBedAssignmentsExistError",
    "BedAlreadyAssignedError",
    "BedCountInvalidError",
    "BedDomainError",
    "BedNotRegisteredError",
    "BedRoomNameEmptyError",
    "BedRoomNameRequiredError",
    "DuplicateBedRoomNameError",
    "InsufficientBedsForRecordersError",
]
