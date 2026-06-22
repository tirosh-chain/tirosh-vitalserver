"""Pure state policy for virtual VRecorder sessions."""

from __future__ import annotations

from dataclasses import replace

from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionState,
    VirtualRecorderSessionVitalState,
    VirtualRecorderVitalArtifact,
    VirtualRecorderVitalExportStatus,
    VirtualRecorderVitalUploadResult,
    VirtualRecorderVitalUploadStatus,
)

TERMINAL_SESSION_STATES = frozenset({
    VirtualRecorderSessionState.STOPPED,
    VirtualRecorderSessionState.FAILED,
    VirtualRecorderSessionState.VITAL_READY,
    VirtualRecorderSessionState.UPLOADED,
    VirtualRecorderSessionState.UPLOAD_FAILED,
})


def session_is_active_state(state: VirtualRecorderSessionState) -> bool:
    """Return whether a session state still owns runtime resources."""

    return state not in TERMINAL_SESSION_STATES


def session_can_stop(state: VirtualRecorderSessionState) -> bool:
    """Return whether stop may transition the session to stopping."""

    return session_is_active_state(state)


def session_can_pause(state: VirtualRecorderSessionState) -> bool:
    """Return whether pause may transition the session to paused."""

    return state == VirtualRecorderSessionState.RUNNING


def session_can_resume(state: VirtualRecorderSessionState) -> bool:
    """Return whether resume may transition the session to running."""

    return state == VirtualRecorderSessionState.PAUSED


def vital_state_after_stream_error(
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


def vital_state_finalizing(
    vital_state: VirtualRecorderSessionVitalState,
) -> VirtualRecorderSessionVitalState:
    """Return vital state while artifact export is running."""

    return replace(
        vital_state,
        export_status=VirtualRecorderVitalExportStatus.FINALIZING,
    )


def vital_state_export_ready(
    vital_state: VirtualRecorderSessionVitalState,
    artifact: VirtualRecorderVitalArtifact,
) -> VirtualRecorderSessionVitalState:
    """Return vital state after a `.vital` artifact was created."""

    return replace(
        vital_state,
        export_status=VirtualRecorderVitalExportStatus.READY,
        artifact=artifact,
        export_error=None,
    )


def vital_state_export_failed(
    vital_state: VirtualRecorderSessionVitalState,
    *,
    error: str,
    upload_requested: bool,
) -> VirtualRecorderSessionVitalState:
    """Return vital state after artifact export failed."""

    return replace(
        vital_state,
        export_status=VirtualRecorderVitalExportStatus.FAILED,
        upload_status=(
            VirtualRecorderVitalUploadStatus.BLOCKED
            if upload_requested
            else vital_state.upload_status
        ),
        export_error=error,
    )


def vital_state_upload_blocked(
    vital_state: VirtualRecorderSessionVitalState,
    error: str,
) -> VirtualRecorderSessionVitalState:
    """Return vital state when upload cannot start."""

    return replace(
        vital_state,
        upload_status=VirtualRecorderVitalUploadStatus.BLOCKED,
        upload_error=error,
    )


def vital_state_uploading(
    vital_state: VirtualRecorderSessionVitalState,
) -> VirtualRecorderSessionVitalState:
    """Return vital state while upload is running."""

    return replace(
        vital_state,
        upload_status=VirtualRecorderVitalUploadStatus.UPLOADING,
        upload_error=None,
    )


def vital_state_upload_succeeded(
    vital_state: VirtualRecorderSessionVitalState,
    result: VirtualRecorderVitalUploadResult,
) -> VirtualRecorderSessionVitalState:
    """Return vital state after upload succeeded."""

    return replace(
        vital_state,
        upload_status=VirtualRecorderVitalUploadStatus.UPLOADED,
        upload_result=result,
        upload_error=None,
    )


def vital_state_upload_failed(
    vital_state: VirtualRecorderSessionVitalState,
    *,
    error: str,
    result: VirtualRecorderVitalUploadResult | None = None,
) -> VirtualRecorderSessionVitalState:
    """Return vital state after upload failed."""

    return replace(
        vital_state,
        upload_status=VirtualRecorderVitalUploadStatus.FAILED,
        upload_result=result if result is not None else vital_state.upload_result,
        upload_error=error,
    )
