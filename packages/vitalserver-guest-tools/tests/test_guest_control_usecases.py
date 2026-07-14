from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from tirosh_guest_tools.application.guest_control.usecases import GuestControlUseCases
from tirosh_guest_tools.domain.guest_control.models import (
    TERMINAL_OPERATION_STATES,
    DatastoreRepairDependencyError,
    GuestControlDependencyError,
    GuestServiceDesiredState,
    GuestServiceResource,
    GuestServiceSpec,
    GuestServiceStatusRead,
    OperationEvent,
    OperationFailure,
    OperationLease,
    OperationState,
    ProductLabDependencyError,
    ProductLabReadModelResult,
    ProductLabRecorderResult,
    ProductLabSessionResult,
    RecorderIngressDependencyError,
    RedisBackupDependencyError,
    RedisBackupResult,
    RedisRelayDependencyError,
    RedisRelayStatusContractError,
    RedisRestoreDependencyError,
    RedisRestoreResult,
    ServiceCommand,
    ServiceNotFoundError,
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


def redis_relay_status_document(*, copied: int = 8) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "observedAt": "2026-07-01T00:00:00Z",
        "enabled": True,
        "state": "running",
        "scope": "vital_reconstruction",
        "targetUrl": "redis://relay.example:6379/0",
        "targetUsernameConfigured": True,
        "targetPasswordConfigured": True,
        "settingsFingerprint": "relay-settings",
        "batches": 3,
        "totals": {
            "scanned": 10,
            "copied": copied,
            "published": copied,
            "unchanged": 1,
            "duplicates": 0,
            "skipped": 1,
            "denied": 0,
            "missing": 0,
            "errors": 0,
        },
        "lastBatch": None,
        "lastSuccessAt": "2026-07-01T00:00:05Z",
        "lastErrorAt": None,
        "lastError": None,
    }


class FakeOperations:
    def __init__(
        self,
        *,
        ready_failure: GuestControlDependencyError | None = None,
    ) -> None:
        self.ready_failure = ready_failure
        self.saved: list[ServiceOperation] = []
        self.events: list[OperationEvent] = []
        self.active_lease: OperationLease | None = None
        self.status_snapshots: list[ServiceStatus] = []
        self.service_resources: dict[str, GuestServiceResource] = {}
        self.redis_relay_status: dict[str, object] | None = None

    def check_ready(self) -> None:
        if self.ready_failure is not None:
            raise self.ready_failure

    def record_accepted(
        self,
        operation: ServiceOperation,
        *,
        lease: OperationLease,
    ) -> None:
        self.saved.append(operation)
        self.events.append(operation_event(operation))
        self.active_lease = lease

    def record_transition(
        self,
        operation: ServiceOperation,
    ) -> None:
        self.saved.append(operation)
        self.events.append(operation_event(operation))
        if operation.state in TERMINAL_OPERATION_STATES:
            self.active_lease = None

    def list_unfinished_operations(self) -> list[ServiceOperation]:
        latest: dict[str, ServiceOperation] = {}
        for operation in self.saved:
            latest[operation.operation_id] = operation
        return [
            operation
            for operation in latest.values()
            if operation.state in {OperationState.ACCEPTED, OperationState.RUNNING}
        ]

    def save_service_status_snapshot(self, status: ServiceStatus) -> None:
        self.status_snapshots.append(status)

    def save_guest_service_resource(self, resource: GuestServiceResource) -> None:
        self.service_resources[resource.service] = resource

    def get_guest_service_resource(self, service: str) -> GuestServiceResource | None:
        return self.service_resources.get(service)

    def save_status(self, document: dict[str, object]) -> None:
        self.redis_relay_status = document

    def status(self) -> dict[str, object]:
        if self.redis_relay_status is None:
            return {
                "readState": "readFailed",
                "document": None,
                "readError": "Redis relay status snapshot is missing.",
            }
        return {
            "readState": "loaded",
            "document": self.redis_relay_status,
            "readError": None,
        }

    def get(self, operation_id: str) -> ServiceOperation | None:
        return next(
            (
                operation
                for operation in reversed(self.saved)
                if operation.operation_id == operation_id
            ),
            None,
        )

    def query_events(self, **_: object) -> dict[str, object]:
        return {"events": [], "nextCursor": None, "matchingCount": None}


