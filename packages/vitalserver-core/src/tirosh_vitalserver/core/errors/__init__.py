"""Shared VitalServer domain error contracts."""

from __future__ import annotations


class VitalServerCoreError(Exception):
    """Base error for shared VitalServer domain operations."""


class InvalidVitalFilenameError(VitalServerCoreError, ValueError):
    """Raised when upload input filenames do not match VitalServer policy."""

    def __init__(self, filenames: tuple[str, ...]) -> None:
        self.filenames = filenames
        super().__init__("invalid .vital filename(s): " + ", ".join(filenames))


class RawArchiveDecodeError(VitalServerCoreError, ValueError):
    """Raised when a recorder-ingress raw archive record is invalid."""


class VitalFileFormatError(VitalServerCoreError, ValueError):
    """Raised when a `.vital` format contract cannot be decoded."""

    def __init__(self, *, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")


__all__ = [
    "InvalidVitalFilenameError",
    "RawArchiveDecodeError",
    "VitalFileFormatError",
    "VitalServerCoreError",
]
