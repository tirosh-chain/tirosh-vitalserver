from __future__ import annotations

import json
from typing import Any

from .time import utc_now_iso


def write_diagnostic_event(event: str, **fields: Any) -> None:
    """Write a structured diagnostic event to container stdout."""

    payload = {
        "schemaVersion": 1,
        "source": "vitaldb-observer",
        "event": event,
        "observedAt": utc_now_iso(),
        **fields,
    }
    print(json.dumps(payload, sort_keys=True), flush=True)