def operation_event(operation: ServiceOperation) -> OperationEvent:
    return OperationEvent(
        operation_id=operation.operation_id,
        state=operation.state,
        observed_at=operation.updated_at,
        failure=operation.failure,
        result=operation.result,
    )


class MissingOperationRead(FakeOperations):
    def get(self, operation_id: str) -> ServiceOperation | None:
        del operation_id
        return None


class FakeServiceControl:
    def __init__(
        self,
        *,
        fail_command: str | None = None,
        fail_status: bool = False,
        services: list[str] | None = None,
    ) -> None:
        self.fail_command = fail_command
        self.fail_status = fail_status
        self.services = services or ["app", "redis"]
        self.service_states: dict[str, str] = dict.fromkeys(self.services, "running")
        self.started: list[str] = []
        self.stopped: list[str] = []
        self.restarted: list[str] = []
        self.reconciled = 0

    def list_services(self) -> list[str]:
        return self.services

    def get_service_status(self, service: str) -> ServiceStatus:
        if service not in self.services:
            raise ServiceNotFoundError(service, available_services=self.services)
        if self.fail_status:
            raise GuestControlDependencyError(
                "compose status read failed",
                kind="guest-stack-status-read-failed",
            )
        return ServiceStatus(
            service=service,
            state=self.service_states[service],
            health="healthy" if self.service_states[service] == "running" else "none",
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
        self.service_states[service] = "running"

    def stop_service(self, service: str) -> None:
        self.stopped.append(service)
        self._raise_if_failed("stop")
        self.service_states[service] = "stopped"

    def restart_service(self, service: str) -> None:
        self.restarted.append(service)
        self._raise_if_failed("restart")
        self.service_states[service] = "running"

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
    def __init__(
        self,
        *,
        fail_create: bool = False,
        fail_delete: bool = False,
    ) -> None:
        self.fail_create = fail_create
        self.fail_delete = fail_delete
        self.created: list[dict[str, object]] = []
        self.deleted_sessions: list[str] = []

    def list_scenarios(self) -> dict[str, object]:
        return {"state": "loaded", "scenarios": [], "readError": None}

    def list_vital_files(self) -> dict[str, object]:
        return {"state": "loaded", "vitalFiles": [], "readError": None}

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
        recorders = (
            []
            if "lab-session-1" in self.deleted_sessions
            else [
                {
                    "recorderId": "lab-session-1-recorder-1",
                    "sessionId": "lab-session-1",
                    "bedId": "lab-session-1-bed-1",
                    "vrcode": "LAB-lab-session-1-1",
                    "state": "running",
                }
            ]
        )
        return {
            "state": "loaded",
            "recorders": recorders,
            "readError": None,
        }

    def list_sessions(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "sessions": [self.get_session("lab-session-1").session],
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

    def start_recorder(
        self, session_id: str, recorder_id: str
    ) -> ProductLabRecorderResult:
        return self._recorder_result(session_id, recorder_id, "running")

    def stop_recorder(
        self, session_id: str, recorder_id: str
    ) -> ProductLabRecorderResult:
        return self._recorder_result(session_id, recorder_id, "stopped")

    def _recorder_result(
        self, session_id: str, recorder_id: str, state: str
    ) -> ProductLabRecorderResult:
        return ProductLabRecorderResult(
            recorder={
                **self.list_recorders()["recorders"][0],
                "sessionId": session_id,
                "recorderId": recorder_id,
                "state": state,
            },
            lab_operation_id=f"lab-recorder-{state}-{recorder_id}",
        )

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

    def delete_session(self, session_id: str) -> ProductLabReadModelResult:
        if self.fail_delete:
            raise ProductLabDependencyError(
                "Product Lab service is not reachable",
                kind="product-lab-unavailable",
            )
        self.deleted_sessions.append(session_id)
        return ProductLabReadModelResult(
            document={"state": "loaded", "sessions": [], "readError": None}
        )

    def replay_vital_file(self, request: dict[str, object]) -> dict[str, object]:
        raise NotImplementedError(request)

class FakeVitalDBReadModel:
    def __init__(self, *, fail: bool = False, lab_owned: bool = False) -> None:
        self.fail = fail
        self.lab_owned = lab_owned
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
                "vrcode": ("LAB-lab-session-1-1" if self.lab_owned else "VR-001"),
                "bedName": "OR-A",
                "status": "connected",
                "version": "vitalserver-lab" if self.lab_owned else "1.0",
                "visibility": (
                    "hidden"
                    if ("LAB-lab-session-1-1" if self.lab_owned else "VR-001")
                    in self.hidden_recorders
                    else "visible"
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
                "vrcode": ("LAB-lab-session-1-1" if self.lab_owned else "VR-001"),
                "linkedRecorderVersion": (
                    "vitalserver-lab" if self.lab_owned else "1.0"
                ),
                "recorderCount": 1,
                "visibility": "hidden" if "bed-a" in self.hidden_beds else "visible",
            }
        ]
        return {
            "state": "loaded",
            "beds": [bed for bed in beds if bed["bedID"] not in self.deleted_beds],
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


class FakeRedisRelay:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.saved: dict[str, object] | None = None

    def save_status(self, document: dict[str, object]) -> None:
        if self.fail:
            raise RedisRelayDependencyError(
                "Redis relay status document is invalid.",
                kind="redis-relay-contract-invalid",
            )
        self.saved = document

    def status(self) -> dict[str, object]:
        if self.fail:
            raise RedisRelayDependencyError(
                "Redis relay status document is invalid.",
                kind="redis-relay-contract-invalid",
            )
        return {
            "readState": "loaded",
            "document": redis_relay_status_document(copied=1),
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


def build_usecases(
    *,
    service_control: FakeServiceControl,
    operations: FakeOperations,
    operation_ids: FakeOperationIds,
    clock: FakeClock,
    **adapters: object,
) -> GuestControlUseCases:
    """Compose the three required control repositories around one test store."""
    return GuestControlUseCases(
        service_control=service_control,
        operations=operations,
        service_status_snapshots=operations,
        guest_service_resources=operations,
        operation_ids=operation_ids,
        clock=clock,
        **adapters,
    )


class FakeVitalFileLibrary:
    def import_files(
        self, files: list[tuple[str, bytes]]
    ) -> list[dict[str, object]]:
        return [
            {"fileName": name, "relativePath": name, "sizeBytes": len(content)}
            for name, content in files
        ]


def test_capabilities_include_only_configured_adapter_features() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
        vitaldb_read_model=FakeVitalDBReadModel(),
        recorder_ingress=FakeRecorderIngress(),
        redis_relay=FakeRedisRelay(),
        redis_backup=FakeRedisBackup(),
        datastore_repair=FakeDatastoreRepair(),
        update_activation=FakeUpdateActivation(),
        update_shutdown=FakeUpdateShutdown(),
        vital_file_library=FakeVitalFileLibrary(),
    )

    document = usecases.capabilities()

    assert document["schemaVersion"] == 1
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
        "lab:scenarios",
        "lab:vital-files",
        "lab:beds",
        "lab:beds:create",
        "lab:beds:delete",
        "lab:beds:reset",
        "lab:recorders",
        "lab:recorders:create",
        "lab:recorders:delete",
        "lab:recorders:reset",
        "lab:recorders:start",
        "lab:recorders:stop",
        "lab:sessions:list",
        "lab:sessions:create",
        "lab:sessions:get",
        "lab:sessions:start",
        "lab:sessions:stop",
        "lab:vital-files:replay",
        "lab:vital-files:upload",
        "maintenance:redis-backup:create",
        "maintenance:redis-restore:create",
        "maintenance:datastore-repair:create",
        "maintenance:update-activation:create",
        "maintenance:update-shutdown:create",
        "maintenance:guest-poweroff:create",
        "recorder-ingress:status:get",
        "redis-relay:status:get",
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
    usecases = build_usecases(
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
            "services:resource:get",
            "services:spec:update",
            "services:reconcile",
            "services:start",
            "services:stop",
            "services:restart",
            "stack:reconcile",
            "operations:get",
        ],
    }


def test_readiness_only_probes_required_control_dependencies() -> None:
    class UnprobedVitalDBReadModel(FakeVitalDBReadModel):
        def check_ready(self) -> None:
            raise AssertionError("/ready must not probe the Product VitalDB read model")

    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=UnprobedVitalDBReadModel(),
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
        ],
    }


