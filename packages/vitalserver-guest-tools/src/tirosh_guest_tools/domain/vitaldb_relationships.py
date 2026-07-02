from __future__ import annotations

from collections.abc import Mapping

RELATIONSHIP_HISTORY_STATES = {"loaded", "partiallyLoaded", "readFailed"}
RELATIONSHIP_EVENT_TYPES = {
    "handoff",
    "duplicateAssignment",
    "unlinkedBed",
    "unlinkedRecorder",
    "staleLink",
}
RELATIONSHIP_SEVERITIES = {"info", "warning", "critical"}
ASSIGNMENT_STATUSES = {"online", "stale", "offline"}


class VitalDBRelationshipProjectionError(ValueError):
    pass


def relationship_history_from_observation(
    observation: Mapping[str, object],
    *,
    previous_history: Mapping[str, object] | None = None,
) -> dict[str, object]:
    observed_at = required_string(observation, "observedAt")
    beds = required_list(observation, "beds")
    recorders = recorder_index(required_list(observation, "recorders"))
    read_error = read_issue_text(observation.get("readIssues"))
    previous = (
        validated_previous_history(previous_history)
        if previous_history is not None
        else {"assignments": [], "events": []}
    )

    assignments_by_id = {
        assignment["assignmentID"]: dict(assignment)
        for assignment in previous["assignments"]
    }
    active_assignments_by_bed_id = {
        assignment["bedID"]: assignment
        for assignment in previous["assignments"]
        if assignment["endedAt"] is None
    }
    new_events: list[dict[str, object]] = []

    for item in sorted(beds, key=bed_sort_key):
        bed = required_mapping_item(item, "beds")
        vrcode = optional_string(bed, "vrcode")
        bed_id = required_string(bed, "bedID")
        open_assignment = active_assignments_by_bed_id.get(bed_id)
        if not vrcode:
            if open_assignment is not None:
                assignments_by_id[open_assignment["assignmentID"]] = {
                    **open_assignment,
                    "endedAt": observed_at,
                    "lastObservedAt": observed_at,
                }
            continue

        bed_online = required_bool(bed, "online")
        linked_recorder = recorders.get(vrcode)
        status = assignment_status(bed_online=bed_online, recorder=linked_recorder)
        last_seen_at = optional_string(bed, "lastSeenAt")

        if open_assignment is not None and open_assignment["vrcode"] == vrcode:
            assignments_by_id[open_assignment["assignmentID"]] = {
                **open_assignment,
                "bedName": optional_string(bed, "name"),
                "lastSeenAt": last_seen_at,
                "lastObservedAt": observed_at,
                "status": status,
                "patientConnected": optional_bool(bed, "patientConnected"),
                "observationCount": open_assignment["observationCount"] + 1,
            }
            continue

        if open_assignment is not None:
            assignments_by_id[open_assignment["assignmentID"]] = {
                **open_assignment,
                "endedAt": observed_at,
                "lastObservedAt": observed_at,
            }
            new_events.append(
                relationship_event(
                    event_type="handoff",
                    observed_at=observed_at,
                    severity="info",
                    bed_id=bed_id,
                    bed_name=optional_string(bed, "name"),
                    vrcode=vrcode,
                    previous_vrcode=open_assignment["vrcode"],
                    previous_bed_id=None,
                    message="Bed VRecorder assignment changed.",
                )
            )

        assignments_by_id[f"assignment:{bed_id}:{vrcode}:{observed_at}"] = {
            "assignmentID": f"assignment:{bed_id}:{vrcode}:{observed_at}",
            "bedID": bed_id,
            "bedName": optional_string(bed, "name"),
            "vrcode": vrcode,
            "startedAt": observed_at,
            "endedAt": None,
            "lastSeenAt": last_seen_at,
            "lastObservedAt": observed_at,
            "status": status,
            "patientConnected": optional_bool(bed, "patientConnected"),
            "observationCount": 1,
        }

    new_events.extend(planned_events(observation))

    return {
        "state": "partiallyLoaded" if read_error is not None else "loaded",
        "assignments": sorted(assignments_by_id.values(), key=assignment_sort_key),
        "events": merged_events(previous["events"], new_events),
        "readError": read_error,
    }


def bed_sort_key(item: object) -> tuple[str]:
    bed = required_mapping_item(item, "beds")
    return (required_string(bed, "bedID"),)


def assignment_sort_key(assignment: Mapping[str, object]) -> tuple[int, str, str]:
    ended_at = assignment["endedAt"]
    return (
        0 if ended_at is None else 1,
        str(assignment["bedID"]),
        str(assignment["startedAt"]),
    )


