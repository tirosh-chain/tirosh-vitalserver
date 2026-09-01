"""Errors raised while reading the legacy VitalServer HL7 endpoint."""

from __future__ import annotations

from tirosh_vitalserver.testkit.errors.base import TestKitError


class Hl7Error(TestKitError):
    """Base error for VitalServer HL7 polling."""


class Hl7ParseError(Hl7Error, ValueError):
    """Base error for an invalid HL7 response body."""


class Hl7FramingError(Hl7ParseError):
    """Raised when the response does not use the expected MLLP-like framing."""


class Hl7SegmentError(Hl7ParseError):
    """Raised when a framed message has an invalid required segment."""


class Hl7RequestError(Hl7Error):
    """Raised when VitalServer does not return a successful HL7 response."""


__all__ = [
    "Hl7Error",
    "Hl7FramingError",
    "Hl7ParseError",
    "Hl7RequestError",
    "Hl7SegmentError",
]
