"""JSON Lines presentation for parsed VitalServer HL7 polling results."""

from __future__ import annotations

import json

from tirosh_vitalserver.testkit.application.usecases.server.hl7 import Hl7PollResult


def render_hl7_result_json(
    result: Hl7PollResult,
    *,
    show_patient_id: bool,
) -> str:
    """Render one poll result without exposing patient identity by default."""

    messages: list[dict[str, object]] = []
    for message in result.messages:
        document: dict[str, object] = {
            "version": message.version,
            "group": message.group,
            "bedName": message.bed_name,
            "observedAt": message.observed_at,
            "observations": [
                {
                    "valueType": observation.value_type,
                    "identifier": observation.identifier,
                    "subId": observation.sub_id,
                    "value": observation.value,
                    "unit": observation.unit,
                    "status": observation.status,
                }
                for observation in message.observations
            ],
        }
        if show_patient_id:
            document["patientId"] = message.patient_id
        messages.append(document)

    return json.dumps(
        {
            "state": result.state.value,
            "polledAt": result.polled_at.isoformat(),
            "responseBytes": result.response_bytes,
            "elapsedSeconds": result.elapsed_seconds,
            "messages": messages,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