def test_readiness_preserves_control_store_failure() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(
            ready_failure=GuestControlDependencyError(
                "control SQLite schema is not at the required revision",
                kind="controlStoreSchemaMismatch",
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
                "kind": "controlStoreSchemaMismatch",
                "message": "control SQLite schema is not at the required revision",
            }
        ],
    }


def test_start_service_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = build_usecases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.start_service("app")

    assert operation.state == OperationState.COMPLETED
    assert operation.command == ServiceCommand.START
    assert operation.result == {
        "effect": "none",
        "command": None,
        "reason": "DesiredStateObserved",
        "message": "Guest service already matches desired running state.",
    }
    assert service_control.started == []
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
    resource = operations.service_resources["app"]
    assert resource.spec.as_json()["desiredState"] == "running"
    assert resource.last_operation_id == "op_app_start_1"


def test_service_command_lease_conflict_does_not_write_desired_state() -> None:
    class LeaseConflictOperations(FakeOperations):
        def record_accepted(
            self,
            operation: ServiceOperation,
            *,
            lease: OperationLease,
        ) -> None:
            del operation
            del lease
            raise GuestControlDependencyError(
                "a Guest Control operation already owns the command lease",
                kind="operationLeaseConflict",
            )

    operations = LeaseConflictOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    with pytest.raises(GuestControlDependencyError) as error:
        usecases.stop_service("app")

    assert error.value.kind == "operationLeaseConflict"
    assert operations.saved == []
    assert operations.service_resources == {}


