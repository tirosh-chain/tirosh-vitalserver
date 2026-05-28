"""Filesystem-backed virtual VRecorder session registry."""

from __future__ import annotations

import json
import logging
import threading
from pathlib import Path
from typing import Any

from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionSnapshot,
)
from tirosh_vitalserver.testkit.application.recorder_session.store import (
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

        sessions = []
        for record in payload.get("sessions", []):
            if not isinstance(record, dict):
                continue
            try:
                sessions.append(session_snapshot_from_record(record))
            except Exception as exc:
                emit_testkit_event(
                    "session_store.load_record.failed",
                    level=logging.WARNING,
                    path=str(self._path),
                    error=str(exc),
                )

        return tuple(sessions)

    def save_session(self, snapshot: VirtualRecorderSessionSnapshot) -> None:
        """Persist or replace one session snapshot."""

        with self._lock:
            payload = self._read_payload()
            sessions = [
                record
                for record in payload.get("sessions", [])
                if isinstance(record, dict)
                and record.get("session_id") != snapshot.session_id
            ]
            sessions.append(session_snapshot_to_record(snapshot))
            self._write_payload({"sessions": sessions})

    def delete_session(self, session_id: str) -> None:
        """Remove one persisted session snapshot."""

        with self._lock:
            payload = self._read_payload()
            sessions = [
                record
                for record in payload.get("sessions", [])
                if isinstance(record, dict)
                and record.get("session_id") != session_id
            ]
            self._write_payload({"sessions": sessions})

    def delete_all_sessions(self) -> None:
        """Remove every persisted session snapshot."""

        with self._lock:
            self._write_payload({"sessions": []})

    def _read_payload(self) -> dict[str, Any]:
        if not self._path.exists():
            return {"sessions": []}

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
            return {"sessions": []}

        return payload if isinstance(payload, dict) else {"sessions": []}

    def _write_payload(self, payload: dict[str, Any]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self._path.with_suffix(f"{self._path.suffix}.tmp")
        with temporary_path.open("w", encoding="utf-8") as file:
            json.dump(payload, file, separators=(",", ":"), sort_keys=True)
            file.write("\n")
        temporary_path.replace(self._path)
