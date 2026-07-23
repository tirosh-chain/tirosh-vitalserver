from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import UTC, datetime
from typing import Any, NotRequired, TypedDict


class RecorderVitalFileProjectionError(ValueError):
    pass


class RecorderVitalFileProjection(TypedDict):
    state: str
    vrcode: str
    files: list[dict[str, object]]
    readError: str | None
    unattributedCount: NotRequired[int]


def native_uploads_for_recorder(
    vrcode: str,
    *,
    uploads: Sequence[Mapping[str, object]],
    relationships: Mapping[str, object],
) -> RecorderVitalFileProjection:
    if not isinstance(vrcode, str) or not vrcode:
        raise RecorderVitalFileProjectionError("Recorder vrcode is invalid.")
    relationship_state = _required_string(relationships, "state")
    if relationship_state not in {"loaded", "partiallyLoaded", "readFailed"}:
        raise RecorderVitalFileProjectionError(
            "Relationship read state is invalid."
        )
    relationship_error = _optional_string(relationships, "readError")
    assignments = _required_list(relationships, "assignments")
    if any(not isinstance(item, Mapping) for item in assignments):
        raise RecorderVitalFileProjectionError(
            "Relationship assignment item is invalid."
        )

    files: list[dict[str, object]] = []
    unattributed_count = 0
    for item in uploads:
        upload = _validated_native_upload(item)
        attribution = _attribute_upload(
            upload,
            assignments=assignments,
            relationship_state=relationship_state,
            relationship_error=relationship_error,
        )
        attributed_vrcode = attribution["vrcode"]
        if attributed_vrcode is None:
            unattributed_count += 1
            continue
        if attributed_vrcode != vrcode:
            continue
        files.append(_native_file_document(upload, attribution))

    files.sort(
        key=lambda item: (
            str(item["receivedAt"]),
            str(item["fileID"]),
        ),
        reverse=True,
    )
    state = (
        "loaded"
        if relationship_state == "loaded"
        else "partiallyLoaded"
    )
    return {
        "state": state,
        "vrcode": vrcode,
        "files": files,
        "unattributedCount": unattributed_count,
        "readError": relationship_error,
    }


def recovery_artifacts_for_recorder(
    vrcode: str,
    *,
    artifacts: Sequence[Mapping[str, object]],
) -> RecorderVitalFileProjection:
    if not isinstance(vrcode, str) or not vrcode:
        raise RecorderVitalFileProjectionError("Recorder vrcode is invalid.")
    files: list[dict[str, object]] = []
    for artifact in artifacts:
        receipt_value = artifact.get("receipt")
        if not isinstance(receipt_value, Mapping):
            raise RecorderVitalFileProjectionError(
                "Recovery artifact receipt is invalid."
            )
        receipt = receipt_value
        if receipt.get("origin") != "coldPathRecovery":
            continue
        artifact_vrcode = _required_string(receipt, "vrcode")
        if artifact_vrcode != vrcode:
            continue
        room_names = receipt.get("roomNames")
        if not isinstance(room_names, list) or any(
            not isinstance(value, str) or not value
            for value in room_names
        ):
            raise RecorderVitalFileProjectionError(
                "Recovery artifact roomNames is invalid."
            )
        size = receipt.get("sizeBytes")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise RecorderVitalFileProjectionError(
                "Recovery artifact sizeBytes is invalid."
            )
        failure = artifact.get("failure")
        if failure is not None and not isinstance(failure, Mapping):
            raise RecorderVitalFileProjectionError(
                "Recovery artifact failure is invalid."
            )
        created_at = _timestamp_value(
            _required_number(receipt, "createdAt"),
            "receipt.createdAt",
        )
        files.append(
            {
                "fileID": _required_string(receipt, "artifactId"),
                "origin": "coldPathRecovery",
                "vrcode": artifact_vrcode,
                "bedName": room_names[0] if room_names else None,
                "filename": _required_string(receipt, "filename"),
                "sizeBytes": size,
                "status": _required_string(artifact, "publishState"),
                "receivedAt": created_at,
                "recordingStartedAt": _timestamp_value(
                    _required_number(receipt, "coverageStartedAt"),
                    "receipt.coverageStartedAt",
                ),
                "recordingEndedAt": _timestamp_value(
                    _required_number(receipt, "coverageEndedAt"),
                    "receipt.coverageEndedAt",
                ),
                "uploadedAt": _optional_timestamp_value(
                    artifact.get("publishedAt"),
                    "artifact.publishedAt",
                ),
                "attribution": {
                    "state": "recoveryReceipt",
                    "assignmentID": None,
                    "resolvedAt": created_at,
                    "readError": None,
                },
                "failure": (
                    _normalized_failure(failure, timestamp_field="failedAt")
                    if failure is not None
                    else None
                ),
            }
        )
    files.sort(
        key=lambda item: (str(item["receivedAt"]), str(item["fileID"])),
        reverse=True,
    )
    return {
        "state": "loaded",
        "vrcode": vrcode,
        "files": files,
        "readError": None,
    }