def test_controller_recovery_marks_unfinished_operation_as_interrupted() -> None:
    operations = FakeOperations()
    accepted = ServiceOperation(
        operation_id="op_app_restart_1",
        service="app",
        command=ServiceCommand.RESTART,
        state=OperationState.ACCEPTED,
        created_at=datetime(2026, 7, 1, tzinfo=UTC),
        updated_at=datetime(2026, 7, 1, tzinfo=UTC),
    )
    operations.record_accepted(
        accepted,
        lease=OperationLease(
            resource_key="guest-control",
            operation_id=accepted.operation_id,
            acquired_at=accepted.created_at,
        ),
    )
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    usecases.recover_interrupted_operations()

    interrupted = operations.saved[-1]
    assert interrupted.state == OperationState.INTERRUPTED
    assert interrupted.failure is not None
    assert interrupted.failure.kind == "controllerRestarted"
    assert operations.events[-1].state == OperationState.INTERRUPTED
    assert operations.active_lease is None


def test_guest_service_resource_get_is_side_effect_free() -> None:
    operations = FakeOperations()
    operations.save_guest_service_resource(
        GuestServiceResource(
            service="app",
            spec=GuestServiceSpec.configured(
                desired_state=GuestServiceDesiredState.RUNNING,
                updated_at=datetime(2026, 7, 1, tzinfo=UTC),
            ),
            status=GuestServiceStatusRead.failed(
                OperationFailure(
                    kind="notObserved",
                    message="not observed",
                )
            ),
            conditions=[],
        )
    )
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    document = usecases.get_guest_service_resource("app")

    assert document["spec"]["state"] == "configured"
    assert document["spec"]["desiredState"] == "running"
    assert operations.status_snapshots == []


def test_guest_service_resource_get_reports_missing_spec_without_seeding() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    document = usecases.get_guest_service_resource("app")

    assert document["spec"]["state"] == "missing"
    assert document["spec"]["desiredState"] is None
    assert document["status"]["state"] == "failed"
    assert document["status"]["readError"] == {
        "kind": "guestServiceStatusNotObserved",
        "message": "Guest service status has not been observed.",
    }
    assert document["conditions"] == []
    assert operations.service_resources == {}


def test_guest_service_spec_initialization_seeds_missing_resources_explicitly() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    usecases.initialize_guest_service_specs(
        {
            "app": GuestServiceDesiredState.RUNNING,
            "redis": GuestServiceDesiredState.RUNNING,
        }
    )

    assert operations.service_resources["app"].spec.as_json() == {
        "state": "configured",
        "desiredState": "running",
        "updatedAt": "2026-07-01T00:00:00+00:00",
    }
    assert operations.service_resources["redis"].spec.as_json()["state"] == (
        "configured"
    )


