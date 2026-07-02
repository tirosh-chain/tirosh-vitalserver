from __future__ import annotations

from datetime import UTC, datetime, timedelta

from tirosh_guest_tools.application.guest_control.usecases import GuestControlUseCases
from tirosh_guest_tools.domain.guest_control.models import (
    DatastoreRepairDependencyError,
    GuestControlDependencyError,
    OperationEvent,
    OperationState,
    ProductLabDependencyError,
    ProductLabReadModelResult,
    ProductLabSessionResult,
    RecorderIngressDependencyError,
    RedisBackupDependencyError,
    RedisBackupResult,
    RedisRestoreDependencyError,
    RedisRestoreResult,
    ServiceCommand,
    ServiceOperation,
    ServiceStatus,
    StackStatus,
    UpdateActivationDependencyError,
    UpdateActivationResult,
    UpdateShutdownDependencyError,
    UpdateShutdownResult,
    VitalDBReadModelDependencyError,
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
        fail_status: bool = False,
    ) -> None:
        self.fail_command = fail_command
        self.fail_status = fail_status
        self.started: list[str] = []
        self.stopped: list[str] = []
        self.restarted: list[str] = []
        self.reconciled = 0

    def list_services(self) -> list[str]:
        return ["app", "redis"]

    def get_service_status(self, service: str) -> ServiceStatus:
        if self.fail_status:
            raise GuestControlDependencyError(
                "compose status read failed",
                kind="guest-stack-status-read-failed",
            )
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


class FakeProductLab:
    def __init__(self, *, fail_create: bool = False) -> None:
        self.fail_create = fail_create
        self.created: list[dict[str, object]] = []

    def list_scenarios(self) -> dict[str, object]:
        return {"state": "loaded", "scenarios": [], "readError": None}

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
        return ProductLabReadModelResult(document={"state": "loaded", "beds": [], "readError": None})

    def reset_beds(self) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(document={"state": "loaded", "beds": [], "readError": None})

    def create_recorders(self, request: dict[str, object]) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(document=self.list_recorders())

    def delete_recorders(self, request: dict[str, object]) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(document={"state": "loaded", "recorders": [], "readError": None})

    def reset_recorders(self) -> ProductLabReadModelResult:
        return ProductLabReadModelResult(document={"state": "loaded", "recorders": [], "readError": None})

    def create_session(
        self,
        request: dict[str, object],
    ) -> ProductLabSessionResult:
        self.created.append(request)
        if self.fail_create:
            raise ProductLabDependencyError(
                "Product Lab service is not reachable",
                kind="product-lab-unavailable",
            )
        return ProductLabSessionResult(
            session={
                "sessionId": "lab-session-1",
                "state": "accepted",
                "scenarioId": str(request["scenarioId"]),
                "name": "ProductLab",
                "recorderCount": 1,
                "targetURL": "http://edge/",
                "createdAt": "2026-07-01T00:00:00+00:00",
                "updatedAt": "2026-07-01T00:00:01+00:00",
            },
            lab_operation_id="lab-session-create-lab-session-1",
        )

    def get_session(self, session_id: str) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session={
                "sessionId": session_id,
                "state": "running",
                "scenarioId": "normal_monitoring",
                "name": "ProductLab",
                "recorderCount": 1,
                "targetURL": "http://edge/",
                "createdAt": "2026-07-01T00:00:00+00:00",
                "updatedAt": "2026-07-01T00:00:01+00:00",
            },
            lab_operation_id=None,
        )

    def start_session(self, session_id: str) -> dict[str, object]:
        raise NotImplementedError(session_id)

    def stop_session(self, session_id: str) -> dict[str, object]:
        raise NotImplementedError(session_id)

    def replay_vital_file(self, request: dict[str, object]) -> dict[str, object]:
        raise NotImplementedError(request)


