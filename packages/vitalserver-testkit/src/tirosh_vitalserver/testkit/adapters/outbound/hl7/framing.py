"""Decoder for the MLLP-like framing used by legacy VitalServer."""

from __future__ import annotations

from tirosh_vitalserver.testkit.errors import Hl7FramingError


class VitalServerHl7FramingDecoder:
    """Split one HTTP response body into explicitly framed HL7 messages."""

    start_byte = 0x0B
    end_byte = 0x1C

    def decode(self, payload: bytes) -> tuple[bytes, ...]:
        """Return every framed message while rejecting malformed boundaries."""

        if payload == b"":
            return ()

        frames: list[bytes] = []
        cursor = 0

        while cursor < len(payload):
            while cursor < len(payload) and payload[cursor] in (0x0A, 0x0D):
                cursor += 1

            if cursor == len(payload):
                break

            if payload[cursor] != self.start_byte:
                raise Hl7FramingError(
                    f"expected HL7 start byte 0x0b at offset {cursor}"
                )

            frame_start = cursor + 1
            frame_end = payload.find(bytes((self.end_byte,)), frame_start)
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
