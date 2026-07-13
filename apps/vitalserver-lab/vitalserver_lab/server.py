from __future__ import annotations

import json
from datetime import UTC, datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from .execution import (
    LabExecutionEngine,
    LabRecorderSendError,
    LabVitalFileUploadReceipt,
    VitalServerRecorderPayloadSender,
)
from .model import (
    DEFAULT_SCENARIOS,
    InMemoryLabSessionStore,
    LabBedCreateInput,
    LabBedDeleteInput,
    LabRecorderCreateInput,
    LabRecorderDeleteInput,
    LabScenario,
    LabSessionCreateInput,
    LabSessionStore,
    LabSessionStoreUnavailable,
    LabVitalFile,
    lab_recorder_control_rejection,
    utc_now_iso,
)
from .persistence import SQLAlchemyLabSessionStore
from .settings import LabSettings, load_settings


class LabServer(ThreadingHTTPServer):
    def __init__(
        self,
        server_address: tuple[str, int],
        settings: LabSettings,
        scenarios: tuple[LabScenario, ...] = DEFAULT_SCENARIOS,
        session_store: LabSessionStore | None = None,
        execution_engine: LabExecutionEngine | None = None,
    ) -> None:
        super().__init__(server_address, LabRequestHandler)
        self.settings = settings
        self.scenarios = scenarios
        self.session_store = session_store or build_session_store(settings)
        self.execution_engine = execution_engine or build_execution_engine(
            settings=settings
        )

    def server_close(self) -> None:
        self.execution_engine.shutdown()
        super().server_close()


