from __future__ import annotations

import pytest

from tirosh_vitalserver.testkit.adapters.outbound.hl7 import (
    VitalServerHl7FramingDecoder,
    VitalServerHl7MessageDecoder,
    VitalServerHl7ResponseDecoder,
)
from tirosh_vitalserver.testkit.errors import Hl7FramingError, Hl7SegmentError


def _message(
    *,
    patient_id: str = "PATIENT001",
    group: str = "ICU",
    bed_name: str = "BED01",
    observed_at: str = "20260901143025",
    observations: tuple[str, ...] = (
        "OBX||NM|SpHb|0|12.3|g/dL|||||F",
        "OBX||NM|PVI|0|0|%|||||F",
    ),
) -> bytes:
    segments = (
        "MSH|^~&|||||||ORU^R01|VR|P|2.3||||||8859/1",
        f"PID|||{patient_id}^^^^MR||???^\"\"||\"\"|U",
        f"PV1||I|OR^^OR&{group}&{bed_name}",
        f"OBR|||||||{observed_at}",
        *observations,
    )
    return b"\x0b" + "\n".join(segments).encode("latin-1") + b"\n\x1c\n"


def _decoder() -> VitalServerHl7ResponseDecoder:
    return VitalServerHl7ResponseDecoder(
        framing_decoder=VitalServerHl7FramingDecoder(),
        message_decoder=VitalServerHl7MessageDecoder(),
    )


def test_response_decoder_preserves_current_vitalserver_fields() -> None:
    messages = _decoder().decode(_message())

    assert len(messages) == 1
    message = messages[0]
    assert message.patient_id == "PATIENT001"
    assert message.group == "ICU"
    assert message.bed_name == "BED01"
    assert message.observed_at == "20260901143025"
    assert message.version == "2.3"
    assert [observation.identifier for observation in message.observations] == [
        "SpHb",
        "PVI",
    ]
    assert message.observations[0].value == "12.3"
    assert message.observations[0].unit == "g/dL"
    assert message.observations[0].status == "F"
    assert message.observations[1].value == "0"


def test_response_decoder_reads_concatenated_bed_messages() -> None:
    messages = _decoder().decode(
        _message(patient_id="A", bed_name="BED01")
        + _message(patient_id="B", bed_name="BED02")
    )

    assert [message.patient_id for message in messages] == ["A", "B"]
    assert [message.bed_name for message in messages] == ["BED01", "BED02"]


def test_response_decoder_returns_explicit_empty_result() -> None:
    assert _decoder().decode(b"") == ()


def test_framing_decoder_rejects_unframed_payload() -> None:
    with pytest.raises(Hl7FramingError, match="start byte"):
        VitalServerHl7FramingDecoder().decode(b"MSH|^~&|unframed")


def test_message_decoder_rejects_missing_required_segment() -> None:
    payload = _message().replace(b"OBR|||||||20260901143025\n", b"")
    frame = VitalServerHl7FramingDecoder().decode(payload)[0]

    with pytest.raises(Hl7SegmentError, match="OBR"):
        VitalServerHl7MessageDecoder().decode(frame)


def test_message_decoder_preserves_empty_observation_value() -> None:
    payload = _message(observations=("OBX||NM|PVI|0||%|||||F",))
    frame = VitalServerHl7FramingDecoder().decode(payload)[0]

    message = VitalServerHl7MessageDecoder().decode(frame)

    assert message.observations[0].value == ""
