from __future__ import annotations

import base64
import json
import zlib
from pathlib import Path

from vitaldb import VitalFile

from tirosh_vitalserver.testkit.adapters.outbound.raw_archive_vital_artifact import (
    RawArchiveVitalFileExporter,
)


def test_raw_archive_exporter_writes_vital_file(tmp_path: Path) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    output_dir = tmp_path / "exported"
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
    raw_archive.write_text(json.dumps(record) + "\n", encoding="utf-8")

    artifacts = RawArchiveVitalFileExporter().export_raw_archive(
        raw_archive,
        output_dir,
    )

    assert len(artifacts) == 1
    assert artifacts[0].vrcode == "VR_RAW"
    assert artifacts[0].filename.endswith(".vital")
    assert artifacts[0].size_bytes > 0

    vital_file = VitalFile(artifacts[0].path, header_only=True)
    assert vital_file.dtstart == 1782620000.0
    assert "OR1_Demo/HR" in vital_file.get_track_names()
    assert "TestKit/METADATA" in vital_file.get_track_names()