def _attribute_upload(
    upload: Mapping[str, object],
    *,
    assignments: Sequence[Mapping[str, object]],
    relationship_state: str,
    relationship_error: str | None,
) -> dict[str, object]:
    declared_vrcode = _optional_string(upload, "declaredVrcode")
    received_at = _required_string(upload, "receivedAt")
    if declared_vrcode is not None:
        return {
            "state": "recorderDeclared",
            "vrcode": declared_vrcode,
            "assignmentID": None,
            "resolvedAt": received_at,
            "readError": None,
        }
    if relationship_state != "loaded":
        return {
            "state": "relationshipReadFailed",
            "vrcode": None,
            "assignmentID": None,
            "resolvedAt": received_at,
            "readError": relationship_error,
        }

    bed_name = _required_string(upload, "bedName")
    instant = _parse_timestamp(received_at, "receivedAt")
    candidates = [
        assignment
        for assignment in assignments
        if _assignment_covers(
            assignment,
            bed_name=bed_name,
            instant=instant,
        )
    ]
    identities = {
        _required_string(assignment, "vrcode")
        for assignment in candidates
    }
    if len(candidates) == 1 and len(identities) == 1:
        assignment = candidates[0]
        return {
            "state": "bedAssignmentResolved",
            "vrcode": next(iter(identities)),
            "assignmentID": _required_string(assignment, "assignmentID"),
            "resolvedAt": received_at,
            "readError": None,
        }
    return {
        "state": "ambiguous" if len(identities) > 1 else "unresolved",
        "vrcode": None,
        "assignmentID": None,
        "resolvedAt": received_at,
        "readError": None,
    }


def _assignment_covers(
    assignment: Mapping[str, object],
    *,
    bed_name: str,
    instant: datetime,
) -> bool:
    if _optional_string(assignment, "bedName") != bed_name:
        return False
    started_at = _parse_timestamp(
        _required_string(assignment, "startedAt"),
        "assignment.startedAt",
    )
    ended_value = _optional_string(assignment, "endedAt")
    ended_at = (
        _parse_timestamp(ended_value, "assignment.endedAt")
        if ended_value is not None
        else None
    )
    return started_at <= instant and (ended_at is None or instant < ended_at)


def _validated_native_upload(
    value: Mapping[str, object],
) -> dict[str, object]:
    if value.get("schemaVersion") != 1:
        raise RecorderVitalFileProjectionError(
            "Native upload schemaVersion is invalid."
        )
    if value.get("origin") != "nativeRecorderUpload":
        raise RecorderVitalFileProjectionError(
            "Native upload origin is invalid."
        )
    for field in ("uploadId", "bedName", "filename", "state", "receivedAt"):
        _required_string(value, field)
    declared_vrcode = value.get("declaredVrcode")
    if declared_vrcode is not None:
        _required_string(value, "declaredVrcode")
    size = value.get("declaredSizeBytes")
    if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
        raise RecorderVitalFileProjectionError(
            "Native upload declaredSizeBytes is invalid."
        )
    _parse_timestamp(_required_string(value, "receivedAt"), "receivedAt")
    return dict(value)


