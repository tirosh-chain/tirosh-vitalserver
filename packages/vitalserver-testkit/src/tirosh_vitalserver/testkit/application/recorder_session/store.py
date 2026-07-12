"""Persistence boundary for virtual VRecorder session registry."""

from __future__ import annotations

from dataclasses import asdict
from math import isfinite
from pathlib import Path
from typing import Any, Protocol

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderManagementEvent,
    RecorderRuntimeSnapshot,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    RecorderCondition,
    RecorderScenarioWindow,
    RecorderSessionOutput,
    RecorderSource,
    RecorderSourceType,
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
from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalSampleScenario,
)
from tirosh_vitalserver.testkit.domain.signal import SignalQualityProfile

SESSION_STORE_SCHEMA_VERSION = 4


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
    data["request"]["source"] = recorder_source_to_record(snapshot.request.source)
    data["vital_state"]["export_status"] = snapshot.vital_state.export_status.value
    data["vital_state"]["upload_status"] = snapshot.vital_state.upload_status.value
    data["recorders"] = [
        recorder_snapshot_to_record(recorder)
        for recorder in snapshot.recorders
    ]

    return data


def session_snapshot_from_record(
    data: dict[str, Any],
) -> VirtualRecorderSessionSnapshot:
    """Convert one complete persisted JSON record into a session snapshot."""

    return VirtualRecorderSessionSnapshot(
        session_id=require_string(data["session_id"], "session_id"),
        state=VirtualRecorderSessionState(
            require_string(data["state"], "state")
        ),
        request=session_request_from_record(
            require_object(data["request"], "request")
        ),
        created_at=require_number(data["created_at"], "created_at"),
        started_at=optional_number(data["started_at"], "started_at"),
        stopped_at=optional_number(data["stopped_at"], "stopped_at"),
        recorders=tuple(
            recorder_snapshot_from_record(
                require_object(record, "recorders[]")
            )
            for record in require_list(data["recorders"], "recorders")
        ),
        messages_sent=require_integer(data["messages_sent"], "messages_sent"),
        bytes_sent=require_integer(data["bytes_sent"], "bytes_sent"),
        error=optional_string(data["error"], "error"),
        cleanup_errors=tuple(
            cleanup_error_from_record(
                require_object(error, "cleanup_errors[]")
            )
            for error in require_list(data["cleanup_errors"], "cleanup_errors")
        ),
        vital_state=vital_state_from_record(
            require_object(data["vital_state"], "vital_state")
        ),
    )


def session_request_from_record(data: dict[str, Any]) -> VirtualRecorderSessionRequest:
    """Convert a complete persisted request record into its application contract."""

    scenario = RecorderTestScenario(require_string(data["scenario"], "scenario"))
    window_data = optional_object(data["window"], "window")
    output_data = require_object(data["output"], "output")
    source_data = optional_object(data["source"], "source")

    return VirtualRecorderSessionRequest(
        target_url=require_string(data["target_url"], "target_url"),
        recorders=require_integer(data["recorders"], "recorders"),
        bedroom_name=require_string(data["bedroom_name"], "bedroom_name"),
        bed_room_names=tuple(
            require_string(room_name, "bed_room_names[]")
            for room_name in require_list(data["bed_room_names"], "bed_room_names")
        ),
        scenario=scenario,
        window=None
        if window_data is None
        else RecorderScenarioWindow(
            start_offset_seconds=optional_number(
                window_data["start_offset_seconds"],
                "window.start_offset_seconds",
            ),
            duration_seconds=optional_number(
                window_data["duration_seconds"],
                "window.duration_seconds",
            ),
        ),
        output=RecorderSessionOutput(
            export_vital=require_boolean(
                output_data["export_vital"],
                "output.export_vital",
            ),
            upload_vital=require_boolean(
                output_data["upload_vital"],
                "output.upload_vital",
            ),
            vital_upload_endpoint=require_string(
                output_data["vital_upload_endpoint"],
                "output.vital_upload_endpoint",
            ),
        ),
        vrcode=optional_string(data["vrcode"], "vrcode"),
        version=require_string(data["version"], "version"),
        signal_quality=SignalQualityProfile(
            require_string(data["signal_quality"], "signal_quality")
        ),
        recorder_condition=RecorderCondition(
            require_string(data["recorder_condition"], "recorder_condition")
        ),
        source=None
        if source_data is None
        else recorder_source_from_record(source_data),
        real_sample_key=optional_string(
            data["real_sample_key"],
            "real_sample_key",
        ),
        interval_seconds=require_number(
            data["interval_seconds"],
            "interval_seconds",
        ),
        max_messages=optional_integer(data["max_messages"], "max_messages"),
        shift_time=require_boolean(data["shift_time"], "shift_time"),
        generate_frames=require_boolean(
            data["generate_frames"],
            "generate_frames",
        ),
    )


