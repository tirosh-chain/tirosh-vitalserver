from __future__ import annotations

import argparse
import base64
import json
import zlib
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.inbound.cli import vital_files


def test_recover_raw_archive_vital_exports_then_uploads(
    tmp_path: Path,
    monkeypatch,
) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    output_dir = tmp_path / "exported"
    raw_archive.write_text(json.dumps(raw_archive_record()) + "\n", encoding="utf-8")
    captured: dict[str, object] = {}

    class FakeClient:
        def __init__(self, url: str, *, timeout: float) -> None:
            captured["client"] = (url, timeout)

    def fake_upload_vital_files(client, payloads, **kwargs):
        captured["payloads"] = tuple(payloads)
        captured["kwargs"] = kwargs
        return object()

    monkeypatch.setattr(vital_files, "VitalServerClient", FakeClient)
    monkeypatch.setattr(vital_files, "upload_vital_files", fake_upload_vital_files)
    monkeypatch.setattr(vital_files, "print_summary", lambda summary: None)
    monkeypatch.setattr(
        vital_files,
        "assert_transfer_success",
        lambda summary, *, max_failure_rate: captured.setdefault(
            "max_failure_rate", max_failure_rate
        ),
    )

    result = vital_files.run_recover_raw_archive_vital(
        argparse.Namespace(
            raw_archive_path=raw_archive,
            output_dir=output_dir,
            vitalserver_url="http://vitalserver.local",
            timeout=12.0,
            vrcode=None,
            concurrency=4,
            repeat=1,
            endpoint="/upload",
            max_failure_rate=0.0,
            skip_filename_check=False,
        )
    )

    assert result == 0
    assert captured["client"] == ("http://vitalserver.local", 12.0)
    payloads = captured["payloads"]
    assert len(payloads) == 1
    assert payloads[0].path.parent == output_dir
    assert payloads[0].path.name.endswith(".vital")
    assert captured["kwargs"] == {
        "vrcode": None,
        "concurrency": 4,
        "repeat": 1,
        "endpoint": "/upload",
    }
    assert captured["max_failure_rate"] == 0.0


def raw_archive_record() -> dict[str, object]:
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
    return {
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
