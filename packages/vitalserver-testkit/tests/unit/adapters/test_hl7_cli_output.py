from __future__ import annotations

import json
from datetime import UTC, datetime

from tirosh_vitalserver.testkit.adapters.inbound.cli.hl7_output import (
    render_hl7_result_json,
)
from tirosh_vitalserver.testkit.application.usecases.server.hl7 import (
    Hl7PollResult,
    Hl7PollState,
)
from tirosh_vitalserver.testkit.schemas.hl7 import Hl7Message, Hl7Observation


def poll_result() -> Hl7PollResult:
    return Hl7PollResult(
        state=Hl7PollState.DATA,
        polled_at=datetime(2026, 9, 1, tzinfo=UTC),
        response_bytes=100,
        elapsed_seconds=0.01,
        messages=(
            Hl7Message(
                version="2.3",
                patient_id="PATIENT001",
                group="ICU",
                bed_name="BED01",
                observed_at="20260901143025",
                observations=(
                    Hl7Observation(
                        value_type="NM",
                        identifier="SpHb",
                        sub_id="0",
                        value="12.3",
                        unit="g/dL",
                        status="F",
                    ),
                ),
            ),
        ),
    )


def test_render_hl7_result_json_omits_patient_id_by_default() -> None:
    document = json.loads(
        render_hl7_result_json(poll_result(), show_patient_id=False)
    )

    assert "patientId" not in document["messages"][0]


def test_render_hl7_result_json_includes_patient_id_when_requested() -> None:
    document = json.loads(
        render_hl7_result_json(poll_result(), show_patient_id=True)
    )

    assert document["messages"][0]["patientId"] == "PATIENT001"
