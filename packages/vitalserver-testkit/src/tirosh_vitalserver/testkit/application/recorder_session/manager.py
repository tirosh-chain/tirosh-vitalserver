"""Virtual VRecorder session registry."""

from __future__ import annotations

import logging
import threading
import uuid
from dataclasses import replace

from tirosh_vitalserver.testkit.application.ports import (
    RecorderManagementPort,
    SocketIoConnectorPort,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderCleanupError,
    VirtualRecorderDeletionResult,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionScenario,
    VirtualRecorderSessionSnapshot,
    VirtualRecorderSessionState,
)
from tirosh_vitalserver.testkit.application.recorder_session.session import (
    VirtualRecorderSession,
)
from tirosh_vitalserver.testkit.application.recorder_session.store import (
    VirtualRecorderSessionStorePort,
)
from tirosh_vitalserver.testkit.domain.bed import Bed
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario
from tirosh_vitalserver.testkit.errors import BedAlreadyAssignedError
from tirosh_vitalserver.testkit.observability import emit_testkit_event


_DELETE_STOP_TIMEOUT_SECONDS = 10.0


class VirtualRecorderSessionManager:
    """Thread-safe registry for virtual VRecorder sessions."""

    def __init__(
        self,
        *,
        connector: SocketIoConnectorPort,
        recorder_management: RecorderManagementPort | None = None,
        session_store: VirtualRecorderSessionStorePort | None = None,
    ) -> None:
        self._connector = connector
        self._recorder_management = recorder_management
        self._session_store = session_store
        self._sessions: dict[str, VirtualRecorderSession] = {}
        self._stored_sessions = load_stored_sessions(session_store)
        self._lock = threading.RLock()

    def start_session(
        self,
        request: VirtualRecorderSessionRequest,
    ) -> VirtualRecorderSessionSnapshot:
        """Create and start a virtual recorder session."""

        request = request_with_scenario_defaults(request)
        with self._lock:
            conflicts = active_bed_room_conflicts(
                request.bed_room_names,
                self._active_snapshots_locked(),
            )
            if conflicts:
                raise BedAlreadyAssignedError(conflicts)

            session_id = f"vrecorder-{uuid.uuid4()}"
            session = VirtualRecorderSession(
                session_id=session_id,
                request=request,
                connector=self._connector,
                snapshot_handler=self._save_snapshot,
            )
            self._sessions[session_id] = session
            self._stored_sessions[session_id] = session.snapshot()
        self._save_snapshot(session.snapshot())

        emit_testkit_event(
            "session.created",
            session_id=session_id,
            target_url=request.target_url,
            recorders=request.recorders,
            beds=len(request.bed_room_names),
            vrcode=request.vrcode,
            interval_seconds=request.interval_seconds,
            duration_seconds=request.duration_seconds,
            max_messages=request.max_messages,
            default_scenario=request.default_scenario.value,
        )
        session.start()

        snapshot = session.snapshot()
        self._save_snapshot(snapshot)
        return snapshot

    def list_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]:
        """Return snapshots for every known session."""

        with self._lock:
            sessions = tuple(self._sessions.values())
            stored = dict(self._stored_sessions)

        active_snapshots = tuple(session.snapshot() for session in sessions)
        for snapshot in active_snapshots:
            stored[snapshot.session_id] = snapshot
            self._save_snapshot(snapshot)

        return tuple(stored.values())

    def active_bed_room_names(self) -> tuple[str, ...]:
        """Return bed room names held by active or uncleared sessions."""

        with self._lock:
            snapshots = self._active_snapshots_locked()

        return tuple(sorted({
            room_name
            for snapshot in snapshots
            for room_name in snapshot.request.bed_room_names
        }))

    def has_active_sessions(self) -> bool:
        """Return whether any managed or stored session is still active."""

        with self._lock:
            return bool(self._active_snapshots_locked())

    def get_session(self, session_id: str) -> VirtualRecorderSessionSnapshot | None:
        """Return one session snapshot by id."""

        session = self._session(session_id)
        if session is None:
            with self._lock:
                return self._stored_sessions.get(session_id)

        snapshot = session.snapshot()
        self._save_snapshot(snapshot)
        return snapshot

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
        snapshot = session.snapshot()
        self._save_snapshot(snapshot)
        return snapshot

    def delete_session(self, session_id: str) -> VirtualRecorderSessionSnapshot | None:
        """Stop and remove one managed virtual recorder session."""

        session = self._session(session_id)
        if session is None:
            with self._lock:
                snapshot = self._stored_sessions.get(session_id)
            if snapshot is None:
                emit_testkit_event(
                    "session.delete.missing",
                    level=logging.WARNING,
                    session_id=session_id,
                )
                return None

            emit_testkit_event("session.delete.stored", session_id=session_id)
            cleanup_errors = self._delete_vitalserver_recorders(snapshot)
            if cleanup_errors:
                failed_snapshot = snapshot_with_cleanup_errors(snapshot, cleanup_errors)
                self._save_snapshot(failed_snapshot)
                return failed_snapshot
            self._delete_stored_snapshot(session_id)
            return snapshot

        emit_testkit_event("session.delete.requested", session_id=session_id)
        session.stop()
        if not session.wait(timeout=_DELETE_STOP_TIMEOUT_SECONDS):
            snapshot = snapshot_with_stop_timeout(
                session.snapshot(),
                timeout_seconds=_DELETE_STOP_TIMEOUT_SECONDS,
            )
            self._save_snapshot(snapshot)
            emit_testkit_event(
                "session.delete.stop_timeout",
                level=logging.WARNING,
                session_id=session_id,
                timeout_seconds=_DELETE_STOP_TIMEOUT_SECONDS,
            )
            return snapshot

        snapshot = session.snapshot()
        cleanup_errors = self._delete_vitalserver_recorders(snapshot)

        with self._lock:
            if self._sessions.get(session_id) is session:
                del self._sessions[session_id]

        if cleanup_errors:
            failed_snapshot = snapshot_with_cleanup_errors(snapshot, cleanup_errors)
            self._save_snapshot(failed_snapshot)
            emit_testkit_event(
                "session.delete.cleanup_failed",
                level=logging.WARNING,
                session_id=session_id,
                failed_recorders=len(cleanup_errors),
            )
            return failed_snapshot

        self._delete_stored_snapshot(session_id)

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
    ) -> tuple[VirtualRecorderCleanupError, ...]:
        if self._recorder_management is None:
            return ()

        errors: list[VirtualRecorderCleanupError] = []
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
                errors.append(
                    VirtualRecorderCleanupError(
                        vrcode=vrcode,
                        target_url=snapshot.request.target_url,
                        error=str(exc),
                    )
                )
                emit_testkit_event(
                    "vrecorder.delete_from_vitalserver.failed",
                    level=logging.WARNING,
                    session_id=snapshot.session_id,
                    target_url=snapshot.request.target_url,
                    vrcode=vrcode,
                    error=str(exc),
                )
        return tuple(errors)

    def delete_vitalserver_beds(
        self,
        target_url: str,
        beds: tuple[Bed, ...],
    ) -> tuple[str, ...]:
        """Best-effort cleanup for VitalServer bed assignments owned by TestKit."""

        if self._recorder_management is None:
            return ()

        errors: list[str] = []
        for bed in beds:
            try:
                self._recorder_management.delete_bed(
                    target_url,
                    bed_id=bed.bed_id,
                    bed_name=bed.room_name,
                )
                emit_testkit_event(
                    "bed.deleted_from_vitalserver",
                    target_url=target_url,
                    bed_id=bed.bed_id,
                    bed_name=bed.room_name,
                )
            except Exception as exc:
                message = f"{bed.room_name}({bed.bed_id}): {exc}"
                errors.append(message)
                emit_testkit_event(
                    "bed.delete_from_vitalserver.failed",
                    level=logging.WARNING,
                    target_url=target_url,
                    bed_id=bed.bed_id,
                    bed_name=bed.room_name,
                    error=str(exc),
                )
        return tuple(errors)

    def delete_all_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]:
        """Stop and remove every managed virtual recorder session."""

        with self._lock:
            session_ids = tuple(
                set(self._sessions.keys()) | set(self._stored_sessions.keys())
            )

        deleted = tuple(
            snapshot
            for session_id in session_ids
            if (snapshot := self.delete_session(session_id)) is not None
        )
        emit_testkit_event("sessions.reset", deleted_sessions=len(deleted))

        return deleted

    def delete_vrecorder(
        self,
        target_url: str,
        vrcode: str,
    ) -> VirtualRecorderDeletionResult:
        """Delete one VitalServer VRecorder by vrcode, independent of sessions."""

        normalized_vrcode = vrcode.strip()
        if not normalized_vrcode:
            raise ValueError("vrcode is required")
        if self._recorder_management is None:
            raise RuntimeError("recorder management is not configured")

        emit_testkit_event(
            "vrecorder.delete.requested",
            target_url=target_url,
            vrcode=normalized_vrcode,
        )
        try:
            self._recorder_management.delete_vrecorder(target_url, normalized_vrcode)
        except Exception as exc:
            emit_testkit_event(
                "vrecorder.delete.failed",
                level=logging.WARNING,
                target_url=target_url,
                vrcode=normalized_vrcode,
                error=str(exc),
            )
            return VirtualRecorderDeletionResult(
                vrcode=normalized_vrcode,
                target_url=target_url,
                deleted=False,
                error=str(exc),
            )

        emit_testkit_event(
            "vrecorder.delete.accepted",
            target_url=target_url,
            vrcode=normalized_vrcode,
        )
        return VirtualRecorderDeletionResult(
            vrcode=normalized_vrcode,
            target_url=target_url,
            deleted=True,
        )

    def wait_session(self, session_id: str, timeout: float | None = None) -> bool:
        """Wait for one session to stop."""

        session = self._session(session_id)
        if session is None:
            return False

        return session.wait(timeout=timeout)

    def _session(self, session_id: str) -> VirtualRecorderSession | None:
        with self._lock:
            return self._sessions.get(session_id)

    def _active_snapshots_locked(self) -> tuple[VirtualRecorderSessionSnapshot, ...]:
        snapshots: dict[str, VirtualRecorderSessionSnapshot] = dict(
            self._stored_sessions
        )
        for session_id, session in self._sessions.items():
            snapshots[session_id] = session.snapshot()

        return tuple(
            snapshot
            for snapshot in snapshots.values()
            if session_is_active(snapshot)
        )

    def _save_snapshot(self, snapshot: VirtualRecorderSessionSnapshot) -> None:
        with self._lock:
            self._stored_sessions[snapshot.session_id] = snapshot

        if self._session_store is None:
            return

        try:
            self._session_store.save_session(snapshot)
        except Exception as exc:
            emit_testkit_event(
                "session_store.save.failed",
                level=logging.WARNING,
                session_id=snapshot.session_id,
                error=str(exc),
            )

    def _delete_stored_snapshot(self, session_id: str) -> None:
        with self._lock:
            self._stored_sessions.pop(session_id, None)

        if self._session_store is None:
            return

        try:
            self._session_store.delete_session(session_id)
        except Exception as exc:
            emit_testkit_event(
                "session_store.delete.failed",
                level=logging.WARNING,
                session_id=session_id,
                error=str(exc),
            )


