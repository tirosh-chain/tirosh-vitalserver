from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.recorder_recovery.application.ports import (
    IndexedVitalArtifact,
)
from tirosh_vitalserver.recorder_recovery.application.usecases.publish_artifact import (
    publish_recovery_artifact,
)
from tirosh_vitalserver.recorder_recovery.domain import (
    ArtifactPublishState,
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
    RecoveryArtifactRecord,
)


class MemoryRegistry:
    def __init__(self, record: RecoveryArtifactRecord) -> None:
        self.record = record
        self.saved: list[RecoveryArtifactRecord] = []

    def get_record(self, artifact_id: str) -> RecoveryArtifactRecord | None:
        return self.record if artifact_id == self.record.receipt.artifact_id else None

    def save_publish(self, record: RecoveryArtifactRecord) -> None:
        self.record = record
        self.saved.append(record)


class RecordingPublisher:
    def __init__(
        self,
        *,
        collision: IndexedVitalArtifact | None = None,
        indexed: IndexedVitalArtifact | None = None,
    ) -> None:
        self.collision = collision
        self.indexed = indexed
        self.uploads: list[str] = []
        self.index_reads = 0

    def find_indexed(self, filename: str) -> IndexedVitalArtifact | None:
        del filename
        self.index_reads += 1
        return self.collision

    def upload(self, receipt: RecoveryArtifactReceipt) -> None:
        self.uploads.append(receipt.artifact_id)

    def wait_until_indexed(
        self,
        filename: str,
        *,
        size_bytes: int,
    ) -> IndexedVitalArtifact | None:
        del filename, size_bytes
        return self.indexed


def test_publish_persists_transitions_and_index_proof(tmp_path: Path) -> None:
    initial = RecoveryArtifactRecord(_receipt(tmp_path))
    registry = MemoryRegistry(initial)
    indexed = IndexedVitalArtifact(
        filename=initial.receipt.filename,
        relative_path="VR_A/202601/260101/VR_A_260101_000000.vital",
        size_bytes=10,
    )
    publisher = RecordingPublisher(indexed=indexed)
    times = iter((10.0, 11.0, 12.0, 13.0))

    result = publish_recovery_artifact(
        initial.receipt.artifact_id,
        registry=registry,
        publisher=publisher,
        clock=lambda: next(times),
        attempt_id_factory=lambda: "attempt-a",
    )

    assert [record.publish_state for record in registry.saved] == [
        ArtifactPublishState.REQUESTED,
        ArtifactPublishState.PUBLISHING,
        ArtifactPublishState.RECONCILING,
        ArtifactPublishState.PUBLISHED,
    ]
    assert publisher.uploads == [initial.receipt.artifact_id]
    assert result.indexed_relative_path == indexed.relative_path


def test_publish_rejects_existing_filename_without_upload(tmp_path: Path) -> None:
    initial = RecoveryArtifactRecord(_receipt(tmp_path))
    registry = MemoryRegistry(initial)
    collision = IndexedVitalArtifact(
        filename=initial.receipt.filename,
        relative_path="existing/file.vital",
        size_bytes=10,
    )
    publisher = RecordingPublisher(collision=collision)
    times = iter((10.0, 11.0))

    result = publish_recovery_artifact(
        initial.receipt.artifact_id,
        registry=registry,
        publisher=publisher,
        clock=lambda: next(times),
        attempt_id_factory=lambda: "attempt-a",
    )

    assert result.publish_state is ArtifactPublishState.FAILED
    assert result.failure is not None
    assert result.failure.code == "filenameCollision"
    assert publisher.uploads == []


def test_publishing_state_reconciles_without_reupload(tmp_path: Path) -> None:
    initial = RecoveryArtifactRecord(
        _receipt(tmp_path),
        publish_state=ArtifactPublishState.PUBLISHING,
        publish_attempt_id="attempt-a",
        publish_requested_at=10.0,
        publish_started_at=11.0,
    )
    registry = MemoryRegistry(initial)
    indexed = IndexedVitalArtifact(
        filename=initial.receipt.filename,
        relative_path="VR_A/202601/260101/VR_A_260101_000000.vital",
        size_bytes=10,
    )
    publisher = RecordingPublisher(indexed=indexed)

    result = publish_recovery_artifact(
        initial.receipt.artifact_id,
        registry=registry,
        publisher=publisher,
        clock=lambda: 12.0,
    )

    assert result.publish_state is ArtifactPublishState.PUBLISHED
    assert publisher.uploads == []
    assert publisher.index_reads == 0


def _receipt(tmp_path: Path) -> RecoveryArtifactReceipt:
    return RecoveryArtifactReceipt(
        artifact_id="a" * 64,
        origin=RecoveryArtifactOrigin.COLD_PATH_RECOVERY,
        producer="recorder-recovery",
        writer_version="3",
        vrcode="VR_A",
        room_names=("OR-A",),
        source_archive_id="raw-a",
        source_start_offset=0,
        source_end_offset=10,
        coverage_started_at=1.0,
        coverage_ended_at=2.0,
        format_version=3,
        sha256="b" * 64,
        path=str(tmp_path / "VR_A_260101_000000.vital"),
        filename="VR_A_260101_000000.vital",
        size_bytes=10,
        created_at=3.0,
        track_count=1,
    )
