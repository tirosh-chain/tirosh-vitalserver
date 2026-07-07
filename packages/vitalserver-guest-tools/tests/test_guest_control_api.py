from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from http import HTTPStatus
from io import BytesIO

import pytest

from tirosh_guest_tools.adapters.inbound import guest_control_api
from tirosh_guest_tools.adapters.inbound.guest_control_api import route_request
from tirosh_guest_tools.application.guest_control.usecases import GuestControlUseCases
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    GuestServiceResource,
    OperationEvent,
    ProductLabReadModelResult,
    ProductLabSessionResult,
    ProductLabUploadResult,
    RedisBackupResult,
    RedisRestoreResult,
    ServiceNotFoundError,
    ServiceOperation,
    ServiceStatus,
    StackStatus,
    UpdateActivationResult,
    UpdateShutdownResult,
)


class FakeClock:
    def __init__(self) -> None:
        self._now = datetime(2026, 7, 1, tzinfo=UTC)

    def now(self) -> datetime:
        value = self._now
        self._now = self._now + timedelta(seconds=1)
        return value


class FakeOperationIds:
    def new_operation_id(self, *, service: str, command: str) -> str:
        return f"op_{service}_{command}_1"


class FakeOperations:
    def __init__(
        self,
        *,
        ready_failure: GuestControlDependencyError | None = None,
    ) -> None:
        self.ready_failure = ready_failure
        self.saved: list[ServiceOperation] = []
        self.events: list[OperationEvent] = []
        self.status_snapshots: list[ServiceStatus] = []
        self.service_resources: dict[str, GuestServiceResource] = {}

    def check_ready(self) -> None:
        if self.ready_failure is not None:
            raise self.ready_failure

    def create(self, operation: ServiceOperation) -> None:
        self.saved.append(operation)

    def save(self, operation: ServiceOperation) -> None:
        self.saved.append(operation)

    def append_event(self, event: OperationEvent) -> None:
        self.events.append(event)

    def save_service_status_snapshot(self, status: ServiceStatus) -> None:
        self.status_snapshots.append(status)

    def save_guest_service_resource(self, resource: GuestServiceResource) -> None:
        self.service_resources[resource.service] = resource

    def get_guest_service_resource(self, service: str) -> GuestServiceResource | None:
        return self.service_resources.get(service)

    def get(self, operation_id: str) -> ServiceOperation | None:
        return next(
            (
                operation
                for operation in reversed(self.saved)
                if operation.operation_id == operation_id
            ),
            None,
        )


class FakeServiceControl:
    def __init__(
        self,
        *,
        fail_command: str | None = None,
        services: list[str] | None = None,
    ) -> None:
        self.started: list[str] = []
        self.stopped: list[str] = []
        self.restarted: list[str] = []
        self.reconciled = 0
        self.fail_command = fail_command
        self.services = services or ["app", "redis"]

    def list_services(self) -> list[str]:
        return self.services

    def get_service_status(self, service: str) -> ServiceStatus:
        if service not in self.services:
            raise ServiceNotFoundError(service, available_services=self.services)
        return ServiceStatus(
            service=service,
            state="running",
            health="healthy",
            observed_at=datetime(2026, 7, 1, tzinfo=UTC),
        )

    def get_stack_status(self) -> StackStatus:
        observed_at = datetime(2026, 7, 1, tzinfo=UTC)
        return StackStatus(
            state="loaded",
            observed_at=observed_at,
            services=[
                ServiceStatus(
                    service="app",
                    state="running",
                    health="healthy",
                    observed_at=observed_at,
                ),
                ServiceStatus(
                    service="redis",
                    state="running",
                    health="healthy",
                    observed_at=observed_at,
                ),
            ],
        )

    def start_service(self, service: str) -> None:
        self.started.append(service)
        self._raise_if_failed("start")

    def stop_service(self, service: str) -> None:
        self.stopped.append(service)
        self._raise_if_failed("stop")

    def restart_service(self, service: str) -> None:
        self.restarted.append(service)
        self._raise_if_failed("restart")

    def reconcile_services(self) -> None:
        self.reconciled += 1
        self._raise_if_failed("reconcile")

    def _raise_if_failed(self, command: str) -> None:
        if self.fail_command == command:
            raise GuestControlDependencyError(
                f"docker compose {command} failed",
                kind="guest-compose-command-failed",
            )


