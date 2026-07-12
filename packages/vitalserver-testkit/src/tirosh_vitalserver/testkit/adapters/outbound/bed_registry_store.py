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
            return self._beds_from_payload(payload)

    def save_beds(self, beds: tuple[Bed, ...]) -> None:
        """Persist the current bed registry."""

        with self._lock:
            # Do not erase a corrupt persisted registry while publishing a
            # replacement. The existing document is part of this adapter's
            # explicit state contract.
            self._beds_from_payload(self._read_payload())
            records = self._bed_records_for_write(beds)
            self._write_payload(
                {
                    "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                    "bed_registry": records,
                }
            )

    def delete_beds(self) -> None:
        """Remove every persisted bed identity."""

        with self._lock:
            # Deletion is an overwrite too; invalid stored state must remain
            # visible instead of being silently reset.
            self._beds_from_payload(self._read_payload())
            self._write_payload(
                {
                    "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                    "bed_registry": [],
                }
            )

    def _beds_from_payload(self, payload: dict[str, Any]) -> tuple[Bed, ...]:
        """Decode one complete persisted registry payload."""

        beds: list[Bed] = []
        room_names: set[str] = set()
        for record in payload["bed_registry"]:
            if not isinstance(record, dict):
                raise ValueError("bed registry record must be an object")
            try:
                bed = bed_from_record(record)
            except Exception as exc:
                emit_testkit_event(
                    "bed_registry_store.load_record.failed",
                    level=logging.WARNING,
                    path=str(self._path),
                    error=str(exc),
                )
                raise
            if bed.room_name in room_names:
                raise ValueError("bed registry store contains duplicate room_name")
            room_names.add(bed.room_name)
            beds.append(bed)

        return tuple(beds)

    def _bed_records_for_write(self, beds: tuple[Bed, ...]) -> list[dict[str, str]]:
        """Validate outgoing bed identities before persisting them."""

        records: list[dict[str, str]] = []
        room_names: set[str] = set()
        for bed in beds:
            if not isinstance(bed, Bed):
                raise ValueError("bed registry store bed must be a Bed")
            record = bed_to_record(bed)
            validated_bed = bed_from_record(record)
            if validated_bed.room_name in room_names:
                raise ValueError("bed registry store contains duplicate room_name")
            room_names.add(validated_bed.room_name)
            records.append(record)
        return records

    def _read_payload(self) -> dict[str, Any]:
        try:
            self._path.lstat()
        except FileNotFoundError:
            # A missing document is the explicit first-run empty registry.
            # lstat intentionally distinguishes a truly absent path from a
            # dangling symlink, which is an existing but unreadable contract.
            return {
                "schema_version": BED_REGISTRY_STORE_SCHEMA_VERSION,
                "bed_registry": [],
            }

        try:
            with self._path.open("r", encoding="utf-8") as file:
                payload = json.load(file)
        except (OSError, json.JSONDecodeError) as exc:
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
        if "bed_registry" not in payload:
            raise KeyError("bed_registry")
        if not isinstance(payload["bed_registry"], list):
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

    if "schema_version" not in payload:
        raise ValueError("bed registry store schema_version is required")
    value = payload["schema_version"]
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("bed registry store schema_version must be an integer")
    if value != BED_REGISTRY_STORE_SCHEMA_VERSION:
        raise ValueError("bed registry store schema_version is unsupported")
    return value