def planned_events(observation: Mapping[str, object]) -> list[dict[str, object]]:
    observed_at = required_string(observation, "observedAt")
    beds = required_list(observation, "beds")
    recorders = recorder_index(required_list(observation, "recorders"))
    linked_bed_vrcodes: set[str] = set()
    beds_by_vrcode: dict[str, list[Mapping[str, object]]] = {}
    events: list[dict[str, object]] = []

    for item in sorted(beds, key=bed_sort_key):
        bed = required_mapping_item(item, "beds")
        bed_id = required_string(bed, "bedID")
        vrcode = optional_string(bed, "vrcode")
        if not vrcode:
            events.append(
                relationship_event(
                    event_type="unlinkedBed",
                    observed_at=observed_at,
                    severity="warning",
                    bed_id=bed_id,
                    bed_name=optional_string(bed, "name"),
                    vrcode=None,
                    previous_vrcode=None,
                    previous_bed_id=None,
                    message="Bed has no linked VRecorder.",
                )
            )
            continue

        linked_bed_vrcodes.add(vrcode)
        beds_by_vrcode.setdefault(vrcode, []).append(bed)
        recorder = recorders.get(vrcode)
        if recorder is not None and required_bool(bed, "online") != required_bool(
            recorder,
            "online",
        ):
            events.append(
                relationship_event(
                    event_type="staleLink",
                    observed_at=observed_at,
                    severity="warning",
                    bed_id=bed_id,
                    bed_name=optional_string(bed, "name"),
                    vrcode=vrcode,
                    previous_vrcode=None,
                    previous_bed_id=None,
                    message="Bed and VRecorder online state differ.",
                )
            )

    for vrcode in sorted(beds_by_vrcode):
        linked_beds = beds_by_vrcode[vrcode]
        if len(linked_beds) < 2:
            continue
        bed_ids = sorted(required_string(bed, "bedID") for bed in linked_beds)
        events.append(
            relationship_event(
                event_type="duplicateAssignment",
                observed_at=observed_at,
                severity="warning",
                bed_id=bed_ids[0],
                bed_name=None,
                vrcode=vrcode,
                previous_vrcode=None,
                previous_bed_id=None,
                message=f"VRecorder is linked to multiple beds: {', '.join(bed_ids)}.",
            )
        )

    for vrcode in sorted(recorders):
        if vrcode in linked_bed_vrcodes:
            continue
        recorder = recorders[vrcode]
        severity = "warning" if optional_bool(recorder, "online") is True else "info"
        events.append(
            relationship_event(
                event_type="unlinkedRecorder",
                observed_at=observed_at,
                severity=severity,
                bed_id=None,
                bed_name=None,
                vrcode=vrcode,
                previous_vrcode=None,
                previous_bed_id=None,
                message="VRecorder has no linked bed.",
            )
        )

    return events


def relationship_event(
    *,
    event_type: str,
    observed_at: str,
    severity: str,
    bed_id: str | None,
    bed_name: str | None,
    vrcode: str | None,
    previous_vrcode: str | None,
    previous_bed_id: str | None,
    message: str,
) -> dict[str, object]:
    return {
        "eventID": event_id(
            event_type,
            observed_at,
            bed_id,
            vrcode,
            previous_vrcode,
        ),
        "observedAt": observed_at,
        "eventType": event_type,
        "severity": severity,
        "bedID": bed_id,
        "bedName": bed_name,
        "vrcode": vrcode,
        "previousVrcode": previous_vrcode,
        "previousBedID": previous_bed_id,
        "message": message,
    }


def event_id(
    event_type: str,
    observed_at: str,
    bed_id: str | None,
    vrcode: str | None,
    previous: str | None,
) -> str:
    return ":".join(
        [
            "relationship",
            event_type,
            observed_at,
            bed_id or "-",
            vrcode or "-",
            previous or "-",
        ]
    )


def merged_events(
    previous_events: list[dict[str, object]],
    new_events: list[dict[str, object]],
) -> list[dict[str, object]]:
    events_by_id = {event["eventID"]: event for event in previous_events}
    for event in new_events:
        events_by_id.setdefault(event["eventID"], event)
    return list(events_by_id.values())


def recorder_index(items: list[object]) -> dict[str, Mapping[str, object]]:
    indexed: dict[str, Mapping[str, object]] = {}
    for item in items:
        recorder = required_mapping_item(item, "recorders")
        vrcode = required_string(recorder, "vrcode")
        indexed[vrcode] = recorder
    return indexed


def assignment_status(
    *,
    bed_online: bool,
    recorder: Mapping[str, object] | None,
) -> str:
    if not bed_online:
        return "offline"
    if recorder is None:
        return "online"
    if optional_bool(recorder, "stale") is True:
        return "stale"
    if required_bool(recorder, "online") is False:
        return "stale"
    return "online"


def read_issue_text(value: object) -> str | None:
    if value is None:
        return None
    if not isinstance(value, list):
        raise VitalDBRelationshipProjectionError(
            "VitalDB observation readIssues field is invalid."
        )
    messages: list[str] = []
    for item in value:
        issue = required_mapping_item(item, "readIssues")
        source = optional_string(issue, "source")
        message = required_string(issue, "message")
        messages.append(f"{source}={message}" if source else message)
    return "; ".join(messages) if messages else None


