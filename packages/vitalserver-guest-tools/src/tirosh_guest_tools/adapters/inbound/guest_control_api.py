from __future__ import annotations

import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import unquote, urlparse

from tirosh_guest_tools.adapters.outbound.compose import ComposeGuestControlAdapter
from tirosh_guest_tools.adapters.outbound.maintenance import (
    DatastoreRepairMaintenanceAdapter,
    RedisBackupMaintenanceAdapter,
    UpdateActivationMaintenanceAdapter,
    UpdateShutdownMaintenanceAdapter,
)
from tirosh_guest_tools.adapters.outbound.postgres import (
    PostgresOperationRepository,
    PostgresVitalDBReadModelRepository,
)
from tirosh_guest_tools.adapters.outbound.product_lab import ProductLabServiceAdapter
from tirosh_guest_tools.adapters.outbound.recorder_ingress import (
    RecorderIngressStatusServiceAdapter,
)
from tirosh_guest_tools.application.guest_control.runtime import (
    SystemClock,
    UUIDOperationIdFactory,
)
from tirosh_guest_tools.application.guest_control.usecases import GuestControlUseCases
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    ServiceNotFoundError,
)

DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 18330


class GuestControlAPIError(Exception):
    def __init__(self, status: HTTPStatus, *, detail: str, code: str) -> None:
        super().__init__(detail)
        self.status = status
        self.detail = detail
        self.code = code


def build_default_usecases() -> GuestControlUseCases:
    operations = PostgresOperationRepository()
    vitaldb_read_model = PostgresVitalDBReadModelRepository()
    operations.ensure_schema()
    vitaldb_read_model.ensure_schema()
    return GuestControlUseCases(
        service_control=ComposeGuestControlAdapter(),
        product_lab=ProductLabServiceAdapter(),
        recorder_ingress=RecorderIngressStatusServiceAdapter(),
        vitaldb_read_model=vitaldb_read_model,
        redis_backup=RedisBackupMaintenanceAdapter(),
        datastore_repair=DatastoreRepairMaintenanceAdapter(),
        update_activation=UpdateActivationMaintenanceAdapter(),
        update_shutdown=UpdateShutdownMaintenanceAdapter(),
        operations=operations,
        operation_ids=UUIDOperationIdFactory(),
        clock=SystemClock(),
    )


