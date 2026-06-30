"""Single virtual VRecorder session runtime."""

from __future__ import annotations

import threading
import time
import logging
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy

from tirosh_vitalserver.testkit.application.ports import (
    SessionVitalFileExporterPort,
    SessionVitalFileUploaderPort,
    SocketIoConnectorPort,
)
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeRegistry,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionSnapshot,
    VirtualRecorderSessionState,
    VirtualRecorderSessionVitalState,
)
from tirosh_vitalserver.testkit.application.recorder_session.policy import (
    session_can_pause,
    session_can_resume,
    session_can_stop,
    session_stream_stall_error,
    vital_state_after_stream_error,
    vital_state_export_failed,
    vital_state_export_ready,
    vital_state_finalizing,
    vital_state_upload_blocked,
    vital_state_upload_failed,
    vital_state_upload_succeeded,
    vital_state_uploading,
)
from tirosh_vitalserver.testkit.application.recorder_session.recording import (
    SessionPlaybackEvent,
    SessionPlaybackEventType,
    SessionRecorderPlayback,
    SessionVitalPlayback,
)
from tirosh_vitalserver.testkit.application.recorder_session.scenarios import (
    RecorderScenarioProvider,
    require_scenario_definition,
    scenario_window_for_request,
)
from tirosh_vitalserver.testkit.application.results import RealtimeStreamResult
from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalReaderPort,
    build_real_vital_recorder_payload,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.stream_loop import (
    stream_realtime_payload,
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
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    profile_for_scenario,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event
from tirosh_vitalserver.testkit.types.json import JsonObject

_STREAM_STALL_GRACE_SECONDS = 30.0
_STREAM_STALL_INTERVAL_MULTIPLIER = 10.0


class VirtualRecorderSession:
    """Owns one background virtual recorder streaming run."""

    def __init__(
        self,
        *,
        session_id: str,
        request: VirtualRecorderSessionRequest,
        connector: SocketIoConnectorPort,
        vital_file_exporter: SessionVitalFileExporterPort | None = None,
        vital_file_uploader: SessionVitalFileUploaderPort | None = None,
        real_vital_reader: RealVitalReaderPort | None = None,
        snapshot_handler: Callable[
            [VirtualRecorderSessionSnapshot],
            None,
        ]
        | None = None,
    ) -> None:
        self._session_id = session_id
        self._request = request
        self._connector = connector
        self._vital_file_exporter = vital_file_exporter
        self._vital_file_uploader = vital_file_uploader
        self._real_vital_reader = real_vital_reader
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
        self._playback_events: list[SessionPlaybackEvent] = []
        self._vital_state = VirtualRecorderSessionVitalState.for_request(request)
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
            scenario=self._request.scenario.value,
            vrcode=self._request.vrcode,
        )
        self._thread.start()

    def stop(self) -> None:
        """Request graceful session shutdown."""

        with self._lock:
            if not session_can_stop(self._state):
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
            if not session_can_pause(self._state):
                return self.snapshot()
            self._state = VirtualRecorderSessionState.PAUSED
            self._pause_event.set()
            self._record_playback_event(
                SessionPlaybackEventType.PAUSED,
                time.time(),
            )
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
            if not session_can_resume(self._state):
                return self.snapshot()
            self._state = VirtualRecorderSessionState.RUNNING
            self._pause_event.clear()
            self._record_playback_event(
                SessionPlaybackEventType.RESUMED,
                time.time(),
            )
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
                vital_state=self._vital_state,
            )

    def refresh_runtime_liveness(
        self,
        *,
        now: float | None = None,
    ) -> VirtualRecorderSessionSnapshot:
        """Fail a running session whose send_data heartbeat has stalled."""

        observed_at = time.time() if now is None else now
        with self._lock:
            snapshot = self.snapshot()
            error = session_stream_stall_error(
                snapshot,
                now=observed_at,
                timeout_seconds=stream_stall_timeout_seconds(self._request),
            )
            if error is None:
                return snapshot

            self._error = error
            self._state = VirtualRecorderSessionState.FAILED
            self._stopped_at = observed_at
            self._stop_event.set()
            self._record_playback_event(
                SessionPlaybackEventType.STOPPED,
                observed_at,
            )
            self._vital_state = vital_state_after_stream_error(
                self._vital_state,
                error,
            )
            snapshot = self.snapshot()

        emit_testkit_event(
            "session.stream_stalled",
            level=logging.WARNING,
            session_id=self._session_id,
            target_url=self._request.target_url,
            vrcode=self._request.vrcode,
            error=error,
        )
        self._publish_snapshot(snapshot)
        return snapshot

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
            self._record_playback_event(
                SessionPlaybackEventType.STARTED,
                self._started_at,
            )
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.running",
            session_id=self._session_id,
            target_url=self._request.target_url,
            recorders=self._request.recorders,
            beds=len(self._request.bed_room_names),
            scenario=self._request.scenario.value,
            vrcode=self._request.vrcode,
        )
        self._publish_snapshot(snapshot)

        try:
            results = self._stream_recorders()
            error = first_result_error(results)

            with self._lock:
                self._results = results
                if (
                    self._state == VirtualRecorderSessionState.FAILED
                    and self._error is not None
                ):
                    error = self._error
                else:
                    self._error = error
                    self._stopped_at = time.time()
                    self._record_playback_event(
                        SessionPlaybackEventType.STOPPED,
                        self._stopped_at,
                    )
                if self._error:
                    self._state = VirtualRecorderSessionState.FAILED
                    self._vital_state = vital_state_after_stream_error(
                        self._vital_state,
                        self._error,
                    )
                else:
                    self._state = VirtualRecorderSessionState.STOPPED
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
                error=self._error,
            )
            self._publish_snapshot(snapshot)
            if self._error is None:
                self._finalize_vital_artifact()
        except Exception as exc:
            with self._lock:
                self._error = str(exc)
                self._state = VirtualRecorderSessionState.FAILED
                self._stopped_at = time.time()
                self._record_playback_event(
                    SessionPlaybackEventType.STOPPED,
                    self._stopped_at,
                )
                self._vital_state = vital_state_after_stream_error(
                    self._vital_state,
                    str(exc),
                )
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
        definition = require_scenario_definition(request.scenario)
        if definition.provider != RecorderScenarioProvider.GENERATED_PROFILE:
            signal_profile = DEFAULT_SIGNAL_PROFILE
            generate_frames = False
        elif definition.signal_profile is None:
            raise ValueError(
                f"scenario {request.scenario.value} is missing signal profile"
            )
        else:
            signal_profile = profile_for_scenario(definition.signal_profile)
            generate_frames = request.generate_frames

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
                    generate_frames=generate_frames,
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

    def _finalize_vital_artifact(self) -> None:
        if not self._request.export_vital:
            return

        if self._vital_file_exporter is None:
            self._mark_vital_export_failed("vital file exporter is not configured")
            return

        with self._lock:
            self._state = VirtualRecorderSessionState.FINALIZING_VITAL
            self._vital_state = vital_state_finalizing(self._vital_state)
            snapshot = self.snapshot()
        self._publish_snapshot(snapshot)

        try:
            playback = self._vital_playback(snapshot)
            artifact = self._vital_file_exporter.export_session_vital_file(
                snapshot,
                playback,
            )
        except Exception as exc:
            self._mark_vital_export_failed(str(exc))
            return

        with self._lock:
            self._state = VirtualRecorderSessionState.VITAL_READY
            self._vital_state = vital_state_export_ready(
                self._vital_state,
                artifact,
            )
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.vital_ready",
            session_id=self._session_id,
            path=artifact.path,
            size_bytes=artifact.size_bytes,
        )
        self._publish_snapshot(snapshot)

        if self._request.upload_vital:
            self.retry_vital_upload()

    def retry_vital_upload(self) -> VirtualRecorderSessionSnapshot:
        """Upload or re-upload the generated `.vital` artifact."""

        with self._lock:
            artifact = self._vital_state.artifact
            if artifact is None:
                self._state = VirtualRecorderSessionState.UPLOAD_FAILED
                self._vital_state = vital_state_upload_blocked(
                    self._vital_state,
                    "vital artifact is not ready",
                )
                snapshot = self.snapshot()
                self._publish_snapshot(snapshot)
                return snapshot

            self._state = VirtualRecorderSessionState.UPLOADING
            self._vital_state = vital_state_uploading(self._vital_state)
            snapshot = self.snapshot()
        self._publish_snapshot(snapshot)

        if self._vital_file_uploader is None:
            return self._mark_vital_upload_failed(
                "vital file uploader is not configured"
            )

        try:
            result = self._vital_file_uploader.upload_session_vital_file(
                target_url=self._request.target_url,
                artifact_path=artifact.path,
                vrcode=self._request.vrcode,
            endpoint=self._request.vital_upload_endpoint,
            )
        except Exception as exc:
            return self._mark_vital_upload_failed(str(exc))

        with self._lock:
            if result.ok:
                self._state = VirtualRecorderSessionState.UPLOADED
                self._vital_state = vital_state_upload_succeeded(
                    self._vital_state,
                    result,
                )
            else:
                self._state = VirtualRecorderSessionState.UPLOAD_FAILED
                self._vital_state = vital_state_upload_failed(
                    self._vital_state,
                    error=result.error or "vital upload failed",
                    result=result,
                )
            snapshot = self.snapshot()
        self._publish_snapshot(snapshot)
        return snapshot

    def _mark_vital_export_failed(
        self,
        error: str,
    ) -> VirtualRecorderSessionSnapshot:
        with self._lock:
            self._state = VirtualRecorderSessionState.FAILED
            self._error = error
            self._vital_state = vital_state_export_failed(
                self._vital_state,
                error=error,
                upload_requested=self._request.upload_vital,
            )
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.vital_export_failed",
            session_id=self._session_id,
            error=error,
        )
        self._publish_snapshot(snapshot)
        return snapshot

    def _mark_vital_upload_failed(
        self,
        error: str,
    ) -> VirtualRecorderSessionSnapshot:
        with self._lock:
            self._state = VirtualRecorderSessionState.UPLOAD_FAILED
            self._vital_state = vital_state_upload_failed(
                self._vital_state,
                error=error,
            )
            snapshot = self.snapshot()
        emit_testkit_event(
            "session.vital_upload_failed",
            session_id=self._session_id,
            error=error,
        )
        self._publish_snapshot(snapshot)
        return snapshot

    def _vital_playback(
        self,
        snapshot: VirtualRecorderSessionSnapshot,
    ) -> SessionVitalPlayback:
        if snapshot.started_at is None:
            raise ValueError("session started_at is required for vital export")
        if snapshot.stopped_at is None:
            raise ValueError("session stopped_at is required for vital export")
        if not self._results:
            raise ValueError("session stream results are required for vital export")

        return SessionVitalPlayback(
            recorders=tuple(
                SessionRecorderPlayback(
                    vrcode=virtual_payload.vrcode,
                    payload=deepcopy(virtual_payload.payload),
                    messages_sent=result.messages_sent,
                )
                for virtual_payload, result in zip(
                    self._virtual_payloads,
                    self._results,
                    strict=True,
                )
            ),
            events=tuple(self._playback_events),
            started_at=snapshot.started_at,
            stopped_at=snapshot.stopped_at,
            interval_seconds=self._request.interval_seconds,
            generate_frames=self._request.generate_frames,
            scenario=self._request.scenario,
        )

    def _record_playback_event(
        self,
        event_type: SessionPlaybackEventType,
        at: float,
    ) -> None:
        self._playback_events.append(SessionPlaybackEvent(type=event_type, at=at))

    def _build_virtual_payloads(self) -> tuple[VirtualRecorderPayload, ...]:
        request = self._request
        base_vrcode = request.vrcode or unique_testkit_vrcode()
        payload = self._scenario_payload(vrcode=base_vrcode)
        return build_virtual_recorder_payloads(
            payload,
            count=request.recorders,
            vrcode=base_vrcode,
            version=request.version,
        )

    def _scenario_payload(self, *, vrcode: str) -> JsonObject:
        request = self._request
        definition = require_scenario_definition(request.scenario)
        window = scenario_window_for_request(request.window, definition)

        if definition.provider == RecorderScenarioProvider.GENERATED_PROFILE:
            return build_simulated_recorder_payload(
                room_names=request.bed_room_names,
            )

        if definition.provider == RecorderScenarioProvider.VITAL_FILE_WINDOW:
            if self._real_vital_reader is None:
                raise RuntimeError("real vital reader is not configured")
            if definition.source_path is None:
                raise ValueError(
                    f"scenario {request.scenario.value} is missing source path"
                )
            if definition.source_scenario is None:
                raise ValueError(
                    f"scenario {request.scenario.value} is missing source scenario"
                )
            return build_real_vital_recorder_payload(
                self._real_vital_reader,
                definition.source_path,
                scenario=definition.source_scenario,
                room_name=request.bedroom_name,
                start_offset_seconds=(
                    0.0 if window is None else window.start_offset_seconds or 0.0
                ),
                duration_seconds=None if window is None else window.duration_seconds,
                vrcode=vrcode,
                version=request.version,
            )

        raise ValueError(f"unsupported scenario provider: {definition.provider}")


def first_result_error(results: tuple[RealtimeStreamResult, ...]) -> str | None:
    """Return the first stream error in a result set."""

    for result in results:
        if result.error:
            return result.error

    return None


def stream_stall_timeout_seconds(request: VirtualRecorderSessionRequest) -> float:
    """Return the allowed send_data silence for one running session."""

    return max(
        _STREAM_STALL_GRACE_SECONDS,
        request.interval_seconds * _STREAM_STALL_INTERVAL_MULTIPLIER,
    )