class FakeVitalDBReadModel:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.hidden_recorders: set[str] = set()
        self.deleted_recorders: set[str] = set()
        self.hidden_beds: set[str] = set()
        self.deleted_beds: set[str] = set()

    def check_ready(self) -> None:
        if self.fail:
            raise VitalDBReadModelDependencyError(
                "Postgres read model is unreachable.",
                kind="vitaldb-read-model-unavailable",
            )

    def latest_observation(self) -> dict[str, object]:
        if self.fail:
            raise VitalDBReadModelDependencyError(
                "Postgres read model is unreachable.",
                kind="vitaldb-read-model-unavailable",
            )
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
        if self.fail:
            raise VitalDBReadModelDependencyError(
                "Postgres read model is unreachable.",
                kind="vitaldb-read-model-unavailable",
            )
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
            raise VitalDBReadModelDependencyError(
                "VitalDB entity must be hidden before delete: "
                + ", ".join(sorted(not_hidden)),
                kind="vitaldb-read-model-delete-not-hidden",
            )
        self.deleted_recorders.update(requested)
        return self.recorders()

    def recorder_activity(self, vrcode: str) -> dict[str, object]:
        if self.fail:
            raise VitalDBReadModelDependencyError(
                "Postgres read model is unreachable.",
                kind="vitaldb-read-model-unavailable",
            )
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
        if self.fail:
            raise VitalDBReadModelDependencyError(
                "Postgres read model is unreachable.",
                kind="vitaldb-read-model-unavailable",
            )
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
            raise VitalDBReadModelDependencyError(
                "VitalDB entity must be hidden before delete: "
                + ", ".join(sorted(not_hidden)),
                kind="vitaldb-read-model-delete-not-hidden",
            )
        self.deleted_beds.update(requested)
        return self.beds()

    def relationships(self) -> dict[str, object]:
        if self.fail:
            raise VitalDBReadModelDependencyError(
                "Postgres read model is unreachable.",
                kind="vitaldb-read-model-unavailable",
            )
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
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail

    def status(self) -> dict[str, object]:
        if self.fail:
            raise RecorderIngressDependencyError(
                "Recorder ingress status service is unreachable.",
                kind="recorder-ingress-unavailable",
            )
        return {
            "readState": "loaded",
            "httpStatus": "200",
            "document": {
                "activeRecorderConnections": 1,
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
    def __init__(self, *, fail: bool = False, fail_restore: bool = False) -> None:
        self.fail = fail
        self.fail_restore = fail_restore
        self.created = 0
        self.restored: list[str] = []

    def create_backup(self) -> RedisBackupResult:
        self.created += 1
        if self.fail:
            raise RedisBackupDependencyError(
                "redis volume mount is missing",
                kind="redis-volume-mount-missing",
            )
        return RedisBackupResult(
            archive="/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
        )

    def restore_backup(self, archive: str) -> RedisRestoreResult:
        self.restored.append(archive)
        if self.fail_restore:
            raise RedisRestoreDependencyError(
                "redis restore archive is missing",
                kind="redis-restore-archive-missing",
            )
        return RedisRestoreResult(restored_archive=archive)


class FakeDatastoreRepair:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.repaired = 0

    def repair_datastore(self) -> None:
        self.repaired += 1
        if self.fail:
            raise DatastoreRepairDependencyError(
                "redis append-only file repair failed",
                kind="datastore-repair-failed",
            )


class FakeUpdateActivation:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.activated: list[tuple[str, str]] = []

    def activate_update(
        self,
        *,
        request_id: str,
        version: str,
    ) -> UpdateActivationResult:
        self.activated.append((request_id, version))
        if self.fail:
            raise UpdateActivationDependencyError(
                "docker image bundle directory is missing",
                kind="docker-image-bundle-directory-missing",
            )
        return UpdateActivationResult(request_id=request_id, version=version)


class FakeUpdateShutdown:
    def __init__(
        self,
        *,
        fail: bool = False,
        ready_immediately: bool = False,
    ) -> None:
        self.fail = fail
        self.ready_immediately = ready_immediately
        self.prepared: list[tuple[str, str]] = []
        self.poweroff_requests = 0

    def prepare_update_shutdown(
        self,
        *,
        request_id: str,
        version: str,
        on_ready,
        on_failure,
    ) -> None:
        self.prepared.append((request_id, version))
        if self.fail:
            raise UpdateShutdownDependencyError(
                "guest-sidecar-service-stop-timeout",
                kind="guest-sidecar-service-stop-timeout",
            )
        if self.ready_immediately:
            on_ready(
                UpdateShutdownResult(
                    request_id=request_id,
                    version=version,
                    shutdown_phase="poweroff-ready",
                    redis_backup_path="/mnt/tirosh-runtime/backups/redis/update.tar.gz",
                )
            )

    def request_poweroff(self) -> None:
        self.poweroff_requests += 1
        if self.fail:
            raise UpdateShutdownDependencyError(
                "systemctl poweroff failed",
                kind="guest-poweroff-request-failed",
            )


def test_capabilities_include_only_configured_adapter_features() -> None:
    usecases = GuestControlUseCases(
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

    document = usecases.capabilities()

    assert document["schemaVersion"] == 1
    assert document["capabilities"] == [
        "services:list",
        "stack:status",
        "services:status",
        "services:start",
        "services:stop",
        "services:restart",
        "stack:reconcile",
        "operations:get",
        "lab:scenarios",
        "lab:beds",
        "lab:beds:create",
        "lab:beds:delete",
        "lab:beds:reset",
        "lab:recorders",
        "lab:recorders:create",
        "lab:recorders:delete",
        "lab:recorders:reset",
        "lab:sessions:create",
        "lab:sessions:get",
        "lab:sessions:start",
        "lab:sessions:stop",
        "lab:vital-files:replay",
        "maintenance:redis-backup:create",
        "maintenance:redis-restore:create",
        "maintenance:datastore-repair:create",
        "maintenance:update-activation:create",
        "maintenance:update-shutdown:create",
        "maintenance:guest-poweroff:create",
        "recorder-ingress:status:get",
        "vitaldb:observations:latest",
        "vitaldb:recorders:list",
        "vitaldb:recorders:hide",
        "vitaldb:recorders:unhide",
        "vitaldb:recorders:delete",
        "vitaldb:recorders:activity",
        "vitaldb:beds:list",
        "vitaldb:beds:hide",
        "vitaldb:beds:unhide",
        "vitaldb:beds:delete",
        "vitaldb:relationships:get",
    ]


def test_capabilities_omit_unconfigured_adapter_features() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    document = usecases.capabilities()

    assert document == {
        "schemaVersion": 1,
        "capabilities": [
            "services:list",
            "stack:status",
            "services:status",
            "services:start",
            "services:stop",
            "services:restart",
            "stack:reconcile",
            "operations:get",
        ],
    }


def test_readiness_reports_ready_dependency_state() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    document = usecases.readiness()

    assert document == {
        "status": "ready",
        "dependencies": [
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
        ],
    }


def test_readiness_preserves_postgres_operation_repository_failure() -> None:
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

    document = usecases.readiness()

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


def test_start_service_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = GuestControlUseCases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.start_service("app")

    assert operation.state == OperationState.COMPLETED
    assert operation.command == ServiceCommand.START
    assert service_control.started == ["app"]
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert usecases.get_operation("op_app_start_1") == operation


def test_get_service_status_persists_status_snapshot() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status = usecases.get_service_status("app")

    assert status.service == "app"
    assert operations.status_snapshots == [status]


def test_get_stack_status_persists_each_service_status_snapshot() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status = usecases.get_stack_status()

    assert status.state == "loaded"
    assert [service.service for service in status.services] == ["app", "redis"]
    assert operations.status_snapshots == status.services


def test_stop_service_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = GuestControlUseCases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.stop_service("app")

    assert operation.state == OperationState.COMPLETED
    assert operation.command == ServiceCommand.STOP
    assert service_control.stopped == ["app"]
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [status.service for status in operations.status_snapshots] == ["app"]
    assert usecases.get_operation("op_app_stop_1") == operation


def test_restart_service_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = GuestControlUseCases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.restart_service("app")

    assert operation.state == OperationState.COMPLETED
    assert operation.command == ServiceCommand.RESTART
    assert service_control.restarted == ["app"]
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [status.service for status in operations.status_snapshots] == ["app"]
    assert usecases.get_operation("op_app_restart_1") == operation


def test_restart_service_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(fail_command="restart"),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.restart_service("app")

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "guest-compose-command-failed"
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]
    assert operations.status_snapshots == []


def test_restart_service_status_snapshot_failure_is_persisted_as_failed_operation(
) -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl(fail_status=True)
    usecases = GuestControlUseCases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.restart_service("app")

    assert operation.state == OperationState.FAILED
    assert service_control.restarted == ["app"]
    assert operation.failure is not None
    assert operation.failure.kind == "guest-stack-status-read-failed"
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]
    assert operations.status_snapshots == []


def test_reconcile_services_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = GuestControlUseCases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.reconcile_services()

    assert operation.state == OperationState.COMPLETED
    assert operation.service == "guest-stack"
    assert operation.command == ServiceCommand.RECONCILE
    assert [status.service for status in operations.status_snapshots] == [
        "app",
        "redis",
    ]
    assert service_control.reconciled == 1
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert usecases.get_operation("op_guest-stack_reconcile_1") == operation


def test_reconcile_services_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(fail_command="reconcile"),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.reconcile_services()

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "guest-compose-command-failed"
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]


