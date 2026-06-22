"""Filesystem-backed bed identity registry."""

from __future__ import annotations

import json
import logging
import threading
from pathlib import Path
from typing import Any

from tirosh_vitalserver.testkit.application.bed_registry.store import (
    BED_REGISTRY_STORE_SCHEMA_VERSION,
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
        for record in payload["bed_registry"]:
            if not isinstance(record, dict):
                raise ValueError("bed registry record must be an object")
            try:
                beds.append(bed_from_record(record))
            except Exception as exc:
                emit_testkit_event(
                    "bed_registry_store.load_record.failed",
                    level=logging.WARNING,
                    path=str(self._path),
                    error=str(exc),
                )
                raise

        return tuple(beds)

    def save_beds(self, beds: tuple[Bed, ...]) -> None:
        """Persist the current bed registry."""

        with self._lock:
            self._write_payload({
                "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                "bed_registry": [bed_to_record(bed) for bed in beds],
            })

    def delete_beds(self) -> None:
        """Remove every persisted bed identity."""

        with self._lock:
            self._write_payload({
                "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                "bed_registry": [],
            })

    def _read_payload(self) -> dict[str, Any]:
        if not self._path.exists():
            return {
                "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                "bed_registry": [],
            }

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
            raise

        if not isinstance(payload, dict):
            raise ValueError("bed registry store payload must be an object")
        bed_registry_store_schema_version(payload)
        if not isinstance(payload.get("bed_registry"), list):
            raise ValueError("bed registry store bed_registry must be an array")
        return payload

    def _write_payload(self, payload: dict[str, Any]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self._path.with_suffix(f"{self._path.suffix}.tmp")
        with temporary_path.open("w", encoding="utf-8") as file:
            json.dump(payload, file, separators=(",", ":"), sort_keys=True)
            file.write("\n")
        temporary_path.replace(self._path)


def bed_registry_store_schema_version(payload: dict[str, Any]) -> int:
    """Return the explicit bed registry store schema version."""

    value = payload.get("schema_version")
    if value is None:
        return BED_REGISTRY_STORE_SCHEMA_VERSION
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("bed registry store schema_version must be an integer")
    if value != BED_REGISTRY_STORE_SCHEMA_VERSION:
        raise ValueError("bed registry store schema_version is unsupported")
    return value