class LabRequestHandler(BaseHTTPRequestHandler):
    server: LabServer

    def do_GET(self) -> None:
        status, payload = route_lab_request(
            method="GET",
            path=urlparse(self.path).path,
            body=b"",
            settings=self.server.settings,
            scenarios=self.server.scenarios,
            session_store=self.server.session_store,
            execution_engine=self.server.execution_engine,
        )
        self._json(payload, status=status)

    def do_POST(self) -> None:
        status, payload = route_lab_request(
            method="POST",
            path=urlparse(self.path).path,
            body=self._request_body(),
            settings=self.server.settings,
            scenarios=self.server.scenarios,
            session_store=self.server.session_store,
            execution_engine=self.server.execution_engine,
        )
        self._json(payload, status=status)

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _request_body(self) -> bytes:
        content_length = self.headers.get("Content-Length")
        if content_length is None:
            return b""
        try:
            length = int(content_length)
        except ValueError:
            return b""
        if length <= 0:
            return b""
        return self.rfile.read(length)

    def _json(
        self,
        payload: dict[str, Any],
        status: HTTPStatus = HTTPStatus.OK,
    ) -> None:
        body = json.dumps(payload, sort_keys=True).encode()
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def route_lab_request(
    *,
    method: str,
    path: str,
    body: bytes,
    settings: LabSettings,
    scenarios: tuple[LabScenario, ...],
    session_store: LabSessionStore,
    execution_engine: LabExecutionEngine,
) -> tuple[HTTPStatus, dict[str, object]]:
    parts = [unquote(part) for part in path.split("/") if part]

    if method == "GET" and path == "/health":
        return HTTPStatus.OK, {"status": "ok", "observedAt": utc_now_iso()}

    if method == "GET" and path == "/ready":
        try:
            session_store.ensure_ready()
        except LabSessionStoreUnavailable as error:
            return HTTPStatus.SERVICE_UNAVAILABLE, {
                "ready": False,
                "service": settings.service_name,
                "observedAt": utc_now_iso(),
                "dependency": "lab-session-store",
                "readError": error.message,
            }
        return HTTPStatus.OK, {
            "ready": True,
            "service": settings.service_name,
            "observedAt": utc_now_iso(),
            "dependency": "lab-session-store",
            "readError": None,
        }

    if method == "GET" and path == "/lab/scenarios":
        return HTTPStatus.OK, {
            "state": "loaded",
            "scenarios": [scenario.as_json() for scenario in scenarios],
            "readError": None,
        }

    if method == "GET" and path == "/lab/vital-files":
        try:
            vital_files = list_vital_files(settings=settings)
        except LabRequestError as error:
            return error.status, {
                "state": "failed",
                "vitalFiles": [],
                "readError": error.message,
            }
        return HTTPStatus.OK, {
            "state": "loaded",
            "vitalFiles": [vital_file.as_json() for vital_file in vital_files],
            "readError": None,
        }

    if method == "GET" and path == "/lab/beds":
        try:
            beds = session_store.list_beds()
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="beds")
        return HTTPStatus.OK, {
            "state": "loaded",
            "beds": [bed.as_json() for bed in beds],
            "readError": None,
        }

    if method == "GET" and path == "/lab/recorders":
        try:
            recorders = session_store.list_recorders()
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="recorders")
        return HTTPStatus.OK, {
            "state": "loaded",
            "recorders": [recorder.as_json() for recorder in recorders],
            "readError": None,
        }

    if method == "GET" and path == "/lab/sessions":
        try:
            sessions = session_store.list_sessions()
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="sessions")
        return HTTPStatus.OK, {
            "state": "loaded",
            "sessions": [session.as_json() for session in sessions],
            "readError": None,
        }

    if method == "POST" and path == "/lab/beds/create":
        try:
            request = _parse_bed_create(_json_body(body))
            beds = session_store.create_beds(request)
        except LabRequestError as error:
            return error.status, {"error": error.code, "message": error.message}
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="beds")
        return HTTPStatus.ACCEPTED, _bed_list_response(beds)

    if method == "POST" and path == "/lab/beds/delete":
        try:
            request = _parse_bed_delete(_json_body(body))
            beds = session_store.delete_beds(request)
        except LabRequestError as error:
            return error.status, {"error": error.code, "message": error.message}
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="beds")
        return HTTPStatus.ACCEPTED, _bed_list_response(beds)

    if method == "POST" and path == "/lab/beds/reset":
        try:
            beds = session_store.reset_beds()
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="beds")
        return HTTPStatus.ACCEPTED, _bed_list_response(beds)

    if method == "POST" and path == "/lab/recorders/create":
        try:
            request = _parse_recorder_create(_json_body(body))
            recorders = session_store.create_recorders(request)
        except LabRequestError as error:
            return error.status, {"error": error.code, "message": error.message}
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="recorders")
        return HTTPStatus.ACCEPTED, _recorder_list_response(recorders)

    if method == "POST" and path == "/lab/recorders/delete":
        try:
            request = _parse_recorder_delete(_json_body(body))
            recorders = session_store.delete_recorders(request)
        except LabRequestError as error:
            return error.status, {"error": error.code, "message": error.message}
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="recorders")
        return HTTPStatus.ACCEPTED, _recorder_list_response(recorders)

    if method == "POST" and path == "/lab/recorders/reset":
        try:
            recorders = session_store.reset_recorders()
        except LabSessionStoreUnavailable as error:
            return _read_model_failure_response(error, collection="recorders")
        return HTTPStatus.ACCEPTED, _recorder_list_response(recorders)

    if method == "POST" and path == "/lab/sessions":
        try:
            request = _parse_session_create(_json_body(body), scenarios=scenarios)
        except LabRequestError as error:
            return error.status, {"error": error.code, "message": error.message}
        try:
            session = session_store.create(request)
        except LabSessionStoreUnavailable as error:
            return _store_failure_response(error, operation_id=None)
        return HTTPStatus.ACCEPTED, _session_response(
            session.as_json(),
            operation_id=f"lab-session-create-{session.session_id}",
        )

    if method == "GET" and len(parts) == 3 and parts[:2] == ["lab", "sessions"]:
        session_id = parts[2]
        try:
            session = session_store.get(session_id)
        except LabSessionStoreUnavailable as error:
            return _store_failure_response(error, operation_id=None)
        if session is None:
            return HTTPStatus.NOT_FOUND, _missing_session_response(
                session_id,
                operation_id=None,
            )
        return HTTPStatus.OK, _session_response(session.as_json(), operation_id=None)

    if method == "POST" and len(parts) == 4 and parts[:2] == ["lab", "sessions"]:
        session_id = parts[2]
        if parts[3] == "start":
            operation_id = f"lab-session-start-{session_id}"
            try:
                session = session_store.start(session_id)
                if session is not None:
                    beds = tuple(
                        bed
                        for bed in session_store.list_beds()
                        if bed.session_id == session.session_id
                    )
                    recorders = tuple(
                        recorder
                        for recorder in session_store.list_recorders()
                        if recorder.session_id == session.session_id
                    )
                    execution_results = execution_engine.start_session(
                        session=session,
                        beds=beds,
                        recorders=recorders,
                        result_sink=session_store.save_recorder_execution_results,
                    )
                    session_store.save_recorder_execution_results(
                        execution_results,
                    )
            except LabSessionStoreUnavailable as error:
                return _store_failure_response(error, operation_id=operation_id)
        elif parts[3] == "stop":
            operation_id = f"lab-session-stop-{session_id}"
            try:
                execution_engine.stop_session(session_id)
                session = session_store.stop(session_id)
            except LabSessionStoreUnavailable as error:
                return _store_failure_response(error, operation_id=operation_id)
        else:
            return HTTPStatus.NOT_FOUND, {"error": "not_found"}
        if session is None:
            return HTTPStatus.NOT_FOUND, _missing_session_response(
                session_id,
                operation_id=operation_id,
            )
        return HTTPStatus.ACCEPTED, _session_response(
            session.as_json(),
            operation_id=operation_id,
        )

    if (
        method == "POST"
        and len(parts) == 6
        and parts[:2] == ["lab", "sessions"]
        and parts[3] == "recorders"
        and parts[5] in {"start", "stop"}
    ):
        session_id = parts[2]
        recorder_id = parts[4]
        action = parts[5]
        operation_id = f"lab-recorder-{action}-{recorder_id}"
        try:
            session = session_store.get(session_id)
            if session is None:
                return HTTPStatus.NOT_FOUND, _missing_session_response(
                    session_id,
                    operation_id=operation_id,
                )
            session_beds = tuple(
                bed for bed in session_store.list_beds() if bed.session_id == session_id
            )
            session_recorders = tuple(
                recorder
                for recorder in session_store.list_recorders()
                if recorder.session_id == session_id
            )
            target_recorder = next(
                (
                    recorder
                    for recorder in session_recorders
                    if recorder.recorder_id == recorder_id
                ),
                None,
            )
            if target_recorder is None:
                return HTTPStatus.NOT_FOUND, {
                    "state": "failed",
                    "operationId": operation_id,
                    "recorder": None,
                    "readError": (
                        "Lab recorder is not available in session: "
                        f"{session_id} recorder={recorder_id}"
                    ),
                }
            rejection = lab_recorder_control_rejection(
                action=action,
                session_state=session.state,
                recorder_state=target_recorder.state,
            )
            if rejection is not None:
                return HTTPStatus.CONFLICT, {
                    "state": "failed",
                    "operationId": operation_id,
                    "recorder": None,
                    "readError": f"Lab recorder {action} rejected: {rejection}",
                }
            if action == "start":
                recorder = session_store.start_recorder(session_id, recorder_id)
                if recorder is not None:
                    execution_engine.start_recorder(
                        session=session,
                        beds=session_beds,
                        recorders=session_recorders,
                        recorder_id=recorder_id,
                        result_sink=session_store.save_recorder_execution_results,
                    )
            else:
                recorder = session_store.stop_recorder(session_id, recorder_id)
                if recorder is not None:
                    execution_engine.stop_recorder(session_id, recorder_id)
        except LabSessionStoreUnavailable as error:
            return HTTPStatus.SERVICE_UNAVAILABLE, {
                "state": "failed",
                "operationId": operation_id,
                "recorder": None,
                "readError": error.message,
            }
        if recorder is None:
            return HTTPStatus.NOT_FOUND, {
                "state": "failed",
                "operationId": operation_id,
                "recorder": None,
                "readError": (
                    "Lab recorder is not available in session: "
                    f"{session_id}/{recorder_id}"
                ),
            }
        try:
            refreshed = next(
                (
                    candidate
                    for candidate in session_store.list_recorders()
                    if candidate.recorder_id == recorder_id
                ),
                recorder,
            )
        except LabSessionStoreUnavailable as error:
            return HTTPStatus.SERVICE_UNAVAILABLE, {
                "state": "failed",
                "operationId": operation_id,
                "recorder": None,
                "readError": error.message,
            }
        return HTTPStatus.ACCEPTED, {
            "state": "loaded",
            "operationId": operation_id,
            "recorder": refreshed.as_json(),
            "readError": None,
        }

    if method == "POST" and parts == ["lab", "vital-files", "replay"]:
        try:
            payload = _json_body(body)
            vital_file_path = string_field(payload, "vitalFilePath")
            validate_vital_file_path(vital_file_path, settings=settings)
            session_name = optional_string_field(payload, "sessionName")
            target_url = optional_string_field(payload, "targetURL")
        except LabRequestError as error:
            return error.status, {"error": error.code, "message": error.message}
        try:
            session = session_store.create(
                LabSessionCreateInput(
                    scenario_id="vital-file-replay",
                    name=session_name or "Vital File Replay",
                    recorder_count=1,
                    target_url=target_url,
                    vital_file_path=vital_file_path,
                )
            )
        except LabSessionStoreUnavailable as error:
            return _store_failure_response(error, operation_id=None)
        return HTTPStatus.ACCEPTED, _session_response(
            session.as_json(),
            operation_id=f"lab-vital-file-replay-{session.session_id}",
        )

    if method == "POST" and parts == ["lab", "vital-files", "upload"]:
        operation_id = "lab-vital-file-upload"
        try:
            payload = _json_body(body)
            vital_file_path = string_field(payload, "vitalFilePath")
            validate_vital_file_path(vital_file_path, settings=settings)
            target_url = string_field(payload, "targetURL")
            endpoint = optional_string_field(payload, "endpoint") or "/upload"
            vrcode = optional_string_field(payload, "vrcode")
        except LabRequestError as error:
            return error.status, {"error": error.code, "message": error.message}
        try:
            receipt = execution_engine.upload_vital_file(
                target_url=target_url,
                file_path=Path(vital_file_path),
                endpoint=endpoint,
                vrcode=vrcode,
            )
        except LabRecorderSendError as error:
            return HTTPStatus.BAD_GATEWAY, _vital_file_upload_failure_response(
                str(error),
                operation_id=operation_id,
            )
        return HTTPStatus.ACCEPTED, _vital_file_upload_response(
            receipt,
            operation_id=operation_id,
        )

    return HTTPStatus.NOT_FOUND, {"error": "not_found"}