def load_stored_sessions(
    session_store: VirtualRecorderSessionStorePort | None,
) -> dict[str, VirtualRecorderSessionSnapshot]:
    """Load persisted session snapshots by id."""

    if session_store is None:
        return {}

    try:
        return {
            snapshot.session_id: snapshot
            for snapshot in session_store.load_sessions()
        }
    except Exception as exc:
        emit_testkit_event(
            "session_store.load.failed",
            level=logging.WARNING,
            error=str(exc),
        )
        return {}


def session_is_active(snapshot: VirtualRecorderSessionSnapshot) -> bool:
    """Return whether a session still owns runtime resources."""

    return snapshot.state not in (
        VirtualRecorderSessionState.STOPPED,
        VirtualRecorderSessionState.FAILED,
    )


def active_bed_room_conflicts(
    requested_room_names: tuple[str, ...],
    active_snapshots: tuple[VirtualRecorderSessionSnapshot, ...],
) -> tuple[str, ...]:
    """Return active bed room names that would be reused."""

    active_room_names = {
        room_name
        for snapshot in active_snapshots
        for room_name in snapshot.request.bed_room_names
    }

    return tuple(
        room_name
        for room_name in requested_room_names
        if room_name in active_room_names
    )


def request_with_scenario_defaults(
    request: VirtualRecorderSessionRequest,
) -> VirtualRecorderSessionRequest:
    """Apply session-level scenario defaults without hiding explicit controls."""

    match request.scenario:
        case VirtualRecorderSessionScenario.NORMAL:
            return request
        case VirtualRecorderSessionScenario.MULTIPLE_RECORDERS:
            recorders = max(request.recorders, 5)
            return replace(request, recorders=recorders)
        case VirtualRecorderSessionScenario.BURST_TRAFFIC:
            return replace(request, interval_seconds=min(request.interval_seconds, 0.1))
        case VirtualRecorderSessionScenario.DISCONNECT_RECONNECT:
            return replace(request, max_messages=request.max_messages or 3)
        case VirtualRecorderSessionScenario.STALE_RECORDER:
            return replace(request, max_messages=request.max_messages or 1)
        case VirtualRecorderSessionScenario.SIGNAL_ANOMALY:
            scenario = (
                RecorderSignalScenario.ARTIFACT
                if request.default_scenario == RecorderSignalScenario.NORMAL
                else request.default_scenario
            )
            return replace(request, default_scenario=scenario)


def snapshot_with_cleanup_errors(
    snapshot: VirtualRecorderSessionSnapshot,
    cleanup_errors: tuple[VirtualRecorderCleanupError, ...],
) -> VirtualRecorderSessionSnapshot:
    """Return a snapshot that preserves failed cleanup details for retry."""

    failed = ", ".join(error.vrcode for error in cleanup_errors)
    message = f"Failed to delete virtual VRecorder cleanup targets: {failed}"
    return replace(snapshot, error=message, cleanup_errors=cleanup_errors)


def snapshot_with_stop_timeout(
    snapshot: VirtualRecorderSessionSnapshot,
    *,
    timeout_seconds: float,
) -> VirtualRecorderSessionSnapshot:
    """Return a snapshot that keeps a still-running session visible for retry."""

    message = (
        "Timed out waiting for virtual VRecorder session to stop "
        f"after {timeout_seconds:g}s; cleanup was not run."
    )
    return replace(snapshot, error=message)
