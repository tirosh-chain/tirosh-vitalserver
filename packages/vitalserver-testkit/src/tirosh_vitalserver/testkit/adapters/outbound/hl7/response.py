"""Response-level composition for the legacy VitalServer HL7 decoder."""

from __future__ import annotations

from dataclasses import dataclass

from tirosh_vitalserver.testkit.adapters.outbound.hl7.framing import (
    VitalServerHl7FramingDecoder,
)
from tirosh_vitalserver.testkit.adapters.outbound.hl7.message import (
    VitalServerHl7MessageDecoder,
)
from tirosh_vitalserver.testkit.schemas.hl7 import Hl7Message


@dataclass(frozen=True, slots=True)
class VitalServerHl7ResponseDecoder:
    """Compose framing and message decoders for one HTTP response body."""

    framing_decoder: VitalServerHl7FramingDecoder
    message_decoder: VitalServerHl7MessageDecoder

    def decode(self, payload: bytes) -> tuple[Hl7Message, ...]:
        """Decode every framed message without converting failures to empty data."""

        frames = self.framing_decoder.decode(payload)
        return tuple(self.message_decoder.decode(frame) for frame in frames)
