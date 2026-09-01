"""Pure parser for the legacy VitalServer ``/HL7`` response contract."""

from __future__ import annotations

from dataclasses import dataclass

from tirosh_vitalserver.testkit.errors import Hl7FramingError, Hl7SegmentError

MLLP_START = 0x0B
MLLP_END = 0x1C


@dataclass(frozen=True, slots=True)
class Hl7Observation:
    """One OBX observation without interpreting or defaulting its value."""

    value_type: str
    identifier: str
    sub_id: str
    value: str
    unit: str
    status: str


@dataclass(frozen=True, slots=True)
class Hl7Message:
    """One bed-level ORU message emitted by the legacy VitalServer endpoint."""

    version: str
    patient_id: str
    group: str
    bed_name: str
    observed_at: str
    observations: tuple[Hl7Observation, ...]


def parse_hl7_stream(payload: bytes) -> tuple[Hl7Message, ...]:
    """Parse all MLLP-like messages returned by ``GET /HL7``.

    VitalServer returns an empty body when it has no eligible observations. That
    state is valid and remains distinct from malformed framing or segments.
    """

    if payload == b"":
        return ()

    frames = _split_frames(payload)
    return tuple(_parse_frame(frame) for frame in frames)


def _split_frames(payload: bytes) -> tuple[bytes, ...]:
    frames: list[bytes] = []
    cursor = 0

    while cursor < len(payload):
        while cursor < len(payload) and payload[cursor] in (0x0A, 0x0D):
            cursor += 1

        if cursor == len(payload):
            break

        if payload[cursor] != MLLP_START:
            raise Hl7FramingError(
                f"expected HL7 start byte 0x0b at offset {cursor}"
            )

        frame_start = cursor + 1
        frame_end = payload.find(bytes((MLLP_END,)), frame_start)
        if frame_end < 0:
            raise Hl7FramingError(
                f"missing HL7 end byte 0x1c after offset {cursor}"
            )
        if frame_end == frame_start:
            raise Hl7FramingError(f"empty HL7 frame at offset {cursor}")

        frames.append(payload[frame_start:frame_end])
        cursor = frame_end + 1

    if not frames:
        raise Hl7FramingError("HL7 response did not contain a framed message")

    return tuple(frames)


def _parse_frame(frame: bytes) -> Hl7Message:
    text = frame.decode("latin-1")
    segments = tuple(segment for segment in text.splitlines() if segment != "")
    if not segments:
        raise Hl7SegmentError("HL7 frame has no segments")

    msh = _required_segment(segments, "MSH")
    pid = _required_segment(segments, "PID")
    pv1 = _required_segment(segments, "PV1")
    obr = _required_segment(segments, "OBR")
    obx_segments = tuple(
        segment.split("|") for segment in segments if segment.startswith("OBX|")
    )
    if not obx_segments:
        raise Hl7SegmentError("HL7 frame requires at least one OBX segment")

    msh_fields = msh.split("|")
    pid_fields = pid.split("|")
    pv1_fields = pv1.split("|")
    obr_fields = obr.split("|")
    _require_field_count("MSH", msh_fields, 12)
    _require_field_count("PID", pid_fields, 4)
    _require_field_count("PV1", pv1_fields, 4)
    _require_field_count("OBR", obr_fields, 8)

    observed_at = obr_fields[7]
    if len(observed_at) != 14 or not observed_at.isdigit():
        raise Hl7SegmentError(
            "OBR observation timestamp must use YYYYMMDDHHMMSS"
        )

    group, bed_name = _parse_location(pv1_fields[3])
    observations = tuple(_parse_observation(fields) for fields in obx_segments)

    return Hl7Message(
        version=msh_fields[11],
        patient_id=pid_fields[3].split("^", maxsplit=1)[0],
        group=group,
        bed_name=bed_name,
        observed_at=observed_at,
        observations=observations,
    )


def _required_segment(segments: tuple[str, ...], name: str) -> str:
    matches = tuple(segment for segment in segments if segment.startswith(f"{name}|"))
    if len(matches) != 1:
        raise Hl7SegmentError(
            f"HL7 frame requires exactly one {name} segment; found {len(matches)}"
        )
    return matches[0]


def _require_field_count(name: str, fields: list[str], minimum: int) -> None:
    if len(fields) < minimum:
        raise Hl7SegmentError(
            f"{name} segment requires at least {minimum} fields; found {len(fields)}"
        )


def _parse_location(field: str) -> tuple[str, str]:
    components = field.split("^")
    if len(components) < 3:
        raise Hl7SegmentError(
            "PV1 location requires the VitalServer OR^^OR&group&bed form"
        )

    facility_parts = components[2].split("&")
    if len(facility_parts) < 3:
        raise Hl7SegmentError("PV1 location requires explicit group and bed fields")

    return facility_parts[1], facility_parts[2]


def _parse_observation(fields: list[str]) -> Hl7Observation:
    _require_field_count("OBX", fields, 12)
    if fields[3] == "":
        raise Hl7SegmentError("OBX observation identifier must not be empty")

    return Hl7Observation(
        value_type=fields[2],
        identifier=fields[3],
        sub_id=fields[4],
        value=fields[5],
        unit=fields[6],
        status=fields[11],
    )
