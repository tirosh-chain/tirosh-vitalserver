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


__all__ = [
    "BedCountInvalidError",
    "BedDomainError",
    "BedRoomNameEmptyError",
    "BedRoomNameRequiredError",
    "DuplicateBedRoomNameError",
    "InsufficientBedsForRecordersError",
]
