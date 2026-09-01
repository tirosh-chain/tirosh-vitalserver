"""Public composition helpers for polling VitalServer HL7 snapshots."""

from __future__ import annotations

from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.usecases.server.hl7 import (
    Hl7Poller,
    Hl7PollResult,
    Hl7PollState,
)
from tirosh_vitalserver.testkit.domain.hl7 import (
    Hl7Message,
    Hl7Observation,
    parse_hl7_stream,
)


def create_hl7_poller(
    base_url: str = "http://localhost",
    *,
    timeout: float = 30.0,
) -> Hl7Poller:
    """Create a poller backed by the standard-library VitalServer HTTP client."""

    return Hl7Poller(VitalServerClient(base_url, timeout=timeout))


__all__ = [
    "Hl7Message",
    "Hl7Observation",
    "Hl7PollResult",
    "Hl7PollState",
    "Hl7Poller",
    "create_hl7_poller",
    "parse_hl7_stream",
]
