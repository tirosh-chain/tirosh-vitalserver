from __future__ import annotations

import pytest
from pydantic import ValidationError

from tirosh_vitalserver.testkit.schemas import (
    HttpResponse,
    RealtimeMessageDocument,
    RecorderPayloadDocument,
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