def _json_body(body: bytes) -> dict[str, Any]:
    if not body:
        raise LabRequestError(
            "missing_body",
            "Request body is required.",
            HTTPStatus.BAD_REQUEST,
        )
    try:
        decoded = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LabRequestError(
            "invalid_json",
            "Request body must be valid JSON.",
            HTTPStatus.BAD_REQUEST,
        ) from error
    if not isinstance(decoded, dict):
        raise LabRequestError(
            "invalid_json_document",
            "Request body must be a JSON object.",
            HTTPStatus.BAD_REQUEST,
        )
    return decoded


def _parse_session_create(
    payload: dict[str, Any],
    *,
    scenarios: tuple[LabScenario, ...],
) -> LabSessionCreateInput:
    scenario_id = string_field(payload, "scenarioId")
    available_scenarios = {scenario.scenario_id for scenario in scenarios}
    if scenario_id not in available_scenarios:
        raise LabRequestError(
            "scenario_not_found",
            f"Lab scenario is not available: {scenario_id}",
            HTTPStatus.NOT_FOUND,
        )
    name = optional_string_field(payload, "name") or scenario_id
    recorder_count = int_field(payload, "recorderCount", default=1)
    if recorder_count < 1:
        raise LabRequestError(
            "invalid_recorder_count",
            "recorderCount must be greater than zero.",
            HTTPStatus.BAD_REQUEST,
        )
    target_url = optional_string_field(payload, "targetURL")
    bed_room_names = optional_string_list_field(payload, "bedRoomNames")
    bed_ids = optional_string_list_field(payload, "bedIds")
    if bed_ids and bed_room_names:
        raise LabRequestError(
            "bedIds_with_bedRoomNames",
            "bedIds cannot be combined with bedRoomNames.",
            HTTPStatus.BAD_REQUEST,
        )
    if bed_ids and "recorderCount" in payload and recorder_count != len(bed_ids):
        raise LabRequestError(
            "recorderCount_bedIds_mismatch",
            "recorderCount must match bedIds when bedIds are provided.",
            HTTPStatus.BAD_REQUEST,
        )
    if bed_ids:
        recorder_count = len(bed_ids)
    if bed_room_names is not None and len(bed_room_names) < recorder_count:
        raise LabRequestError(
            "bedRoomNames_insufficient",
            "bedRoomNames must include at least one bed per recorder.",
            HTTPStatus.BAD_REQUEST,
        )
    return LabSessionCreateInput(
        scenario_id=scenario_id,
        name=name,
        recorder_count=recorder_count,
        target_url=target_url,
        bed_room_names=bed_room_names or (),
        bed_ids=bed_ids or (),
    )


