from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any


class VitalDBHistoryProjectionError(ValueError):
    pass


def project_vitaldb_history(
    observations: Sequence[Mapping[str, Any]],
    *,
    recorder_visibility: Mapping[str, str],
    bed_visibility: Mapping[str, str],
) -> dict[str, Any]:
    """Build the Runtime-owned recorder and bed history from explicit snapshots."""
    if not observations:
        raise VitalDBHistoryProjectionError("VitalDB observation history is empty.")

    ordered = sorted(
        (_validated_observation(document) for document in observations),
        key=lambda document: document["observedAt"],
    )
    latest = ordered[-1]
    recorder_builders: dict[str, dict[str, Any]] = {}
    bed_builders: dict[str, dict[str, Any]] = {}
    recorder_duplicates: dict[str, int] = {}
    bed_duplicates: dict[str, int] = {}

    for observation in ordered:
        _add_duplicate_counts(
            recorder_duplicates,
            observation["recorders"],
            identity="vrcode",
        )
        _add_duplicate_counts(bed_duplicates, observation["beds"], identity="bedID")
        beds_by_recorder = {
            bed["vrcode"]: bed
            for bed in _unique_by_identity(observation["beds"], "bedID")
            if isinstance(bed.get("vrcode"), str) and bed["vrcode"]
        }
        for recorder in _unique_by_identity(observation["recorders"], "vrcode"):
            builder = recorder_builders.setdefault(
                recorder["vrcode"],
                _new_recorder_builder(recorder["vrcode"]),
            )
            _observe_recorder(builder, recorder, beds_by_recorder.get(recorder["vrcode"]))
        for bed in _unique_by_identity(observation["beds"], "bedID"):
            builder = bed_builders.setdefault(
                bed["bedID"],
                _new_bed_builder(bed["bedID"]),
            )
            _observe_bed(builder, bed)

    latest_recorders = {
        recorder["vrcode"]: recorder
        for recorder in _unique_by_identity(latest["recorders"], "vrcode")
    }
    latest_beds = {
        bed["bedID"]: bed
        for bed in _unique_by_identity(latest["beds"], "bedID")
    }
    latest_beds_by_recorder = {
        bed["vrcode"]: bed
        for bed in latest_beds.values()
        if isinstance(bed.get("vrcode"), str) and bed["vrcode"]
    }
    anomalies_by_subject = _group_anomalies(latest["anomalies"])
    activity_by_recorder, activity_history = _project_activity(ordered)

    recorders: list[dict[str, Any]] = []
    for vrcode, builder in recorder_builders.items():
        visibility = recorder_visibility.get(vrcode, "visible")
        if visibility == "deleted":
            continue
        latest_recorder = latest_recorders.get(vrcode)
        latest_bed = latest_beds_by_recorder.get(vrcode)
        anomalies = anomalies_by_subject.get(vrcode, [])
        latest_anomaly = _latest_anomaly(anomalies)
        present = latest_recorder is not None
        recorders.append(
            {
                "vrcode": vrcode,
                "status": _recorder_status(
                    latest_recorder,
                    evaluated_at=latest["observedAt"],
                    threshold_seconds=latest["recorderOnlineThresholdSeconds"],
                ),
                "lastIP": _current_or_history(latest_recorder, "ip", builder["lastIP"]),
                "version": _current_or_history(latest_recorder, "version", builder["version"]),
                "bedID": _current_or_history(latest_bed, "bedID", builder["bedID"]),
                "bedName": _current_or_history(latest_bed, "name", builder["bedName"]),
                "patientConnected": _current_or_history(
                    latest_bed, "patientConnected", builder["patientConnected"]
                ),
                "firstSeenAt": builder["firstSeenAt"],
                "lastSeenAt": _current_or_history(
                    latest_recorder, "lastSeenAt", builder["lastSeenAt"]
                ),
                "observationCount": builder["observationCount"],
                "duplicateObservationCount": recorder_duplicates.get(vrcode, 0),
                "currentAnomalyCount": len(anomalies),
                "latestAnomalyKind": _optional_field(latest_anomaly, "kind"),
                "latestAnomalySeverity": _optional_field(latest_anomaly, "severity"),
                "latestAnomalyMessage": _optional_field(latest_anomaly, "message"),
                "latestAnomalyObservedAt": _optional_field(latest_anomaly, "observedAt"),
                "presentInLatestObservation": present,
                "visibility": visibility,
                "activityTimeline": activity_by_recorder.get(vrcode),
                "redisIPSync": None,
            }
        )

    recorders.sort(key=_last_seen_sort_key)
    recorders_by_vrcode = {record["vrcode"]: record for record in recorders}

    beds: list[dict[str, Any]] = []
    for bed_id, builder in bed_builders.items():
        visibility = bed_visibility.get(bed_id, "visible")
        if visibility == "deleted":
            continue
        latest_bed = latest_beds.get(bed_id)
        present = latest_bed is not None
        vrcode = _current_or_history(latest_bed, "vrcode", builder["vrcode"])
        linked_recorder = recorders_by_vrcode.get(vrcode) if isinstance(vrcode, str) else None
        anomalies = anomalies_by_subject.get(bed_id, [])
        latest_anomaly = _latest_anomaly(anomalies)
        beds.append(
            {
                "bedID": bed_id,
                "name": _current_or_history(latest_bed, "name", builder["name"]),
                "vrcode": vrcode,
                "linkedRecorderStatus": _optional_field(linked_recorder, "status"),
                "linkedRecorderIP": _optional_field(linked_recorder, "lastIP"),
                "linkedRecorderLastSeenAt": _optional_field(linked_recorder, "lastSeenAt"),
                "status": _bed_status(latest_bed),
                "patientConnected": _current_or_history(
                    latest_bed, "patientConnected", builder["patientConnected"]
                ),
                "firstSeenAt": builder["firstSeenAt"],
                "lastSeenAt": _current_or_history(latest_bed, "lastSeenAt", builder["lastSeenAt"]),
                "observationCount": builder["observationCount"],
                "duplicateObservationCount": bed_duplicates.get(bed_id, 0),
                "currentAnomalyCount": len(anomalies),
                "latestAnomalyKind": _optional_field(latest_anomaly, "kind"),
                "latestAnomalySeverity": _optional_field(latest_anomaly, "severity"),
                "latestAnomalyMessage": _optional_field(latest_anomaly, "message"),
                "latestAnomalyObservedAt": _optional_field(latest_anomaly, "observedAt"),
                "visibility": visibility,
            }
        )
    beds.sort(key=_last_seen_sort_key)

    summary = _summary(recorders, beds)
    return {
        "state": "loaded",
        "updatedAt": latest["observedAt"],
        "recorders": recorders,
        "beds": beds,
        "summary": summary,
        "activityHistory": activity_history,
        "recorderIngressStatusRead": None,
        "readError": None,
    }


