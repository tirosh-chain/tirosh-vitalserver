from __future__ import annotations

import base64
import json
import zlib
from pathlib import Path

from vitaldb import VitalFile

from tirosh_vitalserver.recorder_recovery.adapters.outbound import (
    RawArchiveVitalFileExporter,
)


def test_raw_archive_exporter_writes_vital_file(tmp_path: Path) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    output_dir = tmp_path / "exported"
    record = raw_archive_record("senddata-test", "VR_RAW", 1782620000.0, 72)
    raw_archive.write_text(json.dumps(record) + "\n", encoding="utf-8")

    artifacts = RawArchiveVitalFileExporter().export_raw_archive(
        raw_archive,
        output_dir,
    )

    assert len(artifacts) == 1
    assert artifacts[0].vrcode == "VR_RAW"
    assert artifacts[0].filename.endswith("_auto_export.vital")
    assert artifacts[0].size_bytes > 0

    vital_file = VitalFile(artifacts[0].path, header_only=True)
    assert vital_file.dtstart == 1782620000.0
    assert "VR_RAW_Demo/HR" in vital_file.get_track_names()
    assert "RecorderRecovery/METADATA" in vital_file.get_track_names()


def test_raw_archive_exporter_writes_one_vital_file_per_recorder(
    tmp_path: Path,
) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    output_dir = tmp_path / "exported"
    records = [
        raw_archive_record("senddata-a", "VR_A", 1782620000.0, 72),
        raw_archive_record("senddata-b", "VR_B", 1782620001.0, 83),
    ]
    raw_archive.write_text(
        "\n".join(json.dumps(record) for record in records) + "\n",
        encoding="utf-8",
    )

    artifacts = RawArchiveVitalFileExporter().export_raw_archive(
        raw_archive,
        output_dir,
    )

    assert [artifact.vrcode for artifact in artifacts] == ["VR_A", "VR_B"]
    assert all(
        artifact.filename.endswith("_auto_export.vital") for artifact in artifacts
    )


def raw_archive_record(
    item_id: str,
    vrcode: str,
    record_time: float,
    value: int,
) -> dict[str, object]:
    payload = {
        "vrcode": vrcode,
        "ver": "recorder",
        "rooms": {
            vrcode: {
                "roomname": vrcode,
                "trks": [
                    {
                        "name": "HR",
                        "type": "num",
                        "srate": 0,
                        "unit": "/min",
                        "mindisp": 0,
                        "maxdisp": 200,
                        "montype": "ECG_HR",
                        "recs": [{"dt": record_time, "val": value}],
                    }
                ],
            }
        },
    }
    return {
        "schemaVersion": 1,
        "kind": "send_data_raw_payload",
        "itemId": item_id,
        "vrcode": vrcode,
        "receivedAt": "2026-06-28T06:55:39.810Z",
        "archivedAt": "2026-06-28T06:55:39.812Z",
        "payloadBase64": base64.b64encode(
            zlib.compress(json.dumps(payload).encode())
        ).decode(),
    }
