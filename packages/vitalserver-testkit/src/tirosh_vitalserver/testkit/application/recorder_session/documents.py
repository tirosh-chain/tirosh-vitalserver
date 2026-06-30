"""Public documents for virtual VRecorder sessions."""

from __future__ import annotations

from dataclasses import asdict
from typing import Any

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeSnapshot,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    RecorderSource,
    RecorderSourceType,
    VirtualRecorderDeletionResult,
    VirtualRecorderSessionSnapshot,
)


def session_snapshot_to_document(
    snapshot: VirtualRecorderSessionSnapshot,
) -> dict[str, Any]:
    """Convert a session snapshot into the public API document."""

    request = snapshot.request

    return {
        "id": snapshot.session_id,
        "state": snapshot.state.value,
        "targetUrl": request.target_url,
        "recordersRequested": request.recorders,
        "bedsRequested": len(request.bed_room_names),
        "bedroomName": request.bedroom_name,
        "bedRoomNames": list(request.bed_room_names),
        "vrcode": request.vrcode,
        "version": request.version,
        "intervalSeconds": request.interval_seconds,
        "durationSeconds": request.duration_seconds,
        "maxMessages": request.max_messages,
        "shiftTime": request.shift_time,
        "generateFrames": request.generate_frames,
        "scenario": request.scenario.value,
        "signalQuality": request.signal_quality.value,
        "recorderCondition": request.recorder_condition.value,
        "source": recorder_source_to_document(request.source),
        "realSampleKey": request.real_sample_key,
        "window": None
        if request.window is None
        else {
            "startOffsetSeconds": request.window.start_offset_seconds,
            "durationSeconds": request.window.duration_seconds,
        },
        "output": {
            "exportVital": request.output.export_vital,
            "uploadVital": request.output.upload_vital,
            "vitalUploadEndpoint": request.output.vital_upload_endpoint,
        },
        "createdAt": snapshot.created_at,
        "startedAt": snapshot.started_at,
        "stoppedAt": snapshot.stopped_at,
        "messagesSent": snapshot.messages_sent,
        "bytesSent": snapshot.bytes_sent,
        "lastError": snapshot.error,
        "cleanupErrors": [
            {
                "vrcode": error.vrcode,
                "targetUrl": error.target_url,
                "error": error.error,
            }
            for error in snapshot.cleanup_errors
        ],
        "vital": vital_state_to_document(snapshot),
        "recorders": [
            recorder_snapshot_to_document(recorder)
            for recorder in snapshot.recorders
        ],
    }


def recorder_source_to_document(source: RecorderSource | None) -> dict[str, Any] | None:
    """Convert an explicit recorder source into the public API document."""

    if source is None:
        return None
    if source.source_type == RecorderSourceType.VITAL_FILE:
        return {
            "type": source.source_type.value,
            "path": None if source.path is None else str(source.path),
            "scenario": None if source.scenario is None else source.scenario.value,
            "startOffsetSeconds": source.start_offset_seconds,
            "durationSeconds": source.duration_seconds,
        }
    raise ValueError(f"unsupported recorder source type: {source.source_type}")


def vital_state_to_document(
    snapshot: VirtualRecorderSessionSnapshot,
) -> dict[str, Any]:
    """Convert explicit `.vital` export/upload state to API JSON."""

    vital_state = snapshot.vital_state
    artifact = vital_state.artifact
    upload_result = vital_state.upload_result

    return {
        "exportStatus": vital_state.export_status.value,
        "uploadStatus": vital_state.upload_status.value,
        "exportError": vital_state.export_error,
        "uploadError": vital_state.upload_error,
        "artifact": None
        if artifact is None
        else {
            "path": artifact.path,
            "filename": artifact.filename,
            "sizeBytes": artifact.size_bytes,
            "createdAt": artifact.created_at,
            "format": artifact.format,
            "retentionPolicy": artifact.retention_policy,
        },
        "uploadResult": None
        if upload_result is None
        else {
            "statusCode": upload_result.status_code,
            "ok": upload_result.ok,
            "elapsedSeconds": upload_result.elapsed_seconds,
            "uploadedAt": upload_result.uploaded_at,
            "responseText": upload_result.response_text,
            "error": upload_result.error,
        },
    }


def deletion_result_to_document(
    result: VirtualRecorderDeletionResult,
) -> dict[str, Any]:
    """Convert a direct VRecorder deletion result into API JSON."""

    return {
        "vrcode": result.vrcode,
        "targetUrl": result.target_url,
        "deleted": result.deleted,
        "error": result.error,
    }


def recorder_snapshot_to_document(
    snapshot: RecorderRuntimeSnapshot,
) -> dict[str, Any]:
    """Convert a recorder runtime snapshot into a JSON-friendly document."""

    data = asdict(snapshot)
    data["management_events"] = [
        {
            "name": event.name,
            "received_at": event.received_at,
            "payload": event.payload,
        }
        for event in snapshot.management_events
    ]

    return snake_to_camel_document(data)


def snake_to_camel_document(data: dict[str, Any]) -> dict[str, Any]:
    """Convert one-level snake_case keys to lower camelCase."""

    return {snake_to_camel(key): value for key, value in data.items()}


def snake_to_camel(value: str) -> str:
    """Convert a snake_case field name to lower camelCase."""

    head, *tail = value.split("_")

    return head + "".join(part.capitalize() for part in tail)