def handle_with_test_handler(
    *,
    method: str,
    path: str,
    body: bytes,
    usecases: GuestControlUseCases,
) -> tuple[HTTPStatus, dict[str, object]]:
    handler_type = guest_control_api.make_handler(usecases)
    handler = object.__new__(handler_type)
    captured: dict[str, int] = {}
    handler.path = path
    handler.headers = {"Content-Length": str(len(body))}
    handler.rfile = BytesIO(body)
    handler.wfile = BytesIO()
    handler.send_response = lambda status_code: captured.__setitem__(
        "status",
        status_code,
    )
    handler.send_header = lambda key, value: None
    handler.end_headers = lambda: None

    handler._handle_request(method)

    return HTTPStatus(captured["status"]), json.loads(
        handler.wfile.getvalue().decode("utf-8")
    )


class FakeProductLab:
    def list_scenarios(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "scenarios": [
                {
                    "scenarioId": "normal_monitoring",
                    "name": "Normal monitoring",
                    "category": "virtual-recorder",
                    "description": "Stable monitoring",
                }
            ],
            "readError": None,
        }

    def list_vital_files(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "vitalFiles": [
                {
                    "displayName": "sample.vital",
                    "relativePath": "MORA04/sample.vital",
                    "guestPath": "/mnt/tirosh-vital-files/MORA04/sample.vital",
                    "sizeBytes": 123,
                    "modifiedAt": "2026-07-01T00:00:00Z",
                }
            ],
            "readError": None,
        }

    def list_beds(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "beds": [
                {
                    "bedId": "lab-session-1-bed-1",
                    "sessionId": "lab-session-1",
                    "name": "OR-A",
                    "state": "running",
                }
            ],
            "readError": None,
        }

    def list_recorders(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "recorders": [
                {
                    "recorderId": "lab-session-1-recorder-1",
                    "sessionId": "lab-session-1",
                    "bedId": "lab-session-1-bed-1",
                    "vrcode": "LAB-lab-session-1-1",
                    "state": "running",
                }
            ],
            "readError": None,
        }

    def create_beds(self, request: dict[str, object]) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(document=self.list_beds())

    def delete_beds(self, request: dict[str, object]) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(
            document={"state": "loaded", "beds": [], "readError": None}
        )

    def reset_beds(self) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(
            document={"state": "loaded", "beds": [], "readError": None}
        )

    def create_recorders(self, request: dict[str, object]) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(document=self.list_recorders())

    def delete_recorders(self, request: dict[str, object]) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(
            document={"state": "loaded", "recorders": [], "readError": None}
        )

    def reset_recorders(self) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(
            document={"state": "loaded", "recorders": [], "readError": None}
        )

    def create_session(self, request: dict[str, object]) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session=lab_session(
                session_id="lab-session-1",
                scenario_id=str(request["scenarioId"]),
            ),
            lab_operation_id="lab-session-create-lab-session-1",
        )

    def get_session(self, session_id: str) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session=lab_session(session_id=session_id, scenario_id="normal_monitoring")
        )

    def start_session(self, session_id: str) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session=lab_session(
                session_id=session_id,
                scenario_id="normal_monitoring",
                state="running",
            ),
            lab_operation_id=f"lab-session-start-{session_id}",
        )

    def stop_session(self, session_id: str) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session=lab_session(
                session_id=session_id,
                scenario_id="normal_monitoring",
                state="stopped",
            ),
            lab_operation_id=f"lab-session-stop-{session_id}",
        )

    def replay_vital_file(self, request: dict[str, object]) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session=lab_session(
                session_id="lab-replay-1",
                scenario_id="normal_monitoring",
                name=str(request["vitalFilePath"]),
            ),
            lab_operation_id="lab-vital-file-replay-lab-replay-1",
        )

    def upload_vital_file(self, request: dict[str, object]) -> ProductLabUploadResult:
        return ProductLabUploadResult(
            document={
                "state": "loaded",
                "operationId": "lab-vital-file-upload",
                "upload": {
                    "filename": "sample.vital",
                    "endpoint": "/upload",
                    "targetURL": request["targetURL"],
                    "statusCode": 200,
                    "bytesSent": 456,
                    "responseText": "success",
                    "ok": True,
                },
                "readError": None,
            },
            lab_operation_id="lab-vital-file-upload",
        )


