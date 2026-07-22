from __future__ import annotations

import pytest

from tirosh_guest_tools.domain.vitaldb_relationships import (
    VitalDBRelationshipProjectionError,
    relationship_history_from_observation,
)


def test_relationship_history_projects_current_bed_recorder_assignments() -> None:
    history = relationship_history_from_observation(
        {
            "observedAt": "2026-07-01T00:00:00+00:00",
            "recorders": [
                {
                    "vrcode": "VR-001",
                    "online": True,
                    "stale": False,
                },
                {
                    "vrcode": "VR-STALE",
                    "online": False,
                    "stale": True,
                },
            ],
            "beds": [
                {
                    "bedID": "bed-a",
                    "name": "OR-A",
                    "vrcode": "VR-001",
                    "lastSeenAt": "2026-07-01T00:00:00+00:00",
                    "patientConnected": True,
                    "online": True,
                },
                {
                    "bedID": "bed-b",
                    "name": "OR-B",
                    "vrcode": "VR-STALE",
                    "lastSeenAt": "2026-07-01T00:00:00+00:00",
                    "patientConnected": False,
                    "online": True,
                },
                {
                    "bedID": "bed-c",
                    "name": "OR-C",
                    "vrcode": None,
                    "lastSeenAt": None,
                    "patientConnected": None,
                    "online": False,
                },
            ],
            "readIssues": [],
        }
    )

    assert history["state"] == "loaded"
    assert history["assignments"] == [
        {
            "assignmentID": (
                "assignment:bed-a:VR-001:2026-07-01T00:00:00+00:00"
            ),
            "bedID": "bed-a",
            "bedName": "OR-A",
            "vrcode": "VR-001",
            "startedAt": "2026-07-01T00:00:00+00:00",
            "endedAt": None,
            "lastSeenAt": "2026-07-01T00:00:00+00:00",
            "lastObservedAt": "2026-07-01T00:00:00+00:00",
            "status": "online",
            "patientConnected": True,
            "observationCount": 1,
        },
        {
            "assignmentID": (
                "assignment:bed-b:VR-STALE:2026-07-01T00:00:00+00:00"
            ),
            "bedID": "bed-b",
            "bedName": "OR-B",
            "vrcode": "VR-STALE",
            "startedAt": "2026-07-01T00:00:00+00:00",
            "endedAt": None,
            "lastSeenAt": "2026-07-01T00:00:00+00:00",
            "lastObservedAt": "2026-07-01T00:00:00+00:00",
            "status": "stale",
            "patientConnected": False,
            "observationCount": 1,
        },
    ]
    assert {event["eventType"] for event in history["events"]} == {
        "staleLink",
        "unlinkedBed",
    }
    assert history["projectionVersion"] == 2
    assert len(history["activeIssueIDs"]) == 2
    assert history["readError"] is None


def test_relationship_history_preserves_observation_read_issues() -> None:
    history = relationship_history_from_observation(
        {
            "observedAt": "2026-07-01T00:00:00+00:00",
            "recorders": [],
            "beds": [],
            "readIssues": [
                {
                    "source": "vitaldb-observer",
                    "message": "redis timed out",
                }
            ],
        }
    )

    assert history["state"] == "partiallyLoaded"
    assert history["readError"] == "vitaldb-observer=redis timed out"


def test_relationship_history_updates_previous_open_assignment() -> None:
    history = relationship_history_from_observation(
        {
            "observedAt": "2026-07-01T00:01:00+00:00",
            "recorders": [{"vrcode": "VR-001", "online": True, "stale": False}],
            "beds": [
                {
                    "bedID": "bed-a",
                    "name": "OR-A",
                    "vrcode": "VR-001",
                    "lastSeenAt": "2026-07-01T00:01:00+00:00",
                    "patientConnected": False,
                    "online": True,
                }
            ],
            "readIssues": [],
        },
        previous_history={
            "state": "loaded",
            "assignments": [
                {
                    "assignmentID": (
                        "assignment:bed-a:VR-001:2026-07-01T00:00:00+00:00"
                    ),
                    "bedID": "bed-a",
                    "bedName": "OR-A",
                    "vrcode": "VR-001",
                    "startedAt": "2026-07-01T00:00:00+00:00",
                    "endedAt": None,
                    "lastSeenAt": "2026-07-01T00:00:00+00:00",
                    "lastObservedAt": "2026-07-01T00:00:00+00:00",
                    "status": "online",
                    "patientConnected": True,
                    "observationCount": 1,
                }
            ],
            "events": [],
            "readError": None,
        },
    )

    assert history["assignments"] == [
        {
            "assignmentID": "assignment:bed-a:VR-001:2026-07-01T00:00:00+00:00",
            "bedID": "bed-a",
            "bedName": "OR-A",
            "vrcode": "VR-001",
            "startedAt": "2026-07-01T00:00:00+00:00",
            "endedAt": None,
            "lastSeenAt": "2026-07-01T00:01:00+00:00",
            "lastObservedAt": "2026-07-01T00:01:00+00:00",
            "status": "online",
            "patientConnected": False,
            "observationCount": 2,
        }
    ]
    assert history["events"] == []