def _parse_bed_create(payload: dict[str, Any]) -> LabBedCreateInput:
    room_names = optional_string_list_field(payload, "roomNames") or ()
    count = int_field(payload, "count", default=len(room_names) or 1)
    if count < 1:
        raise LabRequestError(
            "count_invalid",
            "count must be greater than zero.",
            HTTPStatus.BAD_REQUEST,
        )
    if room_names and len(room_names) < count:
        raise LabRequestError(
            "roomNames_insufficient",
            "roomNames must include at least one name per bed.",
            HTTPStatus.BAD_REQUEST,
        )
    prefix = optional_string_field(payload, "prefix") or "Lab bed"
    names = room_names or tuple(f"{prefix}-{index}" for index in range(1, count + 1))
    return LabBedCreateInput(
        count=count,
        room_names=names,
        prefix=prefix,
        target_url=optional_string_field(payload, "targetURL"),
    )


def _parse_bed_delete(payload: dict[str, Any]) -> LabBedDeleteInput:
    request = LabBedDeleteInput(
        bed_ids=optional_string_list_field(payload, "bedIds") or (),
        room_names=(
            optional_string_list_field(payload, "roomNames")
            or optional_string_list_field(payload, "names")
            or ()
        ),
        session_id=optional_string_field(payload, "sessionId"),
    )
    if not request.bed_ids and not request.room_names and request.session_id is None:
        raise LabRequestError(
            "bed_delete_target_required",
            "bedIds, roomNames, or sessionId is required.",
            HTTPStatus.BAD_REQUEST,
        )
    return request


