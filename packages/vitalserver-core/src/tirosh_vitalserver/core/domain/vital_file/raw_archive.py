"""Pure mapping from recorder-ingress raw archive records to `.vital` tracks."""

from __future__ import annotations

import base64
import binascii
import json
import zlib
from collections.abc import Iterable, Iterator, Mapping
from dataclasses import dataclass
from datetime import datetime

from tirosh_vitalserver.core.domain.vital_file.format import VitalTrackKind
from tirosh_vitalserver.core.domain.vital_file.session_recording import (
    VitalTrack,
    collect_frame_tracks,
    frame_rooms,
)
from tirosh_vitalserver.core.errors import RawArchiveDecodeError
from tirosh_vitalserver.core.types.json import JsonObject, JsonValue


@dataclass(frozen=True)
class RawArchivePayload:
    """One decoded recorder-ingress raw archive payload."""

    archive_id: str
    vrcode: str
    received_at: float | None
    archived_at: float | None
    payload: JsonObject


@dataclass(frozen=True)
class RawArchiveVitalGroup:
    """Canonical tracks and explicit room identities for one recorder."""

    vrcode: str
    room_names: tuple[str, ...]
    tracks: tuple[VitalTrack, ...]


def raw_archive_payloads_from_jsonl_lines(
    lines: Iterable[str],
) -> tuple[RawArchivePayload, ...]:
    """Decode raw archive JSONL text lines without reading external state."""

    return tuple(iter_raw_archive_payloads_from_jsonl_lines(lines))


def iter_raw_archive_payloads_from_jsonl_lines(
    lines: Iterable[str],
) -> Iterator[RawArchivePayload]:
    """Yield decoded raw archive payloads without retaining source documents."""

    for line_number, line in enumerate(lines, start=1):
        text = line.strip()
        if not text:
            continue
        record = json_object_from_text(
            text,
            context=f"raw archive line {line_number}",
        )
        yield raw_archive_payload_from_record(record)


def raw_archive_payload_from_record(
    record: Mapping[str, JsonValue],
) -> RawArchivePayload:
    """Decode one raw archive record into an explicit payload document."""

    if type(record.get("schemaVersion")) is not int or record["schemaVersion"] != 1:
        raise RawArchiveDecodeError("raw archive record schemaVersion must be 1")
    if record.get("kind") != "send_data_raw_payload":
        raise RawArchiveDecodeError(
            "raw archive record kind must be send_data_raw_payload"
        )

    archive_id = required_string(record, "itemId")
    vrcode = required_string(record, "vrcode")
    received_at = optional_iso8601_epoch(record, "receivedAt")
    archived_at = optional_iso8601_epoch(record, "archivedAt")
    payload = raw_archive_payload_object(required_string(record, "payloadBase64"))
    assert_payload_vrcode_matches_archive(payload, vrcode)

    return RawArchivePayload(
        archive_id=archive_id,
        vrcode=vrcode,
        received_at=received_at,
        archived_at=archived_at,
        payload=payload,
    )


def vital_tracks_by_vrcode_from_raw_archive(
    payloads: Iterable[RawArchivePayload],
) -> dict[str, tuple[VitalTrack, ...]]:
    """Return exportable `.vital` tracks grouped by recorder code."""

    return {
        group.vrcode: group.tracks
        for group in vital_groups_from_raw_archive(payloads)
    }


def vital_groups_from_raw_archive(
    payloads: Iterable[RawArchivePayload],
) -> tuple[RawArchiveVitalGroup, ...]:
    """Return tracks with recorder and room identities from explicit payloads."""

    grouped_records: dict[str, dict[str, list]] = {}
    grouped_configs: dict[
        str,
        dict[str, tuple[VitalTrackKind, float, str, float, float, int]],
    ] = {}
    grouped_room_names: dict[str, set[str]] = {}

    for raw_payload in payloads:
        track_records = grouped_records.setdefault(raw_payload.vrcode, {})
        track_configs = grouped_configs.setdefault(raw_payload.vrcode, {})
        room_names = grouped_room_names.setdefault(raw_payload.vrcode, set())
        room_names.update(recorder_room_names(raw_payload.payload))
        collect_frame_tracks(
            raw_payload.payload,
            track_records=track_records,
            track_configs=track_configs,
        )

    return tuple(
        RawArchiveVitalGroup(
            vrcode=vrcode,
            room_names=tuple(sorted(grouped_room_names[vrcode])),
            tracks=tuple(
                VitalTrack(
                    dtname=dtname,
                    kind=grouped_configs[vrcode][dtname][0],
                    records=tuple(sorted(records, key=lambda record: record.dt)),
                    srate=grouped_configs[vrcode][dtname][1],
                    unit=grouped_configs[vrcode][dtname][2],
                    mindisp=grouped_configs[vrcode][dtname][3],
                    maxdisp=grouped_configs[vrcode][dtname][4],
                    montype=grouped_configs[vrcode][dtname][5],
                )
                for dtname, records in sorted(track_records.items())
                if records
            ),
        )
        for vrcode, track_records in sorted(grouped_records.items())
    )


