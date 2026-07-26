from __future__ import annotations

from tirosh_guest_tools.domain.recorder_vital_files import (
    native_uploads_for_recorder,
    recovery_artifacts_for_recorder,
)


def test_resolves_bed_upload_to_the_only_active_recorder_assignment() -> None:
    result = native_uploads_for_recorder(
        "VR-001",
        uploads=[native_upload()],
        relationships=relationships(
            assignments=[
                assignment(
                    assignment_id="assignment-1",
                    vrcode="VR-001",
                    started_at="2026-07-23T09:00:00+00:00",
                    ended_at=None,
                )
            ]
        ),
    )

    assert result["state"] == "loaded"
    assert len(result["files"]) == 1
    assert result["files"][0]["vrcode"] == "VR-001"
    assert result["files"][0]["attribution"] == {
        "state": "bedAssignmentResolved",
        "assignmentID": "assignment-1",
        "resolvedAt": "2026-07-23T10:00:00.000Z",
        "readError": None,
    }


def test_does_not_resolve_upload_from_filename_when_assignment_is_missing() -> None:
    result = native_uploads_for_recorder(
        "VR-001",
        uploads=[native_upload()],
        relationships=relationships(assignments=[]),
    )

    assert result["files"] == []
    assert result["unattributedCount"] == 1


def test_does_not_resolve_ambiguous_bed_name_assignments() -> None:
    result = native_uploads_for_recorder(
        "VR-001",
        uploads=[native_upload()],
        relationships=relationships(
            assignments=[
                assignment(
                    assignment_id="assignment-1",
                    vrcode="VR-001",
                    started_at="2026-07-23T09:00:00+00:00",
                    ended_at=None,
                ),
                assignment(
                    assignment_id="assignment-2",
                    vrcode="VR-002",
                    started_at="2026-07-23T09:30:00+00:00",
                    ended_at=None,
                ),
            ]
        ),
    )

    assert result["files"] == []
    assert result["unattributedCount"] == 1


def test_preserves_explicit_recorder_declaration_without_bed_inference() -> None:
    upload = native_upload()
    upload["declaredVrcode"] = "VR-001"

    result = native_uploads_for_recorder(
        "VR-001",
        uploads=[upload],
        relationships={
            "state": "readFailed",
            "assignments": [],
            "events": [],
            "readError": "relationship repository failed",
        },
    )

    assert len(result["files"]) == 1
    assert result["files"][0]["attribution"]["state"] == "recorderDeclared"
    assert result["files"][0]["attribution"]["assignmentID"] is None


def test_preserves_relationship_read_failure_as_partial_read() -> None:
    result = native_uploads_for_recorder(
        "VR-001",
        uploads=[native_upload()],
        relationships={
            "state": "readFailed",
            "assignments": [],
            "events": [],
            "readError": "relationship repository failed",
        },
    )

    assert result["state"] == "partiallyLoaded"
    assert result["files"] == []
    assert result["unattributedCount"] == 1
    assert result["readError"] == "relationship repository failed"


def test_recovery_artifact_uses_explicit_receipt_recorder_identity() -> None:
    result = recovery_artifacts_for_recorder(
        "VR-001",
        artifacts=[
            {
                "exportState": "exported",
                "publishState": "published",
                "publishAttemptId": "publish-1",
                "publishRequestedAt": 1,
                "publishStartedAt": 2,
                "uploadAcceptedAt": 3,
                "publishedAt": 4,
                "indexedRelativePath": "OR-01/2026-07/file.vital",
                "indexedSizeBytes": 100,
                "failure": None,
                "receipt": {
                    "artifactId": "artifact-1",
                    "origin": "coldPathRecovery",
                    "producer": "recorder-recovery",
                    "writerVersion": "1",
                    "vrcode": "VR-001",
                    "roomNames": ["OR-01"],
                    "sourceArchiveId": "archive-1",
                    "sourceStartOffset": 0,
                    "sourceEndOffset": 100,
                    "coverageStartedAt": 1,
                    "coverageEndedAt": 2,
                    "formatVersion": 3,
                    "sha256": "a" * 64,
                    "filename": "OR-01_260723_100000.vital",
                    "sizeBytes": 100,
                    "createdAt": 3,
                    "trackCount": 4,
                },
            }
        ],
    )

    assert result["state"] == "loaded"
    assert result["files"] == [
        {
            "fileID": "artifact-1",
            "origin": "coldPathRecovery",
            "vrcode": "VR-001",
            "bedName": "OR-01",
            "filename": "OR-01_260723_100000.vital",
            "sizeBytes": 100,
            "status": "published",
            "receivedAt": "1970-01-01T00:00:03+00:00",
            "recordingStartedAt": "1970-01-01T00:00:01+00:00",
            "recordingEndedAt": "1970-01-01T00:00:02+00:00",
            "uploadedAt": "1970-01-01T00:00:04+00:00",
            "attribution": {
                "state": "recoveryReceipt",
                "assignmentID": None,
                "resolvedAt": "1970-01-01T00:00:03+00:00",
                "readError": None,
            },
            "failure": None,
        }
    ]


def native_upload() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "origin": "nativeRecorderUpload",
        "uploadId": "upload-001",
        "bedName": "OR-01",
        "declaredVrcode": None,
        "filename": "OR-01_260723_100000.vital",
        "declaredSizeBytes": 20_971_520,
        "state": "indexed",
        "receivedAt": "2026-07-23T10:00:00.000Z",
        "upstreamAcceptedAt": "2026-07-23T10:00:02.000Z",
        "indexedAt": "2026-07-23T10:00:03.000Z",
        "reconciliationAttempts": 1,
        "lastReconciliationAt": "2026-07-23T10:00:03.000Z",
        "indexEvidence": {
            "filename": "OR-01_260723_100000.vital",
            "sizeBytes": 20_971_520,
            "recordingStartedAt": 1,
            "recordingEndedAt": 2,
            "uploadedAt": 3,
        },
        "failure": None,
    }


def relationships(
    *,
    assignments: list[dict[str, object]],
) -> dict[str, object]:
    return {
        "state": "loaded",
        "assignments": assignments,
        "events": [],
        "readError": None,
    }


def assignment(
    *,
    assignment_id: str,
    vrcode: str,
    started_at: str,
    ended_at: str | None,
) -> dict[str, object]:
    return {
        "assignmentID": assignment_id,
        "bedID": "bed-01",
        "bedName": "OR-01",
        "vrcode": vrcode,
        "startedAt": started_at,
        "endedAt": ended_at,
        "lastSeenAt": "2026-07-23T10:00:00+00:00",
        "lastObservedAt": "2026-07-23T10:00:00+00:00",
        "status": "online",
        "patientConnected": True,
        "observationCount": 1,
    }