def attach_recorder_ingress_status(
    history: Mapping[str, Any],
    status_read: Mapping[str, Any],
) -> dict[str, Any]:
    result = dict(history)
    result["recorderIngressStatusRead"] = dict(status_read)
    document = status_read.get("document")
    ingress_recorders = document.get("recorders") if isinstance(document, Mapping) else None
    sync_by_vrcode: dict[str, Any] = {}
    if isinstance(ingress_recorders, list):
        for recorder in ingress_recorders:
            if not isinstance(recorder, Mapping):
                continue
            vrcode = recorder.get("vrcode")
            sync = recorder.get("redisIpSync")
            if isinstance(vrcode, str) and isinstance(sync, Mapping):
                sync_by_vrcode[vrcode] = dict(sync)

    read_state = status_read.get("readState")
    read_error = status_read.get("readError")
    enriched: list[dict[str, Any]] = []
    for source in result.get("recorders", []):
        recorder = dict(source)
        vrcode = recorder.get("vrcode")
        sync = sync_by_vrcode.get(vrcode)
        if sync is None and isinstance(vrcode, str):
            if read_state == "loaded":
                sync = _empty_redis_sync("unknown", vrcode, None)
            else:
                message = read_error if isinstance(read_error, str) else f"recorder ingress status {read_state}"
                sync = _empty_redis_sync("unavailable", vrcode, message)
        recorder["redisIPSync"] = sync
        enriched.append(recorder)
    result["recorders"] = enriched
    return result


