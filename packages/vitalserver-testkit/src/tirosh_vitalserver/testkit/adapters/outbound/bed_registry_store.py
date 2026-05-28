"""Filesystem-backed bed identity registry."""

from __future__ import annotations

import json
import logging
import threading
from pathlib import Path
from typing import Any

from tirosh_vitalserver.testkit.application.bed_registry.store import (
    bed_from_record,
    bed_to_record,
)
from tirosh_vitalserver.testkit.domain.bed import Bed
from tirosh_vitalserver.testkit.observability import emit_testkit_event


class JsonFileBedRegistryStore:
    """Persist created bed identities in one JSON file."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = threading.RLock()

    def load_beds(self) -> tuple[Bed, ...]:
        """Load every persisted bed identity."""

        with self._lock:
            payload = self._read_payload()

        beds = []
        for record in payload.get("bed_registry", []):
            if not isinstance(record, dict):
                continue
            try:
                beds.append(bed_from_record(record))
            except Exception as exc:
                emit_testkit_event(
                    "bed_registry_store.load_record.failed",
                    level=logging.WARNING,
                    path=str(self._path),
                    error=str(exc),
                )

        return tuple(beds)

    def save_beds(self, beds: tuple[Bed, ...]) -> None:
        """Persist the current bed registry."""

        with self._lock:
            self._write_payload({
                "bed_registry": [bed_to_record(bed) for bed in beds],
            })

    def delete_beds(self) -> None:
        """Remove every persisted bed identity."""

        with self._lock:
            self._write_payload({"bed_registry": []})

    def _read_payload(self) -> dict[str, Any]:
        if not self._path.exists():
            return {"bed_registry": []}

        try:
            with self._path.open("r", encoding="utf-8") as file:
                payload = json.load(file)
        except json.JSONDecodeError as exc:
            emit_testkit_event(
                "bed_registry_store.read.failed",
                level=logging.WARNING,
                path=str(self._path),
                error=str(exc),
            )
            return {"bed_registry": []}

        return payload if isinstance(payload, dict) else {"bed_registry": []}

    def _write_payload(self, payload: dict[str, Any]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self._path.with_suffix(f"{self._path.suffix}.tmp")
        with temporary_path.open("w", encoding="utf-8") as file:
            json.dump(payload, file, separators=(",", ":"), sort_keys=True)
            file.write("\n")
        temporary_path.replace(self._path)
