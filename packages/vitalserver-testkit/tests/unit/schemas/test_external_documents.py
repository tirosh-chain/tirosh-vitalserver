from __future__ import annotations

import pytest
from pydantic import ValidationError

from tirosh_vitalserver.testkit.schemas import (
    HttpResponse,
    RealtimeMessageDocument,
    RecorderPayloadDocument,
)
from tirosh_vitalserver.testkit.schemas.recorder_dataset import (
    load_recorder_dataset_manifest,
)


def test_recorder_payload_document_validates_external_payload() -> None:
    document = RecorderPayloadDocument.from_external(
        {
            "recorder-code": {
                "roomname": "BED01",
                "trks": [],
            },
        }
    )

    internal_payload = document.to_internal()

    assert internal_payload == {
        "recorder-code": {
            "roomname": "BED01",
            "trks": [],
        },
    }


def test_recorder_payload_document_rejects_empty_payload() -> None:
    with pytest.raises(ValidationError):
        RecorderPayloadDocument.from_external({})


def test_http_response_schema_exposes_response_helpers() -> None:
    response = HttpResponse(
        status_code=200,
        headers={"content-type": "application/json"},
        body=b'{"ok":true}',
        elapsed_seconds=0.01,
    )

    assert response.ok
    assert response.text == '{"ok":true}'


def test_realtime_message_document_converts_to_internal_json_object() -> None:
    document = RealtimeMessageDocument.model_validate(
        {
            "vrcode": "recorder-code",
            "ver": "testkit",
            "rooms": {
                "recorder-code": {
                    "roomname": "BED01",
                    "trks": [],
                },
            },
        }
    )

    internal_payload = document.to_internal()

    assert internal_payload["vrcode"] == "recorder-code"
    assert internal_payload["ver"] == "testkit"


def test_recorder_dataset_manifest_selects_recommended_payload(tmp_path) -> None:
    payload_path = tmp_path / "payload.json"
    manifest_path = tmp_path / "manifest.json"
    payload_path.write_text("{}", encoding="utf-8")
    manifest_path.write_text(
        """
        {
          "schemaVersion": 1,
          "dataset": "mo-real-vital-recorder-json-120s",
          "recommendedSets": {
            "baseline": {
              "source": "source.vital",
              "payload": "payload.json",
              "payloadTrackCount": 50,
              "recordCount": 5000,
              "sampleCount": 79000,
              "devices": ["Bx50", "Primus"],
              "tags": ["high_track_count"]
            }
          },
          "payloads": []
        }
        """,
        encoding="utf-8",
    )

    manifest = load_recorder_dataset_manifest(manifest_path)

    assert manifest.dataset == "mo-real-vital-recorder-json-120s"
    assert manifest.require_recommended_payload(
        "baseline",
        manifest_path=manifest_path,
    ) == payload_path


def test_recorder_dataset_manifest_rejects_unknown_key(tmp_path) -> None:
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        """
        {
          "schemaVersion": 1,
          "dataset": "mo-real-vital-recorder-json-120s",
          "recommendedSets": {},
          "payloads": []
        }
        """,
        encoding="utf-8",
    )
    manifest = load_recorder_dataset_manifest(manifest_path)

    with pytest.raises(ValueError, match="unknown dataset key"):
        manifest.require_recommended_payload("missing", manifest_path=manifest_path)
