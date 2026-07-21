from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_vitalserver.recorder_recovery.domain import (
    ArtifactPublishEvent,
    ArtifactPublishFailure,
    ArtifactPublishState,
    ArtifactPublishTransitionError,
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
    RecoveryArtifactRecord,
    transition_artifact_publish,
)


def test_publish_state_machine_requires_request_before_side_effects(
    tmp_path: Path,
) -> None:
    initial = RecoveryArtifactRecord(receipt=_receipt(tmp_path))

    requested = transition_artifact_publish(
        initial,
        ArtifactPublishEvent.REQUEST,
        occurred_at=10.0,
        attempt_id="attempt-a",
    )
    publishing = transition_artifact_publish(
        requested,
        ArtifactPublishEvent.START_UPLOAD,
        occurred_at=11.0,
    )
    reconciling = transition_artifact_publish(
        publishing,
        ArtifactPublishEvent.UPLOAD_ACCEPTED,
        occurred_at=12.0,
    )
    published = transition_artifact_publish(
        reconciling,
        ArtifactPublishEvent.PUBLISH_CONFIRMED,
        occurred_at=13.0,
        indexed_relative_path="VR_A/202601/260101/VR_A_260101_000000.vital",
        indexed_size_bytes=10,
    )

    assert requested.publish_state is ArtifactPublishState.REQUESTED
    assert publishing.publish_state is ArtifactPublishState.PUBLISHING
    assert reconciling.publish_state is ArtifactPublishState.RECONCILING
    assert published.publish_state is ArtifactPublishState.PUBLISHED
    assert published.publish_attempt_id == "attempt-a"


def test_failed_publish_requires_explicit_retry_request(tmp_path: Path) -> None:
    requested = transition_artifact_publish(
        RecoveryArtifactRecord(receipt=_receipt(tmp_path)),
        ArtifactPublishEvent.REQUEST,
        occurred_at=10.0,
        attempt_id="attempt-a",
    )
    failed = transition_artifact_publish(
        requested,
        ArtifactPublishEvent.FAIL,
        occurred_at=11.0,
        failure=ArtifactPublishFailure(
            stage="libraryRead",
            code="libraryUnavailable",
            message="unavailable",
            failed_at=11.0,
        ),
    )

    with pytest.raises(ArtifactPublishTransitionError):
        transition_artifact_publish(
            failed,
            ArtifactPublishEvent.START_UPLOAD,
            occurred_at=12.0,
        )

    retried = transition_artifact_publish(
        failed,
        ArtifactPublishEvent.REQUEST,
        occurred_at=13.0,
        attempt_id="attempt-b",
    )
    assert retried.publish_state is ArtifactPublishState.REQUESTED
    assert retried.publish_attempt_id == "attempt-b"
    assert retried.failure is None


def test_published_artifact_cannot_be_requested_again(tmp_path: Path) -> None:
    record = RecoveryArtifactRecord(
        receipt=_receipt(tmp_path),
        publish_state=ArtifactPublishState.PUBLISHED,
        publish_attempt_id="attempt-a",
        published_at=10.0,
        indexed_relative_path="VR_A/file.vital",
        indexed_size_bytes=10,
    )

    with pytest.raises(ArtifactPublishTransitionError):
        transition_artifact_publish(
            record,
            ArtifactPublishEvent.REQUEST,
            occurred_at=11.0,
            attempt_id="attempt-b",
        )


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
