from __future__ import annotations

from datetime import datetime

from ..model import (
    LabBed,
    LabRecorder,
    LabSession,
    LabSessionStoreUnavailable,
    LabVitalFileReplayPolicy,
)
from .records import LabBedRecord, LabRecorderRecord, LabSessionRecord


def session_record(domain: LabSession) -> LabSessionRecord:
    return LabSessionRecord(
        session_id=domain.session_id,
        document=domain.as_private_json(),
        created_at=_timestamp(domain.created_at),
        updated_at=_timestamp(domain.updated_at),
    )


def bed_record(domain: LabBed) -> LabBedRecord:
    return LabBedRecord(
        bed_id=domain.bed_id,
        document=domain.as_json(),
        updated_at=_timestamp(domain.updated_at),
    )


def recorder_record(domain: LabRecorder) -> LabRecorderRecord:
    return LabRecorderRecord(
        recorder_id=domain.recorder_id,
        document=domain.as_json(),
        updated_at=_timestamp(domain.updated_at),
    )


def session_domain(record: LabSessionRecord) -> LabSession:
    d = _document(record.document, "Lab session")
    return LabSession(
        session_id=_string(d, "sessionId"),
        scenario_id=_string(d, "scenarioId"),
        name=_string(d, "name"),
        recorder_count=_integer(d, "recorderCount"),
        target_url=_optional_string(d, "targetURL"),
        bed_room_names=_strings(d, "bedRoomNames"),
        bed_ids=_strings(d, "bedIds"),
        recorder_ids=_strings(d, "recorderIds"),
        vital_file_path=_optional_string(d, "vitalFilePath"),
        vital_file_relative_path=_optional_string(d, "vitalFileRelativePath"),
        replay_policy=_optional_replay_policy(d, "replayPolicy"),
        state=_string(d, "state"),
        created_at=_string(d, "createdAt"),
        updated_at=_string(d, "updatedAt"),
        archive_finalization_request_ids=_optional_strings(
            d, "archiveFinalizationRequestIds"
        ),
    )


def bed_domain(record: LabBedRecord) -> LabBed:
    d = _document(record.document, "Lab bed")
    return LabBed(
        _string(d, "bedId"),
        _string(d, "sessionId"),
        _string(d, "name"),
        _string(d, "state"),
        _string(d, "createdAt"),
        _string(d, "updatedAt"),
    )


def recorder_domain(record: LabRecorderRecord) -> LabRecorder:
    d = _document(record.document, "Lab recorder")
    return LabRecorder(
        _string(d, "recorderId"),
        _string(d, "sessionId"),
        _string(d, "bedId"),
        _string(d, "vrcode"),
        _string(d, "state"),
        _string(d, "createdAt"),
        _string(d, "updatedAt"),
        _integer(d, "messagesSent"),
        _string(d, "lastSendState"),
        _optional_string(d, "lastSendAt"),
        _optional_string(d, "lastSendError"),
    )


def _document(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise _invalid(f"{label} document is not an object.")
    return value


def _string(document: dict[str, object], field: str) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not value:
        raise _invalid(f"Lab document field is invalid: {field}")
    return value


def _optional_string(document: dict[str, object], field: str) -> str | None:
    value = document.get(field)
    if value is not None and not isinstance(value, str):
        raise _invalid(f"Lab document field is invalid: {field}")
    return value


def _integer(document: dict[str, object], field: str) -> int:
    value = document.get(field)
    if not isinstance(value, int):
        raise _invalid(f"Lab document field is invalid: {field}")
    return value


def _strings(document: dict[str, object], field: str) -> tuple[str, ...]:
    value = document.get(field, [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise _invalid(f"Lab document field is invalid: {field}")
    return tuple(value)


def _optional_strings(
    document: dict[str, object], field: str
) -> tuple[str, ...] | None:
    if field not in document:
        return None
    value = document[field]
    if not isinstance(value, list) or not value or not all(
        isinstance(item, str) and item for item in value
    ):
        raise _invalid(f"Lab document field is invalid: {field}")
    return tuple(value)


def _optional_replay_policy(
    document: dict[str, object], field: str
) -> LabVitalFileReplayPolicy | None:
    value = document.get(field)
    if value is None:
        return None
    if not isinstance(value, dict):
        raise _invalid(f"Lab document field is invalid: {field}")
    mode = value.get("mode")
    count = value.get("count")
    if mode not in ("once", "count", "continuous"):
        raise _invalid(f"Lab document replay mode is invalid: {mode}")
    if count is not None and (isinstance(count, bool) or not isinstance(count, int)):
        raise _invalid("Lab document replay count is invalid")
    try:
        return LabVitalFileReplayPolicy(mode=mode, count=count)
    except ValueError as error:
        raise _invalid(str(error)) from error


def _timestamp(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise _invalid(f"Lab document timestamp is invalid: {value}") from error


def _invalid(message: str) -> LabSessionStoreUnavailable:
    return LabSessionStoreUnavailable(message, kind="labSessionDocumentInvalid")
