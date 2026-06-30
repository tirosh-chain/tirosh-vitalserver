from __future__ import annotations

from tirosh_vitalserver.testkit.application.recorder_session.models import (
    RecorderSessionOutput,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionState,
    VirtualRecorderSessionVitalState,
    VirtualRecorderVitalArtifact,
    VirtualRecorderVitalExportStatus,
    VirtualRecorderVitalUploadResult,
    VirtualRecorderVitalUploadStatus,
)
from tirosh_vitalserver.testkit.application.recorder_session.policy import (
    session_can_pause,
    session_can_resume,
    session_can_stop,
    session_is_active_state,
    vital_state_after_stream_error,
    vital_state_export_failed,
    vital_state_export_ready,
    vital_state_finalizing,
    vital_state_upload_blocked,
    vital_state_upload_failed,
    vital_state_upload_succeeded,
    vital_state_uploading,
)


def test_session_policy_preserves_active_and_terminal_states() -> None:
    assert session_is_active_state(VirtualRecorderSessionState.RUNNING) is True
    assert session_can_stop(VirtualRecorderSessionState.RUNNING) is True
    assert session_can_pause(VirtualRecorderSessionState.RUNNING) is True
    assert session_can_resume(VirtualRecorderSessionState.PAUSED) is True

    terminal_states = (
        VirtualRecorderSessionState.STOPPED,
        VirtualRecorderSessionState.FAILED,
        VirtualRecorderSessionState.VITAL_READY,
        VirtualRecorderSessionState.UPLOADED,
        VirtualRecorderSessionState.UPLOAD_FAILED,
    )

    for state in terminal_states:
        assert session_is_active_state(state) is False
        assert session_can_stop(state) is False


def test_vital_policy_blocks_export_and_upload_after_stream_error() -> None:
    vital_state = VirtualRecorderSessionVitalState.for_request(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bedroom_name="OR-A",
            output=RecorderSessionOutput(
                export_vital=True,
                upload_vital=True,
            ),
        )
    )

    blocked = vital_state_after_stream_error(vital_state, "stream failed")

    assert blocked.export_status == VirtualRecorderVitalExportStatus.BLOCKED
    assert blocked.upload_status == VirtualRecorderVitalUploadStatus.BLOCKED
    assert blocked.export_error == "stream failed"


def test_vital_policy_preserves_not_requested_export_after_stream_error() -> None:
    vital_state = VirtualRecorderSessionVitalState.for_request(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            bedroom_name="OR-A",
        )
    )

    assert vital_state_after_stream_error(vital_state, "stream failed") == vital_state


def test_vital_policy_models_export_lifecycle() -> None:
    vital_state = VirtualRecorderSessionVitalState(
        export_status=VirtualRecorderVitalExportStatus.PENDING,
        upload_status=VirtualRecorderVitalUploadStatus.PENDING,
    )
    artifact = VirtualRecorderVitalArtifact(
        path="/tmp/session.vital",
        filename="session.vital",
        size_bytes=128,
        created_at=1.0,
        format="vitaldb-vital",
    )

    finalizing = vital_state_finalizing(vital_state)
    ready = vital_state_export_ready(finalizing, artifact)
    failed = vital_state_export_failed(
        finalizing,
        error="write failed",
        upload_requested=True,
    )

    assert finalizing.export_status == VirtualRecorderVitalExportStatus.FINALIZING
    assert ready.export_status == VirtualRecorderVitalExportStatus.READY
    assert ready.artifact == artifact
    assert ready.export_error is None
    assert failed.export_status == VirtualRecorderVitalExportStatus.FAILED
    assert failed.upload_status == VirtualRecorderVitalUploadStatus.BLOCKED
    assert failed.export_error == "write failed"


def test_vital_policy_models_upload_lifecycle() -> None:
    vital_state = VirtualRecorderSessionVitalState(
        export_status=VirtualRecorderVitalExportStatus.READY,
        upload_status=VirtualRecorderVitalUploadStatus.PENDING,
    )
    result = VirtualRecorderVitalUploadResult(
        status_code=200,
        ok=True,
        elapsed_seconds=0.1,
        uploaded_at=2.0,
        response_text="ok",
    )

    blocked = vital_state_upload_blocked(vital_state, "artifact missing")
    uploading = vital_state_uploading(vital_state)
    uploaded = vital_state_upload_succeeded(uploading, result)
    failed = vital_state_upload_failed(uploading, error="upload failed")

    assert blocked.upload_status == VirtualRecorderVitalUploadStatus.BLOCKED
    assert blocked.upload_error == "artifact missing"
    assert uploading.upload_status == VirtualRecorderVitalUploadStatus.UPLOADING
    assert uploading.upload_error is None
    assert uploaded.upload_status == VirtualRecorderVitalUploadStatus.UPLOADED
    assert uploaded.upload_result == result
    assert uploaded.upload_error is None
    assert failed.upload_status == VirtualRecorderVitalUploadStatus.FAILED
    assert failed.upload_error == "upload failed"