def test_guest_service_spec_initialization_migrates_missing_and_preserves_configured(
) -> None:
    operations = FakeOperations()
    operations.save_guest_service_resource(
        GuestServiceResource(
            service="app",
            spec=GuestServiceSpec.configured(
                desired_state=GuestServiceDesiredState.STOPPED,
                updated_at=datetime(2026, 6, 30, tzinfo=UTC),
            ),
            status=GuestServiceStatusRead.failed(
                OperationFailure(kind="notObserved", message="not observed")
            ),
            conditions=[],
        )
    )
    operations.save_guest_service_resource(
        GuestServiceResource(
            service="redis",
            spec=GuestServiceSpec.missing(),
            status=GuestServiceStatusRead.failed(
                OperationFailure(kind="notObserved", message="not observed")
            ),
            conditions=[],
        )
    )
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    usecases.initialize_guest_service_specs(
        {
            "app": GuestServiceDesiredState.RUNNING,
            "redis": GuestServiceDesiredState.RUNNING,
        }
    )

    assert operations.service_resources["app"].spec.desired_state == (
        GuestServiceDesiredState.STOPPED
    )
    assert operations.service_resources["app"].spec.updated_at == datetime(
        2026, 6, 30, tzinfo=UTC
    )
    assert operations.service_resources["redis"].spec.desired_state == (
        GuestServiceDesiredState.RUNNING
    )


def test_observe_guest_service_reads_and_persists_loaded_status() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    document = usecases.observe_guest_service("app")

    assert document["spec"]["state"] == "missing"
    assert document["spec"]["desiredState"] is None
    assert document["status"]["state"] == "loaded"
    assert document["status"]["observedState"] == "running"
    assert document["conditions"][0]["reason"] == "SpecMissing"
    assert operations.status_snapshots[0].service == "app"
    assert operations.service_resources["app"].spec.as_json()["state"] == "missing"
    assert operations.service_resources["app"].status.as_json()["observedState"] == (
        "running"
    )


