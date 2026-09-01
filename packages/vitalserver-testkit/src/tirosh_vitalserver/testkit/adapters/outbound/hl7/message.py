"""Decoder for one legacy VitalServer HL7 ORU message."""

from __future__ import annotations

from tirosh_vitalserver.testkit.errors import Hl7EncodingError, Hl7SegmentError
from tirosh_vitalserver.testkit.schemas.hl7 import Hl7Message, Hl7Observation


class VitalServerHl7MessageDecoder:
    """Decode one framed message into the explicit TestKit HL7 contract."""

    def decode(self, frame: bytes) -> Hl7Message:
        """Decode one UTF-8 frame and preserve required segment field values.

        ``MSH-18`` is legacy message text. It does not select a transport
        encoding.
        """

        try:
            text = frame.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise Hl7EncodingError("HL7 frame is not valid UTF-8") from exc
        segments = tuple(segment for segment in text.splitlines() if segment != "")
        if not segments:
            raise Hl7SegmentError("HL7 frame has no segments")

        indexed_segments: dict[str, list[list[str]]] = {}
        for segment in segments:
            fields = segment.split("|")
            indexed_segments.setdefault(fields[0], []).append(fields)

        required_field_counts = {
            "MSH": 12,
            "PID": 4,
            "PV1": 4,
            "OBR": 8,
        }
        required_segments: dict[str, list[str]] = {}
        for name, minimum_fields in required_field_counts.items():
            matches = indexed_segments.get(name, [])
            if len(matches) != 1:
                raise Hl7SegmentError(
                    f"HL7 frame requires exactly one {name} segment; "
                    f"found {len(matches)}"
                )
            fields = matches[0]
            if len(fields) < minimum_fields:
                raise Hl7SegmentError(
                    f"{name} segment requires at least {minimum_fields} fields; "
                    f"found {len(fields)}"
                )
            required_segments[name] = fields

        obx_segments = indexed_segments.get("OBX", [])
        if not obx_segments:
            raise Hl7SegmentError("HL7 frame requires at least one OBX segment")

        msh_fields = required_segments["MSH"]
        pid_fields = required_segments["PID"]
        pv1_fields = required_segments["PV1"]
        obr_fields = required_segments["OBR"]

        observed_at = obr_fields[7]
        if len(observed_at) != 14 or not observed_at.isdigit():
            raise Hl7SegmentError(
                "OBR observation timestamp must use YYYYMMDDHHMMSS"
            )

        location_components = pv1_fields[3].split("^")
        if len(location_components) < 3:
            raise Hl7SegmentError(
                "PV1 location requires the VitalServer OR^^OR&group&bed form"
            )
        facility_parts = location_components[2].split("&")
        if len(facility_parts) < 3:
            raise Hl7SegmentError(
                "PV1 location requires explicit group and bed fields"
            )

        observations: list[Hl7Observation] = []
        for fields in obx_segments:
            if len(fields) < 12:
                raise Hl7SegmentError(
                    "OBX segment requires at least 12 fields; "
                    f"found {len(fields)}"
                )
            if fields[3] == "":
                raise Hl7SegmentError(
                    "OBX observation identifier must not be empty"
                )
            observations.append(
                Hl7Observation(
                    value_type=fields[2],
                    identifier=fields[3],
                    sub_id=fields[4],
                    value=fields[5],
                    unit=fields[6],
                    status=fields[11],
                )
            )

        return Hl7Message(
            version=msh_fields[11],
            patient_id=pid_fields[3].split("^", maxsplit=1)[0],
            group=facility_parts[1],
            bed_name=facility_parts[2],
            observed_at=observed_at,
            observations=tuple(observations),
        )
