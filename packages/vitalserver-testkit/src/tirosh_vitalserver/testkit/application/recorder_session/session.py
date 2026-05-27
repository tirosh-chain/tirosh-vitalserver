"""Single virtual VRecorder session runtime."""

from __future__ import annotations

import threading
import time
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
from tirosh_vitalserver.testkit.domain.recorder.payloads import (
    build_virtual_recorder_payloads,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.templates import (
    build_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.signal import profile_for_scenario


class VirtualRecorderSession:
    """Owns one background virtual recorder streaming run."""

    def __init__(
        self,
        *,
        session_id: str,
        request: VirtualRecorderSessionRequest,
        connector: SocketIoConnectorPort,
    ) -> None:
        self._session_id = session_id
        self._request = request
        self._connector = connector
        self._runtime_registry = RecorderRuntimeRegistry()
        self._stop_event = threading.Event()
        self._lock = threading.RLock()
        self._state = VirtualRecorderSessionState.STARTING
        self._created_at = time.time()
        self._started_at: float | None = None
        self._stopped_at: float | None = None
        self._results: tuple[RealtimeStreamResult, ...] = ()
        self._error: str | None = None
        self._thread = threading.Thread(target=self._run, daemon=True)

    @property
    def session_id(self) -> str:
        """Return the session identifier."""

        return self._session_id

    def start(self) -> None:
        """Start the background streaming thread."""

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

    def _run(self) -> None:
        with self._lock:
            self._state = VirtualRecorderSessionState.RUNNING
            self._started_at = time.time()

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
        except Exception as exc:
            with self._lock:
                self._error = str(exc)
                self._state = VirtualRecorderSessionState.FAILED
                self._stopped_at = time.time()

    def _stream_recorders(self) -> tuple[RealtimeStreamResult, ...]:
        request = self._request
        payload = build_simulated_recorder_payload()
        virtual_payloads = build_virtual_recorder_payloads(
            payload,
            count=request.recorders,
            vrcode=request.vrcode,
            version=request.version,
        )
        duration_seconds = (
            request.duration_seconds
            if request.duration_seconds is not None and request.duration_seconds > 0
            else None
        )
        signal_profile = profile_for_scenario(request.default_scenario)

        with ThreadPoolExecutor(max_workers=len(virtual_payloads)) as executor:
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
                    runtime_state=self._runtime_registry.state_for(
                        vrcode=virtual_payload.vrcode,
                        base_url=request.target_url,
                    ),
                    connector=self._connector,
                )
                for virtual_payload in virtual_payloads
            ]

            return tuple(future.result() for future in futures)


def first_result_error(results: tuple[RealtimeStreamResult, ...]) -> str | None:
    """Return the first stream error in a result set."""

    for result in results:
        if result.error:
            return result.error

    return None
