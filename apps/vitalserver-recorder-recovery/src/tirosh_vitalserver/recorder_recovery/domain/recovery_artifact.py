"""Explicit identity and provenance for generated recovery artifacts."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class RecoveryArtifactOrigin(StrEnum):
    """Owner-provided source of one generated artifact."""

    COLD_PATH_RECOVERY = "coldPathRecovery"
    PRODUCT_LAB_GENERATED = "productLabGenerated"


@dataclass(frozen=True, slots=True)
class RecoveryArtifactReceipt:
    """Proof for one complete generated `.vital` artifact."""

    artifact_id: str
    origin: RecoveryArtifactOrigin
    producer: str
    writer_version: str
    vrcode: str
    room_names: tuple[str, ...]
    source_archive_id: str
    source_start_offset: int
    source_end_offset: int
    coverage_started_at: float
    coverage_ended_at: float
    format_version: int
    sha256: str
    path: str
    filename: str
    size_bytes: int
    created_at: float
    track_count: int


def recovery_artifact_receipt_to_document(
    receipt: RecoveryArtifactReceipt,
) -> dict[str, object]:
    """Return a JSON-ready artifact receipt document."""

    return {
        "artifactId": receipt.artifact_id,
        "origin": receipt.origin.value,
        "producer": receipt.producer,
        "writerVersion": receipt.writer_version,
        "vrcode": receipt.vrcode,
        "roomNames": list(receipt.room_names),
        "sourceArchiveId": receipt.source_archive_id,
        "sourceStartOffset": receipt.source_start_offset,
        "sourceEndOffset": receipt.source_end_offset,
        "coverageStartedAt": receipt.coverage_started_at,
        "coverageEndedAt": receipt.coverage_ended_at,
        "formatVersion": receipt.format_version,
        "sha256": receipt.sha256,
        "filename": receipt.filename,
        "sizeBytes": receipt.size_bytes,
        "createdAt": receipt.created_at,
        "trackCount": receipt.track_count,
    }
