from __future__ import annotations

import json
import os
import stat
from datetime import UTC, datetime
from email import policy
from email.parser import BytesParser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import ThreadingMixIn, UnixStreamServer
from threading import Thread
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

from tirosh_guest_tools.adapters.outbound.compose import ComposeGuestControlAdapter
from tirosh_guest_tools.adapters.outbound.maintenance import (
    DatastoreRepairMaintenanceAdapter,
    RedisBackupMaintenanceAdapter,
    UpdateActivationMaintenanceAdapter,
    UpdateShutdownMaintenanceAdapter,
)
from tirosh_guest_tools.adapters.outbound.postgres import (
    PostgresVitalDBReadModelRepository,
)
from tirosh_guest_tools.adapters.outbound.product_lab import ProductLabServiceAdapter
from tirosh_guest_tools.adapters.outbound.recorder_ingress import (
    RecorderIngressStatusServiceAdapter,
)
from tirosh_guest_tools.adapters.outbound.redis_relay_settings import (
    FileRedisRelaySettingsRepository,
)
from tirosh_guest_tools.adapters.outbound.runtime_admin import (
    FileRuntimeAdminRepository,
)
from tirosh_guest_tools.adapters.outbound.runtime_settings import (
    FileRuntimeSettingsRepository,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control import SQLiteControlRepository
from tirosh_guest_tools.adapters.outbound.vital_files import FileVitalFileLibrary
from tirosh_guest_tools.application.guest_control.runtime import (
    SystemClock,
    UUIDOperationIdFactory,
)
from tirosh_guest_tools.application.guest_control.usecases import GuestControlUseCases
from tirosh_guest_tools.domain.guest_control.models import (
    RUNTIME_OPERATION_EVENT_TYPES,
    GuestControlDependencyError,
    GuestServiceDesiredState,
    RedisRelayStatusContractError,
    ServiceNotFoundError,
    VitalDBReadModelDependencyError,
)
from tirosh_guest_tools.domain.redis_relay_settings import (
    RedisRelaySettingsContractError,
    validated_redis_relay_settings,
)
from tirosh_guest_tools.domain.runtime_admin import (
    RuntimeAdminPasswordContractError,
    validated_admin_password,
)
from tirosh_guest_tools.domain.runtime_settings import (
    RuntimeSettingsContractError,
    validated_runtime_settings,
)
from tirosh_guest_tools.infrastructure.settings import SETTINGS

DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 18330
DEFAULT_GUEST_SERVICE_SPECS = dict.fromkeys(
    (
        "postgres",
        "redis",
        "app",
        "recorder-recovery",
        "recorder-ingress",
        "vitaldb-observer",
        "redis-relay",
        "lab",
        "redis-ui",
        "swagger-ui",
        "edge",
    ),
    GuestServiceDesiredState.RUNNING,
)
REDIS_RELAY_STATUS_OWNER_PATH = "/runtime/redis-relay/status"
# This declaration is a build-time parity boundary. The normal Guest HTTP
# transport continues to dispatch explicit extension routes below; it must not
# become a core-only allowlist.
RUNTIME_V2_READ_CORE_ROUTES = (
    ("GET", "/runtime/capabilities"),
    ("GET", "/runtime/services"),
    ("GET", "/runtime/stack"),
)
RUNTIME_EVENT_QUERY_ERROR_KINDS = frozenset(
    {"runtimeEventCursorInvalid", "runtimeEventQueryInvalid"}
)


class GuestControlAPIError(Exception):
    def __init__(self, status: HTTPStatus, *, detail: str, code: str) -> None:
        super().__init__(detail)
        self.status = status
        self.detail = detail
        self.code = code


def build_default_usecases() -> GuestControlUseCases:
    operations = SQLiteControlRepository(
        SETTINGS.paths.control_state_dir / "control.sqlite"
    )
    vitaldb_read_model = PostgresVitalDBReadModelRepository()
    operations.check_ready()
    usecases = GuestControlUseCases(
        service_control=ComposeGuestControlAdapter(),
        product_lab=ProductLabServiceAdapter(),
        recorder_ingress=RecorderIngressStatusServiceAdapter(),
        redis_relay=operations,
        runtime_settings=FileRuntimeSettingsRepository(
            SETTINGS.paths.runtime_settings_file
        ),
        runtime_admin=FileRuntimeAdminRepository(SETTINGS.paths.runtime_config_file),
        redis_relay_settings=FileRedisRelaySettingsRepository(
            SETTINGS.paths.redis_relay_config_file,
            SETTINGS.paths.redis_relay_password_file,
        ),
        vitaldb_read_model=vitaldb_read_model,
        redis_backup=RedisBackupMaintenanceAdapter(),
        datastore_repair=DatastoreRepairMaintenanceAdapter(),
        update_activation=UpdateActivationMaintenanceAdapter(),
        update_shutdown=UpdateShutdownMaintenanceAdapter(),
        operations=operations,
        service_status_snapshots=operations,
        guest_service_resources=operations,
        operation_ids=UUIDOperationIdFactory(),
        clock=SystemClock(),
        vital_file_library=FileVitalFileLibrary(SETTINGS.shares.vital_files_mount),
    )
    usecases.recover_interrupted_operations()
    usecases.initialize_guest_service_specs(DEFAULT_GUEST_SERVICE_SPECS)
    return usecases


def make_handler(
    usecases: GuestControlUseCases,
    *,
    allowed_routes: frozenset[tuple[str, str]] | None = None,
) -> type[BaseHTTPRequestHandler]:
    class GuestControlAPIHandler(BaseHTTPRequestHandler):
        server_version = "TiroshGuestControlAPI/0.1"

        def do_GET(self) -> None:
            self._handle_request("GET")

        def do_POST(self) -> None:
            self._handle_request("POST")

        def do_PUT(self) -> None:
            self._handle_request("PUT")

        def log_message(self, format: str, *args: Any) -> None:
            del format
            del args

        def _handle_request(self, method: str) -> None:
            try:
                parsed = urlparse(self.path)
                if (
                    allowed_routes is not None
                    and (method, parsed.path) not in allowed_routes
                ):
                    raise GuestControlAPIError(
                        HTTPStatus.NOT_FOUND,
                        detail="The status owner transport does not serve this route.",
                        code="statusOwnerRouteNotFound",
                    )
                status, document = route_request(
                    method=method,
                    path=parsed.path,
                    query=parse_qs(parsed.query, keep_blank_values=True),
                    body=self._request_body(),
                    headers={key.lower(): value for key, value in self.headers.items()},
                    usecases=usecases,
                )
            except GuestControlAPIError as error:
                self._write_json(
                    error.status,
                    {
                        "detail": error.detail,
                        "code": error.code,
                    },
                )
                return
            except ServiceNotFoundError as error:
                self._write_json(
                    HTTPStatus.NOT_FOUND,
                    {
                        "detail": error.message,
                        "code": error.kind,
                        "availableServices": error.available_services,
                    },
                )
                return
            except GuestControlDependencyError as error:
                if error.kind == "vitalFileUploadInvalid":
                    self._write_json(
                        HTTPStatus.BAD_REQUEST,
                        {"detail": error.message, "code": error.kind},
                    )
                    return
                if error.kind == "vitalFileUploadConflict":
                    self._write_json(
                        HTTPStatus.CONFLICT,
                        {"detail": error.message, "code": error.kind},
                    )
                    return
                if error.kind == "guestServiceSpecInvalid":
                    self._write_json(
                        HTTPStatus.BAD_REQUEST,
                        {
                            "detail": error.message,
                            "code": error.kind,
                        },
                    )
                    return
                if error.kind == "operationLeaseConflict":
                    self._write_json(
                        HTTPStatus.CONFLICT,
                        {
                            "detail": error.message,
                            # The SQLite lease is an adapter detail. The HTTP
                            # contract exposes the domain meaning: one command
                            # is already in progress, so accepting another one
                            # would violate the global control lease.
                            "code": "operationInProgress",
                        },
                    )
                    return
                self._write_json(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    {
                        "detail": error.message,
                        "code": error.kind,
                    },
                )
                return
            except VitalDBReadModelDependencyError as error:
                self._write_json(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    {
                        "detail": error.message,
                        "code": error.kind,
                    },
                )
                return

            self._write_json(status, document)

        def _write_json(
            self,
            status: HTTPStatus,
            document: dict[str, Any],
        ) -> None:
            payload = json.dumps(document, sort_keys=True).encode("utf-8")
            self.send_response(status.value)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def _request_body(self) -> bytes:
            length_text = self.headers.get("Content-Length")
            if not length_text:
                return b""
            try:
                length = int(length_text)
            except ValueError:
                return b""
            if length <= 0:
                return b""
            return self.rfile.read(length)

    return GuestControlAPIHandler


def route_request(
    *,
    method: str,
    path: str,
    query: dict[str, list[str]] | None = None,
    body: bytes = b"",
    headers: dict[str, str] | None = None,
    usecases: GuestControlUseCases,
) -> tuple[HTTPStatus, dict[str, Any]]:
    parts = [unquote(part) for part in path.split("/") if part]
    query = query or {}
    headers = headers or {}

    if method == "GET" and parts == ["health"]:
        return HTTPStatus.OK, {"status": "ok"}

    if method == "GET" and parts == ["ready"]:
        readiness = usecases.readiness()
        status = (
            HTTPStatus.OK
            if readiness["status"] == "ready"
            else HTTPStatus.SERVICE_UNAVAILABLE
        )
        return status, readiness

    if method == "GET" and parts == ["runtime", "capabilities"]:
        return HTTPStatus.OK, usecases.capabilities()

    if method == "GET" and parts == ["runtime", "events"]:
        try:
            events = usecases.get_runtime_events(
                limit=_query_int(query, "limit", default=100, minimum=1, maximum=500),
                event_type=_optional_runtime_operation_event_type(query),
                since=_optional_query_datetime(query, "since"),
                cursor=_optional_query_string(query, "cursor"),
            )
        except GuestControlDependencyError as error:
            if error.kind not in RUNTIME_EVENT_QUERY_ERROR_KINDS:
                raise
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail=error.message,
                code="queryParameterInvalid",
            ) from error
        return HTTPStatus.OK, events

    if method == "GET" and parts == ["runtime", "settings"]:
        return HTTPStatus.OK, usecases.get_runtime_settings()

    if method == "PUT" and parts == ["runtime", "settings"]:
        request = _json_body(body)
        settings = request.get("settings")
        if not isinstance(settings, dict):
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail="JSON request settings field must be an object.",
                code="runtimeSettingsInvalid",
            )
        try:
            validated = validated_runtime_settings(settings)
        except RuntimeSettingsContractError as error:
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail=str(error),
                code="runtimeSettingsInvalid",
            ) from error
        return HTTPStatus.ACCEPTED, usecases.apply_runtime_settings(validated).as_json()

    if method == "POST" and parts == ["runtime", "admin-password"]:
        request = _json_body(body)
        try:
            password = validated_admin_password(request.get("password"))
        except RuntimeAdminPasswordContractError as error:
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail=str(error),
                code="runtimeAdminPasswordInvalid",
            ) from error
        return HTTPStatus.ACCEPTED, usecases.apply_admin_password(password).as_json()

    if method == "GET" and parts == ["runtime", "services"]:
        return HTTPStatus.OK, {"services": usecases.list_services()}

    if method == "GET" and parts == ["runtime", "stack"]:
        return HTTPStatus.OK, usecases.get_stack_status().as_json()

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:2] == ["runtime", "services"]
        and parts[3] == "status"
    ):
        return HTTPStatus.OK, usecases.get_service_status(parts[2]).as_json()

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:2] == ["runtime", "services"]
        and parts[3] == "resource"
    ):
        return HTTPStatus.OK, usecases.get_guest_service_resource(parts[2])

    if (
        method == "PUT"
        and len(parts) == 4
        and parts[:2] == ["runtime", "services"]
        and parts[3] == "spec"
    ):
        return HTTPStatus.OK, usecases.update_guest_service_spec(
            parts[2],
            _json_body(body),
        )

    if (
        method == "POST"
        and len(parts) == 4
        and parts[:2] == ["runtime", "services"]
        and parts[3] == "observe"
    ):
        return HTTPStatus.ACCEPTED, usecases.observe_guest_service(parts[2])

    if (
        method == "POST"
        and len(parts) == 4
        and parts[:2] == ["runtime", "services"]
        and parts[3] == "reconcile"
    ):
        return HTTPStatus.ACCEPTED, usecases.reconcile_guest_service(parts[2]).as_json()

    if (
        method == "POST"
        and len(parts) == 4
        and parts[:2] == ["runtime", "services"]
        and parts[3] in {"start", "stop", "restart"}
    ):
        command = parts[3]
        if command == "start":
            operation = usecases.start_service(parts[2])
        elif command == "stop":
            operation = usecases.stop_service(parts[2])
        else:
            operation = usecases.restart_service(parts[2])
        return HTTPStatus.ACCEPTED, operation.as_json()

    if method == "POST" and parts == ["runtime", "stack", "reconcile"]:
        return HTTPStatus.ACCEPTED, usecases.reconcile_services().as_json()

    if method == "GET" and parts == ["runtime", "lab", "scenarios"]:
        return HTTPStatus.OK, usecases.list_lab_scenarios()

    if method == "GET" and parts == ["runtime", "lab", "vital-files"]:
        return HTTPStatus.OK, usecases.list_lab_vital_files()

    if method == "GET" and parts == ["runtime", "lab", "beds"]:
        return HTTPStatus.OK, usecases.list_lab_beds()

    if method == "GET" and parts == ["runtime", "lab", "recorders"]:
        return HTTPStatus.OK, usecases.list_lab_recorders()

    if method == "GET" and parts == ["runtime", "lab", "sessions"]:
        return HTTPStatus.OK, usecases.list_lab_sessions()

    if method == "POST" and parts == ["runtime", "lab", "beds", "create"]:
        return HTTPStatus.ACCEPTED, usecases.create_lab_beds(_json_body(body))

    if method == "POST" and parts == ["runtime", "lab", "beds", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_lab_beds(_json_body(body))

    if method == "POST" and parts == ["runtime", "lab", "beds", "reset"]:
        return HTTPStatus.ACCEPTED, usecases.reset_lab_beds()

    if method == "POST" and parts == ["runtime", "lab", "recorders", "create"]:
        return HTTPStatus.ACCEPTED, usecases.create_lab_recorders(_json_body(body))

    if method == "POST" and parts == ["runtime", "lab", "recorders", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_lab_recorders(_json_body(body))

    if method == "POST" and parts == ["runtime", "lab", "recorders", "reset"]:
        return HTTPStatus.ACCEPTED, usecases.reset_lab_recorders()

    if method == "POST" and parts == ["runtime", "lab", "sessions"]:
        return HTTPStatus.ACCEPTED, usecases.create_lab_session(_json_body(body))

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:3] == ["runtime", "lab", "sessions"]
    ):
        return HTTPStatus.OK, usecases.get_lab_session(parts[3])

    if (
        method == "POST"
        and len(parts) == 5
        and parts[:3] == ["runtime", "lab", "sessions"]
        and parts[4] == "start"
    ):
        return HTTPStatus.ACCEPTED, usecases.start_lab_session(parts[3])

    if (
        method == "POST"
        and len(parts) == 5
        and parts[:3] == ["runtime", "lab", "sessions"]
        and parts[4] == "stop"
    ):
        return HTTPStatus.ACCEPTED, usecases.stop_lab_session(parts[3])

    if (
        method == "POST"
        and len(parts) == 7
        and parts[:3] == ["runtime", "lab", "sessions"]
        and parts[4] == "recorders"
        and parts[6] == "start"
    ):
        return HTTPStatus.ACCEPTED, usecases.start_lab_recorder(parts[3], parts[5])

    if (
        method == "POST"
        and len(parts) == 7
        and parts[:3] == ["runtime", "lab", "sessions"]
        and parts[4] == "recorders"
        and parts[6] == "stop"
    ):
        return HTTPStatus.ACCEPTED, usecases.stop_lab_recorder(parts[3], parts[5])

    if method == "POST" and parts == ["runtime", "lab", "vital-files", "replay"]:
        return HTTPStatus.ACCEPTED, usecases.replay_lab_vital_file(_json_body(body))

    if method == "POST" and parts == ["runtime", "lab", "vital-files", "upload"]:
        files = _multipart_vital_files(
            body,
            content_type=headers.get("content-type"),
        )
        return HTTPStatus.OK, usecases.import_lab_vital_files(files)

    if method == "POST" and parts == ["runtime", "maintenance", "redis-backup"]:
        return HTTPStatus.ACCEPTED, usecases.create_redis_backup().as_json()

    if method == "POST" and parts == ["runtime", "maintenance", "redis-restore"]:
        return HTTPStatus.ACCEPTED, usecases.restore_redis_backup(
            _required_string(_json_body(body), "archive")
        ).as_json()

    if method == "POST" and parts == ["runtime", "maintenance", "datastore", "repair"]:
        return HTTPStatus.ACCEPTED, usecases.repair_datastore().as_json()

    if method == "POST" and parts == ["runtime", "maintenance", "update-activation"]:
        request = _json_body(body)
        return HTTPStatus.ACCEPTED, usecases.activate_update(
            request_id=_required_string(request, "requestId"),
            version=_required_string(request, "version"),
        ).as_json()

    if method == "POST" and parts == ["runtime", "maintenance", "update-shutdown"]:
        request = _json_body(body)
        return HTTPStatus.ACCEPTED, usecases.prepare_update_shutdown(
            request_id=_required_string(request, "requestId"),
            version=_required_string(request, "version"),
        ).as_json()

    if method == "POST" and parts == ["runtime", "maintenance", "guest-poweroff"]:
        return HTTPStatus.ACCEPTED, usecases.request_guest_poweroff().as_json()

    if method == "GET" and parts == ["runtime", "recorder-ingress", "status"]:
        return HTTPStatus.OK, usecases.get_recorder_ingress_status()

    if method == "GET" and parts == ["runtime", "redis-relay", "status"]:
        return HTTPStatus.OK, usecases.get_redis_relay_status()

    if method == "GET" and parts == ["runtime", "redis-relay", "settings"]:
        return HTTPStatus.OK, usecases.get_redis_relay_settings()

    if method == "PUT" and parts == ["runtime", "redis-relay", "settings"]:
        request = _json_body(body)
        try:
            validated_redis_relay_settings(request)
        except RedisRelaySettingsContractError as error:
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail=str(error),
                code="redisRelaySettingsInvalid",
            ) from error
        return (
            HTTPStatus.ACCEPTED,
            usecases.apply_redis_relay_settings(request).as_json(),
        )

    if method == "PUT" and parts == ["runtime", "redis-relay", "status"]:
        try:
            return HTTPStatus.OK, usecases.put_redis_relay_status(_json_body(body))
        except RedisRelayStatusContractError as error:
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail=error.message,
                code="redisRelayStatusInvalid",
            ) from error

    if method == "GET" and parts == ["runtime", "vitaldb", "observations", "latest"]:
        return HTTPStatus.OK, usecases.get_latest_vitaldb_observation()

    if method == "GET" and parts == ["runtime", "vitaldb", "recorders"]:
        return HTTPStatus.OK, usecases.list_vitaldb_recorders()

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:3] == ["runtime", "vitaldb", "recorders"]
    ):
        recorder = usecases.get_vitaldb_recorder(parts[3])
        if recorder is None:
            raise GuestControlAPIError(
                HTTPStatus.NOT_FOUND,
                detail=f"VitalDB recorder not found: {parts[3]}",
                code="vitalDBRecorderNotFound",
            )
        return HTTPStatus.OK, recorder

    if method == "POST" and parts == ["runtime", "vitaldb", "recorders", "hide"]:
        return HTTPStatus.ACCEPTED, usecases.hide_vitaldb_recorders(_json_body(body))

    if method == "POST" and parts == ["runtime", "vitaldb", "recorders", "unhide"]:
        return HTTPStatus.ACCEPTED, usecases.unhide_vitaldb_recorders(_json_body(body))

    if method == "POST" and parts == ["runtime", "vitaldb", "recorders", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_vitaldb_recorders(_json_body(body))

    if (
        method == "GET"
        and len(parts) == 5
        and parts[:3] == ["runtime", "vitaldb", "recorders"]
        and parts[4] == "activity"
    ):
        return HTTPStatus.OK, usecases.get_vitaldb_recorder_activity(parts[3])

    if method == "GET" and parts == ["runtime", "vitaldb", "beds"]:
        return HTTPStatus.OK, usecases.list_vitaldb_beds()

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:3] == ["runtime", "vitaldb", "beds"]
    ):
        bed = usecases.get_vitaldb_bed(parts[3])
        if bed is None:
            raise GuestControlAPIError(
                HTTPStatus.NOT_FOUND,
                detail=f"VitalDB bed not found: {parts[3]}",
                code="vitalDBBedNotFound",
            )
        return HTTPStatus.OK, bed

    if method == "POST" and parts == ["runtime", "vitaldb", "beds", "hide"]:
        return HTTPStatus.ACCEPTED, usecases.hide_vitaldb_beds(_json_body(body))

    if method == "POST" and parts == ["runtime", "vitaldb", "beds", "unhide"]:
        return HTTPStatus.ACCEPTED, usecases.unhide_vitaldb_beds(_json_body(body))

    if method == "POST" and parts == ["runtime", "vitaldb", "beds", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_vitaldb_beds(_json_body(body))

    if method == "GET" and parts == ["runtime", "vitaldb", "relationships"]:
        return HTTPStatus.OK, usecases.get_vitaldb_relationships()

    if method == "GET" and len(parts) == 3 and parts[:2] == ["runtime", "operations"]:
        requested_operation = usecases.get_operation(parts[2])
        if requested_operation is None:
            raise GuestControlAPIError(
                HTTPStatus.NOT_FOUND,
                detail=f"operation is not available: {parts[2]}",
                code="operationNotFound",
            )
        return HTTPStatus.OK, requested_operation.as_json()

    raise GuestControlAPIError(
        HTTPStatus.NOT_FOUND,
        detail=f"route is not available: {method} {path}",
        code="routeNotFound",
    )


def _multipart_vital_files(
    body: bytes,
    *,
    content_type: str | None,
) -> list[tuple[str, bytes]]:
    if content_type is None or not content_type.lower().startswith(
        "multipart/form-data;"
    ):
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail="Vital Files upload requires multipart/form-data.",
            code="vitalFileUploadInvalid",
        )
    message = BytesParser(policy=policy.default).parsebytes(
        b"Content-Type: "
        + content_type.encode("latin-1")
        + b"\r\nMIME-Version: 1.0\r\n\r\n"
        + body
    )
    if not message.is_multipart():
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail="Vital Files upload multipart body is invalid.",
            code="vitalFileUploadInvalid",
        )

    files: list[tuple[str, bytes]] = []
    for part in message.iter_parts():
        if part.get_content_disposition() != "form-data":
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail="Vital Files upload contains an invalid multipart part.",
                code="vitalFileUploadInvalid",
            )
        if part.get_param("name", header="content-disposition") != "files":
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail="Vital Files upload only accepts multipart field 'files'.",
                code="vitalFileUploadInvalid",
            )
        filename = part.get_filename()
        if not isinstance(filename, str) or not filename:
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail="Every Vital Files upload part requires a filename.",
                code="vitalFileUploadInvalid",
            )
        content = part.get_payload(decode=True)
        if not isinstance(content, bytes):
            raise GuestControlAPIError(
                HTTPStatus.BAD_REQUEST,
                detail=f"Vital Files upload part could not be decoded: {filename}",
                code="vitalFileUploadInvalid",
            )
        files.append((filename, content))
    if not files:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail="Select at least one .vital file.",
            code="vitalFileUploadInvalid",
        )
    return files