def test_create_redis_backup_persists_completed_operation_result() -> None:
    operations = FakeOperations()
    redis_backup = FakeRedisBackup()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_backup=redis_backup,
    )

    operation = usecases.create_redis_backup()

    assert redis_backup.created == 1
    assert operation.state == OperationState.COMPLETED
    assert operation.service == "redis-backup"
    assert operation.command == ServiceCommand.REDIS_BACKUP
    assert operation.result == {
        "archive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    }
    assert operations.events[-1].result == operation.result
    assert usecases.get_operation("op_redis-backup_redis-backup_1") == operation


def test_create_redis_backup_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_backup=FakeRedisBackup(fail=True),
    )

    operation = usecases.create_redis_backup()

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "redis-volume-mount-missing"
    assert operation.result is None
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]


def test_restore_redis_backup_persists_completed_operation_result() -> None:
    operations = FakeOperations()
    redis_backup = FakeRedisBackup()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_backup=redis_backup,
    )

    operation = usecases.restore_redis_backup(
        "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    )

    assert redis_backup.restored == [
        "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    ]
    assert operation.state == OperationState.COMPLETED
    assert operation.service == "redis-restore"
    assert operation.command == ServiceCommand.REDIS_RESTORE
    assert operation.result == {
        "restoredArchive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
    }
    assert operations.events[-1].result == operation.result
    assert usecases.get_operation("op_redis-restore_redis-restore_1") == operation


def test_restore_redis_backup_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_backup=FakeRedisBackup(fail_restore=True),
    )

    operation = usecases.restore_redis_backup(
        "/mnt/tirosh-runtime/backups/redis/missing.tar.gz"
    )

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "redis-restore-archive-missing"
    assert operation.result is None


def test_repair_datastore_persists_completed_operation() -> None:
    operations = FakeOperations()
    datastore_repair = FakeDatastoreRepair()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        datastore_repair=datastore_repair,
    )

    operation = usecases.repair_datastore()

    assert datastore_repair.repaired == 1
    assert operation.state == OperationState.COMPLETED
    assert operation.service == "datastore-repair"
    assert operation.command == ServiceCommand.REPAIR_DATASTORE
    assert operation.result is None
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert usecases.get_operation("op_datastore-repair_repair-datastore_1") == operation


