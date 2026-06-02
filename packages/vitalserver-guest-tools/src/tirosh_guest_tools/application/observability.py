from __future__ import annotations

import logging
import traceback

from tirosh_guest_tools.adapters.outbound.observability.collectors import (
    OBSERVABILITY_DIR,
    collect_snapshot,
    utc_now,
)
from tirosh_guest_tools.adapters.outbound.observability.writer import (
    append_jsonl,
    write_daemon_snapshot,
    write_oneshot_snapshot,
)
from tirosh_guest_tools.domain.observability import GuestObservabilitySnapshot
from tirosh_guest_tools.domain.operations import ObservationPhase

logger = logging.getLogger(__name__)


def write_daemon_observability_snapshot() -> GuestObservabilitySnapshot:
    snapshot = collect_snapshot(detail="daemon")
    write_daemon_snapshot(snapshot)
    return snapshot


def write_guest_observability_snapshot(
    phase: ObservationPhase | str,
) -> GuestObservabilitySnapshot:
    phase_value = phase.value if isinstance(phase, ObservationPhase) else phase
    snapshot = collect_snapshot(phase=phase_value, detail="oneshot")
    write_oneshot_snapshot(phase_value, snapshot, snapshot.text_report())
    return snapshot


def record_daemon_error(error: Exception) -> None:
    OBSERVABILITY_DIR.mkdir(parents=True, exist_ok=True)
    message = {
        "schemaVersion": 1,
        "type": "daemon-error",
        "observedAt": utc_now(),
        "message": str(error),
        "traceback": traceback.format_exc(),
    }
    append_jsonl(OBSERVABILITY_DIR / "events.jsonl", message)
    logger.exception("guest observability daemon error")
