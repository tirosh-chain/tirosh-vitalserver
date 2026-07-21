"""Persistence contract for exported recovery artifact receipts."""

from __future__ import annotations

from typing import Protocol

from tirosh_vitalserver.recorder_recovery.domain import (
    RecoveryArtifactReceipt,
    RecoveryArtifactRecord,
)


class RecoveryArtifactRegistryPort(Protocol):
    """Store and load owner-issued recovery artifact receipts."""

    def register_export(self, receipt: RecoveryArtifactReceipt) -> None:
        """Persist one completed export idempotently."""

    def get(self, artifact_id: str) -> RecoveryArtifactReceipt | None:
        """Return the exact receipt, or explicit absence."""

    def list(self) -> tuple[RecoveryArtifactReceipt, ...]:
        """Return all receipts ordered newest first."""

    def get_record(self, artifact_id: str) -> RecoveryArtifactRecord | None:
        """Return receipt and persisted publish state, or explicit absence."""

    def list_records(self) -> tuple[RecoveryArtifactRecord, ...]:
        """Return receipts and publish states ordered newest first."""

    def save_publish(self, record: RecoveryArtifactRecord) -> None:
        """Persist an explicit publish transition for an existing artifact."""