def bed_history_from_recorder_history(history: Mapping[str, Any]) -> dict[str, Any]:
    summary = history.get("summary")
    if not isinstance(summary, Mapping):
        raise VitalDBHistoryProjectionError("VitalDB recorder history summary is invalid.")
    return {
        "state": history.get("state"),
        "updatedAt": history.get("updatedAt"),
        "beds": list(history.get("beds", [])),
        "summary": {
            "knownBeds": summary.get("knownBeds"),
            "onlineBeds": summary.get("onlineBeds"),
            "staleBeds": summary.get("staleBeds"),
            "bedAssignments": summary.get("bedAssignments"),
            "bedAnomalies": summary.get("bedAnomalies"),
        },
        "readError": history.get("readError"),
    }


def _validated_observation(source: Mapping[str, Any]) -> dict[str, Any]:
    document = dict(source)
    if not isinstance(document.get("observedAt"), str):
        raise VitalDBHistoryProjectionError("VitalDB observation observedAt is invalid.")
    if not isinstance(document.get("ready"), bool):
        raise VitalDBHistoryProjectionError("VitalDB observation ready is invalid.")
    threshold = document.get("recorderOnlineThresholdSeconds")
    if not isinstance(threshold, int) or isinstance(threshold, bool):
        raise VitalDBHistoryProjectionError(
            "VitalDB observation recorderOnlineThresholdSeconds is invalid."
        )
    document.setdefault("anomalies", [])
    document.setdefault("activityBuckets", [])
    for field in ("recorders", "beds", "anomalies"):
        values = document.get(field)
        if not isinstance(values, list) or not all(isinstance(value, dict) for value in values):
            raise VitalDBHistoryProjectionError(f"VitalDB observation {field} is invalid.")
    for recorder in document["recorders"]:
        if not isinstance(recorder.get("vrcode"), str):
            raise VitalDBHistoryProjectionError("VitalDB recorder vrcode is invalid.")
        if not isinstance(recorder.get("online"), bool) or not isinstance(recorder.get("stale"), bool):
            raise VitalDBHistoryProjectionError("VitalDB recorder status is invalid.")
    for bed in document["beds"]:
        if not isinstance(bed.get("bedID"), str) or not isinstance(bed.get("online"), bool):
            raise VitalDBHistoryProjectionError("VitalDB bed identity or status is invalid.")
    return document


def _new_recorder_builder(vrcode: str) -> dict[str, Any]:
    return {
        "vrcode": vrcode,
        "lastIP": None,
        "version": None,
        "bedID": None,
        "bedName": None,
        "patientConnected": None,
        "firstSeenAt": None,
        "lastSeenAt": None,
        "observationCount": 0,
    }


def _observe_recorder(
    builder: dict[str, Any], recorder: Mapping[str, Any], bed: Mapping[str, Any] | None
) -> None:
    builder["observationCount"] += 1
    _observe_seen_at(builder, recorder.get("lastSeenAt"))
    for target, source in (("lastIP", "ip"), ("version", "version")):
        value = recorder.get(source)
        if value is not None:
            builder[target] = value
    if bed is not None:
        for target, source in (
            ("bedID", "bedID"),
            ("bedName", "name"),
            ("patientConnected", "patientConnected"),
        ):
            value = bed.get(source)
            if value is not None:
                builder[target] = value


def _new_bed_builder(bed_id: str) -> dict[str, Any]:
    return {
        "bedID": bed_id,
        "name": None,
        "vrcode": None,
        "patientConnected": None,
        "firstSeenAt": None,
        "lastSeenAt": None,
        "observationCount": 0,
    }