def test_repair_datastore_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        datastore_repair=FakeDatastoreRepair(fail=True),
    )

    operation = usecases.repair_datastore()

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "datastore-repair-failed"
    assert operation.result is None


def test_activate_update_persists_completed_operation_result() -> None:
    operations = FakeOperations()
    update_activation = FakeUpdateActivation()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_activation=update_activation,
    )

    operation = usecases.activate_update(
        request_id="update-activation-request-1",
        version="0.2.0",
    )

    assert update_activation.activated == [("update-activation-request-1", "0.2.0")]
    assert operation.state == OperationState.COMPLETED
    assert operation.service == "update-activation"
    assert operation.command == ServiceCommand.UPDATE_ACTIVATION
    assert operation.result == {
        "requestId": "update-activation-request-1",
        "version": "0.2.0",
    }
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert operations.events[-1].result == operation.result
    assert usecases.get_operation("op_update-activation_activate-update_1") == operation


def test_activate_update_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_activation=FakeUpdateActivation(fail=True),
    )

    operation = usecases.activate_update(
        request_id="update-activation-request-1",
        version="0.2.0",
    )

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "docker-image-bundle-directory-missing"
    assert operation.result is None


def test_prepare_update_shutdown_returns_running_background_operation() -> None:
    operations = FakeOperations()
    update_shutdown = FakeUpdateShutdown()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_shutdown=update_shutdown,
    )

    operation = usecases.prepare_update_shutdown(
        request_id="update-shutdown-request-1",
        version="0.2.0",
    )

    assert update_shutdown.prepared == [("update-shutdown-request-1", "0.2.0")]
    assert operation.state == OperationState.RUNNING
    assert operation.service == "update-shutdown"
    assert operation.command == ServiceCommand.UPDATE_SHUTDOWN
    assert operation.result is None
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
    ]
    assert (
        usecases.get_operation("op_update-shutdown_prepare-update-shutdown_1")
        == operation
    )