def validated_previous_history(
    history: Mapping[str, object],
) -> dict[str, list[dict[str, object]]]:
    state = history.get("state")
    assignments = history.get("assignments")
    events = history.get("events")
    read_error = history.get("readError")
    if state not in RELATIONSHIP_HISTORY_STATES:
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship history state field is invalid."
        )
    if not isinstance(assignments, list):
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship history assignments field is invalid."
        )
    if not isinstance(events, list):
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship history events field is invalid."
        )
    if read_error is not None and not isinstance(read_error, str):
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship history readError field is invalid."
        )
    return {
        "assignments": [
            validated_assignment(assignment) for assignment in assignments
        ],
        "events": [validated_event(event) for event in events],
    }


def validated_assignment(value: object) -> dict[str, object]:
    assignment = required_mapping_item(value, "relationship assignments")
    assignment_id = required_relationship_string(assignment, "assignmentID")
    bed_id = required_relationship_string(assignment, "bedID")
    bed_name = optional_string(assignment, "bedName")
    vrcode = required_relationship_string(assignment, "vrcode")
    started_at = required_relationship_string(assignment, "startedAt")
    ended_at = optional_string(assignment, "endedAt")
    last_seen_at = optional_string(assignment, "lastSeenAt")
    last_observed_at = required_relationship_string(assignment, "lastObservedAt")
    status = required_relationship_string(assignment, "status")
    if status not in ASSIGNMENT_STATUSES:
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship assignment status field is invalid."
        )
    patient_connected = optional_bool(assignment, "patientConnected")
    observation_count = assignment.get("observationCount")
    if not isinstance(observation_count, int) or observation_count < 0:
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship assignment observationCount field is invalid."
        )
    return {
        "assignmentID": assignment_id,
        "bedID": bed_id,
        "bedName": bed_name,
        "vrcode": vrcode,
        "startedAt": started_at,
        "endedAt": ended_at,
        "lastSeenAt": last_seen_at,
        "lastObservedAt": last_observed_at,
        "status": status,
        "patientConnected": patient_connected,
        "observationCount": observation_count,
    }


def validated_event(value: object) -> dict[str, object]:
    event = required_mapping_item(value, "relationship events")
    event_id_value = required_relationship_string(event, "eventID")
    observed_at = required_relationship_string(event, "observedAt")
    event_type = required_relationship_string(event, "eventType")
    if event_type not in RELATIONSHIP_EVENT_TYPES:
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship event eventType field is invalid."
        )
    severity = required_relationship_string(event, "severity")
    if severity not in RELATIONSHIP_SEVERITIES:
        raise VitalDBRelationshipProjectionError(
            "VitalDB relationship event severity field is invalid."
        )
    return {
        "eventID": event_id_value,
        "observedAt": observed_at,
        "eventType": event_type,
        "severity": severity,
        "bedID": optional_string(event, "bedID"),
        "bedName": optional_string(event, "bedName"),
        "vrcode": optional_string(event, "vrcode"),
        "previousVrcode": optional_string(event, "previousVrcode"),
        "previousBedID": optional_string(event, "previousBedID"),
        "message": required_relationship_string(event, "message"),
    }


def required_list(document: Mapping[str, object], key: str) -> list[object]:
    value = document.get(key)
    if not isinstance(value, list):
        raise VitalDBRelationshipProjectionError(
            f"VitalDB observation {key} field is invalid."
        )
    return value


def required_mapping_item(value: object, collection: str) -> Mapping[str, object]:
    if not isinstance(value, dict):
        raise VitalDBRelationshipProjectionError(
            f"VitalDB observation {collection} item is invalid."
        )
    return value


def required_string(document: Mapping[str, object], key: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise VitalDBRelationshipProjectionError(
            f"VitalDB observation {key} field is invalid."
        )
    return value


def required_relationship_string(document: Mapping[str, object], key: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise VitalDBRelationshipProjectionError(
            f"VitalDB relationship history {key} field is invalid."
        )
    return value


def optional_string(document: Mapping[str, object], key: str) -> str | None:
    value = document.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise VitalDBRelationshipProjectionError(
            f"VitalDB observation {key} field is invalid."
        )
    return value


def required_bool(document: Mapping[str, object], key: str) -> bool:
    value = document.get(key)
    if not isinstance(value, bool):
        raise VitalDBRelationshipProjectionError(
            f"VitalDB observation {key} field is invalid."
        )
    return value


def optional_bool(document: Mapping[str, object], key: str) -> bool | None:
    value = document.get(key)
    if value is None:
        return None
    if not isinstance(value, bool):
        raise VitalDBRelationshipProjectionError(
            f"VitalDB observation {key} field is invalid."
        )
    return value