def _json_body(body: bytes) -> dict[str, Any]:
    if not body:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail="JSON request body is required.",
            code="requestBodyRequired",
        )
    try:
        document = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"JSON request body is invalid: {error}",
            code="requestBodyInvalid",
        ) from error
    if not isinstance(document, dict):
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail="JSON request body must be an object.",
            code="requestBodyInvalid",
        )
    return document


def _required_string(document: dict[str, Any], field: str) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not value.strip():
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"JSON request field is required: {field}",
            code="requestFieldRequired",
        )
    return value


def _optional_query_string(query: dict[str, list[str]], field: str) -> str | None:
    values = query.get(field)
    if values is None:
        return None
    if len(values) != 1 or not values[0].strip():
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"query parameter must be one non-empty value: {field}",
            code="queryParameterInvalid",
        )
    return values[0].strip()


def _query_int(
    query: dict[str, list[str]],
    field: str,
    *,
    default: int,
    minimum: int,
    maximum: int,
) -> int:
    value = _optional_query_string(query, field)
    if value is None:
        return default
    try:
        result = int(value)
    except ValueError as error:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"query parameter must be an integer: {field}",
            code="queryParameterInvalid",
        ) from error
    if result < minimum or result > maximum:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"query parameter is outside {minimum}...{maximum}: {field}",
            code="queryParameterInvalid",
        )
    return result


