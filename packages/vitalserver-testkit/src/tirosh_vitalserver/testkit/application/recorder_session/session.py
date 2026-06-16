"""Single virtual VRecorder session runtime."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from dataclasses import replace

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
    VirtualRecorderVitalExportStatus,
    VirtualRecorderVitalUploadStatus,
)
from tirosh_vitalserver.testkit.application.recorder_session.recording import (
    SessionPlaybackEvent,
    SessionPlaybackEventType,
    SessionRecorderPlayback,
    SessionVitalPlayback,
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
        vital_file_exporter: SessionVitalFileExporterPort | None = None,
        vital_file_uploader: SessionVitalFileUploaderPort | None = None,
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
            vrcode=self._request.vrcode,
        )
        self._thread.start()

    def stop(self) -> None:
        """Request graceful session shutdown."""

        with self._lock:
            if self._state in (
                VirtualRecorderSessionState.STOPPED,
                VirtualRecorderSessionState.FAILED,
                VirtualRecorderSessionState.VITAL_READY,
                VirtualRecorderSessionState.UPLOADED,
                VirtualRecorderSessionState.UPLOAD_FAILED,
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
            if self._state != VirtualRecorderSessionState.PAUSED:
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
            vrcode=self._request.vrcode,
        )
        self._publish_snapshot(snapshot)

        try:
            results = self._stream_recorders()
            error = first_result_error(results)

            with self._lock:
                self._results = results
                self._error = error
                self._stopped_at = time.time()
                self._record_playback_event(
                    SessionPlaybackEventType.STOPPED,
                    self._stopped_at,
                )
                if error:
                    self._state = VirtualRecorderSessionState.FAILED
                    self._vital_state = blocked_vital_state_after_stream_error(
                        self._vital_state,
                        error,
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
                error=error,
            )
            self._publish_snapshot(snapshot)
            if error is None:
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
                self._vital_state = blocked_vital_state_after_stream_error(
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

    def _finalize_vital_artifact(self) -> None:
        if not self._request.export_vital:
            return

        if self._vital_file_exporter is None:
            self._mark_vital_export_failed("vital file exporter is not configured")
            return

        with self._lock:
            self._state = VirtualRecorderSessionState.FINALIZING_VITAL
            self._vital_state = replace(
                self._vital_state,
                export_status=VirtualRecorderVitalExportStatus.FINALIZING,
            )
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
            self._vital_state = replace(
                self._vital_state,
                export_status=VirtualRecorderVitalExportStatus.READY,
                artifact=artifact,
                export_error=None,
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
                self._vital_state = replace(
                    self._vital_state,
                    upload_status=VirtualRecorderVitalUploadStatus.BLOCKED,
                    upload_error="vital artifact is not ready",
                )
                snapshot = self.snapshot()
                self._publish_snapshot(snapshot)
                return snapshot

            self._state = VirtualRecorderSessionState.UPLOADING
            self._vital_state = replace(
                self._vital_state,
                upload_status=VirtualRecorderVitalUploadStatus.UPLOADING,
                upload_error=None,
            )
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
                self._vital_state = replace(
                    self._vital_state,
                    upload_status=VirtualRecorderVitalUploadStatus.UPLOADED,
                    upload_result=result,
                    upload_error=None,
                )
            else:
                self._state = VirtualRecorderSessionState.UPLOAD_FAILED
                self._vital_state = replace(
                    self._vital_state,
                    upload_status=VirtualRecorderVitalUploadStatus.FAILED,
                    upload_result=result,
                    upload_error=result.error or "vital upload failed",
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
            self._vital_state = replace(
                self._vital_state,
                export_status=VirtualRecorderVitalExportStatus.FAILED,
                upload_status=(
                    VirtualRecorderVitalUploadStatus.BLOCKED
                    if self._request.upload_vital
                    else self._vital_state.upload_status
                ),
                export_error=error,
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
            self._vital_state = replace(
                self._vital_state,
                upload_status=VirtualRecorderVitalUploadStatus.FAILED,
                upload_error=error,
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
            default_scenario=self._request.default_scenario,
        )

    def _record_playback_event(
        self,
        event_type: SessionPlaybackEventType,
        at: float,
    ) -> None:
        self._playback_events.append(SessionPlaybackEvent(type=event_type, at=at))

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


def blocked_vital_state_after_stream_error(
    vital_state: VirtualRecorderSessionVitalState,
    error: str,
) -> VirtualRecorderSessionVitalState:
    """Return vital state when streaming failed before export/upload."""

    if vital_state.export_status == VirtualRecorderVitalExportStatus.NOT_REQUESTED:
        return vital_state

    return replace(
        vital_state,
        export_status=VirtualRecorderVitalExportStatus.BLOCKED,
        upload_status=(
            VirtualRecorderVitalUploadStatus.BLOCKED
            if vital_state.upload_status
            != VirtualRecorderVitalUploadStatus.NOT_REQUESTED
            else vital_state.upload_status
        ),
        export_error=error,
    )