class FakeVitalDBReadModel:
    def __init__(self) -> None:
        self.hidden_recorders: set[str] = set()
        self.deleted_recorders: set[str] = set()
        self.hidden_beds: set[str] = set()
        self.deleted_beds: set[str] = set()

    def check_ready(self) -> None:
        return None

    def latest_observation(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "observation": {
                "observedAt": "2026-07-01T00:00:00+00:00",
                "ready": True,
                "recorderOnlineThresholdSeconds": 60,
                "recorders": [],
                "beds": [],
                "readIssues": [],
            },
            "readError": None,
        }

    def recorders(self) -> dict[str, object]:
        recorders = [
            {
                "vrcode": "VR-001",
                "bedName": "OR-A",
                "status": "connected",
                "visibility": (
                    "hidden" if "VR-001" in self.hidden_recorders else "visible"
                ),
            }
        ]
        return {
            "state": "loaded",
            "recorders": [
                recorder
                for recorder in recorders
                if recorder["vrcode"] not in self.deleted_recorders
            ],
            "observedAt": "2026-07-01T00:00:00+00:00",
            "ready": True,
            "recorderOnlineThresholdSeconds": 60,
            "readError": None,
        }

    def hide_recorders(self, request: dict[str, object]) -> dict[str, object]:
        self.hidden_recorders.update(str(value) for value in request["vrcodes"])
        return self.recorders()

    def unhide_recorders(self, request: dict[str, object]) -> dict[str, object]:
        self.hidden_recorders.difference_update(
            str(value) for value in request["vrcodes"]
        )
        return self.recorders()

    def delete_recorders(self, request: dict[str, object]) -> dict[str, object]:
        requested = {str(value) for value in request["vrcodes"]}
        not_hidden = requested - self.hidden_recorders
        if not_hidden:
            from tirosh_guest_tools.domain.guest_control.models import (
                VitalDBReadModelDependencyError,
            )

            raise VitalDBReadModelDependencyError(
                "VitalDB entity must be hidden before delete: "
                + ", ".join(sorted(not_hidden)),
                kind="vitaldb-read-model-delete-not-hidden",
            )
        self.deleted_recorders.update(requested)
        return self.recorders()

    def recorder_activity(self, vrcode: str) -> dict[str, object]:
        return {
            "state": "loaded",
            "vrcode": vrcode,
            "buckets": [
                {
                    "vrcode": vrcode,
                    "bucketStartedAt": "2026-07-01T00:00:00+00:00",
                    "bucketSeconds": 60,
                    "messageCount": 2,
                    "byteCount": 128,
                    "roomCount": 1,
                    "firstObservedAt": "2026-07-01T00:00:00+00:00",
                    "lastObservedAt": "2026-07-01T00:00:59+00:00",
                }
            ],
            "readError": None,
        }

    def beds(self) -> dict[str, object]:
        beds = [
            {
                "bedID": "bed-a",
                "name": "OR-A",
                "recorderCount": 1,
                "visibility": "hidden" if "bed-a" in self.hidden_beds else "visible",
            }
        ]
        return {
            "state": "loaded",
            "beds": [
                bed for bed in beds if bed["bedID"] not in self.deleted_beds
            ],
            "observedAt": "2026-07-01T00:00:00+00:00",
            "ready": True,
            "recorderOnlineThresholdSeconds": 60,
            "readError": None,
        }

    def hide_beds(self, request: dict[str, object]) -> dict[str, object]:
        self.hidden_beds.update(str(value) for value in request["bedIDs"])
        return self.beds()

    def unhide_beds(self, request: dict[str, object]) -> dict[str, object]:
        self.hidden_beds.difference_update(str(value) for value in request["bedIDs"])
        return self.beds()

    def delete_beds(self, request: dict[str, object]) -> dict[str, object]:
        requested = {str(value) for value in request["bedIDs"]}
        not_hidden = requested - self.hidden_beds
        if not_hidden:
            from tirosh_guest_tools.domain.guest_control.models import (
                VitalDBReadModelDependencyError,
            )

            raise VitalDBReadModelDependencyError(
                "VitalDB entity must be hidden before delete: "
                + ", ".join(sorted(not_hidden)),
                kind="vitaldb-read-model-delete-not-hidden",
            )
        self.deleted_beds.update(requested)
        return self.beds()

    def relationships(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "assignments": [
                {
                    "assignmentID": "assignment-1",
                    "bedID": "bed-a",
                    "bedName": "OR-A",
                    "vrcode": "VR-001",
                    "startedAt": "2026-07-01T00:00:00+00:00",
                    "endedAt": None,
                    "lastSeenAt": "2026-07-01T00:00:05+00:00",
                    "lastObservedAt": "2026-07-01T00:00:05+00:00",
                    "status": "online",
                    "patientConnected": True,
                    "observationCount": 2,
                }
            ],
            "events": [],
            "readError": None,
        }


class FakeRecorderIngress:
    def status(self) -> dict[str, object]:
        return {
            "readState": "loaded",
            "httpStatus": "200",
            "document": {
                "activeRecorderConnections": 2,
                "recorders": [
                    {
                        "vrcode": "VR-001",
                        "activeConnections": 1,
                        "selectedIp": "192.168.64.21",
                        "lastSeenAt": "2026-07-01T00:00:00+00:00",
                    }
                ],
            },
            "readError": None,
        }