def _parse_recorder_create(payload: dict[str, Any]) -> LabRecorderCreateInput:
    request = LabRecorderCreateInput(
        bed_ids=optional_string_list_field(payload, "bedIds") or (),
        session_id=optional_string_field(payload, "sessionId"),
    )
    if not request.bed_ids and request.session_id is None:
        raise LabRequestError(
            "recorder_create_target_required",
            "bedIds or sessionId is required.",
            HTTPStatus.BAD_REQUEST,
        )
    return request


def _parse_recorder_delete(payload: dict[str, Any]) -> LabRecorderDeleteInput:
    request = LabRecorderDeleteInput(
        recorder_ids=optional_string_list_field(payload, "recorderIds") or (),
        vrcodes=optional_string_list_field(payload, "vrcodes") or (),
        session_id=optional_string_field(payload, "sessionId"),
    )
    if not request.recorder_ids and not request.vrcodes and request.session_id is None:
        raise LabRequestError(
            "recorder_delete_target_required",
            "recorderIds, vrcodes, or sessionId is required.",
            HTTPStatus.BAD_REQUEST,
        )
    return request


class LabRequestError(Exception):
    def __init__(self, code: str, message: str, status: HTTPStatus) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def string_field(payload: dict[str, Any], field_name: str) -> str:
    value = payload.get(field_name)
    if not isinstance(value, str) or not value.strip():
        raise LabRequestError(
            f"{field_name}_required",
            f"{field_name} is required.",
            HTTPStatus.BAD_REQUEST,
        )
    return value.strip()


