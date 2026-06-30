"""Recorded recorder payload replay helpers."""

from __future__ import annotations

from collections.abc import Mapping
from copy import deepcopy

from tirosh_vitalserver.testkit.types.json import JsonArray, JsonObject, JsonValue


def replay_recorded_recorder_payload(
    payload: Mapping[str, JsonValue],
    *,
    now: float,
    frame_seconds: float,
    sequence: int,
) -> JsonObject:
    """Return the recorded source frame for one realtime replay tick."""

    if sequence < 0:
        raise ValueError("sequence must not be negative")
    if frame_seconds <= 0:
        raise ValueError("frame_seconds must be greater than 0")

    anchor = payload_anchor_timestamp(payload)
    if anchor is None:
        return deepcopy(dict(payload))

    duration = payload_duration_seconds(payload, anchor=anchor)
    elapsed = (sequence * frame_seconds) % duration
    source_start = anchor + elapsed
    source_end = source_start + frame_seconds

    message_vrcode = payload.get("vrcode")
    message_version = payload.get("ver")
    message_rooms = payload.get("rooms")
    rooms = message_rooms if isinstance(message_rooms, dict) else payload

    replayed_rooms = {
        key: replay_room_frame(
            room,
            now=now,
            frame_seconds=frame_seconds,
            anchor=anchor,
            duration=duration,
            source_start=source_start,
            source_end=source_end,
            sequence=sequence,
        )
        for key, room in rooms.items()
    }

    if isinstance(message_vrcode, str) and "ver" in payload:
        return {
            "vrcode": message_vrcode,
            "ver": message_version,
            "rooms": replayed_rooms,
        }

    return replayed_rooms


def replay_room_frame(
    room: JsonValue,
    *,
    now: float,
    frame_seconds: float,
    anchor: float,
    duration: float,
    source_start: float,
    source_end: float,
    sequence: int,
) -> JsonValue:
    """Return one room projected onto a realtime replay frame."""

    if not isinstance(room, dict):
        return deepcopy(room)

    replayed = deepcopy(room)
    replayed["seqid"] = sequence
    replayed["dtstart"] = now
    replayed["dtend"] = now + frame_seconds
    replayed["dtserver"] = now + frame_seconds
    if "dtcase" in replayed:
        replayed["dtcase"] = now - sequence * frame_seconds
    if "dtapp" in replayed:
        replayed["dtapp"] = now

    tracks = replayed.get("trks")
    if isinstance(tracks, list):
        replayed["trks"] = [
            replay_track_frame(
                track,
                now=now,
                anchor=anchor,
                duration=duration,
                source_start=source_start,
                source_end=source_end,
            )
            for track in tracks
        ]

    return replayed


def replay_track_frame(
    track: JsonValue,
    *,
    now: float,
    anchor: float,
    duration: float,
    source_start: float,
    source_end: float,
) -> JsonValue:
    """Return one track with records from the replay source window."""

    if not isinstance(track, dict):
        return deepcopy(track)

    replayed = deepcopy(track)
    records = track.get("recs")
    if not isinstance(records, list):
        replayed["recs"] = []
        return replayed

    replayed_records: JsonArray = []
    for record in records:
        if not isinstance(record, dict):
            continue
        source_dt = record.get("dt")
        if not isinstance(source_dt, int | float):
            continue
        projected_dt = projected_record_timestamp(
            float(source_dt),
            now=now,
            anchor=anchor,
            duration=duration,
            source_start=source_start,
            source_end=source_end,
        )
        if projected_dt is None:
            continue

        replayed_record = deepcopy(record)
        replayed_record["dt"] = projected_dt
        replayed_records.append(replayed_record)

    replayed["recs"] = replayed_records
    return replayed


def projected_record_timestamp(
    source_dt: float,
    *,
    now: float,
    anchor: float,
    duration: float,
    source_start: float,
    source_end: float,
) -> float | None:
    """Project one source timestamp into the current replay frame."""

    source_limit = anchor + duration
    if source_start <= source_dt < min(source_end, source_limit):
        return now + (source_dt - source_start)

    if source_end <= source_limit:
        return None

    wrapped_end = anchor + (source_end - source_limit)
    if anchor <= source_dt < wrapped_end:
        return now + (source_limit - source_start) + (source_dt - anchor)

    return None


def payload_anchor_timestamp(payload: Mapping[str, JsonValue]) -> float | None:
    """Return the earliest explicit timestamp in a recorded payload."""

    timestamps = list(iter_replay_timestamps(payload))
    return min(timestamps) if timestamps else None


def payload_duration_seconds(
    payload: Mapping[str, JsonValue],
    *,
    anchor: float,
) -> float:
    """Return the source replay duration using explicit payload timestamps."""

    timestamps = list(iter_replay_timestamps(payload))
    if not timestamps:
        return 1.0

    return max(1.0, max(timestamps) - anchor)


def iter_replay_timestamps(value: JsonValue) -> tuple[float, ...]:
    """Return timestamp values that define recorded replay timing."""

    timestamps: list[float] = []
    collect_replay_timestamps(value, timestamps)
    return tuple(timestamps)


def collect_replay_timestamps(value: JsonValue, timestamps: list[float]) -> None:
    """Collect explicit timestamp values from a nested JSON payload."""

    if isinstance(value, dict):
        for key, item in value.items():
            if key in {"dt", "dtstart", "dtend", "dtserver"} and isinstance(
                item,
                int | float,
            ):
                timestamps.append(float(item))
            else:
                collect_replay_timestamps(item, timestamps)
    elif isinstance(value, list):
        for item in value:
            collect_replay_timestamps(item, timestamps)
