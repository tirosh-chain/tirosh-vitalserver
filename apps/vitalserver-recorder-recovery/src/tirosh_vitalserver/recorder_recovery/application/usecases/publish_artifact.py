"""Workflow for explicitly publishing one registered recovery artifact."""

from __future__ import annotations

import time
from collections.abc import Callable
from uuid import uuid4

from tirosh_vitalserver.recorder_recovery.application.ports import (
    ArtifactPublishDependencyError,
    ArtifactPublisherPort,
    RecoveryArtifactRegistryPort,
)
from tirosh_vitalserver.recorder_recovery.domain import (
    ArtifactPublishEvent,
    ArtifactPublishFailure,
    ArtifactPublishState,
    RecoveryArtifactRecord,
    recovery_artifact_receipt_to_document,
    transition_artifact_publish,
)


class RecoveryArtifactNotFound(LookupError):
    pass


def publish_recovery_artifact(
    artifact_id: str,
    *,
    registry: RecoveryArtifactRegistryPort,
    publisher: ArtifactPublisherPort,
    clock: Callable[[], float] = time.time,
    attempt_id_factory: Callable[[], str] = lambda: str(uuid4()),
) -> RecoveryArtifactRecord:
    record = registry.get_record(artifact_id)
    if record is None:
        raise RecoveryArtifactNotFound(
            f"recovery artifact not found artifactId={artifact_id}"
        )
    if record.publish_state is ArtifactPublishState.PUBLISHED:
        return record
    if record.publish_state in {
        ArtifactPublishState.PUBLISHING,
        ArtifactPublishState.RECONCILING,
    }:
        return _reconcile(record, registry=registry, publisher=publisher, clock=clock)
    if record.publish_state in {
        ArtifactPublishState.NOT_REQUESTED,
        ArtifactPublishState.FAILED,
    }:
        record = transition_artifact_publish(
            record,
            ArtifactPublishEvent.REQUEST,
            occurred_at=clock(),
            attempt_id=attempt_id_factory(),
        )
        registry.save_publish(record)

    try:
        collision = publisher.find_indexed(record.receipt.filename)
    except ArtifactPublishDependencyError as error:
        return _fail(record, error, registry=registry, clock=clock)
    if collision is not None:
        return _fail(
            record,
            ArtifactPublishDependencyError(
                stage="collisionCheck",
                code="filenameCollision",
                message=(
                    "VitalServer already indexes the artifact filename: "
                    f"{record.receipt.filename}"
                ),
            ),
            registry=registry,
            clock=clock,
        )

    record = transition_artifact_publish(
        record,
        ArtifactPublishEvent.START_UPLOAD,
        occurred_at=clock(),
    )
    registry.save_publish(record)
    try:
        publisher.upload(record.receipt)
    except ArtifactPublishDependencyError as error:
        return _fail(record, error, registry=registry, clock=clock)
    record = transition_artifact_publish(
        record,
        ArtifactPublishEvent.UPLOAD_ACCEPTED,
        occurred_at=clock(),
    )
    registry.save_publish(record)
    return _reconcile(record, registry=registry, publisher=publisher, clock=clock)


def _reconcile(
    record: RecoveryArtifactRecord,
    *,
    registry: RecoveryArtifactRegistryPort,
    publisher: ArtifactPublisherPort,
    clock: Callable[[], float],
) -> RecoveryArtifactRecord:
    try:
        indexed = publisher.wait_until_indexed(
            record.receipt.filename,
            size_bytes=record.receipt.size_bytes,
        )
    except ArtifactPublishDependencyError as error:
        return _fail(record, error, registry=registry, clock=clock)
    if indexed is None:
        return _fail(
            record,
            ArtifactPublishDependencyError(
                stage="indexVerification",
                code="indexNotConfirmed",
                message=(
                    "VitalServer did not index the accepted artifact before the "
                    f"verification deadline: {record.receipt.filename}"
                ),
            ),
            registry=registry,
            clock=clock,
        )
    record = transition_artifact_publish(
        record,
        ArtifactPublishEvent.PUBLISH_CONFIRMED,
        occurred_at=clock(),
        indexed_relative_path=indexed.relative_path,
        indexed_size_bytes=indexed.size_bytes,
    )
    registry.save_publish(record)
    return record


def _fail(
    record: RecoveryArtifactRecord,
    error: ArtifactPublishDependencyError,
    *,
    registry: RecoveryArtifactRegistryPort,
    clock: Callable[[], float],
) -> RecoveryArtifactRecord:
    failed_at = clock()
    failed = transition_artifact_publish(
        record,
        ArtifactPublishEvent.FAIL,
        occurred_at=failed_at,
        failure=ArtifactPublishFailure(
            stage=error.stage,
            code=error.code,
            message=error.message,
            failed_at=failed_at,
        ),
    )
    registry.save_publish(failed)
    return failed


def recovery_artifact_record_to_document(
    record: RecoveryArtifactRecord,
) -> dict[str, object]:
    failure = record.failure
    return {
        "exportState": "exported",
        "publishState": record.publish_state.value,
        "publishAttemptId": record.publish_attempt_id,
        "publishRequestedAt": record.publish_requested_at,
        "publishStartedAt": record.publish_started_at,
        "uploadAcceptedAt": record.upload_accepted_at,
        "publishedAt": record.published_at,
        "indexedRelativePath": record.indexed_relative_path,
        "indexedSizeBytes": record.indexed_size_bytes,
        "failure": (
            None
            if failure is None
            else {
                "stage": failure.stage,
                "code": failure.code,
                "message": failure.message,
                "failedAt": failure.failed_at,
            }
        ),
        "receipt": recovery_artifact_receipt_to_document(record.receipt),
    }