def optional_string_field(payload: dict[str, Any], field_name: str) -> str | None:
    value = payload.get(field_name)
    if value is None:
        return None
    if not isinstance(value, str):
        raise LabRequestError(
            f"{field_name}_invalid",
            f"{field_name} must be a string when provided.",
            HTTPStatus.BAD_REQUEST,
        )
    stripped = value.strip()
    return stripped or None


def optional_string_list_field(
    payload: dict[str, Any],
    field_name: str,
) -> tuple[str, ...] | None:
    value = payload.get(field_name)
    if value is None:
        return None
    if not isinstance(value, list):
        raise LabRequestError(
            f"{field_name}_invalid",
            f"{field_name} must be an array when provided.",
            HTTPStatus.BAD_REQUEST,
        )
    names: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            raise LabRequestError(
                f"{field_name}_invalid",
                f"{field_name} entries must be non-empty strings.",
                HTTPStatus.BAD_REQUEST,
            )
        names.append(item.strip())
    return tuple(names)


def int_field(payload: dict[str, Any], field_name: str, *, default: int) -> int:
    value = payload.get(field_name, default)
    if isinstance(value, bool) or not isinstance(value, int):
        raise LabRequestError(
            f"{field_name}_invalid",
            f"{field_name} must be an integer.",
            HTTPStatus.BAD_REQUEST,
        )
    return value


def validate_vital_file_path(path: str, *, settings: LabSettings) -> None:
    candidate = Path(path)
    if not candidate.is_absolute():
        raise LabRequestError(
            "vitalFilePath_not_absolute",
            "vitalFilePath must be an absolute guest path.",
            HTTPStatus.BAD_REQUEST,
        )
    if candidate.suffix.lower() != ".vital":
        raise LabRequestError(
            "vitalFilePath_invalid_extension",
            "vitalFilePath must point to a .vital file.",
            HTTPStatus.BAD_REQUEST,
        )

    mount = settings.vital_files_mount.resolve(strict=False)
    resolved = candidate.resolve(strict=False)
    if not resolved.is_relative_to(mount):
        raise LabRequestError(
            "vitalFilePath_outside_mount",
            "vitalFilePath must be under the configured vital files mount.",
            HTTPStatus.BAD_REQUEST,
        )
    if not resolved.is_file():
        raise LabRequestError(
            "vitalFilePath_missing",
            "vitalFilePath is not available in the configured mount.",
            HTTPStatus.NOT_FOUND,
        )


def list_vital_files(
    *,
    settings: LabSettings,
    maximum_files: int = 1000,
) -> tuple[LabVitalFile, ...]:
    mount = settings.vital_files_mount.resolve(strict=False)
    if not mount.exists():
        raise LabRequestError(
            "vitalFilesMount_missing",
            "Configured vital files mount is not available.",
            HTTPStatus.NOT_FOUND,
        )
    if not mount.is_dir():
        raise LabRequestError(
            "vitalFilesMount_not_directory",
            "Configured vital files mount is not a directory.",
            HTTPStatus.BAD_REQUEST,
        )

    vital_files: list[LabVitalFile] = []
    for candidate in mount.rglob("*.vital"):
        if len(vital_files) >= maximum_files:
            break
        if not candidate.is_file():
            continue
        stat = candidate.stat()
        relative_path = candidate.relative_to(mount).as_posix()
        vital_files.append(
            LabVitalFile(
                display_name=candidate.name,
                relative_path=relative_path,
                guest_path=str(candidate),
                size_bytes=stat.st_size,
                modified_at=utc_now_iso_from_timestamp(stat.st_mtime),
            )
        )
    return tuple(sorted(vital_files, key=lambda item: item.relative_path.lower()))