class FakeRedisBackup:
    def create_backup(self) -> RedisBackupResult:
        return RedisBackupResult(
            archive="/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
        )

    def restore_backup(self, archive: str) -> RedisRestoreResult:
        return RedisRestoreResult(restored_archive=archive)


class FakeDatastoreRepair:
    def repair_datastore(self) -> None:
        return None


class FakeUpdateActivation:
    def activate_update(
        self,
        *,
        request_id: str,
        version: str,
    ) -> UpdateActivationResult:
        return UpdateActivationResult(request_id=request_id, version=version)


class FakeUpdateShutdown:
    def prepare_update_shutdown(
        self,
        *,
        request_id: str,
        version: str,
        on_ready,
        on_failure,
    ) -> None:
        del on_failure
        on_ready(
            UpdateShutdownResult(
                request_id=request_id,
                version=version,
                shutdown_phase="poweroff-ready",
                redis_backup_path="/mnt/tirosh-runtime/backups/redis/update.tar.gz",
            )
        )

    def request_poweroff(self) -> None:
        return None


@pytest.fixture
def usecases() -> GuestControlUseCases:
    return GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
        vitaldb_read_model=FakeVitalDBReadModel(),
        recorder_ingress=FakeRecorderIngress(),
        redis_backup=FakeRedisBackup(),
        datastore_repair=FakeDatastoreRepair(),
        update_activation=FakeUpdateActivation(),
        update_shutdown=FakeUpdateShutdown(),
    )