def recorder_room_names(payload: Mapping[str, JsonValue]) -> tuple[str, ...]:
    """Return explicit room identities carried by one recorder payload."""

    names: list[str] = []
    for room_key, room in frame_rooms(payload).items():
        if not isinstance(room, dict):
            continue
        room_name = room.get("roomname")
        if isinstance(room_name, str) and room_name.strip():
            names.append(room_name.strip())
        else:
            names.append(room_key)
    return tuple(dict.fromkeys(names))


def required_string(record: Mapping[str, JsonValue], key: str) -> str:
    value = record.get(key)
    if not isinstance(value, str) or not value:
        raise RawArchiveDecodeError(f"raw archive record requires string {key}")
    return value


def raw_archive_payload_object(payload_base64: str) -> JsonObject:
    """Decode one base64/zlib payload without repairing malformed input."""

    try:
        payload_bytes = base64.b64decode(payload_base64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise RawArchiveDecodeError(
            "raw archive record payloadBase64 is not valid base64"
        ) from exc

    try:
        decompressor = zlib.decompressobj()
        compressed_payload = decompressor.decompress(payload_bytes)
        compressed_payload += decompressor.flush()
    except zlib.error as exc:
        raise RawArchiveDecodeError(
            "raw archive record payloadBase64 is not a zlib payload"
        ) from exc
    if not decompressor.eof or decompressor.unused_data:
        raise RawArchiveDecodeError(
            "raw archive record payloadBase64 must contain one complete zlib payload"
        )

    try:
        decoded_text = compressed_payload.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RawArchiveDecodeError(
            "decoded raw archive payload is not valid UTF-8"
        ) from exc

    return json_object_from_text(decoded_text, context="decoded raw archive payload")


def json_object_from_text(text: str, *, context: str) -> JsonObject:
    """Decode a finite JSON object and preserve malformed input as an error."""

    try:
        decoded = json.loads(text, parse_constant=reject_non_finite_json_constant)
    except (json.JSONDecodeError, ValueError) as exc:
        raise RawArchiveDecodeError(f"{context} is not valid JSON") from exc
    if not isinstance(decoded, dict):
        raise RawArchiveDecodeError(f"{context} is not an object")
    return decoded


def reject_non_finite_json_constant(value: str) -> None:
    """Reject JavaScript-style non-finite values not allowed by JSON."""

    raise ValueError(f"non-finite JSON value {value}")


def assert_payload_vrcode_matches_archive(
    payload: JsonObject,
    archive_vrcode: str,
) -> None:
    """Ensure a payload identity, when present, agrees with its archive record."""

    payload_vrcode = payload.get("vrcode")
    if payload_vrcode is None:
        return
    if not isinstance(payload_vrcode, str) or not payload_vrcode:
        raise RawArchiveDecodeError(
            "decoded raw archive payload vrcode must be a non-empty string when present"
        )
    if payload_vrcode != archive_vrcode:
        raise RawArchiveDecodeError(
            "decoded raw archive payload vrcode does not match "
            "raw archive record vrcode"
        )


def optional_iso8601_epoch(
    record: Mapping[str, JsonValue],
    key: str,
) -> float | None:
    """Read an optional, timezone-aware archive timestamp."""

    value = record.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise RawArchiveDecodeError(
            f"raw archive record {key} must be an ISO-8601 timestamp or null"
        )

    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise RawArchiveDecodeError(
            f"raw archive record {key} must be an ISO-8601 timestamp"
        ) from exc
    if parsed.tzinfo is None:
        raise RawArchiveDecodeError(
            f"raw archive record {key} must include a UTC offset"
        )
    return parsed.timestamp()
