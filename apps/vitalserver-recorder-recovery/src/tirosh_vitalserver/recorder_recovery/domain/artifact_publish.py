"""Pure state transitions for publishing one recovery artifact."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from .recovery_artifact import RecoveryArtifactReceipt


class ArtifactPublishState(StrEnum):
    NOT_REQUESTED = "notRequested"
    REQUESTED = "publishRequested"
    PUBLISHING = "publishing"
    RECONCILING = "reconciling"
    PUBLISHED = "published"
    FAILED = "failed"


class ArtifactPublishEvent(StrEnum):
    REQUEST = "request"
    START_UPLOAD = "startUpload"
    UPLOAD_ACCEPTED = "uploadAccepted"
    PUBLISH_CONFIRMED = "publishConfirmed"
    FAIL = "fail"


class ArtifactPublishTransitionError(ValueError):
    """The requested publish event is invalid for the persisted state."""


@dataclass(frozen=True, slots=True)
class ArtifactPublishFailure:
    stage: str
    code: str
    message: str
    failed_at: float


@dataclass(frozen=True, slots=True)
class RecoveryArtifactRecord:
    receipt: RecoveryArtifactReceipt
    publish_state: ArtifactPublishState = ArtifactPublishState.NOT_REQUESTED
    publish_attempt_id: str | None = None
    publish_requested_at: float | None = None
    publish_started_at: float | None = None
    upload_accepted_at: float | None = None
    published_at: float | None = None
    indexed_relative_path: str | None = None
    indexed_size_bytes: int | None = None
    failure: ArtifactPublishFailure | None = None


def transition_artifact_publish(
    record: RecoveryArtifactRecord,
    event: ArtifactPublishEvent,
    *,
    occurred_at: float,
    attempt_id: str | None = None,
    failure: ArtifactPublishFailure | None = None,
    indexed_relative_path: str | None = None,
    indexed_size_bytes: int | None = None,
) -> RecoveryArtifactRecord:
    """Return the next explicit state without performing side effects."""

    if event is ArtifactPublishEvent.REQUEST:
        if record.publish_state not in {
            ArtifactPublishState.NOT_REQUESTED,
            ArtifactPublishState.FAILED,
        }:
            raise _invalid(record, event)
        if not attempt_id:
            raise ArtifactPublishTransitionError("publish request requires attempt_id")
        return replace(
            record,
            publish_state=ArtifactPublishState.REQUESTED,
            publish_attempt_id=attempt_id,
            publish_requested_at=occurred_at,
            publish_started_at=None,
            upload_accepted_at=None,
            published_at=None,
            indexed_relative_path=None,
            indexed_size_bytes=None,
            failure=None,
        )
    if event is ArtifactPublishEvent.START_UPLOAD:
        if record.publish_state is not ArtifactPublishState.REQUESTED:
            raise _invalid(record, event)
        return replace(
            record,
            publish_state=ArtifactPublishState.PUBLISHING,
            publish_started_at=occurred_at,
        )
    if event is ArtifactPublishEvent.UPLOAD_ACCEPTED:
        if record.publish_state is not ArtifactPublishState.PUBLISHING:
            raise _invalid(record, event)
        return replace(
            record,
            publish_state=ArtifactPublishState.RECONCILING,
            upload_accepted_at=occurred_at,
        )
    if event is ArtifactPublishEvent.PUBLISH_CONFIRMED:
        if record.publish_state not in {
            ArtifactPublishState.PUBLISHING,
            ArtifactPublishState.RECONCILING,
        }:
            raise _invalid(record, event)
        if not indexed_relative_path or indexed_size_bytes is None:
            raise ArtifactPublishTransitionError(
                "publish confirmation requires indexed artifact evidence"
            )
        return replace(
            record,
            publish_state=ArtifactPublishState.PUBLISHED,
            published_at=occurred_at,
            indexed_relative_path=indexed_relative_path,
            indexed_size_bytes=indexed_size_bytes,
            failure=None,
        )
    if event is ArtifactPublishEvent.FAIL:
        if record.publish_state not in {
            ArtifactPublishState.REQUESTED,
            ArtifactPublishState.PUBLISHING,
            ArtifactPublishState.RECONCILING,
        }:
            raise _invalid(record, event)
        if failure is None:
            raise ArtifactPublishTransitionError("publish failure requires evidence")
        return replace(
            record,
            publish_state=ArtifactPublishState.FAILED,
            failure=failure,
        )
    raise ArtifactPublishTransitionError(f"unsupported publish event: {event}")


def _invalid(
    record: RecoveryArtifactRecord,
    event: ArtifactPublishEvent,
) -> ArtifactPublishTransitionError:
    return ArtifactPublishTransitionError(
        "invalid artifact publish transition: "
        f"state={record.publish_state.value} event={event.value}"
    )