def test_observe_guest_service_uses_explicit_status_and_resource_repositories() -> None:
    operations = FakeOperations()
    status_snapshots = FakeOperations()
    guest_service_resources = FakeOperations()
    usecases = GuestControlUseCases(
        service_control=FakeServiceControl(),
        operations=operations,
        service_status_snapshots=status_snapshots,
        guest_service_resources=guest_service_resources,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    document = usecases.observe_guest_service("app")

    assert document["status"]["state"] == "loaded"
    assert operations.status_snapshots == []
    assert operations.service_resources == {}
    assert status_snapshots.status_snapshots[0].service == "app"
    assert (
        guest_service_resources.service_resources["app"].status.as_json()[
            "observedState"
        ]
        == "running"
    )


def test_guest_service_spec_update_persists_desired_state() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    document = usecases.update_guest_service_spec(
        "app",
        {"desiredState": "stopped"},
    )

    assert document["spec"]["state"] == "configured"
    assert document["spec"]["desiredState"] == "stopped"
    assert operations.service_resources["app"].spec.as_json()["desiredState"] == (
        "stopped"
    )


def test_guest_service_spec_update_rejects_invalid_desired_state() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    with pytest.raises(GuestControlDependencyError) as error:
        usecases.update_guest_service_spec(
            "app",
            {"desiredState": "paused"},
        )

    assert error.value.kind == "guestServiceSpecInvalid"
    assert operations.service_resources == {}


def test_guest_service_controller_rejects_unknown_service() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(services=["app"]),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    with pytest.raises(ServiceNotFoundError) as get_error:
        usecases.get_guest_service_resource("redis")
    with pytest.raises(ServiceNotFoundError) as observe_error:
        usecases.observe_guest_service("redis")
    with pytest.raises(ServiceNotFoundError) as spec_error:
        usecases.update_guest_service_spec("redis", {"desiredState": "running"})
    with pytest.raises(ServiceNotFoundError) as reconcile_error:
        usecases.reconcile_guest_service("redis")

    assert get_error.value.available_services == ["app"]
    assert observe_error.value.available_services == ["app"]
    assert spec_error.value.available_services == ["app"]
    assert reconcile_error.value.available_services == ["app"]
    assert operations.service_resources == {}
    assert operations.saved == []


def test_get_service_status_persists_status_snapshot() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status = usecases.get_stack_status()

    assert status.state == "loaded"
    assert [service.service for service in status.services] == ["app", "redis"]
    assert operations.status_snapshots == status.services
    assert operations.service_resources["app"].spec.as_json()["state"] == "missing"
    assert operations.service_resources["app"].spec.as_json()["desiredState"] is None
    assert operations.service_resources["app"].status.as_json()["observedState"] == (
        "running"
    )
    assert operations.service_resources["app"].conditions[0].reason == "SpecMissing"


def test_get_stack_status_preserves_existing_guest_service_desired_state() -> None:
    operations = FakeOperations()
    operations.save_guest_service_resource(
        GuestServiceResource(
            service="app",
            spec=GuestServiceSpec.configured(
                desired_state=GuestServiceDesiredState.STOPPED,
                updated_at=datetime(2026, 7, 1, tzinfo=UTC),
            ),
            status=GuestServiceStatusRead.failed(
                OperationFailure(
                    kind="notObserved",
                    message="not observed",
                )
            ),
            conditions=[],
        )
    )
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    usecases.get_stack_status()

    assert operations.service_resources["app"].spec.as_json()["desiredState"] == (
        "stopped"
    )
    assert operations.service_resources["app"].status.as_json()["observedState"] == (
        "running"
    )
    assert operations.service_resources["app"].conditions[0].reason == "StopRequired"


def test_stop_service_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = build_usecases(
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
    assert [status.service for status in operations.status_snapshots] == [
        "app",
        "app",
    ]
    assert usecases.get_operation("op_app_stop_1") == operation
    assert operation.result == {
        "effect": "stop",
        "command": "stop",
        "reason": "StopRequired",
        "message": "Guest service must be stopped to match desired state.",
    }
    resource = operations.service_resources["app"]
    assert resource.status.as_json()["observedState"] == "stopped"
    assert resource.conditions[0].reason == "DesiredStateObserved"


def test_restart_service_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = build_usecases(
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
    assert [status.service for status in operations.status_snapshots] == [
        "app",
        "app",
    ]
    assert usecases.get_operation("op_app_restart_1") == operation
    assert operation.result == {
        "effect": "restart",
        "command": "restart",
        "reason": "RestartRequested",
        "message": "Guest service restart was explicitly requested.",
    }


def test_restart_service_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(fail_command="restart"),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.restart_service("app")

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "guest-compose-command-failed"
    assert operations.status_snapshots != []
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
    assert [status.service for status in operations.status_snapshots] == ["app"]


def test_restart_service_status_snapshot_failure_is_persisted_as_failed_operation() -> (
    None
):
    operations = FakeOperations()
    service_control = FakeServiceControl(fail_status=True)
    usecases = build_usecases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.restart_service("app")

    assert operation.state == OperationState.FAILED
    assert service_control.restarted == []
    assert operation.failure is not None
    assert operation.failure.kind == "guestServiceReconcileBlocked"
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
        OperationState.FAILED,
    ]
    assert operations.status_snapshots == []


def test_reconcile_guest_service_without_spec_is_blocked() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = build_usecases(
        service_control=service_control,
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    operation = usecases.reconcile_guest_service("app")

    assert operation.state == OperationState.FAILED
    assert operation.failure is not None
    assert operation.failure.kind == "guestServiceReconcileBlocked"
    assert operation.failure.message == "Guest service desired state is not configured."
    assert service_control.started == []
    assert service_control.stopped == []
    assert service_control.restarted == []
    assert operations.service_resources["app"].spec.as_json()["state"] == "missing"
    assert operations.service_resources["app"].spec.as_json()["desiredState"] is None
    assert operations.service_resources["app"].conditions[0].reason == "SpecMissing"
    assert operations.service_resources["app"].last_operation_id == "op_app_reconcile_1"


def test_reconcile_services_persists_operation_transitions() -> None:
    operations = FakeOperations()
    service_control = FakeServiceControl()
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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


def test_prepare_update_shutdown_rejects_missing_persisted_operation_state() -> None:
    operations = MissingOperationRead()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        update_shutdown=FakeUpdateShutdown(),
    )

    with pytest.raises(GuestControlDependencyError) as error:
        usecases.prepare_update_shutdown(
            request_id="update-shutdown-request-1",
            version="0.2.0",
        )

    assert error.value.kind == "operationStateMissing"
    assert (
        "operationId=op_update-shutdown_prepare-update-shutdown_1"
        in error.value.message
    )
    assert [saved.state for saved in operations.saved] == [
        OperationState.ACCEPTED,
        OperationState.RUNNING,
    ]


def test_prepare_update_shutdown_ready_callback_persists_completed_result() -> None:
    operations = FakeOperations()
    update_shutdown = FakeUpdateShutdown(ready_immediately=True)
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    beds = usecases.list_lab_beds()
    recorders = usecases.list_lab_recorders()
    sessions = usecases.list_lab_sessions()

    assert beds["state"] == "loaded"
    assert beds["beds"][0]["name"] == "OR-A"
    assert recorders["state"] == "loaded"
    assert recorders["recorders"][0]["vrcode"] == "LAB-lab-session-1-1"
    assert sessions["state"] == "loaded"
    assert sessions["sessions"][0]["sessionId"] == "lab-session-1"


def test_lab_recorder_commands_persist_explicit_operation_and_result() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    stopped = usecases.stop_lab_recorder("lab-session-1", "lab-session-1-recorder-1")
    started = usecases.start_lab_recorder("lab-session-1", "lab-session-1-recorder-1")

    assert stopped["state"] == "loaded"
    assert stopped["recorder"]["state"] == "stopped"
    assert stopped["operationId"] == "op_product-lab_lab-stop-recorder_1"
    assert started["state"] == "loaded"
    assert started["recorder"]["state"] == "running"
    assert started["operationId"] == "op_product-lab_lab-start-recorder_1"
    assert [
        operation.command
        for operation in operations.saved
        if operation.state == OperationState.COMPLETED
    ] == [
        ServiceCommand.LAB_STOP_RECORDER,
        ServiceCommand.LAB_START_RECORDER,
    ]


def test_create_lab_session_failure_is_persisted_as_failed_operation() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.list_vitaldb_recorders()

    assert response["state"] == "readFailed"
    assert response["recorders"] == []
    assert response["updatedAt"] is None
    assert response["readError"] == (
        "VitalDB recorder read model adapter is unavailable."
    )


def test_vitaldb_recorders_return_read_model_document() -> None:
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    delete_without_hide = usecases.delete_vitaldb_recorders({"vrcodes": ["VR-001"]})
    hidden = usecases.hide_vitaldb_recorders({"vrcodes": ["VR-001"]})
    deleted = usecases.delete_vitaldb_recorders({"vrcodes": ["VR-001"]})

    assert delete_without_hide["state"] == "readFailed"
    assert delete_without_hide["recorders"] == []
    assert delete_without_hide["readError"] == (
        "VitalDB entity must be hidden before delete: VR-001"
    )
    assert hidden["recorders"][0]["visibility"] == "hidden"
    assert deleted["recorders"] == []


def test_vitaldb_lab_recorder_delete_removes_owning_lab_session() -> None:
    product_lab = FakeProductLab()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=product_lab,
        vitaldb_read_model=FakeVitalDBReadModel(lab_owned=True),
    )

    vrcode = "LAB-lab-session-1-1"
    usecases.hide_vitaldb_recorders({"vrcodes": [vrcode]})
    deleted = usecases.delete_vitaldb_recorders({"vrcodes": [vrcode]})

    assert deleted["state"] == "loaded"
    assert deleted["recorders"] == []
    assert product_lab.deleted_sessions == ["lab-session-1"]


def test_vitaldb_lab_recorder_delete_preserves_cleanup_failure() -> None:
    product_lab = FakeProductLab(fail_delete=True)
    read_model = FakeVitalDBReadModel(lab_owned=True)
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=product_lab,
        vitaldb_read_model=read_model,
    )

    vrcode = "LAB-lab-session-1-1"
    usecases.hide_vitaldb_recorders({"vrcodes": [vrcode]})
    result = usecases.delete_vitaldb_recorders({"vrcodes": [vrcode]})

    assert result["state"] == "readFailed"
    assert result["readError"] == (
        "Product Lab session cleanup failed: Product Lab service is not reachable"
    )
    assert read_model.deleted_recorders == set()


