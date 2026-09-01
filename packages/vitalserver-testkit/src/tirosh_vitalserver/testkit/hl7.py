"""Public composition helpers for polling VitalServer HL7 snapshots."""

from __future__ import annotations

from tirosh_vitalserver.testkit.adapters.outbound.hl7 import (
    VitalServerHl7FramingDecoder,
    VitalServerHl7MessageDecoder,
    VitalServerHl7ResponseDecoder,
)
from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.usecases.server.hl7 import (
    Hl7Poller,
    Hl7PollResult,
    Hl7PollState,
)
from tirosh_vitalserver.testkit.schemas.hl7 import Hl7Message, Hl7Observation


def create_hl7_decoder() -> VitalServerHl7ResponseDecoder:
    """Compose the explicit framing and message decoder adapters."""

    return VitalServerHl7ResponseDecoder(
        framing_decoder=VitalServerHl7FramingDecoder(),
        message_decoder=VitalServerHl7MessageDecoder(),
    )


def create_hl7_poller(
    base_url: str = "http://localhost",
    *,
    timeout: float = 30.0,
) -> Hl7Poller:
    """Compose the HTTP source, response decoder, and polling workflow."""

    return Hl7Poller(
        VitalServerClient(base_url, timeout=timeout),
        create_hl7_decoder(),
    )


__all__ = [
    "Hl7Message",
    "Hl7Observation",
    "Hl7PollResult",
    "Hl7PollState",
    "Hl7Poller",
    "VitalServerHl7FramingDecoder",
    "VitalServerHl7MessageDecoder",
    "VitalServerHl7ResponseDecoder",
    "create_hl7_decoder",
    "create_hl7_poller",
]
