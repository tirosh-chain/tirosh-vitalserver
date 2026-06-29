"""Pure mapping from recorder-ingress raw archive records to `.vital` tracks."""

from __future__ import annotations

import base64
import json
import re
import zlib
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import datetime

from tirosh_vitalserver.core.domain.vital_file.session_recording import (
    VitalTrack,
    collect_frame_tracks,
)
from tirosh_vitalserver.core.types.json import JsonObject, JsonValue

CONTROL_CHARS_RE = re.compile(r"[\x00-\x1f\x7f]")
NAN_TOKEN_RE = re.compile(r"\bnan\b")


@dataclass(frozen=True)
class RawArchivePayload:
    """One decoded recorder-ingress raw archive payload."""

    archive_id: str
    vrcode: str
    received_at: float | None
    archived_at: float | None
    payload: JsonObject


def raw_archive_payloads_from_jsonl_lines(
    lines: Iterable[str],
) -> tuple[RawArchivePayload, ...]:
    """Decode raw archive JSONL text lines without reading external state."""

    payloads: list[RawArchivePayload] = []
    for line_number, line in enumerate(lines, start=1):
        text = line.strip()
        if not text:
            continue
        try:
            record = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"raw archive line {line_number} is not JSON") from exc
        if not isinstance(record, dict):
            raise ValueError(f"raw archive line {line_number} is not an object")
        payloads.append(raw_archive_payload_from_record(record))
    return tuple(payloads)


def raw_archive_payload_from_record(
    record: Mapping[str, JsonValue],
) -> RawArchivePayload:
    """Decode one raw archive record into an explicit payload document."""

    if record.get("schemaVersion") != 1:
        raise ValueError("raw archive record schemaVersion must be 1")
    if record.get("kind") != "send_data_raw_payload":
        raise ValueError("raw archive record kind must be send_data_raw_payload")

    payload_base64 = required_string(record, "payloadBase64")
    payload_bytes = base64.b64decode(payload_base64, validate=True)
    decoded_text = zlib.decompress(payload_bytes).decode("utf-8", errors="replace")
    cleaned_text = NAN_TOKEN_RE.sub('""', CONTROL_CHARS_RE.sub("", decoded_text))
    payload = json.loads(cleaned_text)
    if not isinstance(payload, dict):
        raise ValueError("decoded raw archive payload is not an object")

    record_vrcode = optional_string(record.get("vrcode"))
    payload_vrcode = optional_string(payload.get("vrcode"))
    vrcode = record_vrcode or payload_vrcode
    if not vrcode:
        raise ValueError("raw archive record has no explicit vrcode")

    return RawArchivePayload(
        archive_id=required_string(record, "itemId"),
        vrcode=vrcode,
        received_at=parse_iso8601_epoch(optional_string(record.get("receivedAt"))),
        archived_at=parse_iso8601_epoch(optional_string(record.get("archivedAt"))),
        payload=payload,
    )


def vital_tracks_by_vrcode_from_raw_archive(
    payloads: Iterable[RawArchivePayload],
) -> dict[str, tuple[VitalTrack, ...]]:
    """Return exportable `.vital` tracks grouped by recorder code."""

    grouped_records: dict[str, dict[str, list]] = {}
    grouped_configs: dict[str, dict[str, tuple[float, str, float, float, int]]] = {}

    for raw_payload in payloads:
        track_records = grouped_records.setdefault(raw_payload.vrcode, {})
        track_configs = grouped_configs.setdefault(raw_payload.vrcode, {})
        collect_frame_tracks(
            raw_payload.payload,
            track_records=track_records,
            track_configs=track_configs,
        )

    return {
        vrcode: tuple(
            VitalTrack(
                dtname=dtname,
                records=tuple(sorted(records, key=lambda record: record.dt)),
                srate=grouped_configs[vrcode][dtname][0],
                unit=grouped_configs[vrcode][dtname][1],
                mindisp=grouped_configs[vrcode][dtname][2],
                maxdisp=grouped_configs[vrcode][dtname][3],
                montype=grouped_configs[vrcode][dtname][4],
            )
            for dtname, records in sorted(track_records.items())
            if records
        )
        for vrcode, track_records in sorted(grouped_records.items())
    }


def required_string(record: Mapping[str, JsonValue], key: str) -> str:
    value = record.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"raw archive record requires string {key}")
    return value


def optional_string(value: JsonValue) -> str | None:
    if isinstance(value, str) and value:
        return value
    return None


def parse_iso8601_epoch(value: str | None) -> float | None:
    if value is None:
        return None
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized).timestamp()