def test_vitaldb_recorders_unhide_restores_visible_state() -> None:
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(fail=True),
    )

    response = usecases.list_vitaldb_recorders()

    assert response["state"] == "readFailed"
    assert response["recorders"] == []
    assert response["readError"] == "Postgres read model is unreachable."


def test_vitaldb_recorder_activity_reports_unavailable_without_adapter() -> None:
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.list_vitaldb_beds()

    assert response["state"] == "readFailed"
    assert response["beds"] == []
    assert response["updatedAt"] is None
    assert response["readError"] == "VitalDB bed read model adapter is unavailable."


def test_vitaldb_beds_return_read_model_document() -> None:
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(),
    )

    delete_without_hide = usecases.delete_vitaldb_beds({"bedIDs": ["bed-a"]})
    hidden = usecases.hide_vitaldb_beds({"bedIDs": ["bed-a"]})
    deleted = usecases.delete_vitaldb_beds({"bedIDs": ["bed-a"]})

    assert delete_without_hide["state"] == "readFailed"
    assert delete_without_hide["beds"] == []
    assert delete_without_hide["readError"] == (
        "VitalDB entity must be hidden before delete: bed-a"
    )
    assert hidden["beds"][0]["visibility"] == "hidden"
    assert deleted["beds"] == []


def test_vitaldb_lab_bed_delete_removes_owning_lab_session() -> None:
    product_lab = FakeProductLab()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=product_lab,
        vitaldb_read_model=FakeVitalDBReadModel(lab_owned=True),
    )

    usecases.hide_vitaldb_beds({"bedIDs": ["bed-a"]})
    deleted = usecases.delete_vitaldb_beds({"bedIDs": ["bed-a"]})

    assert deleted["state"] == "loaded"
    assert deleted["beds"] == []
    assert product_lab.deleted_sessions == ["lab-session-1"]


