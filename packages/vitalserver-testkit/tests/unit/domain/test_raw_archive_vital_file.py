from __future__ import annotations

import base64
import json
import zlib

from tirosh_vitalserver.testkit.domain.vital_file import (
    raw_archive_payloads_from_jsonl_lines,
    vital_tracks_by_vrcode_from_raw_archive,
)


def test_raw_archive_payloads_decode_send_data_jsonl() -> None:
    payload = {
        "vrcode": "VR_RAW",
        "ver": "testkit",
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