def test_prepare_update_shutdown_ready_callback_persists_completed_result() -> None:
    operations = FakeOperations()
    update_shutdown = FakeUpdateShutdown(ready_immediately=True)
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_shutdown=update_shutdown,
    )

    operation = usecases.prepare_update_shutdown(
        request_id="update-shutdown-request-1",
        version="0.2.0",
    )

    assert operation.state == OperationState.COMPLETED
    assert operation.result == {
        "requestId": "update-shutdown-request-1",
        "version": "0.2.0",
        "shutdownPhase": "poweroff-ready",
        "redisBackupPath": "/mnt/tirosh-runtime/backups/redis/update.tar.gz",
    }
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]


def test_prepare_update_shutdown_start_failure_is_persisted() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_shutdown=FakeUpdateShutdown(fail=True),
    )

    operation = usecases.prepare_update_shutdown(
        request_id="update-shutdown-request-1",
        version="0.2.0",
    )

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "guest-sidecar-service-stop-timeout"
    assert operation.result is None


def test_request_guest_poweroff_persists_completed_operation() -> None:
    operations = FakeOperations()
    update_shutdown = FakeUpdateShutdown()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_shutdown=update_shutdown,
    )

    operation = usecases.request_guest_poweroff()

    assert update_shutdown.poweroff_requests == 1
    assert operation.state == OperationState.COMPLETED
    assert operation.service == "guest-poweroff"
    assert operation.command == ServiceCommand.REQUEST_GUEST_POWEROFF
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]


def test_request_guest_poweroff_failure_is_persisted() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_shutdown=FakeUpdateShutdown(fail=True),
    )

    operation = usecases.request_guest_poweroff()

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "guest-poweroff-request-failed"


def test_create_lab_session_persists_operation_transitions() -> None:
    operations = FakeOperations()
    product_lab = FakeProductLab()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=product_lab,
    )

    response = usecases.create_lab_session({"scenarioId": "normal_monitoring"})

    assert response["state"] == "loaded"
    assert response["operationId"] == "op_product-lab_lab-create-session_1"
    assert response["labOperationId"] == "lab-session-create-lab-session-1"
    assert response["session"]["sessionId"] == "lab-session-1"
    assert product_lab.created == [{"scenarioId": "normal_monitoring"}]
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.COMPLETED,
    ]