def test_relationship_history_closes_and_emits_handoff() -> None:
    history = relationship_history_from_observation(
        {
            "observedAt": "2026-07-01T00:05:00+00:00",
            "recorders": [{"vrcode": "VR-002", "online": True, "stale": False}],
            "beds": [
                {
                    "bedID": "bed-a",
                    "name": "OR-A",
                    "vrcode": "VR-002",
                    "lastSeenAt": None,
                    "patientConnected": None,
                    "online": True,
                }
            ],
            "readIssues": [],
        },
        previous_history={
            "state": "loaded",
            "assignments": [
                {
                    "assignmentID": (
                        "assignment:bed-a:VR-001:2026-07-01T00:00:00+00:00"
                    ),
                    "bedID": "bed-a",
                    "bedName": "OR-A",
                    "vrcode": "VR-001",
                    "startedAt": "2026-07-01T00:00:00+00:00",
                    "endedAt": None,
                    "lastSeenAt": "2026-07-01T00:00:00+00:00",
                    "lastObservedAt": "2026-07-01T00:00:00+00:00",
                    "status": "online",
                    "patientConnected": True,
                    "observationCount": 1,
                }
            ],
            "events": [],
            "readError": None,
        },
    )

    assert [assignment["vrcode"] for assignment in history["assignments"]] == [
        "VR-002",
        "VR-001",
    ]
    assert history["assignments"][0]["endedAt"] is None
    assert history["assignments"][1]["endedAt"] == "2026-07-01T00:05:00+00:00"
    assert history["events"] == [
        {
            "eventID": (
                "relationship:handoff:2026-07-01T00:05:00+00:00:"
                "bed-a:VR-002:VR-001"
            ),
            "observedAt": "2026-07-01T00:05:00+00:00",
            "eventType": "handoff",
            "severity": "info",
            "bedID": "bed-a",
            "bedName": "OR-A",
            "vrcode": "VR-002",
            "previousVrcode": "VR-001",
            "previousBedID": None,
            "message": "Bed VRecorder assignment changed.",
        }
    ]


def test_relationship_history_closes_unlinked_bed_assignment() -> None:
    history = relationship_history_from_observation(
        {
            "observedAt": "2026-07-01T00:02:00+00:00",
            "recorders": [{"vrcode": "VR-001", "online": True, "stale": False}],
            "beds": [
                {
                    "bedID": "bed-a",
                    "name": "OR-A",
                    "vrcode": None,
                    "lastSeenAt": None,
                    "patientConnected": None,
                    "online": True,
                }
            ],
            "readIssues": [],
        },
        previous_history={
            "state": "loaded",
            "assignments": [
                {
                    "assignmentID": (
                        "assignment:bed-a:VR-001:2026-07-01T00:00:00+00:00"
                    ),
                    "bedID": "bed-a",
                    "bedName": "OR-A",
                    "vrcode": "VR-001",
                    "startedAt": "2026-07-01T00:00:00+00:00",
                    "endedAt": None,
                    "lastSeenAt": "2026-07-01T00:00:00+00:00",
                    "lastObservedAt": "2026-07-01T00:00:00+00:00",
                    "status": "online",
                    "patientConnected": True,
                    "observationCount": 1,
                }
            ],
            "events": [],
            "readError": None,
        },
    )

    assert history["assignments"][0]["endedAt"] == "2026-07-01T00:02:00+00:00"
    assert history["events"][0]["eventType"] == "unlinkedBed"