def recorder_source_to_record(source: RecorderSource | None) -> dict[str, Any] | None:
    """Convert an explicit recorder source to a persisted JSON record."""

    if source is None:
        return None
    if source.source_type == RecorderSourceType.VITAL_FILE:
        return {
            "type": source.source_type.value,
            "path": None if source.path is None else str(source.path),
            "scenario": None if source.scenario is None else source.scenario.value,
            "start_offset_seconds": source.start_offset_seconds,
            "duration_seconds": source.duration_seconds,
        }
    raise ValueError(f"unsupported recorder source type: {source.source_type}")


def recorder_source_from_record(data: dict[str, Any]) -> RecorderSource:
    """Convert a persisted recorder source record into the application contract."""

    source_type = RecorderSourceType(require_string(data["type"], "source.type"))
    if source_type == RecorderSourceType.VITAL_FILE:
        return RecorderSource(
            source_type=source_type,
            path=Path(require_string(data["path"], "source.path")),
            scenario=RealVitalSampleScenario(
                require_string(data["scenario"], "source.scenario")
            ),
            start_offset_seconds=require_number(
                data["start_offset_seconds"],
                "source.start_offset_seconds",
            ),
            duration_seconds=require_integer(
                data["duration_seconds"],
                "source.duration_seconds",
            ),
        )
    raise ValueError(f"unsupported recorder source type: {source_type}")


