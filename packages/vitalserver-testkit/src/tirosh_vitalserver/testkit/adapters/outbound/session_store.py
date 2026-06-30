"""Filesystem-backed virtual VRecorder session registry."""

from __future__ import annotations

import json
import logging
import threading
from pathlib import Path
from typing import Any, cast

from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionSnapshot,
)
from tirosh_vitalserver.testkit.application.recorder_session.store import (
    SESSION_STORE_SCHEMA_VERSION,
    session_snapshot_from_record,
    session_snapshot_to_record,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event


class JsonFileVirtualRecorderSessionStore:
    """Persist virtual VRecorder session snapshots in one JSON file."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = threading.RLock()

    def load_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]:
        """Load every persisted session snapshot."""

        with self._lock:
            payload = self._read_payload()

        schema_version = session_store_schema_version(payload)
        sessions = []
        for record in payload["sessions"]:
            if not isinstance(record, dict):
                raise ValueError("session record must be an object")
            try:
                sessions.append(
                    session_snapshot_from_record(
                        record,
                        schema_version=schema_version,
                    )
                )
            except Exception as exc:
                emit_testkit_event(
                    "session_store.load_record.failed",
                    level=logging.WARNING,
                    path=str(self._path),
                    error=str(exc),
                )
                raise

        return tuple(sessions)

    def save_session(self, snapshot: VirtualRecorderSessionSnapshot) -> None:
        """Persist or replace one session snapshot."""

        with self._lock:
            payload = self._read_payload()
            records = session_records(payload)
            sessions = [
                record
                for record in records
                if record.get("session_id") != snapshot.session_id
            ]
            sessions.append(session_snapshot_to_record(snapshot))
            self._write_payload({
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": sessions,
            })

    def delete_session(self, session_id: str) -> None:
        """Remove one persisted session snapshot."""

        with self._lock:
            payload = self._read_payload()
            sessions = [
                record
                for record in session_records(payload)
                if record.get("session_id") != session_id
            ]
            self._write_payload({
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": sessions,
            })

    def delete_all_sessions(self) -> None:
        """Remove every persisted session snapshot."""

        with self._lock:
            self._write_payload({
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [],
            })

    def _read_payload(self) -> dict[str, Any]:
        if not self._path.exists():
            return {
                "schema_version": SESSION_STORE_SCHEMA_VERSION,
                "sessions": [],
            }

        try:
            with self._path.open("r", encoding="utf-8") as file:
                payload = json.load(file)
        except json.JSONDecodeError as exc:
            emit_testkit_event(
                "session_store.read.failed",
                level=logging.WARNING,
                path=str(self._path),
                error=str(exc),
            )
            raise

        if not isinstance(payload, dict):
            raise ValueError("session store payload must be an object")
        session_store_schema_version(payload)
        if not isinstance(payload.get("sessions"), list):
            raise ValueError("session store sessions must be an array")
        return payload

    def _write_payload(self, payload: dict[str, Any]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self._path.with_suffix(f"{self._path.suffix}.tmp")
        with temporary_path.open("w", encoding="utf-8") as file:
            json.dump(payload, file, separators=(",", ":"), sort_keys=True)
            file.write("\n")
        temporary_path.replace(self._path)


def session_records(payload: dict[str, Any]) -> list[dict[str, Any]]:
    records = payload["sessions"]
    if not all(isinstance(record, dict) for record in records):
        raise ValueError("session record must be an object")
    return cast(list[dict[str, Any]], records)


def session_store_schema_version(payload: dict[str, Any]) -> int:
    """Return the explicit session store schema version."""

    value = payload.get("schema_version")
    if value is None:
        raise ValueError("session store schema_version is required")
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("session store schema_version must be an integer")
    if value < SESSION_STORE_SCHEMA_VERSION:
        raise ValueError("session store schema_version is unsupported")
    if value > SESSION_STORE_SCHEMA_VERSION:
        raise ValueError("session store schema_version is newer than supported")
    return value