def test_vitaldb_beds_unhide_restores_visible_state() -> None:
    usecases = build_usecases(
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
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vitaldb_read_model=FakeVitalDBReadModel(fail=True),
    )

    response = usecases.list_vitaldb_beds()

    assert response["state"] == "readFailed"
    assert response["beds"] == []
    assert response["readError"] == "Postgres read model is unreachable."


def test_vitaldb_relationships_report_unavailable_without_adapter() -> None:
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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
    usecases = build_usecases(
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


def test_redis_relay_status_reports_unavailable_without_adapter() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    response = usecases.get_redis_relay_status()

    assert response == {
        "readState": "readFailed",
        "document": None,
        "readError": "Redis relay status adapter is unavailable.",
    }


def test_redis_relay_status_returns_status_read_document() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_relay=FakeRedisRelay(),
    )

    response = usecases.get_redis_relay_status()

    assert response["readState"] == "loaded"
    assert response["document"]["state"] == "running"
    assert response["readError"] is None


def test_redis_relay_status_owner_mutation_persists_snapshot() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_relay=operations,
    )

    response = usecases.put_redis_relay_status(redis_relay_status_document())

    assert response["readState"] == "loaded"
    assert response["document"]["state"] == "running"
    assert usecases.get_redis_relay_status()["document"] == response["document"]


def test_redis_relay_status_owner_mutation_rejects_incomplete_snapshot() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_relay=operations,
    )
    document = redis_relay_status_document()
    del document["totals"]["published"]

    with pytest.raises(RedisRelayStatusContractError) as error:
        usecases.put_redis_relay_status(document)

    assert error.value.message == (
        "Redis relay status document field totals.published must be integer."
    )
    assert operations.redis_relay_status is None


def test_redis_relay_status_preserves_dependency_failure() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_relay=FakeRedisRelay(fail=True),
    )

    response = usecases.get_redis_relay_status()

    assert response == {
        "readState": "invalidResponse",
        "document": None,
        "readError": "Redis relay status document is invalid.",
    }