def vital_state_from_record(data: dict[str, Any]) -> VirtualRecorderSessionVitalState:
    """Convert a persisted vital state record into the application contract."""

    artifact_data = optional_object(data["artifact"], "vital_state.artifact")
    upload_result_data = optional_object(
        data["upload_result"],
        "vital_state.upload_result",
    )

    artifact = None
    if artifact_data is not None:
        artifact = VirtualRecorderVitalArtifact(
            path=require_string(artifact_data["path"], "artifact.path"),
            filename=require_string(artifact_data["filename"], "artifact.filename"),
            size_bytes=require_integer(
                artifact_data["size_bytes"],
                "artifact.size_bytes",
            ),
            created_at=require_number(
                artifact_data["created_at"],
                "artifact.created_at",
            ),
            format=require_string(artifact_data["format"], "artifact.format"),
            retention_policy=require_string(
                artifact_data["retention_policy"],
                "artifact.retention_policy",
            ),
        )

    upload_result = None
    if upload_result_data is not None:
        upload_result = VirtualRecorderVitalUploadResult(
            status_code=require_integer(
                upload_result_data["status_code"],
                "upload_result.status_code",
            ),
            ok=require_boolean(upload_result_data["ok"], "upload_result.ok"),
            elapsed_seconds=require_number(
                upload_result_data["elapsed_seconds"],
                "upload_result.elapsed_seconds",
            ),
            uploaded_at=require_number(
                upload_result_data["uploaded_at"],
                "upload_result.uploaded_at",
            ),
            response_text=require_string(
                upload_result_data["response_text"],
                "upload_result.response_text",
            ),
            error=optional_string(
                upload_result_data["error"],
                "upload_result.error",
            ),
        )

    return VirtualRecorderSessionVitalState(
        export_status=VirtualRecorderVitalExportStatus(
            require_string(data["export_status"], "vital_state.export_status")
        ),
        upload_status=VirtualRecorderVitalUploadStatus(
            require_string(data["upload_status"], "vital_state.upload_status")
        ),
        artifact=artifact,
        export_error=optional_string(
            data["export_error"],
            "vital_state.export_error",
        ),
        upload_error=optional_string(
            data["upload_error"],
            "vital_state.upload_error",
        ),
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
    """Convert a persisted recorder runtime snapshot into the application contract."""

    return RecorderRuntimeSnapshot(
        vrcode=require_string(data["vrcode"], "vrcode"),
        base_url=require_string(data["base_url"], "base_url"),
        local_ip=optional_string(data["local_ip"], "local_ip"),
        connected=require_boolean(data["connected"], "connected"),
        join_sent=require_boolean(data["join_sent"], "join_sent"),
        joined_at=optional_number(data["joined_at"], "joined_at"),
        server_dt=data["server_dt"],
        server_dt_received_at=optional_number(
            data["server_dt_received_at"],
            "server_dt_received_at",
        ),
        last_reconnect_at=optional_number(
            data["last_reconnect_at"],
            "last_reconnect_at",
        ),
        last_send_data_at=optional_number(
            data["last_send_data_at"],
            "last_send_data_at",
        ),
        messages_sent=require_integer(data["messages_sent"], "messages_sent"),
        bytes_sent=require_integer(data["bytes_sent"], "bytes_sent"),
        management_events=tuple(
            management_event_from_record(
                require_object(event, "management_events[]")
            )
            for event in require_list(
                data["management_events"],
                "management_events",
            )
        ),
    )


def cleanup_error_from_record(data: dict[str, Any]) -> VirtualRecorderCleanupError:
    """Convert one persisted cleanup error into its application contract."""

    return VirtualRecorderCleanupError(
        vrcode=require_string(data["vrcode"], "cleanup_error.vrcode"),
        target_url=require_string(
            data["target_url"],
            "cleanup_error.target_url",
        ),
        error=require_string(data["error"], "cleanup_error.error"),
    )


def management_event_from_record(data: dict[str, Any]) -> RecorderManagementEvent:
    """Convert one persisted recorder management event into its contract."""

    return RecorderManagementEvent(
        name=require_string(data["name"], "management_event.name"),
        received_at=require_number(
            data["received_at"],
            "management_event.received_at",
        ),
        payload=tuple(require_list(data["payload"], "management_event.payload")),
    )


def require_object(value: Any, field: str) -> dict[str, Any]:
    """Return one persisted object without creating a replacement value."""

    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def optional_object(value: Any, field: str) -> dict[str, Any] | None:
    """Return one persisted object or explicit null."""

    if value is None:
        return None
    return require_object(value, field)


def require_list(value: Any, field: str) -> list[Any]:
    """Return one persisted array without accepting other collection types."""

    if not isinstance(value, list):
        raise ValueError(f"{field} must be an array")
    return value


def require_string(value: Any, field: str) -> str:
    """Return one persisted string without coercing another scalar type."""

    if not isinstance(value, str):
        raise ValueError(f"{field} must be a string")
    return value


def optional_string(value: Any, field: str) -> str | None:
    """Return one persisted string or explicit null."""

    if value is None:
        return None
    return require_string(value, field)


def require_boolean(value: Any, field: str) -> bool:
    """Return one persisted boolean without truthiness coercion."""

    if not isinstance(value, bool):
        raise ValueError(f"{field} must be a boolean")
    return value


def require_integer(value: Any, field: str) -> int:
    """Return one persisted integer without accepting booleans or strings."""

    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{field} must be an integer")
    return value


def optional_integer(value: Any, field: str) -> int | None:
    """Return one persisted integer or explicit null."""

    if value is None:
        return None
    return require_integer(value, field)


def require_number(value: Any, field: str) -> float:
    """Return one finite persisted JSON number without string coercion."""

    if (
        not isinstance(value, (int, float))
        or isinstance(value, bool)
        or not isfinite(value)
    ):
        raise ValueError(f"{field} must be a finite number")
    return float(value)


def optional_number(value: Any, field: str) -> float | None:
    """Return one finite persisted JSON number or explicit null."""

    if value is None:
        return None
    return require_number(value, field)
