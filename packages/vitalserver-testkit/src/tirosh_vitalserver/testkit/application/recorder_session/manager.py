"""Virtual VRecorder session registry."""

from __future__ import annotations

import logging
import threading
import uuid

from tirosh_vitalserver.testkit.application.ports import (
    RecorderManagementPort,
    SocketIoConnectorPort,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionSnapshot,
)
from tirosh_vitalserver.testkit.application.recorder_session.session import (
    VirtualRecorderSession,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event


class VirtualRecorderSessionManager:
    """Thread-safe registry for virtual VRecorder sessions."""

    def __init__(
        self,
        *,
        connector: SocketIoConnectorPort,
        recorder_management: RecorderManagementPort | None = None,
    ) -> None:
        self._connector = connector
        self._recorder_management = recorder_management
        self._sessions: dict[str, VirtualRecorderSession] = {}
        self._lock = threading.RLock()

    def start_session(
        self,
        request: VirtualRecorderSessionRequest,
    ) -> VirtualRecorderSessionSnapshot:
        """Create and start a virtual recorder session."""

        session_id = f"vrecorder-{uuid.uuid4()}"
        session = VirtualRecorderSession(
            session_id=session_id,
            request=request,
            connector=self._connector,
        )

        with self._lock:
            self._sessions[session_id] = session

        emit_testkit_event(
            "session.created",
            session_id=session_id,
            target_url=request.target_url,
            recorders=request.recorders,
            vrcode=request.vrcode,
            interval_seconds=request.interval_seconds,
            duration_seconds=request.duration_seconds,
            max_messages=request.max_messages,
            default_scenario=request.default_scenario.value,
        )
        session.start()

        return session.snapshot()

    def list_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]:
        """Return snapshots for every known session."""

        with self._lock:
            sessions = tuple(self._sessions.values())

        return tuple(session.snapshot() for session in sessions)

    def get_session(self, session_id: str) -> VirtualRecorderSessionSnapshot | None:
        """Return one session snapshot by id."""

        session = self._session(session_id)

        return None if session is None else session.snapshot()

    def stop_session(self, session_id: str) -> VirtualRecorderSessionSnapshot | None:
        """Request graceful stop for one session."""

        session = self._session(session_id)
        if session is None:
            emit_testkit_event(
                "session.stop.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            return None

        emit_testkit_event("session.stop.requested", session_id=session_id)
        session.stop()

        return session.snapshot()

    def delete_session(self, session_id: str) -> VirtualRecorderSessionSnapshot | None:
        """Stop and remove one managed virtual recorder session."""

        session = self._session(session_id)
        if session is None:
            emit_testkit_event(
                "session.delete.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            return None

        emit_testkit_event("session.delete.requested", session_id=session_id)
        session.stop()
        session.wait(timeout=2)
        snapshot = session.snapshot()
        self._delete_vitalserver_recorders(snapshot)

        with self._lock:
            if self._sessions.get(session_id) is session:
                del self._sessions[session_id]

        emit_testkit_event(
            "session.deleted",
            session_id=session_id,
            state=snapshot.state.value,
            messages_sent=snapshot.messages_sent,
            bytes_sent=snapshot.bytes_sent,
        )
        return snapshot

    def _delete_vitalserver_recorders(
        self,
        snapshot: VirtualRecorderSessionSnapshot,
    ) -> None:
        if self._recorder_management is None:
            return

        vrcodes = sorted({recorder.vrcode for recorder in snapshot.recorders})
        for vrcode in vrcodes:
            try:
                self._recorder_management.delete_vrecorder(
                    snapshot.request.target_url,
                    vrcode,
                )
                emit_testkit_event(
                    "vrecorder.deleted_from_vitalserver",
                    session_id=snapshot.session_id,
                    target_url=snapshot.request.target_url,
                    vrcode=vrcode,
                )
            except Exception as exc:
                emit_testkit_event(
                    "vrecorder.delete_from_vitalserver.failed",
                    level=logging.WARNING,
                    session_id=snapshot.session_id,
                    target_url=snapshot.request.target_url,
                    vrcode=vrcode,
                    error=str(exc),
                )

    def delete_all_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]:
        """Stop and remove every managed virtual recorder session."""

        with self._lock:
            session_ids = tuple(self._sessions.keys())

        deleted = tuple(
            snapshot
            for session_id in session_ids
            if (snapshot := self.delete_session(session_id)) is not None
        )
        emit_testkit_event("sessions.reset", deleted_sessions=len(deleted))

        return deleted

    def wait_session(self, session_id: str, timeout: float | None = None) -> bool:
        """Wait for one session to stop."""

        session = self._session(session_id)
        if session is None:
            return False

        return session.wait(timeout=timeout)

    def _session(self, session_id: str) -> VirtualRecorderSession | None:
        with self._lock:
            return self._sessions.get(session_id)
