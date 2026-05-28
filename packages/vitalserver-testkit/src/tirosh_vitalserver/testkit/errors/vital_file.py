"""Vital file domain exceptions."""

from __future__ import annotations

from tirosh_vitalserver.testkit.errors.base import DomainError


class VitalFileDomainError(DomainError):
    """Base error for invalid vital file domain operations."""


class InvalidVitalFilenameError(VitalFileDomainError):
    """Raised when `.vital` file names do not match VitalDB upload rules."""

    def __init__(self, filenames: tuple[str, ...]) -> None:
        joined = ", ".join(filenames)
        super().__init__(f"invalid vital filename format: {joined}")
        self.filenames = filenames


__all__ = [
    "InvalidVitalFilenameError",
    "VitalFileDomainError",
]
