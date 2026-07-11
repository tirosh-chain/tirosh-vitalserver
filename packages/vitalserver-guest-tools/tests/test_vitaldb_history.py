from __future__ import annotations

from tirosh_guest_tools.domain.vitaldb_history import (
    attach_recorder_ingress_status,
    bed_history_from_recorder_history,
    project_vitaldb_history,
)


def test_projects_cumulative_recorder_and_bed_history_from_explicit_snapshots() -> None:
    history = project_vitaldb_history(
        [
            observation(
                observed_at="2026-07-01T00:00:00Z",
                recorders=[recorder("VR-OLD", "2026-07-01T00:00:00Z")],
                beds=[bed("bed-old", "VR-OLD", "2026-07-01T00:00:00Z")],
            ),
            observation(
                observed_at="2026-07-01T00:01:00Z",
                recorders=[
                    recorder("VR-NEW", "2026-07-01T00:01:00Z"),
                    recorder("VR-NEW", "2026-07-01T00:00:59Z"),
                ],
                beds=[bed("bed-new", "VR-NEW", "2026-07-01T00:01:00Z")],
                anomalies=[
                    {
                        "id": "anomaly-1",
                        "kind": "duplicateRecorder",
                        "severity": "warning",
                        "observedAt": "2026-07-01T00:01:00Z",
                        "subject": "VR-NEW",
                        "message": "duplicate",
                    }
                ],
            ),
        ],
        recorder_visibility={"VR-OLD": "hidden"},
        bed_visibility={},
    )

    assert history["state"] == "loaded"
    assert history["updatedAt"] == "2026-07-01T00:01:00Z"
    assert history["summary"] == {
        "knownRecorders": 2,
        "currentRecorders": 1,
        "onlineRecorders": 1,
        "staleRecorders": 0,
        "recorderAnomalies": 1,
        "knownBeds": 2,
        "onlineBeds": 1,
        "staleBeds": 0,
        "bedAssignments": 1,
        "bedAnomalies": 0,
    }
    by_vrcode = {record["vrcode"]: record for record in history["recorders"]}
    assert by_vrcode["VR-OLD"]["status"] == "notObserved"
    assert by_vrcode["VR-OLD"]["visibility"] == "hidden"
    assert by_vrcode["VR-NEW"]["duplicateObservationCount"] == 1
    assert by_vrcode["VR-NEW"]["currentAnomalyCount"] == 1


def test_projects_activity_and_excludes_explicitly_deleted_entities() -> None:
    document = observation(
        observed_at="2026-07-01T00:01:00Z",
        recorders=[recorder("VR-1", "2026-07-01T00:01:00Z")],
        beds=[bed("bed-1", "VR-1", "2026-07-01T00:01:00Z")],
    )
    document["activityBuckets"] = [
        {
            "vrcode": "VR-1",
            "bucketStartedAt": "2026-07-01T00:00:00Z",
            "bucketSeconds": 60,
            "messageCount": 120,
            "byteCount": 600,
            "roomCount": 2,
            "firstObservedAt": "2026-07-01T00:00:01Z",
            "lastObservedAt": "2026-07-01T00:00:59Z",
        }
    ]

    loaded = project_vitaldb_history(
        [document], recorder_visibility={}, bed_visibility={}
    )
    assert loaded["activityHistory"]["bucketCount"] == 1
    assert loaded["recorders"][0]["activityTimeline"][0]["messagesPerSecond"] == 2

    deleted = project_vitaldb_history(
        [document],
        recorder_visibility={"VR-1": "deleted"},
        bed_visibility={"bed-1": "deleted"},
    )
    assert deleted["recorders"] == []
    assert deleted["beds"] == []


def test_attaches_explicit_recorder_ingress_read_without_inventing_success() -> None:
    history = project_vitaldb_history(
        [
            observation(
                observed_at="2026-07-01T00:00:00Z",
                recorders=[recorder("VR-1", "2026-07-01T00:00:00Z")],
                beds=[],
            )
        ],
        recorder_visibility={},
        bed_visibility={},
    )
    failed_read = {
        "readState": "readFailed",
        "httpStatus": "failed",
        "document": None,
        "readError": "ingress denied",
    }

    enriched = attach_recorder_ingress_status(history, failed_read)

    assert enriched["recorderIngressStatusRead"] == failed_read
    assert enriched["recorders"][0]["redisIPSync"]["status"] == "unavailable"
    assert enriched["recorders"][0]["redisIPSync"]["lastFailure"] == "ingress denied"


def test_bed_history_is_an_explicit_view_of_runtime_owned_history() -> None:
    history = project_vitaldb_history(
        [
            observation(
                observed_at="2026-07-01T00:00:00Z",
                recorders=[],
                beds=[bed("bed-1", None, "2026-07-01T00:00:00Z")],
            )
        ],
        recorder_visibility={},
        bed_visibility={},
    )

    beds = bed_history_from_recorder_history(history)

    assert beds["state"] == "loaded"
    assert beds["updatedAt"] == "2026-07-01T00:00:00Z"
    assert beds["summary"]["knownBeds"] == 1


def observation(
    *,
    observed_at: str,
    recorders: list[dict[str, object]],
    beds: list[dict[str, object]],
    anomalies: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "source": "test",
        "observedAt": observed_at,
        "ready": True,
        "recorderOnlineThresholdSeconds": 60,
        "recorders": recorders,
        "beds": beds,
        "devices": [],
        "filters": [],
        "proxyConnections": [],
        "anomalies": anomalies or [],
        "readIssues": [],
        "activityBuckets": [],
    }


def recorder(vrcode: str, last_seen_at: str) -> dict[str, object]:
    return {
        "vrcode": vrcode,
        "ip": "10.0.0.2",
        "lastSeenAt": last_seen_at,
        "version": "1.0",
        "info": None,
        "config": None,
        "online": True,
        "stale": False,
    }


def bed(bed_id: str, vrcode: str | None, last_seen_at: str) -> dict[str, object]:
    return {
        "bedID": bed_id,
        "name": bed_id,
        "vrcode": vrcode,
        "lastSeenAt": last_seen_at,
        "patientConnected": True,
        "online": True,
    }