def make_handler(usecases: GuestControlUseCases) -> type[BaseHTTPRequestHandler]:
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
                status, document = route_request(
                    method=method,
                    path=urlparse(self.path).path,
                    body=self._request_body(),
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
    body: bytes = b"",
    usecases: GuestControlUseCases,
) -> tuple[HTTPStatus, dict[str, Any]]:
    parts = [unquote(part) for part in path.split("/") if part]

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

    if method == "GET" and parts == ["v1", "capabilities"]:
        return HTTPStatus.OK, usecases.capabilities()

    if method == "GET" and parts == ["v1", "services"]:
        return HTTPStatus.OK, {"services": usecases.list_services()}

    if method == "GET" and parts == ["v1", "stack", "status"]:
        return HTTPStatus.OK, usecases.get_stack_status().as_json()

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:2] == ["v1", "services"]
        and parts[3] == "status"
    ):
        return HTTPStatus.OK, usecases.get_service_status(parts[2]).as_json()

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:2] == ["v1", "services"]
        and parts[3] == "resource"
    ):
        return HTTPStatus.OK, usecases.get_guest_service_resource(parts[2])

    if (
        method == "PUT"
        and len(parts) == 4
        and parts[:2] == ["v1", "services"]
        and parts[3] == "spec"
    ):
        return HTTPStatus.OK, usecases.update_guest_service_spec(
            parts[2],
            _json_body(body),
        )

    if (
        method == "POST"
        and len(parts) == 4
        and parts[:2] == ["v1", "services"]
        and parts[3] == "reconcile"
    ):
        return HTTPStatus.ACCEPTED, usecases.reconcile_guest_service(
            parts[2]
        ).as_json()

    if (
        method == "POST"
        and len(parts) == 4
        and parts[:2] == ["v1", "services"]
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

    if method == "POST" and parts == ["v1", "stack", "reconcile"]:
        return HTTPStatus.ACCEPTED, usecases.reconcile_services().as_json()

    if method == "GET" and parts == ["v1", "lab", "scenarios"]:
        return HTTPStatus.OK, usecases.list_lab_scenarios()

    if method == "GET" and parts == ["v1", "lab", "vital-files"]:
        return HTTPStatus.OK, usecases.list_lab_vital_files()

    if method == "GET" and parts == ["v1", "lab", "beds"]:
        return HTTPStatus.OK, usecases.list_lab_beds()

    if method == "GET" and parts == ["v1", "lab", "recorders"]:
        return HTTPStatus.OK, usecases.list_lab_recorders()

    if method == "POST" and parts == ["v1", "lab", "beds", "create"]:
        return HTTPStatus.ACCEPTED, usecases.create_lab_beds(_json_body(body))

    if method == "POST" and parts == ["v1", "lab", "beds", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_lab_beds(_json_body(body))

    if method == "POST" and parts == ["v1", "lab", "beds", "reset"]:
        return HTTPStatus.ACCEPTED, usecases.reset_lab_beds()

    if method == "POST" and parts == ["v1", "lab", "recorders", "create"]:
        return HTTPStatus.ACCEPTED, usecases.create_lab_recorders(_json_body(body))

    if method == "POST" and parts == ["v1", "lab", "recorders", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_lab_recorders(_json_body(body))

    if method == "POST" and parts == ["v1", "lab", "recorders", "reset"]:
        return HTTPStatus.ACCEPTED, usecases.reset_lab_recorders()

    if method == "POST" and parts == ["v1", "lab", "sessions"]:
        return HTTPStatus.ACCEPTED, usecases.create_lab_session(_json_body(body))

    if (
        method == "GET"
        and len(parts) == 4
        and parts[:3] == ["v1", "lab", "sessions"]
    ):
        return HTTPStatus.OK, usecases.get_lab_session(parts[3])

    if (
        method == "POST"
        and len(parts) == 5
        and parts[:3] == ["v1", "lab", "sessions"]
        and parts[4] == "start"
    ):
        return HTTPStatus.ACCEPTED, usecases.start_lab_session(parts[3])

    if (
        method == "POST"
        and len(parts) == 5
        and parts[:3] == ["v1", "lab", "sessions"]
        and parts[4] == "stop"
    ):
        return HTTPStatus.ACCEPTED, usecases.stop_lab_session(parts[3])

    if method == "POST" and parts == ["v1", "lab", "vital-files", "replay"]:
        return HTTPStatus.ACCEPTED, usecases.replay_lab_vital_file(_json_body(body))

    if method == "POST" and parts == ["v1", "lab", "vital-files", "upload"]:
        return HTTPStatus.ACCEPTED, usecases.upload_lab_vital_file(_json_body(body))

    if method == "POST" and parts == ["v1", "maintenance", "redis-backup"]:
        return HTTPStatus.ACCEPTED, usecases.create_redis_backup().as_json()

    if method == "POST" and parts == ["v1", "maintenance", "redis-restore"]:
        return HTTPStatus.ACCEPTED, usecases.restore_redis_backup(
            _required_string(_json_body(body), "archive")
        ).as_json()

    if method == "POST" and parts == ["v1", "maintenance", "datastore-repair"]:
        return HTTPStatus.ACCEPTED, usecases.repair_datastore().as_json()

    if method == "POST" and parts == ["v1", "maintenance", "update-activation"]:
        request = _json_body(body)
        return HTTPStatus.ACCEPTED, usecases.activate_update(
            request_id=_required_string(request, "requestId"),
            version=_required_string(request, "version"),
        ).as_json()

    if method == "POST" and parts == ["v1", "maintenance", "update-shutdown"]:
        request = _json_body(body)
        return HTTPStatus.ACCEPTED, usecases.prepare_update_shutdown(
            request_id=_required_string(request, "requestId"),
            version=_required_string(request, "version"),
        ).as_json()

    if method == "POST" and parts == ["v1", "maintenance", "guest-poweroff"]:
        return HTTPStatus.ACCEPTED, usecases.request_guest_poweroff().as_json()

    if method == "GET" and parts == ["v1", "recorder-ingress", "status"]:
        return HTTPStatus.OK, usecases.get_recorder_ingress_status()

    if method == "GET" and parts == ["v1", "vitaldb", "observations", "latest"]:
        return HTTPStatus.OK, usecases.get_latest_vitaldb_observation()

    if method == "GET" and parts == ["v1", "vitaldb", "recorders"]:
        return HTTPStatus.OK, usecases.list_vitaldb_recorders()

    if method == "POST" and parts == ["v1", "vitaldb", "recorders", "hide"]:
        return HTTPStatus.ACCEPTED, usecases.hide_vitaldb_recorders(_json_body(body))

    if method == "POST" and parts == ["v1", "vitaldb", "recorders", "unhide"]:
        return HTTPStatus.ACCEPTED, usecases.unhide_vitaldb_recorders(_json_body(body))

    if method == "POST" and parts == ["v1", "vitaldb", "recorders", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_vitaldb_recorders(_json_body(body))

    if (
        method == "GET"
        and len(parts) == 5
        and parts[:3] == ["v1", "vitaldb", "recorders"]
        and parts[4] == "activity"
    ):
        return HTTPStatus.OK, usecases.get_vitaldb_recorder_activity(parts[3])

    if method == "GET" and parts == ["v1", "vitaldb", "beds"]:
        return HTTPStatus.OK, usecases.list_vitaldb_beds()

    if method == "POST" and parts == ["v1", "vitaldb", "beds", "hide"]:
        return HTTPStatus.ACCEPTED, usecases.hide_vitaldb_beds(_json_body(body))

    if method == "POST" and parts == ["v1", "vitaldb", "beds", "unhide"]:
        return HTTPStatus.ACCEPTED, usecases.unhide_vitaldb_beds(_json_body(body))

    if method == "POST" and parts == ["v1", "vitaldb", "beds", "delete"]:
        return HTTPStatus.ACCEPTED, usecases.delete_vitaldb_beds(_json_body(body))

    if method == "GET" and parts == ["v1", "vitaldb", "relationships"]:
        return HTTPStatus.OK, usecases.get_vitaldb_relationships()

    if method == "GET" and len(parts) == 3 and parts[:2] == ["v1", "operations"]:
        operation = usecases.get_operation(parts[2])
        if operation is None:
            raise GuestControlAPIError(
                HTTPStatus.NOT_FOUND,
                detail=f"operation is not available: {parts[2]}",
                code="operationNotFound",
            )
        return HTTPStatus.OK, operation.as_json()

    raise GuestControlAPIError(
        HTTPStatus.NOT_FOUND,
        detail=f"route is not available: {method} {path}",
        code="routeNotFound",
    )


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


def serve_guest_control_api(
    *,
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    usecases: GuestControlUseCases | None = None,
) -> None:
    handler = make_handler(usecases or build_default_usecases())
    server = ThreadingHTTPServer((host, port), handler)
    server.serve_forever()