def test_relationship_history_projects_relationship_anomalies() -> None:
    history = relationship_history_from_observation(
        {
            "observedAt": "2026-07-01T00:00:00+00:00",
            "recorders": [
                {"vrcode": "VR-DUP", "online": True, "stale": False},
                {"vrcode": "VR-FREE", "online": True, "stale": False},
                {"vrcode": "VR-STALE", "online": False, "stale": True},
            ],
            "beds": [
                {
                    "bedID": "bed-a",
                    "name": "OR-A",
                    "vrcode": "VR-DUP",
                    "lastSeenAt": None,
                    "patientConnected": None,
                    "online": True,
                },
                {
                    "bedID": "bed-b",
                    "name": "OR-B",
                    "vrcode": "VR-DUP",
                    "lastSeenAt": None,
                    "patientConnected": None,
                    "online": True,
                },
                {
                    "bedID": "bed-c",
                    "name": "OR-C",
                    "vrcode": None,
                    "lastSeenAt": None,
                    "patientConnected": None,
                    "online": True,
                },
                {
                    "bedID": "bed-d",
                    "name": "OR-D",
                    "vrcode": "VR-STALE",
                    "lastSeenAt": None,
                    "patientConnected": None,
                    "online": True,
                },
            ],
            "readIssues": [],
        }
    )

    event_types = {event["eventType"] for event in history["events"]}
    assert event_types == {
        "duplicateAssignment",
        "unlinkedBed",
        "unlinkedRecorder",
        "staleLink",
    }


def test_relationship_history_rejects_invalid_observation_shape() -> None:
    with pytest.raises(VitalDBRelationshipProjectionError) as error:
        relationship_history_from_observation(
            {
                "observedAt": "2026-07-01T00:00:00+00:00",
                "recorders": [],
                "beds": [{"bedID": "bed-a", "vrcode": "VR-001"}],
                "readIssues": [],
            }
        )

    assert error.value.args[0] == "VitalDB observation online field is invalid."


def test_relationship_history_rejects_invalid_previous_history() -> None:
    with pytest.raises(VitalDBRelationshipProjectionError) as error:
        relationship_history_from_observation(
            {
                "observedAt": "2026-07-01T00:00:00+00:00",
                "recorders": [],
                "beds": [],
                "readIssues": [],
            },
            previous_history={
                "state": "loaded",
                "assignments": [{"assignmentID": "assignment-1"}],
                "events": [],
                "readError": None,
            },
        )

    assert (
        error.value.args[0]
        == "VitalDB relationship history bedID field is invalid."
    )


def test_relationship_history_does_not_repeat_a_persisting_issue() -> None:
    first = relationship_history_from_observation(
        issue_observation("2026-07-01T00:00:00+00:00")
    )

    second = relationship_history_from_observation(
        issue_observation("2026-07-01T00:00:05+00:00"),
        previous_history=first,
    )

    assert len(first["events"]) == 1
    assert second["events"] == first["events"]
    assert second["activeIssueIDs"] == first["activeIssueIDs"]


def test_relationship_history_records_an_issue_when_it_reappears() -> None:
    first = relationship_history_from_observation(
        issue_observation("2026-07-01T00:00:00+00:00")
    )
    resolved = relationship_history_from_observation(
        {
            "observedAt": "2026-07-01T00:00:05+00:00",
            "recorders": [],
            "beds": [],
            "readIssues": [],
        },
        previous_history=first,
    )

    reappeared = relationship_history_from_observation(
        issue_observation("2026-07-01T00:00:10+00:00"),
        previous_history=resolved,
    )

    assert resolved["activeIssueIDs"] == []
    assert len(reappeared["events"]) == 2
    assert reappeared["events"][0]["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert reappeared["events"][1]["observedAt"] == "2026-07-01T00:00:10+00:00"


def test_relationship_history_migrates_repeated_legacy_issue_events() -> None:
    first = relationship_history_from_observation(
        issue_observation("2026-07-01T00:00:00+00:00")
    )
    repeated = relationship_history_from_observation(
        issue_observation("2026-07-01T00:00:05+00:00")
    )
    legacy_history = {
        "state": "loaded",
        "assignments": [],
        "events": [first["events"][0], repeated["events"][0]],
        "readError": None,
    }

    migrated = relationship_history_from_observation(
        issue_observation("2026-07-01T00:00:10+00:00"),
        previous_history=legacy_history,
    )

    assert migrated["projectionVersion"] == 2
    assert len(migrated["events"]) == 1
    assert len(migrated["activeIssueIDs"]) == 1


def issue_observation(observed_at: str) -> dict[str, object]:
    return {
        "observedAt": observed_at,
        "recorders": [],
        "beds": [
            {
                "bedID": "bed-a",
                "name": "OR-A",
                "vrcode": None,
                "lastSeenAt": None,
                "patientConnected": None,
                "online": True,
            }
        ],
        "readIssues": [],
    }