def test_lab_read_models_are_loaded_from_product_lab_port() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    beds = usecases.list_lab_beds()
    recorders = usecases.list_lab_recorders()

    assert beds["state"] == "loaded"
    assert beds["beds"][0]["name"] == "OR-A"
    assert recorders["state"] == "loaded"
    assert recorders["recorders"][0]["vrcode"] == "LAB-lab-session-1-1"


def test_create_lab_session_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(fail_create=True),
    )

    response = usecases.create_lab_session({"scenarioId": "normal_monitoring"})

    assert response["state"] == "unavailable"
    assert response["operationId"] == "op_product-lab_lab-create-session_1"
    assert response["session"] is None
    assert response["readError"] == "Product Lab service is not reachable"
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]
    assert [event.state for event in operations.events] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]


def test_get_lab_session_returns_loaded_session_response_without_operation() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    response = usecases.get_lab_session("lab-session-1")

    assert response["state"] == "loaded"
    assert response["operationId"] is None
    assert response["readError"] is None
    assert response["session"]["sessionId"] == "lab-session-1"
    assert response["session"]["state"] == "running"


def test_latest_vitaldb_observation_reports_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.get_latest_vitaldb_observation()

    assert response == {
        "state": "unavailable",
        "observation": None,
        "readError": "VitalDB read model adapter is unavailable.",
    }


def test_latest_vitaldb_observation_returns_read_model_document() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    response = usecases.get_latest_vitaldb_observation()

    assert response["state"] == "loaded"
    assert response["observation"]["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert response["readError"] is None


def test_latest_vitaldb_observation_preserves_dependency_failure() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(fail=True),
    )

    response = usecases.get_latest_vitaldb_observation()

    assert response == {
        "state": "unavailable",
        "observation": None,
        "readError": "Postgres read model is unreachable.",
    }


def test_vitaldb_recorders_report_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.list_vitaldb_recorders()

    assert response == {
        "state": "unavailable",
        "recorders": [],
        "observedAt": None,
        "readError": "VitalDB recorder read model adapter is unavailable.",
    }


def test_vitaldb_recorders_return_read_model_document() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    response = usecases.list_vitaldb_recorders()

    assert response["state"] == "loaded"
    assert response["recorders"][0]["vrcode"] == "VR-001"
    assert response["recorders"][0]["visibility"] == "visible"
    assert response["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert response["readError"] is None


def test_vitaldb_recorders_visibility_commands_require_hidden_before_delete() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    delete_without_hide = usecases.delete_vitaldb_recorders({"vrcodes": ["VR-001"]})
    hidden = usecases.hide_vitaldb_recorders({"vrcodes": ["VR-001"]})
    deleted = usecases.delete_vitaldb_recorders({"vrcodes": ["VR-001"]})

    assert delete_without_hide == {
        "state": "failed",
        "recorders": [],
        "observedAt": None,
        "readError": "VitalDB entity must be hidden before delete: VR-001",
    }
    assert hidden["recorders"][0]["visibility"] == "hidden"
    assert deleted["recorders"] == []


def test_vitaldb_recorders_unhide_restores_visible_state() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    usecases.hide_vitaldb_recorders({"vrcodes": ["VR-001"]})
    response = usecases.unhide_vitaldb_recorders({"vrcodes": ["VR-001"]})

    assert response["recorders"][0]["visibility"] == "visible"


def test_vitaldb_recorders_preserve_dependency_failure() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(fail=True),
    )

    response = usecases.list_vitaldb_recorders()

    assert response == {
        "state": "unavailable",
        "recorders": [],
        "observedAt": None,
        "readError": "Postgres read model is unreachable.",
    }


def test_vitaldb_recorder_activity_reports_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.get_vitaldb_recorder_activity("VR-001")

    assert response == {
        "state": "unavailable",
        "vrcode": "VR-001",
        "buckets": [],
        "readError": "VitalDB recorder activity read model adapter is unavailable.",
    }


