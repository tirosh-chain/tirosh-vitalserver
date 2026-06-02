from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

from tirosh_guest_tools.adapters.outbound.observability.collectors import (
    OBSERVABILITY_DIR,
)
from tirosh_guest_tools.domain.observability import GuestObservabilitySnapshot
from tirosh_guest_tools.domain.operations import ObservationPhase

PHASE_PATTERN = re.compile(r"[^A-Za-z0-9_.-]+")


def write_json(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def append_jsonl(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(document, sort_keys=True))
        handle.write("\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def safe_phase(phase: str) -> str:
    value = PHASE_PATTERN.sub("-", phase.strip())
    return value.strip("-") or ObservationPhase.MANUAL.value


def write_daemon_snapshot(snapshot: GuestObservabilitySnapshot) -> None:
    document = snapshot.as_json()
    write_json(OBSERVABILITY_DIR / "latest.json", document)
    append_jsonl(OBSERVABILITY_DIR / "history.jsonl", document)
    if document.get("collectorErrors"):
        append_jsonl(
            OBSERVABILITY_DIR / "events.jsonl",
            {
                "schemaVersion": 1,
                "type": "collector-errors",
                "observedAt": document.get("observedAt"),
                "collectorErrors": document.get("collectorErrors"),
            },
        )


def write_oneshot_snapshot(
    phase: str,
    snapshot: GuestObservabilitySnapshot,
    text_report: str,
) -> None:
    safe = safe_phase(phase)
    document = snapshot.as_json()
    timestamp = str(document.get("observedAt", "")).replace(":", "").replace("-", "")
    timestamp = timestamp.replace(".", "").replace("Z", "Z")
    base_name = f"{timestamp}-{safe}"
    snapshots = OBSERVABILITY_DIR / "snapshots"
    write_json(snapshots / f"{base_name}.json", document)
    write_text(snapshots / f"{base_name}.log", text_report)
    write_json(OBSERVABILITY_DIR / f"{safe}.latest.json", document)
    write_text(OBSERVABILITY_DIR / f"{safe}.latest.log", text_report)
