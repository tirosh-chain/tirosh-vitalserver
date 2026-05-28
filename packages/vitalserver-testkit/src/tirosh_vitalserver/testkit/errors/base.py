"""Base exception types for vitalserver-testkit."""

from __future__ import annotations


class TestKitError(Exception):
    """Base error for vitalserver-testkit."""


class TestKitValueError(TestKitError, ValueError):
    """Base value error for invalid testkit input."""


class DomainError(TestKitValueError):
    """Base error for invalid domain operations."""


__all__ = [
    "DomainError",
    "TestKitError",
    "TestKitValueError",
]
