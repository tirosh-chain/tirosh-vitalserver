"""Recorder domain exceptions."""

from __future__ import annotations

from tirosh_vitalserver.testkit.errors.base import DomainError


class RecorderDomainError(DomainError):
    """Base error for invalid recorder domain operations."""


class RecorderCountInvalidError(RecorderDomainError):
    """Raised when a virtual recorder count is invalid."""

    def __init__(self) -> None:
        super().__init__("count must be greater than 0")


class RecorderPayloadRoomsRequiredError(RecorderDomainError):
    """Raised when a recorder payload has no bed room payloads."""

    def __init__(self) -> None:
        super().__init__("recorder payload does not contain rooms with roomname")


__all__ = [
    "RecorderCountInvalidError",
    "RecorderDomainError",
    "RecorderPayloadRoomsRequiredError",
]
