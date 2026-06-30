"""Persistence boundary for virtual VRecorder session registry."""

from __future__ import annotations

from dataclasses import asdict
from typing import Any, Protocol

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderManagementEvent,
    RecorderRuntimeSnapshot,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    RecorderScenarioWindow,
    RecorderSessionOutput,
    RecorderTestScenario,
    VirtualRecorderCleanupError,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionSnapshot,
    VirtualRecorderSessionState,
    VirtualRecorderSessionVitalState,
    VirtualRecorderVitalArtifact,
    VirtualRecorderVitalExportStatus,
    VirtualRecorderVitalUploadResult,
    VirtualRecorderVitalUploadStatus,
)

SESSION_STORE_SCHEMA_VERSION = 3


class VirtualRecorderSessionStorePort(Protocol):
    """Persistent registry for virtual VRecorder session snapshots."""

    def load_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]: ...

    def save_session(self, snapshot: VirtualRecorderSessionSnapshot) -> None: ...

    def delete_session(self, session_id: str) -> None: ...

    def delete_all_sessions(self) -> None: ...


def session_snapshot_to_record(
    snapshot: VirtualRecorderSessionSnapshot,
) -> dict[str, Any]:
    """Convert a session snapshot into a persistent JSON record."""

    data = asdict(snapshot)
    data["state"] = snapshot.state.value
    data["request"]["scenario"] = snapshot.request.scenario.value
    data["vital_state"]["export_status"] = snapshot.vital_state.export_status.value
    data["vital_state"]["upload_status"] = snapshot.vital_state.upload_status.value
    data["recorders"] = [
        recorder_snapshot_to_record(recorder)
        for recorder in snapshot.recorders
    ]

    return data


def session_snapshot_from_record(
    data: dict[str, Any],
    *,
    schema_version: int = SESSION_STORE_SCHEMA_VERSION,
) -> VirtualRecorderSessionSnapshot:
    """Convert a persistent JSON record into a session snapshot."""

    request_data = dict(data["request"])
    request_data["scenario"] = RecorderTestScenario(str(request_data["scenario"]))
    if request_data.get("window") is not None:
        request_data["window"] = RecorderScenarioWindow(**request_data["window"])
    if request_data.get("output") is not None:
        request_data["output"] = RecorderSessionOutput(**request_data["output"])

    request = VirtualRecorderSessionRequest(**request_data)
    if "vital_state" in data:
        vital_state = vital_state_from_record(data["vital_state"])
    else:
        raise KeyError("vital_state")

    return VirtualRecorderSessionSnapshot(
        session_id=str(data["session_id"]),
        state=VirtualRecorderSessionState(str(data["state"])),
        request=request,
        created_at=float(data["created_at"]),
        started_at=optional_float(data["started_at"]),
        stopped_at=optional_float(data["stopped_at"]),
        recorders=tuple(
            recorder_snapshot_from_record(recorder)
            for recorder in data["recorders"]
        ),
        messages_sent=int(data["messages_sent"]),
        bytes_sent=int(data["bytes_sent"]),
        error=data["error"],
        cleanup_errors=tuple(
            VirtualRecorderCleanupError(
                vrcode=str(error["vrcode"]),
                target_url=str(error["target_url"]),
                error=str(error["error"]),
            )
            for error in data["cleanup_errors"]
        ),
        vital_state=vital_state,
    )


def vital_state_from_record(data: dict[str, Any]) -> VirtualRecorderSessionVitalState:
    """Convert a persisted vital state record into the application contract."""

    artifact_data = data["artifact"]
    upload_result_data = data["upload_result"]

    artifact = None
    if artifact_data is not None:
        artifact = VirtualRecorderVitalArtifact(
            path=str(artifact_data["path"]),
            filename=str(artifact_data["filename"]),
            size_bytes=int(artifact_data["size_bytes"]),
            created_at=float(artifact_data["created_at"]),
            format=str(artifact_data["format"]),
            retention_policy=str(artifact_data["retention_policy"]),
        )

    upload_result = None
    if upload_result_data is not None:
        upload_result = VirtualRecorderVitalUploadResult(
            status_code=int(upload_result_data["status_code"]),
            ok=bool(upload_result_data["ok"]),
            elapsed_seconds=float(upload_result_data["elapsed_seconds"]),
            uploaded_at=float(upload_result_data["uploaded_at"]),
            response_text=str(upload_result_data["response_text"]),
            error=upload_result_data["error"],
        )

    return VirtualRecorderSessionVitalState(
        export_status=VirtualRecorderVitalExportStatus(str(data["export_status"])),
        upload_status=VirtualRecorderVitalUploadStatus(str(data["upload_status"])),
        artifact=artifact,
        export_error=data["export_error"],
        upload_error=data["upload_error"],
        upload_result=upload_result,
    )


def recorder_snapshot_to_record(snapshot: RecorderRuntimeSnapshot) -> dict[str, Any]:
    """Convert a recorder runtime snapshot into a persistent JSON record."""

    data = asdict(snapshot)
    data["management_events"] = [
        {
            "name": event.name,
            "received_at": event.received_at,
            "payload": list(event.payload),
        }
        for event in snapshot.management_events
    ]

    return data


def recorder_snapshot_from_record(data: dict[str, Any]) -> RecorderRuntimeSnapshot:
    """Convert a persistent JSON record into a recorder runtime snapshot."""

    return RecorderRuntimeSnapshot(
        vrcode=str(data["vrcode"]),
        base_url=str(data["base_url"]),
        local_ip=data["local_ip"],
        connected=bool(data["connected"]),
        join_sent=bool(data["join_sent"]),
        joined_at=optional_float(data["joined_at"]),
        server_dt=data["server_dt"],
        server_dt_received_at=optional_float(data["server_dt_received_at"]),
        last_reconnect_at=optional_float(data["last_reconnect_at"]),
        last_send_data_at=optional_float(data["last_send_data_at"]),
        messages_sent=int(data["messages_sent"]),
        bytes_sent=int(data["bytes_sent"]),
        management_events=tuple(
            RecorderManagementEvent(
                name=str(event["name"]),
                received_at=float(event["received_at"]),
                payload=tuple(event["payload"]),
            )
            for event in data["management_events"]
        ),
    )


def optional_float(value: Any) -> float | None:
    """Return `value` as float when present."""

    return None if value is None else float(value)
