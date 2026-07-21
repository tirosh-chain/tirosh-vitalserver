"""VitalServer library owner contract for recovery artifact publishing."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from tirosh_vitalserver.recorder_recovery.domain import RecoveryArtifactReceipt


@dataclass(frozen=True, slots=True)
class IndexedVitalArtifact:
    filename: str
    relative_path: str
    size_bytes: int


class ArtifactPublishDependencyError(RuntimeError):
    def __init__(self, *, stage: str, code: str, message: str) -> None:
        super().__init__(message)
        self.stage = stage
        self.code = code
        self.message = message


class ArtifactPublisherPort(Protocol):
    def find_indexed(self, filename: str) -> IndexedVitalArtifact | None:
        """Read explicit filename presence from the VitalServer-owned index."""

    def upload(self, receipt: RecoveryArtifactReceipt) -> None:
        """Validate and stream one complete artifact to VitalServer."""

    def wait_until_indexed(
        self,
        filename: str,
        *,
        size_bytes: int,
    ) -> IndexedVitalArtifact | None:
        """Return index proof before the configured deadline, or explicit absence."""