def test_default_usecases_ensure_postgres_schema_during_composition(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    migrations: list[str] = []

    class FakePostgresOperations(FakeOperations):
        def ensure_schema(self) -> None:
            migrations.append("operations")

        def check_ready(self) -> None:
            self.ensure_schema()
            super().check_ready()

    class FakePostgresVitalDB(FakeVitalDBReadModel):
        def ensure_schema(self) -> None:
            migrations.append("vitaldb")

        def check_ready(self) -> None:
            self.ensure_schema()
            super().check_ready()

    monkeypatch.setattr(
        guest_control_api,
        "PostgresOperationRepository",
        FakePostgresOperations,
    )
    monkeypatch.setattr(
        guest_control_api,
        "PostgresVitalDBReadModelRepository",
        FakePostgresVitalDB,
    )
    monkeypatch.setattr(
        guest_control_api,
        "ComposeGuestControlAdapter",
        FakeServiceControl,
    )

    usecases = guest_control_api.build_default_usecases()

    assert migrations == ["operations", "vitaldb"]
    assert usecases.readiness()["status"] == "ready"
    assert migrations == ["operations", "vitaldb", "operations", "vitaldb"]
    operation = usecases.restart_service("app")
    assert operation.operation_id.startswith("op_app_restart_")


def test_health_route_does_not_query_services(usecases: GuestControlUseCases) -> None:
    status, document = route_request(
        method="GET",
        path="/health",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {"status": "ok"}


def test_ready_route_reports_dependency_readiness(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/ready",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["status"] == "ready"
    assert document["dependencies"] == [
        {
            "name": "operationRepository",
            "role": "required",
            "state": "ready",
            "kind": None,
            "message": None,
        },
        {
            "name": "vitaldbReadModel",
            "role": "configured",
            "state": "ready",
            "kind": None,
            "message": None,
        },
    ]


def test_ready_route_reports_postgres_dependency_failure() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(
            ready_failure=GuestControlDependencyError(
                "postgres command failed during guest control operation "
                "repository readiness",
                kind="postgresCommandFailed",
            )
        ),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = route_request(
        method="GET",
        path="/ready",
        usecases=usecases,
    )

    assert status == HTTPStatus.SERVICE_UNAVAILABLE
    assert document == {
        "status": "unavailable",
        "dependencies": [
            {
                "name": "operationRepository",
                "role": "required",
                "state": "failed",
                "kind": "postgresCommandFailed",
                "message": (
                    "postgres command failed during guest control operation "
                    "repository readiness"
                ),
            }
        ],
    }


def test_list_services_route_returns_services(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/services",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {"services": ["app", "redis"]}


def test_capabilities_route_advertises_vitaldb_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/capabilities",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert "vitaldb:observations:latest" in document["capabilities"]
    assert "maintenance:redis-backup:create" in document["capabilities"]
    assert "maintenance:redis-restore:create" in document["capabilities"]
    assert "maintenance:datastore-repair:create" in document["capabilities"]
    assert "maintenance:update-activation:create" in document["capabilities"]
    assert "maintenance:update-shutdown:create" in document["capabilities"]
    assert "maintenance:guest-poweroff:create" in document["capabilities"]
    assert "vitaldb:recorders:list" in document["capabilities"]
    assert "vitaldb:recorders:hide" in document["capabilities"]
    assert "vitaldb:recorders:unhide" in document["capabilities"]
    assert "vitaldb:recorders:delete" in document["capabilities"]
    assert "vitaldb:recorders:activity" in document["capabilities"]
    assert "vitaldb:beds:list" in document["capabilities"]
    assert "vitaldb:beds:hide" in document["capabilities"]
    assert "vitaldb:beds:unhide" in document["capabilities"]
    assert "vitaldb:beds:delete" in document["capabilities"]
    assert "vitaldb:relationships:get" in document["capabilities"]
    assert "recorder-ingress:status:get" in document["capabilities"]
    assert "lab:beds" in document["capabilities"]
    assert "lab:recorders" in document["capabilities"]


def test_capabilities_route_omits_unconfigured_adapter_capabilities() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = route_request(
        method="GET",
        path="/v1/capabilities",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["capabilities"] == [
        "services:list",
        "stack:status",
        "services:status",
        "services:resource:get",
        "services:spec:update",
        "services:reconcile",
        "services:start",
        "services:stop",
        "services:restart",
        "stack:reconcile",
        "operations:get",
    ]
    assert "lab:beds" not in document["capabilities"]
    assert "maintenance:redis-backup:create" not in document["capabilities"]
    assert "vitaldb:observations:latest" not in document["capabilities"]


def test_stack_status_route_returns_explicit_stack_document(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/stack/status",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert document["services"] == [
        {
            "service": "app",
            "state": "running",
            "health": "healthy",
            "observedAt": "2026-07-01T00:00:00+00:00",
        },
        {
            "service": "redis",
            "state": "running",
            "health": "healthy",
            "observedAt": "2026-07-01T00:00:00+00:00",
        },
    ]


def test_restart_route_returns_operation_document(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/services/app/restart",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_app_restart_1"
    assert document["service"] == "app"
    assert document["command"] == "restart"
    assert document["state"] == "completed"


def test_guest_service_resource_routes_return_controller_resource(
    usecases: GuestControlUseCases,
) -> None:
    spec_status, spec_document = route_request(
        method="PUT",
        path="/v1/services/app/spec",
        body=json.dumps({"desiredState": "stopped"}).encode("utf-8"),
        usecases=usecases,
    )
    reconcile_status, reconcile_document = route_request(
        method="POST",
        path="/v1/services/app/reconcile",
        usecases=usecases,
    )
    resource_status, resource_document = route_request(
        method="GET",
        path="/v1/services/app/resource",
        usecases=usecases,
    )

    assert spec_status == HTTPStatus.OK
    assert spec_document["spec"]["desiredState"] == "stopped"
    assert reconcile_status == HTTPStatus.ACCEPTED
    assert reconcile_document["command"] == "reconcile"
    assert reconcile_document["result"]["effect"] == "stop"
    assert resource_status == HTTPStatus.OK
    assert resource_document["service"] == "app"
    assert resource_document["spec"]["state"] == "configured"
    assert resource_document["status"]["state"] == "loaded"
    assert resource_document["status"]["observedState"] == "running"
    assert resource_document["lastOperationId"] == "op_app_reconcile_1"


def test_guest_service_observe_route_returns_observed_resource(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/services/app/observe",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["service"] == "app"
    assert document["spec"]["state"] == "missing"
    assert document["status"]["state"] == "loaded"
    assert document["status"]["observedState"] == "running"


def test_guest_service_spec_invalid_request_returns_bad_request() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = handle_with_test_handler(
        method="PUT",
        path="/v1/services/app/spec",
        body=json.dumps({"desiredState": "paused"}).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.BAD_REQUEST
    assert document == {
        "code": "guestServiceSpecInvalid",
        "detail": "guest service desiredState must be running or stopped",
    }


def test_guest_service_unknown_service_returns_not_found() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(services=["app"]),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = handle_with_test_handler(
        method="GET",
        path="/v1/services/redis/resource",
        body=b"",
        usecases=usecases,
    )

    assert status == HTTPStatus.NOT_FOUND
    assert document == {
        "availableServices": ["app"],
        "code": "serviceNotFound",
        "detail": "compose service is not available: redis",
    }


def test_restart_route_preserves_failed_operation_document() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(fail_command="restart"),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = route_request(
        method="POST",
        path="/v1/services/app/restart",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_app_restart_1"
    assert document["service"] == "app"
    assert document["command"] == "restart"
    assert document["state"] == "failed"
    assert document["failure"] == {
        "kind": "guest-compose-command-failed",
        "message": "docker compose restart failed",
    }
    assert [saved.state.value for saved in operations.saved] == [
        "accepted",
        "running",
        "failed",
    ]
    assert [event.state.value for event in operations.events] == [
        "accepted",
        "running",
        "failed",
    ]


def test_service_command_routes_return_operation_documents(
    usecases: GuestControlUseCases,
) -> None:
    _, start_document = route_request(
        method="POST",
        path="/v1/services/app/start",
        usecases=usecases,
    )
    _, stop_document = route_request(
        method="POST",
        path="/v1/services/app/stop",
        usecases=usecases,
    )
    _, restart_document = route_request(
        method="POST",
        path="/v1/services/app/restart",
        usecases=usecases,
    )

    assert start_document["operationId"] == "op_app_start_1"
    assert start_document["command"] == "start"
    assert start_document["state"] == "completed"
    assert stop_document["operationId"] == "op_app_stop_1"
    assert stop_document["command"] == "stop"
    assert stop_document["state"] == "completed"
    assert restart_document["operationId"] == "op_app_restart_1"
    assert restart_document["command"] == "restart"
    assert restart_document["state"] == "completed"


def test_stack_reconcile_route_returns_operation_document(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/stack/reconcile",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_guest-stack_reconcile_1"
    assert document["service"] == "guest-stack"
    assert document["command"] == "reconcile"
    assert document["state"] == "completed"


def test_redis_backup_route_returns_operation_with_archive_result(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/maintenance/redis-backup",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_redis-backup_redis-backup_1"
    assert document["service"] == "redis-backup"
    assert document["command"] == "redis-backup"
    assert document["state"] == "completed"
    assert document["result"] == {
        "archive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    }


def test_redis_restore_route_returns_operation_with_restored_archive_result(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/maintenance/redis-restore",
        body=json.dumps({
            "archive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz",
        }).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_redis-restore_redis-restore_1"
    assert document["service"] == "redis-restore"
    assert document["command"] == "redis-restore"
    assert document["state"] == "completed"
    assert document["result"] == {
        "restoredArchive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    }


def test_datastore_repair_route_returns_operation_document(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/maintenance/datastore-repair",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_datastore-repair_repair-datastore_1"
    assert document["service"] == "datastore-repair"
    assert document["command"] == "repair-datastore"
    assert document["state"] == "completed"


def test_update_activation_route_returns_operation_with_request_result(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/maintenance/update-activation",
        body=json.dumps({
            "requestId": "update-activation-request-1",
            "version": "0.2.0",
        }).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_update-activation_activate-update_1"
    assert document["service"] == "update-activation"
    assert document["command"] == "activate-update"
    assert document["state"] == "completed"
    assert document["result"] == {
        "requestId": "update-activation-request-1",
        "version": "0.2.0",
    }


def test_update_activation_route_rejects_missing_request_id(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(Exception) as error:
        route_request(
            method="POST",
            path="/v1/maintenance/update-activation",
            body=json.dumps({"version": "0.2.0"}).encode("utf-8"),
            usecases=usecases,
        )

    assert "JSON request field is required: requestId" in str(error.value)


def test_update_shutdown_route_returns_operation_with_ready_result(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/maintenance/update-shutdown",
        body=json.dumps({
            "requestId": "update-shutdown-request-1",
            "version": "0.2.0",
        }).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_update-shutdown_prepare-update-shutdown_1"
    assert document["service"] == "update-shutdown"
    assert document["command"] == "prepare-update-shutdown"
    assert document["state"] == "completed"
    assert document["result"] == {
        "requestId": "update-shutdown-request-1",
        "version": "0.2.0",
        "shutdownPhase": "poweroff-ready",
        "redisBackupPath": "/mnt/tirosh-runtime/backups/redis/update.tar.gz",
    }


def test_update_shutdown_route_rejects_missing_version(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(Exception) as error:
        route_request(
            method="POST",
            path="/v1/maintenance/update-shutdown",
            body=json.dumps({"requestId": "update-shutdown-request-1"}).encode(
                "utf-8"
            ),
            usecases=usecases,
        )

    assert "JSON request field is required: version" in str(error.value)


def test_guest_poweroff_route_returns_operation_document(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/maintenance/guest-poweroff",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_guest-poweroff_request-guest-poweroff_1"
    assert document["service"] == "guest-poweroff"
    assert document["command"] == "request-guest-poweroff"
    assert document["state"] == "completed"


def test_operation_route_returns_latest_operation(
    usecases: GuestControlUseCases,
) -> None:
    _, operation_document = route_request(
        method="POST",
        path="/v1/maintenance/redis-backup",
        usecases=usecases,
    )

    status, document = route_request(
        method="GET",
        path=f"/v1/operations/{operation_document['operationId']}",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert json.dumps(document)
    assert document["operationId"] == operation_document["operationId"]
    assert document["result"] == operation_document["result"]


def test_lab_scenarios_route_returns_product_lab_contract(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/lab/scenarios",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["scenarios"] == [
        {
            "scenarioId": "normal_monitoring",
            "name": "Normal monitoring",
            "category": "virtual-recorder",
            "description": "Stable monitoring",
        }
    ]


def test_lab_vital_files_route_returns_product_lab_catalog(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/lab/vital-files",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["vitalFiles"][0]["relativePath"] == "MORA04/sample.vital"
    assert document["vitalFiles"][0]["guestPath"] == (
        "/mnt/tirosh-vital-files/MORA04/sample.vital"
    )


def test_lab_read_model_routes_return_product_lab_contract(
    usecases: GuestControlUseCases,
) -> None:
    bed_status, beds = route_request(
        method="GET",
        path="/v1/lab/beds",
        usecases=usecases,
    )
    recorder_status, recorders = route_request(
        method="GET",
        path="/v1/lab/recorders",
        usecases=usecases,
    )

    assert bed_status == HTTPStatus.OK
    assert beds["state"] == "loaded"
    assert beds["beds"][0]["name"] == "OR-A"
    assert recorder_status == HTTPStatus.OK
    assert recorders["state"] == "loaded"
    assert recorders["recorders"][0]["vrcode"] == "LAB-lab-session-1-1"


def test_lab_management_routes_return_product_lab_read_models(
    usecases: GuestControlUseCases,
) -> None:
    create_status, created = route_request(
        method="POST",
        path="/v1/lab/beds/create",
        body=json.dumps({"roomNames": ["OR-A"]}).encode("utf-8"),
        usecases=usecases,
    )
    delete_status, deleted = route_request(
        method="POST",
        path="/v1/lab/recorders/delete",
        body=json.dumps({"recorderIds": ["lab-session-1-recorder-1"]}).encode("utf-8"),
        usecases=usecases,
    )

    assert create_status == HTTPStatus.ACCEPTED
    assert created["state"] == "loaded"
    assert created["operationId"] == "op_product-lab_lab-create-beds_1"
    assert created["beds"][0]["name"] == "OR-A"
    assert delete_status == HTTPStatus.ACCEPTED
    assert deleted["state"] == "loaded"
    assert deleted["operationId"] == "op_product-lab_lab-delete-recorders_1"
    assert deleted["recorders"] == []


def test_lab_create_session_route_returns_session_response_with_operation(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/lab/sessions",
        body=json.dumps(
            {
                "scenarioId": "normal_monitoring",
                "recorderCount": 2,
                "targetURL": "http://edge/",
            }
        ).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["state"] == "loaded"
    assert document["operationId"] == "op_product-lab_lab-create-session_1"
    assert document["labOperationId"] == "lab-session-create-lab-session-1"
    assert document["session"]["sessionId"] == "lab-session-1"
    assert document["session"]["scenarioId"] == "normal_monitoring"


def test_lab_get_session_route_returns_loaded_session_response(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/lab/sessions/lab-session-1",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["operationId"] is None
    assert document["session"]["sessionId"] == "lab-session-1"
    assert document["session"]["state"] == "accepted"


def test_recorder_ingress_status_route_returns_explicit_status_read(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/recorder-ingress/status",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "readState": "loaded",
        "httpStatus": "200",
        "document": {
            "activeRecorderConnections": 2,
            "recorders": [
                {
                    "vrcode": "VR-001",
                    "activeConnections": 1,
                    "selectedIp": "192.168.64.21",
                    "lastSeenAt": "2026-07-01T00:00:00+00:00",
                }
            ],
        },
        "readError": None,
    }


def test_lab_session_command_routes_return_explicit_session_state(
    usecases: GuestControlUseCases,
) -> None:
    _, started = route_request(
        method="POST",
        path="/v1/lab/sessions/lab-session-1/start",
        usecases=usecases,
    )
    _, stopped = route_request(
        method="POST",
        path="/v1/lab/sessions/lab-session-1/stop",
        usecases=usecases,
    )

    assert started["session"]["state"] == "running"
    assert started["labOperationId"] == "lab-session-start-lab-session-1"
    assert stopped["session"]["state"] == "stopped"
    assert stopped["labOperationId"] == "lab-session-stop-lab-session-1"


def test_lab_replay_vital_file_route_uses_explicit_request_body(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/lab/vital-files/replay",
        body=json.dumps(
            {"vitalFilePath": "/mnt/tirosh-vital-files/sample.vital"}
        ).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["state"] == "loaded"
    assert document["labOperationId"] == "lab-vital-file-replay-lab-replay-1"
    assert document["session"]["sessionId"] == "lab-replay-1"
    assert document["session"]["name"] == "/mnt/tirosh-vital-files/sample.vital"


def test_lab_upload_vital_file_route_uses_explicit_request_body(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/v1/lab/vital-files/upload",
        body=json.dumps(
            {
                "vitalFilePath": "/mnt/tirosh-vital-files/sample.vital",
                "targetURL": "http://edge/",
            }
        ).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["state"] == "loaded"
    assert document["operationId"] == "op_product-lab_lab-upload-vital-file_1"
    assert document["labOperationId"] == "lab-vital-file-upload"
    assert document["upload"]["filename"] == "sample.vital"
    assert document["upload"]["targetURL"] == "http://edge/"


def test_latest_vitaldb_observation_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/observations/latest",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["observation"]["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert document["readError"] is None


def test_latest_vitaldb_observation_route_reports_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/observations/latest",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "state": "unavailable",
        "observation": None,
        "readError": "VitalDB read model adapter is unavailable.",
    }


def test_vitaldb_recorders_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/recorders",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["recorders"][0]["vrcode"] == "VR-001"
    assert document["recorders"][0]["visibility"] == "visible"
    assert document["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert document["readError"] is None


def test_vitaldb_recorders_visibility_routes_require_hidden_before_delete(
    usecases: GuestControlUseCases,
) -> None:
    _, delete_without_hide = route_request(
        method="POST",
        path="/v1/vitaldb/recorders/delete",
        body=json.dumps({"vrcodes": ["VR-001"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, hidden = route_request(
        method="POST",
        path="/v1/vitaldb/recorders/hide",
        body=json.dumps({"vrcodes": ["VR-001"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, deleted = route_request(
        method="POST",
        path="/v1/vitaldb/recorders/delete",
        body=json.dumps({"vrcodes": ["VR-001"]}).encode("utf-8"),
        usecases=usecases,
    )

    assert delete_without_hide["readError"] == (
        "VitalDB entity must be hidden before delete: VR-001"
    )
    assert hidden["recorders"][0]["visibility"] == "hidden"
    assert deleted["recorders"] == []


def test_vitaldb_recorders_route_reports_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/recorders",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "state": "unavailable",
        "recorders": [],
        "observedAt": None,
        "readError": "VitalDB recorder read model adapter is unavailable.",
    }


def test_vitaldb_recorder_activity_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/recorders/VR-001/activity",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["vrcode"] == "VR-001"
    assert document["buckets"][0]["messageCount"] == 2
    assert document["readError"] is None


def test_vitaldb_beds_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/beds",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["beds"][0]["name"] == "OR-A"
    assert document["beds"][0]["visibility"] == "visible"
    assert document["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert document["readError"] is None


def test_vitaldb_beds_visibility_routes_require_hidden_before_delete(
    usecases: GuestControlUseCases,
) -> None:
    _, delete_without_hide = route_request(
        method="POST",
        path="/v1/vitaldb/beds/delete",
        body=json.dumps({"bedIDs": ["bed-a"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, hidden = route_request(
        method="POST",
        path="/v1/vitaldb/beds/hide",
        body=json.dumps({"bedIDs": ["bed-a"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, deleted = route_request(
        method="POST",
        path="/v1/vitaldb/beds/delete",
        body=json.dumps({"bedIDs": ["bed-a"]}).encode("utf-8"),
        usecases=usecases,
    )

    assert delete_without_hide["readError"] == (
        "VitalDB entity must be hidden before delete: bed-a"
    )
    assert hidden["beds"][0]["visibility"] == "hidden"
    assert deleted["beds"] == []


def test_vitaldb_beds_route_reports_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/beds",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "state": "unavailable",
        "beds": [],
        "observedAt": None,
        "readError": "VitalDB bed read model adapter is unavailable.",
    }


def test_vitaldb_relationships_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/relationships",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["assignments"][0]["assignmentID"] == "assignment-1"
    assert document["events"] == []
    assert document["readError"] is None


def test_vitaldb_relationships_route_reports_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/v1/vitaldb/relationships",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "state": "unavailable",
        "assignments": [],
        "events": [],
        "readError": "VitalDB relationship read model adapter is unavailable.",
    }


def test_lab_post_route_rejects_missing_json_body(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(Exception) as error:
        route_request(
            method="POST",
            path="/v1/lab/sessions",
            usecases=usecases,
        )

    assert "JSON request body is required" in str(error.value)


def lab_session(
    *,
    session_id: str,
    scenario_id: str,
    state: str = "accepted",
    name: str = "ProductLab",
) -> dict[str, object]:
    return {
        "sessionId": session_id,
        "state": state,
        "scenarioId": scenario_id,
        "name": name,
        "recorderCount": 1,
        "targetURL": "http://edge/",
        "createdAt": "2026-07-01T00:00:00+00:00",
        "updatedAt": "2026-07-01T00:00:01+00:00",
    }