def _observe_bed(builder: dict[str, Any], bed: Mapping[str, Any]) -> None:
    builder["observationCount"] += 1
    _observe_seen_at(builder, bed.get("lastSeenAt"))
    for field in ("name", "vrcode", "patientConnected"):
        value = bed.get(field)
        if value is not None:
            builder[field] = value


def _observe_seen_at(builder: dict[str, Any], value: Any) -> None:
    if not isinstance(value, str):
        return
    current_first = builder["firstSeenAt"]
    current_last = builder["lastSeenAt"]
    builder["firstSeenAt"] = value if current_first is None else min(current_first, value)
    builder["lastSeenAt"] = value if current_last is None else max(current_last, value)


def _unique_by_identity(values: Sequence[Mapping[str, Any]], identity: str) -> list[dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    for source in values:
        value = dict(source)
        key = value[identity]
        current = selected.get(key)
        if current is None or _preferred(value, current):
            selected[key] = value
    return [selected[key] for key in sorted(selected)]


def _preferred(candidate: Mapping[str, Any], current: Mapping[str, Any]) -> bool:
    candidate_seen = candidate.get("lastSeenAt")
    current_seen = current.get("lastSeenAt")
    if candidate_seen != current_seen:
        return _timestamp_sort_value(candidate_seen) > _timestamp_sort_value(current_seen)
    if candidate.get("stale") != current.get("stale"):
        return candidate.get("stale") is True
    if candidate.get("online") != current.get("online"):
        return candidate.get("online") is True
    return True


def _add_duplicate_counts(
    target: dict[str, int], values: Sequence[Mapping[str, Any]], *, identity: str
) -> None:
    counts: dict[str, int] = {}
    for value in values:
        key = value[identity]
        counts[key] = counts.get(key, 0) + 1
    for key, count in counts.items():
        if count > 1:
            target[key] = target.get(key, 0) + count - 1


def _group_anomalies(values: Sequence[Mapping[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for source in values:
        subject = source.get("subject")
        if isinstance(subject, str):
            result.setdefault(subject, []).append(dict(source))
    return result


def _latest_anomaly(values: Sequence[Mapping[str, Any]]) -> Mapping[str, Any] | None:
    return max(values, key=lambda value: (str(value.get("observedAt", "")), str(value.get("id", ""))), default=None)


def _recorder_status(
    recorder: Mapping[str, Any] | None,
    *,
    evaluated_at: str,
    threshold_seconds: int,
) -> str:
    if recorder is None:
        return "notObserved"
    if recorder["stale"]:
        return "stale"
    if not recorder["online"]:
        return "offline"
    last_seen = recorder.get("lastSeenAt")
    if isinstance(last_seen, str):
        try:
            age = _timestamp(evaluated_at).timestamp() - _timestamp(last_seen).timestamp()
        except ValueError:
            return "online"
        if age > max(threshold_seconds, 0):
            return "stale"
    return "online"


def _bed_status(bed: Mapping[str, Any] | None) -> str:
    if bed is None:
        return "notObserved"
    return "online" if bed["online"] else "offline"


def _project_activity(
    observations: Sequence[Mapping[str, Any]],
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, Any]]:
    buckets: dict[tuple[str, str, int], dict[str, Any]] = {}
    for observation in observations:
        raw = observation.get("activityBuckets", [])
        if not isinstance(raw, list):
            raise VitalDBHistoryProjectionError("VitalDB observation activityBuckets is invalid.")
        for source in raw:
            if not isinstance(source, Mapping):
                raise VitalDBHistoryProjectionError("VitalDB activity bucket is invalid.")
            bucket = dict(source)
            vrcode = bucket.get("vrcode")
            started_at = bucket.get("bucketStartedAt")
            bucket_seconds = bucket.get("bucketSeconds")
            if not isinstance(vrcode, str) or not isinstance(started_at, str) or not isinstance(bucket_seconds, int):
                raise VitalDBHistoryProjectionError("VitalDB activity bucket identity is invalid.")
            for field in ("messageCount", "byteCount", "roomCount"):
                if not isinstance(bucket.get(field), int):
                    raise VitalDBHistoryProjectionError(f"VitalDB activity bucket {field} is invalid.")
            buckets[(vrcode, started_at, bucket_seconds)] = bucket

    by_recorder: dict[str, list[dict[str, Any]]] = {}
    for bucket in sorted(buckets.values(), key=lambda value: (value["vrcode"], value["bucketStartedAt"])):
        seconds = max(bucket["bucketSeconds"], 1)
        by_recorder.setdefault(bucket["vrcode"], []).append(
            {
                "observedAt": bucket.get("lastObservedAt", bucket["bucketStartedAt"]),
                "windowSeconds": bucket["bucketSeconds"],
                "messageCount": bucket["messageCount"],
                "byteCount": bucket["byteCount"],
                "roomCount": bucket["roomCount"],
                "messagesPerSecond": bucket["messageCount"] / seconds,
                "bytesPerSecond": bucket["byteCount"] / seconds,
                "buckets": [
                    {
                        "bucketStartedAt": bucket["bucketStartedAt"],
                        "bucketSeconds": bucket["bucketSeconds"],
                        "messageCount": bucket["messageCount"],
                        "byteCount": bucket["byteCount"],
                        "roomCount": bucket["roomCount"],
                    }
                ],
            }
        )
    started = [bucket["bucketStartedAt"] for bucket in buckets.values()]
    return by_recorder, {
        "source": "readModelProjection",
        "bucketCount": len(buckets),
        "earliestBucketStartedAt": min(started) if started else None,
        "latestBucketStartedAt": max(started) if started else None,
        "readError": None,
    }


def _summary(recorders: Sequence[Mapping[str, Any]], beds: Sequence[Mapping[str, Any]]) -> dict[str, int]:
    current_recorders = [record for record in recorders if record["presentInLatestObservation"]]
    current_beds = [record for record in beds if record["status"] != "notObserved"]
    return {
        "knownRecorders": len(recorders),
        "currentRecorders": len(current_recorders),
        "onlineRecorders": sum(record["status"] == "online" for record in current_recorders),
        "staleRecorders": sum(record["status"] == "stale" for record in current_recorders),
        "recorderAnomalies": sum(record["currentAnomalyCount"] for record in current_recorders),
        "knownBeds": len(beds),
        "onlineBeds": sum(record["status"] == "online" for record in current_beds),
        "staleBeds": sum(record["status"] == "stale" for record in current_beds),
        "bedAssignments": sum(bool(record.get("vrcode")) for record in current_beds),
        "bedAnomalies": sum(record["currentAnomalyCount"] for record in current_beds),
    }


def _current_or_history(current: Mapping[str, Any] | None, field: str, history: Any) -> Any:
    return current.get(field) if current is not None else history


def _optional_field(value: Mapping[str, Any] | None, field: str) -> Any:
    return value.get(field) if value is not None else None


def _last_seen_sort_key(record: Mapping[str, Any]) -> tuple[int, float, str]:
    value = record.get("lastSeenAt")
    identity = str(record.get("vrcode", record.get("bedID", "")))
    if not isinstance(value, str):
        return (1, 0.0, identity)
    try:
        return (0, -_timestamp(value).timestamp(), identity)
    except ValueError:
        return (0, 0.0, identity)


def _timestamp_sort_value(value: Any) -> tuple[int, float, str]:
    if not isinstance(value, str):
        return (0, 0.0, "")
    try:
        return (2, _timestamp(value).timestamp(), value)
    except ValueError:
        return (1, 0.0, value)


def _timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _empty_redis_sync(status: str, vrcode: str, failure: str | None) -> dict[str, Any]:
    return {
        "status": status,
        "redisKey": f"ip_{vrcode}",
        "selectedIp": None,
        "ipSource": None,
        "redisValue": None,
        "lastWriteAt": None,
        "lastVerifiedAt": None,
        "lastFailure": failure,
    }
