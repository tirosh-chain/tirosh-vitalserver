from __future__ import annotations

import base64
import json
import zlib

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    RawArchiveDecodeError,
    raw_archive_payload_from_record,
    raw_archive_payloads_from_jsonl_lines,
    vital_tracks_by_vrcode_from_raw_archive,
)
from tirosh_vitalserver.core.types.json import JsonValue


def test_raw_archive_payloads_decode_send_data_jsonl() -> None:
    payload = {
        "vrcode": "VR_RAW",
        "ver": "recorder",
        "rooms": {
            "OR1": {
                "roomname": "OR1",
                "trks": [
                    {
                        "name": "HR",
                        "type": "num",
                        "srate": 0,
                        "unit": "/min",
                        "mindisp": 0,
                        "maxdisp": 200,
                        "montype": "ECG_HR",
                        "recs": [{"dt": 1782620000.0, "val": 72}],
                    }
                ],
            }
        },
    }
    record = {
        "schemaVersion": 1,
        "kind": "send_data_raw_payload",
        "itemId": "senddata-test",
        "vrcode": "VR_RAW",
        "receivedAt": "2026-06-28T06:55:39.810Z",
        "archivedAt": "2026-06-28T06:55:39.812Z",
        "payloadBase64": base64.b64encode(
            zlib.compress(json.dumps(payload).encode())
        ).decode(),
    }

    payloads = raw_archive_payloads_from_jsonl_lines((json.dumps(record),))
    tracks = vital_tracks_by_vrcode_from_raw_archive(payloads)

    assert payloads[0].vrcode == "VR_RAW"
    assert payloads[0].archive_id == "senddata-test"
    assert tuple(tracks) == ("VR_RAW",)
    assert tracks["VR_RAW"][0].dtname == "OR1_Demo/HR"
    assert tracks["VR_RAW"][0].records[0].value == 72


@pytest.mark.parametrize(
    ("payload_text", "message"),
    [
        ('{"vrcode":"VR_RAW\\x00"}', "decoded raw archive payload is not valid JSON"),
        ('{"vrcode":nan}', "decoded raw archive payload is not valid JSON"),
        ('{"vrcode":NaN}', "decoded raw archive payload is not valid JSON"),
    ],
)
def test_raw_archive_payload_rejects_malformed_json_without_repair(
    payload_text: str,
    message: str,
) -> None:
    record = raw_archive_record(zlib.compress(payload_text.encode()))

    with pytest.raises(RawArchiveDecodeError, match=message):
        raw_archive_payload_from_record(record)


def test_raw_archive_payload_rejects_invalid_utf8_without_replacement() -> None:
    record = raw_archive_record(zlib.compress(b'{"vrcode":"VR_RAW", "value":"\xff"}'))

    with pytest.raises(RawArchiveDecodeError, match="not valid UTF-8"):
        raw_archive_payload_from_record(record)


def test_raw_archive_payload_rejects_trailing_zlib_data() -> None:
    record = raw_archive_record(
        zlib.compress(b'{"vrcode":"VR_RAW"}') + b"unexpected-trailer"
    )

    with pytest.raises(RawArchiveDecodeError, match="one complete zlib payload"):
        raw_archive_payload_from_record(record)


def test_raw_archive_payload_requires_archive_vrcode_without_payload_fallback() -> None:
    record = raw_archive_record(
        zlib.compress(b'{"vrcode":"VR_FROM_PAYLOAD"}'),
        vrcode=None,
    )

    with pytest.raises(RawArchiveDecodeError, match="requires string vrcode"):
        raw_archive_payload_from_record(record)


def test_raw_archive_payload_uses_archive_vrcode_when_payload_omits_identity() -> None:
    record = raw_archive_record(
        zlib.compress(b'{"rooms":{}}'),
        vrcode="VR_FROM_ARCHIVE",
        receivedAt=None,
    )

    payload = raw_archive_payload_from_record(record)

    assert payload.vrcode == "VR_FROM_ARCHIVE"
    assert payload.received_at is None


def test_raw_archive_payload_rejects_conflicting_archive_and_payload_vrcode() -> None:
    record = raw_archive_record(
        zlib.compress(b'{"vrcode":"VR_FROM_PAYLOAD"}'),
        vrcode="VR_FROM_ARCHIVE",
    )

    with pytest.raises(RawArchiveDecodeError, match="does not match"):
        raw_archive_payload_from_record(record)


def test_raw_archive_payload_rejects_timestamp_without_timezone() -> None:
    record = raw_archive_record(
        zlib.compress(b'{"vrcode":"VR_RAW"}'),
        receivedAt="2026-06-28T06:55:39.810",
    )

    with pytest.raises(RawArchiveDecodeError, match="must include a UTC offset"):
        raw_archive_payload_from_record(record)


@pytest.mark.parametrize("schema_version", (True, 1.0))
def test_raw_archive_payload_requires_integer_schema_version(
    schema_version: JsonValue,
) -> None:
    record = raw_archive_record(
        zlib.compress(b'{"vrcode":"VR_RAW"}'),
        schemaVersion=schema_version,
    )

    with pytest.raises(RawArchiveDecodeError, match="schemaVersion must be 1"):
        raw_archive_payload_from_record(record)


def raw_archive_record(
    payload_bytes: bytes,
    **overrides: JsonValue,
) -> dict[str, JsonValue]:
    record: dict[str, JsonValue] = {
        "schemaVersion": 1,
        "kind": "send_data_raw_payload",
        "itemId": "senddata-test",
        "vrcode": "VR_RAW",
        "receivedAt": "2026-06-28T06:55:39.810Z",
        "archivedAt": "2026-06-28T06:55:39.812Z",
        "payloadBase64": base64.b64encode(payload_bytes).decode(),
    }
    record.update(overrides)
    return record