def _native_file_document(
    upload: Mapping[str, object],
    attribution: Mapping[str, object],
) -> dict[str, object]:
    index_evidence = upload.get("indexEvidence")
    if index_evidence is not None and not isinstance(index_evidence, Mapping):
        raise RecorderVitalFileProjectionError(
            "Native upload indexEvidence is invalid."
        )
    failure = upload.get("failure")
    if failure is not None and not isinstance(failure, Mapping):
        raise RecorderVitalFileProjectionError(
            "Native upload failure is invalid."
        )
    return {
        "fileID": _required_string(upload, "uploadId"),
        "origin": "nativeRecorderUpload",
        "vrcode": attribution["vrcode"],
        "bedName": _required_string(upload, "bedName"),
        "filename": _required_string(upload, "filename"),
        "sizeBytes": upload["declaredSizeBytes"],
        "status": _required_string(upload, "state"),
        "receivedAt": _required_string(upload, "receivedAt"),
        "recordingStartedAt": (
            _optional_timestamp_value(
                index_evidence.get("recordingStartedAt"),
                "indexEvidence.recordingStartedAt",
            )
            if index_evidence is not None
            else None
        ),
        "recordingEndedAt": (
            _optional_timestamp_value(
                index_evidence.get("recordingEndedAt"),
                "indexEvidence.recordingEndedAt",
            )
            if index_evidence is not None
            else None
        ),
        "uploadedAt": (
            _optional_timestamp_value(
                index_evidence.get("uploadedAt"),
                "indexEvidence.uploadedAt",
            )
            if index_evidence is not None
            else None
        ),
        "attribution": {
            "state": attribution["state"],
            "assignmentID": attribution["assignmentID"],
            "resolvedAt": attribution["resolvedAt"],
            "readError": attribution["readError"],
        },
        "failure": (
            _normalized_failure(failure, timestamp_field="occurredAt")
            if failure is not None
            else None
        ),
    }


def _parse_timestamp(value: str, field: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise RecorderVitalFileProjectionError(
            f"{field} timestamp is invalid."
        ) from error
    if parsed.tzinfo is None:
        raise RecorderVitalFileProjectionError(
            f"{field} timestamp lacks timezone."
        )
    return parsed


def _required_list(
    document: Mapping[str, object],
    field: str,
) -> list[Any]:
    value = document.get(field)
    if not isinstance(value, list):
        raise RecorderVitalFileProjectionError(f"{field} must be a list.")
    return value


def _required_string(
    document: Mapping[str, object],
    field: str,
) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not value:
        raise RecorderVitalFileProjectionError(
            f"{field} must be a non-empty string."
        )
    return value


def _optional_string(
    document: Mapping[str, object],
    field: str,
) -> str | None:
    value = document.get(field)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise RecorderVitalFileProjectionError(
            f"{field} must be null or a non-empty string."
        )
    return value


def _required_number(
    document: Mapping[str, object],
    field: str,
) -> int | float:
    value = document.get(field)
    if (
        not isinstance(value, (int, float))
        or isinstance(value, bool)
    ):
        raise RecorderVitalFileProjectionError(
            f"{field} must be a number."
        )
    return value


def _optional_number(
    document: Mapping[str, object],
    field: str,
) -> int | float | None:
    value = document.get(field)
    if value is None:
        return None
    return _required_number(document, field)


def _timestamp_value(value: object, field: str) -> str:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return datetime.fromtimestamp(float(value), tz=UTC).isoformat()
    if isinstance(value, str):
        return _parse_timestamp(value, field).isoformat()
    raise RecorderVitalFileProjectionError(f"{field} timestamp is invalid.")


def _optional_timestamp_value(value: object, field: str) -> str | None:
    if value is None:
        return None
    return _timestamp_value(value, field)


def _normalized_failure(
    failure: Mapping[str, object],
    *,
    timestamp_field: str,
) -> dict[str, object]:
    return {
        "stage": _required_string(failure, "stage"),
        "code": _required_string(failure, "code"),
        "message": _required_string(failure, "message"),
        "failedAt": _timestamp_value(
            failure.get(timestamp_field),
            f"failure.{timestamp_field}",
        ),
    }
