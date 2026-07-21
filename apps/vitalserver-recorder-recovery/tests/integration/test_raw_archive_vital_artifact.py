from __future__ import annotations

import base64
import hashlib
import json
import re
import zlib
from pathlib import Path
from typing import Any

from vitaldb import VitalFile

from tirosh_vitalserver.recorder_recovery.adapters.outbound import (
    RawArchiveVitalFileExporter,
)
from tirosh_vitalserver.recorder_recovery.domain import RecoveryArtifactOrigin


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
    assert re.fullmatch(r"VR_RAW_\d{6}_\d{6}\.vital", artifacts[0].filename)
    assert artifacts[0].size_bytes > 0
    assert artifacts[0].origin is RecoveryArtifactOrigin.COLD_PATH_RECOVERY
    assert artifacts[0].room_names == ("VR_RAW",)
    assert artifacts[0].source_start_offset == 0
    assert artifacts[0].source_end_offset == raw_archive.stat().st_size
    assert artifacts[0].format_version == 3
    assert artifacts[0].track_count == 2
    assert artifacts[0].sha256 == hashlib.sha256(
        Path(artifacts[0].path).read_bytes()
    ).hexdigest()
    assert len(artifacts[0].artifact_id) == 64

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
    assert [artifact.room_names for artifact in artifacts] == [("VR_A",), ("VR_B",)]
    assert all(
        re.fullmatch(r"VR_[AB]_\d{6}_\d{6}\.vital", artifact.filename)
        for artifact in artifacts
    )


def test_raw_archive_exporter_filters_one_recorder_and_byte_window(
    tmp_path: Path,
) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    output_dir = tmp_path / "exported"
    first = json.dumps(
        raw_archive_record("senddata-a-1", "VR_A", 1782620000.0, 72)
    ) + "\n"
    skipped = json.dumps(
        raw_archive_record("senddata-b", "VR_B", 1782620001.0, 83)
    ) + "\n"
    selected = json.dumps(
        raw_archive_record("senddata-a-2", "VR_A", 1782620002.0, 74)
    ) + "\n"
    raw_archive.write_text(first + skipped + selected, encoding="utf-8")

    artifacts = RawArchiveVitalFileExporter().export_raw_archive(
        raw_archive,
        output_dir,
        vrcode="VR_A",
        start_offset=len(first.encode()),
        end_offset=len((first + skipped + selected).encode()),
    )

    assert [artifact.vrcode for artifact in artifacts] == ["VR_A"]
    vital_file = VitalFile(artifacts[0].path, header_only=True)
    assert vital_file.dtstart == 1782620002.0


def test_raw_archive_export_retry_has_deterministic_identity(tmp_path: Path) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    record = raw_archive_record("senddata-test", "VR_RAW", 1782620000.0, 72)
    raw_archive.write_text(json.dumps(record) + "\n", encoding="utf-8")
    exporter = RawArchiveVitalFileExporter()

    first = exporter.export_raw_archive(raw_archive, tmp_path / "first")[0]
    second = exporter.export_raw_archive(raw_archive, tmp_path / "second")[0]

    assert second.artifact_id == first.artifact_id
    assert second.sha256 == first.sha256


def test_raw_archive_exporter_keeps_long_recording_as_one_artifact(
    tmp_path: Path,
) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    records = [
        raw_archive_record("first", "VR_RAW", 1782620000.0, 72),
        raw_archive_record("second", "VR_RAW", 1782620301.0, 73),
    ]
    raw_archive.write_text(
        "\n".join(json.dumps(record) for record in records) + "\n",
        encoding="utf-8",
    )

    artifacts = RawArchiveVitalFileExporter().export_raw_archive(
        raw_archive,
        tmp_path / "exported",
    )

    assert len(artifacts) == 1
    assert artifacts[0].coverage_started_at == 1782620000.0
    assert artifacts[0].coverage_ended_at >= 1782620301.0
    assert not tuple(tmp_path.glob(".raw-archive-vital-spool-*"))


def test_raw_archive_exporter_does_not_read_the_whole_archive_with_path_read_bytes(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    output_dir = tmp_path / "exported"
    first = json.dumps(
        raw_archive_record("senddata-a-1", "VR_A", 1782620000.0, 72)
    ) + "\n"
    second = json.dumps(
        raw_archive_record("senddata-a-2", "VR_A", 1782620001.0, 73)
    ) + "\n"
    raw_archive.write_text(first + second, encoding="utf-8")

    def fail_read_bytes(_path: Path) -> bytes:
        raise AssertionError("raw archive must not be loaded with Path.read_bytes")

    monkeypatch.setattr(Path, "read_bytes", fail_read_bytes)

    artifacts = RawArchiveVitalFileExporter().export_raw_archive(
        raw_archive,
        output_dir,
        start_offset=len(first.encode()),
        end_offset=len((first + second).encode()),
    )

    assert [artifact.vrcode for artifact in artifacts] == ["VR_A"]


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
