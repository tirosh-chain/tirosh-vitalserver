"""Shared VitalServer domain error contracts."""

from __future__ import annotations


class VitalServerCoreError(Exception):
    """Base error for shared VitalServer domain operations."""


class InvalidVitalFilenameError(VitalServerCoreError, ValueError):
    """Raised when upload input filenames do not match VitalServer policy."""

    def __init__(self, filenames: tuple[str, ...]) -> None:
        self.filenames = filenames
        super().__init__(
            "invalid .vital filename(s): " + ", ".join(filenames)
        )


__all__ = [
    "InvalidVitalFilenameError",
    "VitalServerCoreError",
]
