from __future__ import annotations

import logging
import traceback
from typing import Any

from tirosh_guest_tools.domain.operations import ObservationPhase
from tirosh_guest_tools.observability.collectors import (
    OBSERVABILITY_DIR,
    collect_snapshot,
    collect_text_report,
    utc_now,
)
from tirosh_guest_tools.observability.writer import (
    append_jsonl,
    write_daemon_snapshot,
    write_oneshot_snapshot,
)

logger = logging.getLogger(__name__)


def write_daemon_observability_snapshot() -> dict[str, Any]:
    snapshot = collect_snapshot(detail="daemon")
    write_daemon_snapshot(snapshot)
    return snapshot


def write_guest_observability_snapshot(
    phase: ObservationPhase | str,
) -> dict[str, Any]:
    phase_value = phase.value if isinstance(phase, ObservationPhase) else phase
    snapshot = collect_snapshot(phase=phase_value, detail="oneshot")
    write_oneshot_snapshot(phase_value, snapshot, collect_text_report(snapshot))
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
