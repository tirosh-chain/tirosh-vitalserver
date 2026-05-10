from __future__ import annotations

import json
from pathlib import Path
from typing import cast

from tests.support import (
    RecordingHttpHandler,
    recording_http_server,
    server_url,
)
from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.metrics import (
    recorder_visibility_result_visible,
    transfer_successful_requests,
    transfer_total_bytes_sent,
    transfer_total_requests,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.transfer import (
    send_recorder_payloads,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.visibility import (
    wait_for_recorder_visibility,
)
from tirosh_vitalserver.testkit.application.usecases.vital_file.upload import (
    upload_vital_files,
)
from tirosh_vitalserver.testkit.domain.vital_file import iter_vital_files
from tirosh_vitalserver.testkit.schemas.payloads import load_recorder_payload
from tirosh_vitalserver.testkit.types.json import JsonObject


def test_upload_vital_files_sends_multipart_payload(tmp_path: Path) -> None:
    vital_file = tmp_path / "DEMO_260509_120000.vital"
    vital_file.write_bytes(b"payload")

    with recording_http_server() as server:
        client = VitalServerClient(server_url(server))
        summary = upload_vital_files(
            client,
            iter_vital_files(vital_file),
            vrcode="TESTVRCODE",
            concurrency=1,
            repeat=2,
        )

    assert transfer_total_requests(summary) == 2
    assert transfer_successful_requests(summary) == 2
    assert transfer_total_bytes_sent(summary) == len(b"payload") * 2
    assert len(RecordingHttpHandler.requests) == 2

    path, content_type, content_length, body = RecordingHttpHandler.requests[0]
    assert path == "/upload"
    assert content_type.startswith("multipart/form-data; boundary=")
    assert content_length == len(body)
    assert b'name="vrcode"' in body
    assert b"TESTVRCODE" in body
    assert b'name="vitalfile"; filename="DEMO_260509_120000.vital"' in body
    assert b"payload" in body


def test_send_recorder_payloads_posts_json_payload(tmp_path: Path) -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "BED01",
            "seqid": 1,
            "dtstart": 1000.0,
            "dtend": 1001.0,
            "trks": [
                {
                    "name": "ECG",
                    "type": "wav",
                    "srate": 100,
                    "recs": [{"dt": 1000.1, "val": [0.1, 0.2, 0.3]}],
                }
            ],
        }
    }
    payload_path = tmp_path / "recorder.json"
    payload_path.write_text(json.dumps(recorder_payload))

    with recording_http_server() as server:
        client = VitalServerClient(server_url(server))
        summary = send_recorder_payloads(
            client,
            load_recorder_payload(payload_path),
            concurrency=2,
            repeat=3,
        )

    assert transfer_total_requests(summary) == 3
    assert transfer_successful_requests(summary) == 3
    assert transfer_total_bytes_sent(summary) > 0
    assert len(RecordingHttpHandler.requests) == 3

    path, content_type, content_length, body = RecordingHttpHandler.requests[0]
    posted_payload = cast(JsonObject, json.loads(body))
    posted_recorder = cast(JsonObject, posted_payload["recorder-code"])
    shifted_start = posted_recorder["dtstart"]

    assert path == "/api/send"
    assert content_type == "application/json"
    assert content_length == len(body)
    assert isinstance(shifted_start, int | float)
    assert shifted_start > 1000.0


def test_wait_for_recorder_visibility_uses_device_metadata_endpoint() -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "BED01",
            "trks": [],
        }
    }

    with recording_http_server() as server:
        client = VitalServerClient(server_url(server))
        results = wait_for_recorder_visibility(
            client,
            recorder_payload,
            timeout_seconds=1.0,
            interval_seconds=0.1,
        )

    assert len(results) == 1
    assert recorder_visibility_result_visible(results[0])
    assert RecordingHttpHandler.requests[0][0] == "/vr_devs"
    assert b"bedid" in RecordingHttpHandler.requests[0][3]
