"""Single virtual VRecorder session runtime."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

from tirosh_vitalserver.testkit.application.ports import SocketIoConnectorPort
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeRegistry,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionSnapshot,
    VirtualRecorderSessionState,
)
from tirosh_vitalserver.testkit.application.results import RealtimeStreamResult
from tirosh_vitalserver.testkit.application.usecases.recorder.stream_loop import (
    stream_realtime_payload,
)
from tirosh_vitalserver.testkit.domain.bed import (
    Bed,
    beds_for_room_names,
)
from tirosh_vitalserver.testkit.domain.recorder.models import (
    VirtualRecorderPayload,
)
from tirosh_vitalserver.testkit.domain.recorder.payloads import (
    build_virtual_recorder_payloads,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.templates import (
    build_simulated_recorder_payload,
    unique_testkit_vrcode,
)
from tirosh_vitalserver.testkit.domain.signal import profile_for_scenario
from tirosh_vitalserver.testkit.observability import emit_testkit_event


class VirtualRecorderSession:
    """Owns one background virtual recorder streaming run."""

    def __init__(
        self,
        *,
        session_id: str,
        request: VirtualRecorderSessionRequest,
        connector: SocketIoConnectorPort,
        snapshot_handler: Callable[
            [VirtualRecorderSessionSnapshot],
            None,
        ]
        | None = None,
    ) -> None:
        self._session_id = session_id
        self._request = request
        self._connector = connector
        self._snapshot_handler = snapshot_handler
        self._runtime_registry = RecorderRuntimeRegistry()
        self._stop_event = threading.Event()
        self._pause_event = threading.Event()
        self._lock = threading.RLock()
        self._state = VirtualRecorderSessionState.STARTING
        self._created_at = time.time()
        self._started_at: float | None = None
        self._stopped_at: float | None = None
        self._results: tuple[RealtimeStreamResult, ...] = ()
        self._error: str | None = None
        self._virtual_payloads = self._build_virtual_payloads()
        for virtual_payload in self._virtual_payloads:
            self._runtime_registry.state_for(
                vrcode=virtual_payload.vrcode,
                base_url=request.target_url,
            )
        self._thread = threading.Thread(target=self._run, daemon=True)

    @property
    def session_id(self) -> str:
        """Return the session identifier."""

        return self._session_id

    def start(self) -> None:
        """Start the background streaming thread."""

        emit_testkit_event(
            "session.starting",
            session_id=self._session_id,
            target_url=self._request.target_url,
            recorders=self._request.recorders,
            beds=len(self._request.bed_room_names),
            vrcode=self._request.vrcode,
        )
        self._thread.start()

    def stop(self) -> None:
        """Request graceful session shutdown."""

        with self._lock:
            if self._state in (
                VirtualRecorderSessionState.STOPPED,
                VirtualRecorderSessionState.FAILED,
            ):
                return
            self._state = VirtualRecorderSessionState.STOPPING
            self._stop_event.set()
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.stopping",
            session_id=self._session_id,
            target_url=self._request.target_url,
            vrcode=self._request.vrcode,
        )
        self._publish_snapshot(snapshot)

    def pause(self) -> VirtualRecorderSessionSnapshot:
        """Pause data transmission while keeping the recorder connection alive."""

        with self._lock:
            if self._state != VirtualRecorderSessionState.RUNNING:
                return self.snapshot()
            self._state = VirtualRecorderSessionState.PAUSED
            self._pause_event.set()
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.paused",
            session_id=self._session_id,
            target_url=self._request.target_url,
            vrcode=self._request.vrcode,
        )
        self._publish_snapshot(snapshot)
        return snapshot

    def resume(self) -> VirtualRecorderSessionSnapshot:
        """Resume data transmission for a paused recorder connection."""

        with self._lock:
            if self._state != VirtualRecorderSessionState.PAUSED:
                return self.snapshot()
            self._state = VirtualRecorderSessionState.RUNNING
            self._pause_event.clear()
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.resumed",
            session_id=self._session_id,
            target_url=self._request.target_url,
            vrcode=self._request.vrcode,
        )
        self._publish_snapshot(snapshot)
        return snapshot

    def wait(self, timeout: float | None = None) -> bool:
        """Wait for the session thread to stop."""

        self._thread.join(timeout=timeout)

        return not self._thread.is_alive()

    def snapshot(self) -> VirtualRecorderSessionSnapshot:
        """Return a stable snapshot of the current session state."""

        with self._lock:
            recorder_snapshots = self._runtime_registry.snapshots()
            messages_sent = sum(
                snapshot.messages_sent for snapshot in recorder_snapshots
            )
            bytes_sent = sum(snapshot.bytes_sent for snapshot in recorder_snapshots)

            if not recorder_snapshots and self._results:
                messages_sent = sum(result.messages_sent for result in self._results)
                bytes_sent = sum(result.bytes_sent for result in self._results)

            return VirtualRecorderSessionSnapshot(
                session_id=self._session_id,
                state=self._state,
                request=self._request,
                created_at=self._created_at,
                started_at=self._started_at,
                stopped_at=self._stopped_at,
                recorders=recorder_snapshots,
                messages_sent=messages_sent,
                bytes_sent=bytes_sent,
                error=self._error,
            )

    def _publish_snapshot(
        self,
        snapshot: VirtualRecorderSessionSnapshot | None = None,
    ) -> None:
        if self._snapshot_handler is None:
            return
        self._snapshot_handler(snapshot or self.snapshot())

    def _run(self) -> None:
        with self._lock:
            self._state = VirtualRecorderSessionState.RUNNING
            self._started_at = time.time()
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.running",
            session_id=self._session_id,
            target_url=self._request.target_url,
            recorders=self._request.recorders,
            beds=len(self._request.bed_room_names),
            vrcode=self._request.vrcode,
        )
        self._publish_snapshot(snapshot)

        try:
            results = self._stream_recorders()
            error = first_result_error(results)

            with self._lock:
                self._results = results
                self._error = error
                self._state = (
                    VirtualRecorderSessionState.FAILED
                    if error
                    else VirtualRecorderSessionState.STOPPED
                )
                self._stopped_at = time.time()
                snapshot = self.snapshot()
            emit_testkit_event(
                "session.failed" if error else "session.completed",
                session_id=self._session_id,
                state=self._state.value,
                target_url=self._request.target_url,
                recorders=self._request.recorders,
                beds=len(self._request.bed_room_names),
                vrcode=self._request.vrcode,
                messages_sent=sum(result.messages_sent for result in results),
                bytes_sent=sum(result.bytes_sent for result in results),
                error=error,
            )
            self._publish_snapshot(snapshot)
        except Exception as exc:
            with self._lock:
                self._error = str(exc)
                self._state = VirtualRecorderSessionState.FAILED
                self._stopped_at = time.time()
                snapshot = self.snapshot()
            emit_testkit_event(
                "session.failed",
                session_id=self._session_id,
                state=VirtualRecorderSessionState.FAILED.value,
                target_url=self._request.target_url,
                recorders=self._request.recorders,
                beds=len(self._request.bed_room_names),
                vrcode=self._request.vrcode,
                error=str(exc),
            )
            self._publish_snapshot(snapshot)

    def _stream_recorders(self) -> tuple[RealtimeStreamResult, ...]:
        request = self._request
        duration_seconds = (
            request.duration_seconds
            if request.duration_seconds is not None and request.duration_seconds > 0
            else None
        )
        signal_profile = profile_for_scenario(request.default_scenario)

        with ThreadPoolExecutor(max_workers=len(self._virtual_payloads)) as executor:
            futures = [
                executor.submit(
                    stream_realtime_payload,
                    request.target_url,
                    virtual_payload.payload,
                    interval_seconds=request.interval_seconds,
                    duration_seconds=duration_seconds,
                    max_messages=request.max_messages,
                    shift_time=request.shift_time,
                    generate_frames=request.generate_frames,
                    signal_profile=signal_profile,
                    stop_event=self._stop_event,
                    pause_event=self._pause_event,
                    runtime_state=self._runtime_registry.state_for(
                        vrcode=virtual_payload.vrcode,
                        base_url=request.target_url,
                    ),
                    connector=self._connector,
                )
                for virtual_payload in self._virtual_payloads
            ]

            return tuple(future.result() for future in futures)

    def _build_virtual_payloads(self) -> tuple[VirtualRecorderPayload, ...]:
        request = self._request
        beds = request_beds(request)
        return build_virtual_recorder_payloads(
            build_simulated_recorder_payload(
                room_names=tuple(bed.room_name for bed in beds),
            ),
            count=request.recorders,
            vrcode=request.vrcode or unique_testkit_vrcode(),
            version=request.version,
        )


def first_result_error(results: tuple[RealtimeStreamResult, ...]) -> str | None:
    """Return the first stream error in a result set."""

    for result in results:
        if result.error:
            return result.error

    return None


def request_beds(request: VirtualRecorderSessionRequest) -> tuple[Bed, ...]:
    """Return explicitly selected beds for a recorder session."""

    return beds_for_room_names(request.bed_room_names)