def test_vitaldb_recorder_activity_returns_read_model_document() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    response = usecases.get_vitaldb_recorder_activity("VR-001")

    assert response["state"] == "loaded"
    assert response["vrcode"] == "VR-001"
    assert response["buckets"][0]["messageCount"] == 2
    assert response["readError"] is None


def test_vitaldb_recorder_activity_preserves_dependency_failure() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(fail=True),
    )

    response = usecases.get_vitaldb_recorder_activity("VR-001")

    assert response == {
        "state": "unavailable",
        "vrcode": "VR-001",
        "buckets": [],
        "readError": "Postgres read model is unreachable.",
    }


def test_vitaldb_beds_report_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.list_vitaldb_beds()

    assert response == {
        "state": "unavailable",
        "beds": [],
        "observedAt": None,
        "readError": "VitalDB bed read model adapter is unavailable.",
    }


def test_vitaldb_beds_return_read_model_document() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    response = usecases.list_vitaldb_beds()

    assert response["state"] == "loaded"
    assert response["beds"][0]["name"] == "OR-A"
    assert response["beds"][0]["visibility"] == "visible"
    assert response["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert response["readError"] is None


def test_vitaldb_beds_visibility_commands_require_hidden_before_delete() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    delete_without_hide = usecases.delete_vitaldb_beds({"bedIDs": ["bed-a"]})
    hidden = usecases.hide_vitaldb_beds({"bedIDs": ["bed-a"]})
    deleted = usecases.delete_vitaldb_beds({"bedIDs": ["bed-a"]})

    assert delete_without_hide == {
        "state": "failed",
        "beds": [],
        "observedAt": None,
        "readError": "VitalDB entity must be hidden before delete: bed-a",
    }
    assert hidden["beds"][0]["visibility"] == "hidden"
    assert deleted["beds"] == []


def test_vitaldb_beds_unhide_restores_visible_state() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    usecases.hide_vitaldb_beds({"bedIDs": ["bed-a"]})
    response = usecases.unhide_vitaldb_beds({"bedIDs": ["bed-a"]})

    assert response["beds"][0]["visibility"] == "visible"


def test_vitaldb_beds_preserve_dependency_failure() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(fail=True),
    )

    response = usecases.list_vitaldb_beds()

    assert response == {
        "state": "unavailable",
        "beds": [],
        "observedAt": None,
        "readError": "Postgres read model is unreachable.",
    }


def test_vitaldb_relationships_report_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.get_vitaldb_relationships()

    assert response == {
        "state": "unavailable",
        "assignments": [],
        "events": [],
        "readError": "VitalDB relationship read model adapter is unavailable.",
    }


def test_vitaldb_relationships_return_read_model_document() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    response = usecases.get_vitaldb_relationships()

    assert response["state"] == "loaded"
    assert response["assignments"][0]["assignmentID"] == "assignment-1"
    assert response["events"] == []
    assert response["readError"] is None


def test_vitaldb_relationships_preserve_dependency_failure() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(fail=True),
    )

    response = usecases.get_vitaldb_relationships()

    assert response == {
        "state": "unavailable",
        "assignments": [],
        "events": [],
        "readError": "Postgres read model is unreachable.",
    }


def test_recorder_ingress_status_reports_unavailable_without_adapter() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.get_recorder_ingress_status()

    assert response == {
        "readState": "readFailed",
        "httpStatus": "unavailable",
        "document": None,
        "readError": "Recorder ingress status adapter is unavailable.",
    }


def test_recorder_ingress_status_returns_status_read_document() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        recorder_ingress=FakeRecorderIngress(),
    )

    response = usecases.get_recorder_ingress_status()

    assert response["readState"] == "loaded"
    assert response["document"]["activeRecorderConnections"] == 1
    assert response["readError"] is None


def test_recorder_ingress_status_preserves_dependency_failure() -> None:
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        recorder_ingress=FakeRecorderIngress(fail=True),
    )

    response = usecases.get_recorder_ingress_status()

    assert response == {
        "readState": "readFailed",
        "httpStatus": "failed",
        "document": None,
        "readError": "Recorder ingress status service is unreachable.",
    }