def utc_now_iso_from_timestamp(timestamp: float) -> str:
    return (
        datetime.fromtimestamp(timestamp, UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _session_response(
    session: dict[str, object],
    *,
    operation_id: str | None,
) -> dict[str, object]:
    return {
        "state": "loaded",
        "operationId": operation_id,
        "session": session,
        "readError": None,
    }


def _bed_list_response(beds: tuple[object, ...]) -> dict[str, object]:
    return {
        "state": "loaded",
        "beds": [bed.as_json() for bed in beds],
        "readError": None,
    }


def _recorder_list_response(recorders: tuple[object, ...]) -> dict[str, object]:
    return {
        "state": "loaded",
        "recorders": [recorder.as_json() for recorder in recorders],
        "readError": None,
    }


def _vital_file_upload_response(
    receipt: LabVitalFileUploadReceipt,
    *,
    operation_id: str,
) -> dict[str, object]:
    read_error = (
        None
        if receipt.ok
        else (
            receipt.response_text
            or f"VitalServer upload failed: status={receipt.status_code}"
        )
    )
    return {
        "state": "loaded" if receipt.ok else "failed",
        "operationId": operation_id,
        "upload": receipt.as_json(),
        "readError": read_error,
    }


def _vital_file_upload_failure_response(
    message: str,
    *,
    operation_id: str,
) -> dict[str, object]:
    return {
        "state": "failed",
        "operationId": operation_id,
        "upload": None,
        "readError": message,
    }


def _missing_session_response(
    session_id: str,
    *,
    operation_id: str | None,
) -> dict[str, object]:
    return {
        "state": "failed",
        "operationId": operation_id,
        "session": None,
        "readError": f"Lab session is not available: {session_id}",
    }


def _store_failure_response(
    error: LabSessionStoreUnavailable,
    *,
    operation_id: str | None,
) -> tuple[HTTPStatus, dict[str, object]]:
    return HTTPStatus.SERVICE_UNAVAILABLE, {
        "state": "failed",
        "operationId": operation_id,
        "session": None,
        "readError": error.message,
    }


def _read_model_failure_response(
    error: LabSessionStoreUnavailable,
    *,
    collection: str,
) -> tuple[HTTPStatus, dict[str, object]]:
    return HTTPStatus.SERVICE_UNAVAILABLE, {
        "state": "failed",
        collection: [],
        "readError": error.message,
    }


def build_session_store(settings: LabSettings) -> LabSessionStore:
    if settings.session_store == "memory":
        if not settings.allow_memory_store:
            raise LabSessionStoreUnavailable(
                "memory Lab session store requires VITALSERVER_LAB_ALLOW_MEMORY_STORE",
                kind="labSessionStoreConfigurationInvalid",
            )
        return InMemoryLabSessionStore()
    if settings.session_store == "postgres":
        if not settings.database_url:
            raise LabSessionStoreUnavailable(
                "VITALSERVER_LAB_DATABASE_URL is required for postgres session store",
                kind="labSessionStoreConfigurationInvalid",
            )
        store = SQLAlchemyLabSessionStore(settings.database_url)
        store.ensure_ready()
        return store
    raise LabSessionStoreUnavailable(
        f"unsupported Lab session store: {settings.session_store}",
        kind="labSessionStoreConfigurationInvalid",
    )


def build_execution_engine(settings: LabSettings | None = None) -> LabExecutionEngine:
    del settings
    return LabExecutionEngine(sender=VitalServerRecorderPayloadSender())


def main() -> None:
    settings = load_settings()
    server = LabServer((settings.host, settings.port), settings)
    server.serve_forever()


if __name__ == "__main__":
    main()