def _optional_query_datetime(
    query: dict[str, list[str]], field: str
) -> datetime | None:
    value = _optional_query_string(query, field)
    if value is None:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"query parameter must be an ISO-8601 timestamp: {field}",
            code="queryParameterInvalid",
        ) from error
    if parsed.tzinfo is None:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"query timestamp must include a timezone: {field}",
            code="queryParameterInvalid",
        )
    return parsed.astimezone(UTC)


def _optional_runtime_operation_event_type(
    query: dict[str, list[str]],
) -> str | None:
    value = _optional_query_string(query, "type")
    if value is None:
        return None
    if value not in RUNTIME_OPERATION_EVENT_TYPES:
        raise GuestControlAPIError(
            HTTPStatus.BAD_REQUEST,
            detail=f"query parameter is not a RuntimeEventType: type={value}",
            code="queryParameterInvalid",
        )
    return value


def serve_guest_control_api(
    *,
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    usecases: GuestControlUseCases | None = None,
    redis_relay_status_owner_socket: Path | None = None,
) -> None:
    resolved_usecases = usecases or build_default_usecases()
    handler = make_handler(resolved_usecases)
    server = ThreadingHTTPServer((host, port), handler)
    status_owner_server: ThreadingUnixHTTPServer | None = None
    status_owner_thread: Thread | None = None
    try:
        if redis_relay_status_owner_socket is not None:
            status_owner_server = create_redis_relay_status_owner_server(
                socket_path=redis_relay_status_owner_socket,
                usecases=resolved_usecases,
            )
            status_owner_thread = Thread(
                target=status_owner_server.serve_forever,
                daemon=True,
            )
            status_owner_thread.start()
        server.serve_forever()
    finally:
        server.server_close()
        if status_owner_server is not None:
            status_owner_server.shutdown()
            status_owner_server.server_close()
            _remove_status_owner_socket(redis_relay_status_owner_socket)
        if status_owner_thread is not None:
            status_owner_thread.join(timeout=1)


class ThreadingUnixHTTPServer(ThreadingMixIn, UnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True


def create_redis_relay_status_owner_server(
    *,
    socket_path: Path,
    usecases: GuestControlUseCases,
) -> ThreadingUnixHTTPServer:
    _prepare_status_owner_socket(socket_path)
    server = ThreadingUnixHTTPServer(
        os.fspath(socket_path),
        make_handler(
            usecases,
            allowed_routes=frozenset({("PUT", REDIS_RELAY_STATUS_OWNER_PATH)}),
        ),
    )
    os.chmod(socket_path, 0o600)
    return server


def _prepare_status_owner_socket(socket_path: Path) -> None:
    socket_path.parent.mkdir(parents=True, exist_ok=True)
    _remove_status_owner_socket(socket_path, require_socket=True)


def _remove_status_owner_socket(
    socket_path: Path | None,
    *,
    require_socket: bool = False,
) -> None:
    if socket_path is None:
        return
    try:
        mode = socket_path.lstat().st_mode
    except FileNotFoundError:
        return
    if not stat.S_ISSOCK(mode):
        if require_socket:
            raise RuntimeError(
                f"Redis Relay status owner socket path is not a socket: {socket_path}"
            )
        return
    socket_path.unlink()
