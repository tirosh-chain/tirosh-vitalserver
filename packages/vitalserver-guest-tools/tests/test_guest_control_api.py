from __future__ import annotations

import json
import stat
from datetime import UTC, datetime, timedelta
from http import HTTPStatus
from io import BytesIO
from pathlib import Path
from threading import Thread
from uuid import uuid4

import pytest

from tirosh_guest_tools.adapters.inbound import guest_control_api
from tirosh_guest_tools.adapters.inbound.guest_control_api import route_request
from tirosh_guest_tools.application.guest_control.ports import VitalFileUploadSource
from tirosh_guest_tools.application.guest_control.usecases import GuestControlUseCases
from tirosh_guest_tools.domain.guest_control.models import (
    TERMINAL_OPERATION_STATES,
    GuestControlDependencyError,
    GuestServiceResource,
    OperationEvent,
    OperationLease,
    OperationState,
    PostgresBackupResult,
    PostgresRestoreResult,
    ProductLabReadModelResult,
    ProductLabRecorderResult,
    ProductLabSessionResult,
    RedisBackupResult,
    RedisRestoreResult,
    ServiceNotFoundError,
    ServiceOperation,
    ServiceStatus,
    StackStatus,
    UpdateActivationResult,
    UpdateShutdownResult,
    VitalFileUploadItem,
    VitalFileUploadResult,
)
from tirosh_vitalserver.devtools.runtime_v2_conformance import RuntimeV2ConformanceSuite
from vitalserver_redis_relay.status_owner import GuestControlStatusOwnerPublisher


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
        self.event_queries: list[dict[str, object]] = []

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

    def query_events(self, **query: object) -> dict[str, object]:
        self.event_queries.append(query)
        return {
            "events": [
                {
                    "schemaVersion": 1,
                    "id": "runtime-operation-event-1",
                    "source": "runtime-controller",
                    "eventType": "operation-completed",
                    "timestamp": "2026-07-01T00:00:00+00:00",
                    "operationId": "op_app_restart_1",
                    "operationService": "app",
                    "operationCommand": "restart",
                    "operationState": "completed",
                    "message": "app restart completed",
                    "failure": None,
                }
            ],
            "nextCursor": None,
            "matchingCount": None,
        }


def operation_event(operation: ServiceOperation) -> OperationEvent:
    return OperationEvent(
        operation_id=operation.operation_id,
        state=operation.state,
        observed_at=operation.updated_at,
        failure=operation.failure,
        result=operation.result,
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
    allowed_routes: frozenset[tuple[str, str]] | None = None,
    headers: dict[str, str] | None = None,
    request_stream: BytesIO | None = None,
    upload_staging_root: Path | None = None,
    include_content_length: bool = True,
) -> tuple[HTTPStatus, dict[str, object]]:
    handler_type = guest_control_api.make_handler(
        usecases,
        allowed_routes=allowed_routes,
        upload_staging_root=upload_staging_root,
    )
    handler = object.__new__(handler_type)
    captured: dict[str, int] = {}
    handler.path = path
    request_headers = dict(headers or {})
    if include_content_length and "Content-Length" not in request_headers:
        request_headers["Content-Length"] = str(len(body))
    handler.headers = request_headers
    handler.rfile = request_stream or BytesIO(body)
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


class TrackingRequestStream(BytesIO):
    def __init__(self, content: bytes) -> None:
        super().__init__(content)
        self.requested_read_sizes: list[int] = []

    def read(self, size: int = -1) -> bytes:
        self.requested_read_sizes.append(size)
        return super().read(size)

    def readline(self, size: int = -1) -> bytes:
        self.requested_read_sizes.append(size)
        return super().readline(size)


def multipart_upload_body(
    files: list[tuple[str, bytes]],
    *,
    boundary: str,
) -> bytes:
    body = bytearray()
    for filename, content in files:
        body.extend(
            (
                f"--{boundary}\r\n"
                'Content-Disposition: form-data; name="files"; '
                f'filename="{filename}"\r\n'
                "Content-Type: application/octet-stream\r\n\r\n"
            ).encode()
        )
        body.extend(content)
        body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode())
    return bytes(body)


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

    def list_sessions(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "sessions": [
                lab_session(
                    session_id="lab-session-1",
                    scenario_id="normal_monitoring",
                    state="running",
                )
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

    def finish_session(self, session_id: str) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session=lab_session(
                session_id=session_id,
                scenario_id="normal_monitoring",
                state="finished",
            ),
            lab_operation_id=f"lab-session-finish-{session_id}",
        )

    def delete_session(self, session_id: str) -> ProductLabReadModelResult:
        del session_id
        return ProductLabReadModelResult(
            document={"state": "loaded", "sessions": [], "readError": None}
        )

    def start_recorder(
        self, session_id: str, recorder_id: str
    ) -> ProductLabRecorderResult:
        return self._recorder_result(
            session_id=session_id,
            recorder_id=recorder_id,
            state="running",
            command="start",
        )

    def stop_recorder(
        self, session_id: str, recorder_id: str
    ) -> ProductLabRecorderResult:
        return self._recorder_result(
            session_id=session_id,
            recorder_id=recorder_id,
            state="stopped",
            command="stop",
        )

    def _recorder_result(
        self,
        *,
        session_id: str,
        recorder_id: str,
        state: str,
        command: str,
    ) -> ProductLabRecorderResult:
        recorder = dict(self.list_recorders()["recorders"][0])
        recorder.update(
            {
                "recorderId": recorder_id,
                "sessionId": session_id,
                "state": state,
            }
        )
        return ProductLabRecorderResult(
            recorder=recorder,
            lab_operation_id=f"lab-recorder-{command}-{recorder_id}",
        )

    def replay_vital_file(self, request: dict[str, object]) -> ProductLabSessionResult:
        return ProductLabSessionResult(
            session=lab_session(
                session_id="lab-replay-1",
                scenario_id="normal_monitoring",
                name=str(request["vitalFileRelativePath"]),
            ),
            lab_operation_id="lab-vital-file-replay-lab-replay-1",
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

    def relationships(self, *, event_limit: int) -> dict[str, object]:
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
            "eventTotalCount": 0,
            "eventLimit": event_limit,
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

    def native_vital_uploads(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "uploads": [
                {
                    "schemaVersion": 1,
                    "origin": "nativeRecorderUpload",
                    "uploadId": "upload-001",
                    "bedName": "OR-A",
                    "declaredVrcode": None,
                    "filename": "OR-A_260701_000000.vital",
                    "declaredSizeBytes": 100,
                    "state": "indexed",
                    "receivedAt": "2026-07-01T00:00:04+00:00",
                    "upstreamAcceptedAt": "2026-07-01T00:00:05+00:00",
                    "indexedAt": "2026-07-01T00:00:06+00:00",
                    "reconciliationAttempts": 1,
                    "lastReconciliationAt": "2026-07-01T00:00:06+00:00",
                    "indexEvidence": {
                        "filename": "OR-A_260701_000000.vital",
                        "sizeBytes": 100,
                        "recordingStartedAt": 1,
                        "recordingEndedAt": 2,
                        "uploadedAt": 3,
                    },
                    "failure": None,
                }
            ],
            "readError": None,
        }

    def recorder_observability(self) -> dict[str, object]:
        return _recorder_observability_list()

    def recorder_observability_detail(self, vrcode: str) -> dict[str, object]:
        return _recorder_observability_detail(vrcode)

    def apply_recorder_observability_expectation(
        self,
        command: dict[str, object],
    ) -> dict[str, object]:
        return {
            "state": "accepted",
            "commandId": command["commandId"],
            "eventId": "event-001",
            "vrcode": command["vrcode"],
            "currentRevision": 1,
            "failure": None,
        }


class FakeRecorderRecovery:
    def list_artifacts(self) -> dict[str, object]:
        return {
            "state": "loaded",
            "artifacts": [],
            "readError": None,
        }


def _recorder_observability_list() -> dict[str, object]:
    return {
        "state": "loaded",
        "recorders": [
            {
                "vrcode": "VR-001",
                "supportState": "supported",
                "supportSource": "accepted_report",
                "reportState": "current",
                "profileState": "associated",
                "collectionState": "ok",
                "latestObservationReceivedAt": "2026-07-01T00:00:00+00:00",
                "lastBootStartedAt": "2026-07-01T00:00:00+00:00",
                "readIssueCount": 0,
                "expectedSince": None,
                "recorderVersion": None,
                "producerVersion": None,
                "protocolVersion": None,
            }
        ],
        "readError": None,
    }


def _recorder_observability_detail(vrcode: str) -> dict[str, object]:
    missing = {
        "state": "missing",
        "value": None,
        "detail": "health observation is absent",
        "observedAt": None,
    }
    return {
        "state": "loaded",
        "vrcode": vrcode,
        "support": {
            "state": "supported",
            "source": "accepted_report",
            "expectedSince": None,
            "recorderVersion": None,
            "producerVersion": None,
            "protocolVersion": None,
        },
        "report": {
            "state": "current",
            "receivedAt": "2026-07-01T00:00:00+00:00",
            "deviceObservedAt": "2026-07-01T00:00:00+00:00",
            "collectionState": "ok",
            "readIssueCount": 0,
        },
        "profile": {
            "state": "associated",
            "receivedAt": None,
            "deviceObservedAt": None,
            "deviceId": None,
            "bootId": None,
            "software": {},
            "collection": None,
            "capabilities": {},
        },
        "boot": {
            "state": "notReported",
            "bootId": None,
            "startedAt": None,
            "cleanShutdownAt": None,
        },
        "readings": {
            "temperatureCelsius": dict(missing),
            "memoryAvailableBytes": dict(missing),
            "memoryTotalBytes": dict(missing),
            "rootUsedPercent": dict(missing),
            "dataUsedPercent": dict(missing),
            "recorderActiveState": dict(missing),
            "publisherActiveState": dict(missing),
            "publisherBufferBytes": dict(missing),
            "publisherBufferLimitBytes": dict(missing),
            "networkInterfaces": [],
        },
        "readIssues": [],
        "readError": None,
    }


class FakeRedisRelay:
    def __init__(self) -> None:
        self.saved: dict[str, object] | None = None

    def save_status(self, document: dict[str, object]) -> None:
        self.saved = document

    def status(self) -> dict[str, object]:
        return {
            "readState": "loaded",
            "document": redis_relay_status_document(),
            "readError": None,
        }


class FakeRedisBackup:
    def create_backup(self) -> RedisBackupResult:
        return RedisBackupResult(
            archive="/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
        )

    def restore_backup(self, archive: str) -> RedisRestoreResult:
        return RedisRestoreResult(restored_archive=archive)


class FakePostgresBackup:
    def create_backup(self) -> PostgresBackupResult:
        return PostgresBackupResult(
            archive="/mnt/tirosh/backups/postgres/postgres-20260701.tar.gz",
            alembic_revision="0002_observability_expectations",
        )

    def restore_backup(
        self,
        archive: str,
        *,
        restart_runtime: bool,
    ) -> PostgresRestoreResult:
        return PostgresRestoreResult(
            restored_archive=archive,
            alembic_revision="0002_observability_expectations",
            runtime_restarted=restart_runtime,
        )


class FakeDatastoreRepair:
    def repair_datastore(self) -> None:
        return None


class FakeRuntimeSettings:
    def __init__(self) -> None:
        self.settings = runtime_settings_document()

    def read(self) -> dict[str, object]:
        return dict(self.settings)

    def save(self, settings: dict[str, object]) -> None:
        self.settings = dict(settings)


class FakeRuntimeAdmin:
    def __init__(self) -> None:
        self.password: str | None = None

    def replace_admin_password(self, password: str) -> None:
        self.password = password


class FakeRedisRelaySettings:
    def __init__(self) -> None:
        self.settings: dict[str, object] = {
            "enabled": False,
            "target": {
                "url": "redis://redis.example:6379/0",
                "username": "",
                "passwordConfigured": False,
                "tls": False,
            },
            "scope": "vital_reconstruction",
            "includeRecorderNetworkContext": False,
            "intervalSeconds": 1.0,
            "scanCount": 1000,
        }

    def read(self) -> dict[str, object]:
        return self.settings

    def save(self, settings: dict[str, object]) -> None:
        self.settings = settings


def runtime_settings_document() -> dict[str, object]:
    path = (
        Path(__file__).parents[3]
        / "apps/vitalserver-platform-agent/packaging/linux/runtime-settings.json"
    )
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict)
    return value


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
                postgres_backup_path="/mnt/tirosh/backups/postgres/update.tar.gz",
            )
        )

    def request_poweroff(self) -> None:
        return None


class FakeVitalFileLibrary:
    def __init__(self) -> None:
        self.imported: list[list[tuple[str, bytes]]] = []

    def list_files(self) -> list[dict[str, object]]:
        filename = "MORA04_260701_000000.vital"
        relative_path = f"MORA04/202607/260701/{filename}"
        return [
            {
                "displayName": filename,
                "relativePath": relative_path,
                "guestPath": f"/mnt/tirosh-vital-files/{relative_path}",
                "sizeBytes": 123,
                "modifiedAt": "2026-07-01T00:00:00Z",
            }
        ]

    def import_sources(
        self,
        sources: list[VitalFileUploadSource],
    ) -> VitalFileUploadResult:
        files: list[tuple[str, bytes]] = []
        for source in sources:
            with source.open() as stream:
                files.append((source.file_name, stream.read()))
        self.imported.append(files)
        return VitalFileUploadResult.from_items(
            [
                VitalFileUploadItem(
                    file_name=filename,
                    relative_path=filename,
                    size_bytes=len(content),
                )
                for filename, content in files
            ],
            [],
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


@pytest.fixture
def usecases() -> GuestControlUseCases:
    return build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
        vitaldb_read_model=FakeVitalDBReadModel(),
        recorder_ingress=FakeRecorderIngress(),
        recorder_recovery=FakeRecorderRecovery(),
        redis_relay=FakeRedisRelay(),
        runtime_settings=FakeRuntimeSettings(),
        runtime_admin=FakeRuntimeAdmin(),
        redis_relay_settings=FakeRedisRelaySettings(),
        redis_backup=FakeRedisBackup(),
        postgres_backup=FakePostgresBackup(),
        datastore_repair=FakeDatastoreRepair(),
        update_activation=FakeUpdateActivation(),
        update_shutdown=FakeUpdateShutdown(),
        vital_file_library=FakeVitalFileLibrary(),
    )


def test_default_usecases_require_migrated_sqlite_without_postgres_startup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    checks: list[str] = []
    vital_file_library_inputs: list[dict[str, object]] = []

    class FakeSQLiteOperations(FakeOperations):
        def __init__(self, database_path: Path) -> None:
            super().__init__()
            self.database_path = database_path

        def check_ready(self) -> None:
            checks.append("sqlite")
            super().check_ready()

        def migrate_schema(self) -> None:
            raise AssertionError("Guest Control API must not migrate control state")

    class FakePostgresVitalDB(FakeVitalDBReadModel):
        def check_ready(self) -> None:
            raise AssertionError("Guest Control /ready must not probe Product Postgres")

    monkeypatch.setattr(
        guest_control_api,
        "SQLiteControlRepository",
        FakeSQLiteOperations,
    )
    monkeypatch.setattr(
        guest_control_api,
        "PostgresVitalDBReadModelRepository",
        FakePostgresVitalDB,
    )
    monkeypatch.setattr(
        guest_control_api,
        "ComposeGuestControlAdapter",
        lambda: FakeServiceControl(
            services=list(guest_control_api.DEFAULT_GUEST_SERVICE_SPECS)
        ),
    )
    monkeypatch.setattr(
        guest_control_api,
        "VitalServerVitalFileLibrary",
        lambda **inputs: (
            vital_file_library_inputs.append(inputs) or FakeVitalFileLibrary()
        ),
    )

    usecases = guest_control_api.build_default_usecases()

    assert checks == ["sqlite"]
    assert (
        vital_file_library_inputs[0]["base_url"]
        == guest_control_api.VITALSERVER_FILE_LIBRARY_BASE_URL
    )
    assert usecases.readiness()["status"] == "ready"
    assert checks == ["sqlite", "sqlite"]
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


def test_runtime_read_core_manifest_routes_dispatch_from_guest_controller(
    usecases: GuestControlUseCases,
) -> None:
    repository_root = Path(__file__).resolve().parents[3]
    manifest = json.loads(
        (repository_root / "docs/runtime/runtime-v2-route-manifest.json").read_text(
            encoding="utf-8"
        )
    )
    routes = manifest["routes"]
    assert isinstance(routes, list)

    manifest_routes: list[tuple[str, str]] = []
    documents: dict[str, dict[str, object]] = {}
    for route in routes:
        assert isinstance(route, dict)
        if (
            route["owner"] != "runtime-controller"
            or route["delivery"] != "forwarded"
            or route["conformance"] != "required-read"
        ):
            continue
        method = str(route["method"])
        path = str(route["path"])
        manifest_routes.append((method, path))
        status, document = route_request(
            method=method,
            path=path,
            usecases=usecases,
        )
        assert status == HTTPStatus.OK
        documents[path] = document

    assert tuple(manifest_routes) == guest_control_api.RUNTIME_V2_READ_CORE_ROUTES
    report = RuntimeV2ConformanceSuite(lambda path: documents[path]).run(
        platform=False,
        runtime=True,
    )
    assert report.passed, report.issues


def test_redis_relay_status_owner_handler_exposes_only_its_mutation(
    usecases: GuestControlUseCases,
) -> None:
    allowed_routes = frozenset(
        {("PUT", guest_control_api.REDIS_RELAY_STATUS_OWNER_PATH)}
    )
    accepted_status, accepted = handle_with_test_handler(
        method="PUT",
        path=guest_control_api.REDIS_RELAY_STATUS_OWNER_PATH,
        body=json.dumps(redis_relay_status_document()).encode("utf-8"),
        usecases=usecases,
        allowed_routes=allowed_routes,
    )
    denied_status, denied = handle_with_test_handler(
        method="GET",
        path="/health",
        body=b"",
        usecases=usecases,
        allowed_routes=allowed_routes,
    )

    assert accepted_status == HTTPStatus.OK
    assert accepted["readState"] == "loaded"
    assert denied_status == HTTPStatus.NOT_FOUND
    assert denied == {
        "code": "statusOwnerRouteNotFound",
        "detail": "The status owner transport does not serve this route.",
    }


def test_redis_relay_status_owner_socket_publishes_to_guest_control_owner(
    usecases: GuestControlUseCases,
) -> None:
    socket_path = Path("/tmp") / f"vitalserver-guest-control-{uuid4().hex}.sock"
    server = guest_control_api.create_redis_relay_status_owner_server(
        socket_path=socket_path,
        usecases=usecases,
    )
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        assert stat.S_IMODE(socket_path.stat().st_mode) == 0o600
        document = redis_relay_status_document()
        result = GuestControlStatusOwnerPublisher(
            owner_socket_path=socket_path,
            timeout_seconds=1,
        ).publish(document)
        status, snapshot = route_request(
            method="GET",
            path=guest_control_api.REDIS_RELAY_STATUS_OWNER_PATH,
            usecases=usecases,
        )

        assert result.published is True
        assert status == HTTPStatus.OK
        assert snapshot == {
            "readState": "loaded",
            "document": document,
            "readError": None,
        }
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)
        socket_path.unlink(missing_ok=True)


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
    ]


def test_ready_route_reports_control_store_dependency_failure() -> None:
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
                "kind": "controlStoreSchemaMismatch",
                "message": "control SQLite schema is not at the required revision",
            }
        ],
    }


def test_ready_route_does_not_probe_configured_vitaldb() -> None:
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

    status, document = route_request(
        method="GET",
        path="/ready",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "status": "ready",
        "dependencies": [
            {
                "name": "operationRepository",
                "role": "required",
                "state": "ready",
                "kind": None,
                "message": None,
            }
        ],
    }


def test_list_services_route_returns_services(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/services",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {"services": ["app", "redis"]}


def test_capabilities_route_advertises_vitaldb_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/capabilities",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert "vitaldb:observations:latest" in document["capabilities"]
    assert "maintenance:redis-backup:create" in document["capabilities"]
    assert "maintenance:redis-restore:create" in document["capabilities"]
    assert "maintenance:postgres-backup:create" in document["capabilities"]
    assert "maintenance:postgres-restore:create" in document["capabilities"]
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
    assert (
        "vitaldb:recorders:observability-expectation:apply"
        in document["capabilities"]
    )
    assert "lab:beds" in document["capabilities"]
    assert "lab:recorders" in document["capabilities"]


def test_capabilities_route_omits_unconfigured_adapter_capabilities() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = route_request(
        method="GET",
        path="/runtime/capabilities",
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
        path="/runtime/stack",
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
        path="/runtime/services/app/restart",
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
        path="/runtime/services/app/spec",
        body=json.dumps({"desiredState": "stopped"}).encode("utf-8"),
        usecases=usecases,
    )
    reconcile_status, reconcile_document = route_request(
        method="POST",
        path="/runtime/services/app/reconcile",
        usecases=usecases,
    )
    resource_status, resource_document = route_request(
        method="GET",
        path="/runtime/services/app/resource",
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
        path="/runtime/services/app/observe",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["service"] == "app"
    assert document["spec"]["state"] == "missing"
    assert document["spec"]["desiredState"] is None
    assert document["status"]["state"] == "loaded"
    assert document["status"]["observedState"] == "running"
    assert document["conditions"][0]["reason"] == "SpecMissing"


def test_guest_service_spec_invalid_request_returns_bad_request() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = handle_with_test_handler(
        method="PUT",
        path="/runtime/services/app/spec",
        body=json.dumps({"desiredState": "paused"}).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.BAD_REQUEST
    assert document == {
        "code": "guestServiceSpecInvalid",
        "detail": "guest service desiredState must be running or stopped",
    }


def test_guest_service_unknown_service_returns_not_found() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(services=["app"]),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = handle_with_test_handler(
        method="GET",
        path="/runtime/services/redis/resource",
        body=b"",
        usecases=usecases,
    )

    assert status == HTTPStatus.NOT_FOUND
    assert document == {
        "availableServices": ["app"],
        "code": "serviceNotFound",
        "detail": "compose service is not available: redis",
    }


def test_active_control_lease_conflict_returns_explicit_conflict() -> None:
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
                "a Guest Control operation already owns the command lease: "
                "resource=guest-control operationId=op_existing",
                kind="operationLeaseConflict",
            )

    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=LeaseConflictOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = handle_with_test_handler(
        method="POST",
        path="/runtime/services/app/restart",
        body=b"",
        usecases=usecases,
    )

    assert status == HTTPStatus.CONFLICT
    assert document == {
        "code": "operationInProgress",
        "detail": (
            "a Guest Control operation already owns the command lease: "
            "resource=guest-control operationId=op_existing"
        ),
    }


def test_restart_route_preserves_failed_operation_document() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(fail_command="restart"),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = route_request(
        method="POST",
        path="/runtime/services/app/restart",
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
        path="/runtime/services/app/start",
        usecases=usecases,
    )
    _, stop_document = route_request(
        method="POST",
        path="/runtime/services/app/stop",
        usecases=usecases,
    )
    _, restart_document = route_request(
        method="POST",
        path="/runtime/services/app/restart",
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
        path="/runtime/stack/reconcile",
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
        path="/runtime/maintenance/redis-backup",
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


def test_postgres_backup_route_returns_operation_with_database_proof(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/runtime/maintenance/postgres-backup",
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_postgres-backup_postgres-backup_1"
    assert document["service"] == "postgres-backup"
    assert document["command"] == "postgres-backup"
    assert document["state"] == "completed"
    assert document["result"] == {
        "archive": "/mnt/tirosh/backups/postgres/postgres-20260701.tar.gz",
        "alembicRevision": "0002_observability_expectations",
    }


def test_postgres_restore_route_returns_operation_with_database_proof(
    usecases: GuestControlUseCases,
) -> None:
    archive = "/mnt/tirosh/backups/postgres/postgres-20260701.tar.gz"
    status, document = route_request(
        method="POST",
        path="/runtime/maintenance/postgres-restore",
        body=json.dumps(
            {
                "archive": archive,
                "restartRuntime": False,
            }
        ).encode(),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["operationId"] == "op_postgres-restore_postgres-restore_1"
    assert document["service"] == "postgres-restore"
    assert document["command"] == "postgres-restore"
    assert document["state"] == "completed"
    assert document["result"] == {
        "restoredArchive": archive,
        "alembicRevision": "0002_observability_expectations",
        "runtimeRestarted": False,
    }


def test_postgres_restore_route_requires_explicit_restart_runtime(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="POST",
            path="/runtime/maintenance/postgres-restore",
            body=json.dumps(
                {
                    "archive": (
                        "/mnt/tirosh/backups/postgres/postgres-20260701.tar.gz"
                    )
                }
            ).encode(),
            usecases=usecases,
        )

    assert error.value.status == HTTPStatus.BAD_REQUEST
    assert error.value.code == "requestFieldInvalid"


def test_redis_restore_route_returns_operation_with_restored_archive_result(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/runtime/maintenance/redis-restore",
        body=json.dumps(
            {
                "archive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz",
            }
        ).encode("utf-8"),
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
        path="/runtime/maintenance/datastore/repair",
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
        path="/runtime/maintenance/update-activation",
        body=json.dumps(
            {
                "requestId": "update-activation-request-1",
                "version": "0.2.0",
            }
        ).encode("utf-8"),
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
            path="/runtime/maintenance/update-activation",
            body=json.dumps({"version": "0.2.0"}).encode("utf-8"),
            usecases=usecases,
        )

    assert "JSON request field is required: requestId" in str(error.value)


def test_update_shutdown_route_returns_operation_with_ready_result(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/runtime/maintenance/update-shutdown",
        body=json.dumps(
            {
                "requestId": "update-shutdown-request-1",
                "version": "0.2.0",
            }
        ).encode("utf-8"),
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
        "postgresBackupPath": "/mnt/tirosh/backups/postgres/update.tar.gz",
    }


def test_update_shutdown_route_rejects_missing_version(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(Exception) as error:
        route_request(
            method="POST",
            path="/runtime/maintenance/update-shutdown",
            body=json.dumps({"requestId": "update-shutdown-request-1"}).encode("utf-8"),
            usecases=usecases,
        )

    assert "JSON request field is required: version" in str(error.value)


def test_guest_poweroff_route_returns_operation_document(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/runtime/maintenance/guest-poweroff",
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
        path="/runtime/maintenance/redis-backup",
        usecases=usecases,
    )

    status, document = route_request(
        method="GET",
        path=f"/runtime/operations/{operation_document['operationId']}",
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
        path="/runtime/lab/scenarios",
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


def test_lab_vital_files_route_returns_vitalserver_index_catalog(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/lab/vital-files",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["vitalFiles"][0]["relativePath"] == (
        "MORA04/202607/260701/MORA04_260701_000000.vital"
    )
    assert document["vitalFiles"][0]["guestPath"] == (
        "/mnt/tirosh-vital-files/MORA04/202607/260701/MORA04_260701_000000.vital"
    )


def test_lab_read_model_routes_return_product_lab_contract(
    usecases: GuestControlUseCases,
) -> None:
    bed_status, beds = route_request(
        method="GET",
        path="/runtime/lab/beds",
        usecases=usecases,
    )
    recorder_status, recorders = route_request(
        method="GET",
        path="/runtime/lab/recorders",
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
        path="/runtime/lab/beds/create",
        body=json.dumps({"roomNames": ["OR-A"]}).encode("utf-8"),
        usecases=usecases,
    )
    delete_status, deleted = route_request(
        method="POST",
        path="/runtime/lab/recorders/delete",
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
        path="/runtime/lab/sessions",
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
        path="/runtime/lab/sessions/lab-session-1",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["operationId"] is None
    assert document["session"]["sessionId"] == "lab-session-1"
    assert document["session"]["state"] == "accepted"


def test_lab_list_sessions_route_returns_explicit_session_collection(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/lab/sessions",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["readError"] is None
    assert document["sessions"][0]["sessionId"] == "lab-session-1"
    assert document["sessions"][0]["state"] == "running"


def test_recorder_ingress_status_route_returns_explicit_status_read(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/recorder-ingress/status",
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


def test_redis_relay_status_route_returns_explicit_status_read(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/redis-relay/status",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["readState"] == "loaded"
    assert document["document"]["state"] == "running"
    assert document["document"]["totals"]["copied"] == 8
    assert document["readError"] is None


def test_redis_relay_status_route_persists_owner_snapshot() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_relay=operations,
    )
    body = json.dumps(redis_relay_status_document()).encode("utf-8")

    put_status, put_document = route_request(
        method="PUT",
        path="/runtime/redis-relay/status",
        body=body,
        usecases=usecases,
    )
    get_status, get_document = route_request(
        method="GET",
        path="/runtime/redis-relay/status",
        usecases=usecases,
    )

    assert put_status == HTTPStatus.OK
    assert put_document["readState"] == "loaded"
    assert put_document["document"]["state"] == "running"
    assert get_status == HTTPStatus.OK
    assert get_document["document"] == put_document["document"]


def test_redis_relay_status_route_rejects_incomplete_owner_snapshot() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        redis_relay=operations,
    )
    document = redis_relay_status_document()
    document.pop("targetUrl")

    status, response = handle_with_test_handler(
        method="PUT",
        path="/runtime/redis-relay/status",
        body=json.dumps(document).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.BAD_REQUEST
    assert response == {
        "code": "redisRelayStatusInvalid",
        "detail": "Redis relay status document is missing targetUrl.",
    }
    assert operations.redis_relay_status is None


def test_lab_session_command_routes_return_explicit_session_state(
    usecases: GuestControlUseCases,
) -> None:
    _, started = route_request(
        method="POST",
        path="/runtime/lab/sessions/lab-session-1/start",
        usecases=usecases,
    )
    _, stopped = route_request(
        method="POST",
        path="/runtime/lab/sessions/lab-session-1/stop",
        usecases=usecases,
    )
    _, finished = route_request(
        method="POST",
        path="/runtime/lab/sessions/lab-session-1/finish",
        usecases=usecases,
    )

    assert started["session"]["state"] == "running"
    assert started["labOperationId"] == "lab-session-start-lab-session-1"
    assert stopped["session"]["state"] == "stopped"
    assert stopped["labOperationId"] == "lab-session-stop-lab-session-1"
    assert finished["session"]["state"] == "finished"
    assert finished["labOperationId"] == "lab-session-finish-lab-session-1"


def test_lab_recorder_command_routes_return_explicit_recorder_state(
    usecases: GuestControlUseCases,
) -> None:
    _, stopped = route_request(
        method="POST",
        path=(
            "/runtime/lab/sessions/lab-session-1/recorders/"
            "lab-session-1-recorder-1/stop"
        ),
        usecases=usecases,
    )
    _, started = route_request(
        method="POST",
        path=(
            "/runtime/lab/sessions/lab-session-1/recorders/"
            "lab-session-1-recorder-1/start"
        ),
        usecases=usecases,
    )

    assert stopped["state"] == "loaded"
    assert stopped["operationId"] == "op_product-lab_lab-stop-recorder_1"
    assert stopped["labOperationId"] == ("lab-recorder-stop-lab-session-1-recorder-1")
    assert stopped["recorder"]["state"] == "stopped"
    assert started["state"] == "loaded"
    assert started["operationId"] == "op_product-lab_lab-start-recorder_1"
    assert started["recorder"]["state"] == "running"


def test_lab_replay_vital_file_route_uses_explicit_request_body(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="POST",
        path="/runtime/lab/vital-files/replay",
        body=json.dumps(
            {
                "vitalFileRelativePath": "sample.vital",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            }
        ).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert document["state"] == "loaded"
    assert document["labOperationId"] == "lab-vital-file-replay-lab-replay-1"
    assert document["session"]["sessionId"] == "lab-replay-1"
    assert document["session"]["name"] == "sample.vital"


def test_lab_upload_vital_files_route_accepts_multiple_multipart_files(
    usecases: GuestControlUseCases,
) -> None:
    boundary = "vital-files-boundary"
    body = (
        (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="files"; filename="first.vital"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).encode()
        + b"first-content\r\n"
        + (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="files"; filename="second.vital"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).encode()
        + b"second-content\r\n"
        + f"--{boundary}--\r\n".encode()
    )

    status, document = route_request(
        method="POST",
        path="/runtime/lab/vital-files/upload",
        body=body,
        headers={"content-type": f"multipart/form-data; boundary={boundary}"},
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "state": "completed",
        "files": [
            {"fileName": "first.vital", "relativePath": "first.vital", "sizeBytes": 13},
            {
                "fileName": "second.vital",
                "relativePath": "second.vital",
                "sizeBytes": 14,
            },
        ],
        "failedFiles": [],
    }


def test_lab_upload_handler_stages_large_request_with_bounded_reads(
    tmp_path: Path,
) -> None:
    boundary = "bounded-vital-files-boundary"
    content = b"v" * (3 * 1024 * 1024)
    body = multipart_upload_body(
        [("OR-A_260721_120000.vital", content)],
        boundary=boundary,
    )
    request_stream = TrackingRequestStream(body)
    staging_root = tmp_path / "uploads"
    staging_root.mkdir()
    vital_file_library = FakeVitalFileLibrary()
    upload_usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vital_file_library=vital_file_library,
    )

    status, document = handle_with_test_handler(
        method="POST",
        path="/runtime/lab/vital-files/upload",
        body=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        request_stream=request_stream,
        upload_staging_root=staging_root,
        usecases=upload_usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "completed"
    assert document["files"] == [
        {
            "fileName": "OR-A_260721_120000.vital",
            "relativePath": "OR-A_260721_120000.vital",
            "sizeBytes": len(content),
        }
    ]
    assert vital_file_library.imported == [[("OR-A_260721_120000.vital", content)]]
    assert max(request_stream.requested_read_sizes) <= 64 * 1024
    assert list(staging_root.iterdir()) == []


def test_lab_upload_handler_reports_truncated_request_and_cleans_staging(
    tmp_path: Path,
) -> None:
    boundary = "truncated-vital-files-boundary"
    body = multipart_upload_body(
        [("OR-A_260721_120000.vital", b"content")],
        boundary=boundary,
    )
    staging_root = tmp_path / "uploads"
    staging_root.mkdir()
    vital_file_library = FakeVitalFileLibrary()
    upload_usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        vital_file_library=vital_file_library,
    )

    status, document = handle_with_test_handler(
        method="POST",
        path="/runtime/lab/vital-files/upload",
        body=body,
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body) + 17),
        },
        upload_staging_root=staging_root,
        usecases=upload_usecases,
    )

    assert status == HTTPStatus.BAD_REQUEST
    assert document["code"] == "truncatedUpload"
    assert vital_file_library.imported == []
    assert list(staging_root.iterdir()) == []


def test_lab_upload_handler_requires_explicit_content_length(
    usecases: GuestControlUseCases,
) -> None:
    status, document = handle_with_test_handler(
        method="POST",
        path="/runtime/lab/vital-files/upload",
        body=b"",
        headers={"Content-Type": "multipart/form-data; boundary=missing-length"},
        include_content_length=False,
        usecases=usecases,
    )

    assert status == HTTPStatus.BAD_REQUEST
    assert document == {
        "code": "vitalFileUploadInvalid",
        "detail": "Vital Files upload requires a Content-Length header.",
    }


def test_lab_upload_handler_reports_unavailable_staging_storage(
    tmp_path: Path,
    usecases: GuestControlUseCases,
) -> None:
    boundary = "unavailable-staging-boundary"
    body = multipart_upload_body(
        [("OR-A_260721_120000.vital", b"content")],
        boundary=boundary,
    )

    status, document = handle_with_test_handler(
        method="POST",
        path="/runtime/lab/vital-files/upload",
        body=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        upload_staging_root=tmp_path / "missing",
        usecases=usecases,
    )

    assert status == HTTPStatus.SERVICE_UNAVAILABLE
    assert document["code"] == "vitalFileUploadStagingFailed"


def test_latest_vitaldb_observation_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/observations/latest",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["observation"]["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert document["readError"] is None


def test_runtime_events_route_reads_runtime_owned_operation_history(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/events",
        query={
            "limit": ["25"],
            "type": ["operation-completed"],
            "since": ["2026-07-01T00:00:00Z"],
        },
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["events"][0]["source"] == "runtime-controller"
    assert document["events"][0]["operationState"] == "completed"


def test_runtime_events_route_uses_public_default_limit() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, _ = route_request(
        method="GET",
        path="/runtime/events",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert operations.event_queries == [
        {
            "limit": 100,
            "event_type": None,
            "since": None,
            "cursor": None,
        }
    ]


def test_runtime_events_route_rejects_invalid_query(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="GET",
            path="/runtime/events",
            query={"limit": ["0"]},
            usecases=usecases,
        )

    assert error.value.status == HTTPStatus.BAD_REQUEST
    assert error.value.code == "queryParameterInvalid"


def test_runtime_events_route_rejects_timezone_less_since_timestamp(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="GET",
            path="/runtime/events",
            query={"since": ["2026-07-01T00:00:00"]},
            usecases=usecases,
        )

    assert error.value.status == HTTPStatus.BAD_REQUEST
    assert error.value.code == "queryParameterInvalid"


def test_runtime_events_handler_preserves_guest_ledger_cursor_rejection() -> None:
    class CursorRejectingOperations(FakeOperations):
        def query_events(self, **query: object) -> dict[str, object]:
            assert query["cursor"] == "guest-ledger-token"
            raise GuestControlDependencyError(
                "runtime event history cursor is invalid",
                kind="runtimeEventCursorInvalid",
            )

    operations = CursorRejectingOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, document = handle_with_test_handler(
        method="GET",
        path="/runtime/events?cursor=guest-ledger-token",
        body=b"",
        usecases=usecases,
    )

    assert status == HTTPStatus.BAD_REQUEST
    assert document == {
        "code": "queryParameterInvalid",
        "detail": "runtime event history cursor is invalid",
    }


def test_runtime_events_handler_decodes_percent_encoded_offset_and_cursor() -> None:
    operations = FakeOperations()
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=operations,
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
    )

    status, _ = handle_with_test_handler(
        method="GET",
        path=(
            "/runtime/events?since=2026-07-01T09%3A00%3A00%2B09%3A00"
            "&cursor=guest%2Bledger%2Ftoken%3Dv2"
        ),
        body=b"",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert operations.event_queries == [
        {
            "limit": 100,
            "event_type": None,
            "since": datetime(2026, 7, 1, tzinfo=UTC),
            "cursor": "guest+ledger/token=v2",
        }
    ]


@pytest.mark.parametrize("event_type", ["accepted", "operation-unknown"])
def test_runtime_events_route_rejects_unknown_public_event_type(
    usecases: GuestControlUseCases,
    event_type: str,
) -> None:
    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="GET",
            path="/runtime/events",
            query={"type": [event_type]},
            usecases=usecases,
        )

    assert error.value.status == HTTPStatus.BAD_REQUEST
    assert error.value.code == "queryParameterInvalid"


def test_runtime_events_route_normalizes_offset_since_timestamp(
    usecases: GuestControlUseCases,
) -> None:
    status, _ = route_request(
        method="GET",
        path="/runtime/events",
        query={"since": ["2026-07-01T09:00:00+09:00"]},
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert guest_control_api._optional_query_datetime(
        {"since": ["2026-07-01T09:00:00+09:00"]},
        "since",
    ) == datetime(2026, 7, 1, tzinfo=UTC)


def test_runtime_settings_routes_read_apply_and_reconcile(
    usecases: GuestControlUseCases,
) -> None:
    status, read = route_request(
        method="GET",
        path="/runtime/settings",
        usecases=usecases,
    )
    settings = dict(read["settings"])
    settings["publicPort"] = 8080

    applied_status, operation = route_request(
        method="PUT",
        path="/runtime/settings",
        body=json.dumps({"settings": settings}).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert read["state"] == "loaded"
    assert applied_status == HTTPStatus.ACCEPTED
    assert operation["state"] == "completed"
    assert operation["command"] == "apply-settings"


def test_runtime_settings_route_rejects_incomplete_contract(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="PUT",
            path="/runtime/settings",
            body=b'{"settings": {}}',
            usecases=usecases,
        )

    assert error.value.status == HTTPStatus.BAD_REQUEST
    assert error.value.code == "runtimeSettingsInvalid"


def test_runtime_admin_password_route_applies_without_returning_secret(
    usecases: GuestControlUseCases,
) -> None:
    status, operation = route_request(
        method="POST",
        path="/runtime/admin-password",
        body=json.dumps({"password": "new-admin-secret"}).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.ACCEPTED
    assert operation["state"] == "completed"
    assert operation["service"] == "runtime-admin"
    assert operation["command"] == "apply-admin-password"
    assert "new-admin-secret" not in json.dumps(operation)


def test_runtime_admin_password_route_rejects_newline(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="POST",
            path="/runtime/admin-password",
            body=json.dumps({"password": "invalid\nsecret"}).encode("utf-8"),
            usecases=usecases,
        )

    assert error.value.status == HTTPStatus.BAD_REQUEST
    assert error.value.code == "runtimeAdminPasswordInvalid"


def test_redis_relay_settings_routes_read_apply_and_do_not_return_secret(
    usecases: GuestControlUseCases,
) -> None:
    status, read = route_request(
        method="GET", path="/runtime/redis-relay/settings", usecases=usecases
    )
    assert status == HTTPStatus.OK
    assert read["state"] == "loaded"
    assert "password" not in read["settings"]["target"]

    request = {
        "enabled": True,
        "target": {
            "url": "redis://relay.example:6379/1",
            "username": "relay",
            "password": "private-secret",
            "clearPassword": False,
            "tls": True,
        },
        "scope": "waveform_trend_only",
        "includeRecorderNetworkContext": True,
        "intervalSeconds": 0.5,
        "scanCount": 250,
    }
    status, operation = route_request(
        method="PUT",
        path="/runtime/redis-relay/settings",
        body=json.dumps(request).encode("utf-8"),
        usecases=usecases,
    )
    assert status == HTTPStatus.ACCEPTED
    assert operation["command"] == "apply-redis-relay-settings"
    assert operation["state"] == "completed"
    assert "private-secret" not in json.dumps(operation)


def test_latest_vitaldb_observation_route_reports_unavailable_without_adapter() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/observations/latest",
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
        path="/runtime/vitaldb/recorders",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["recorders"][0]["vrcode"] == "VR-001"
    assert document["recorders"][0]["visibility"] == "visible"
    assert document["recorders"][0]["observability"]["supportState"] == "supported"
    assert document["recorders"][0]["observability"]["reportState"] == "current"
    assert document["observedAt"] == "2026-07-01T00:00:00+00:00"
    assert document["readError"] is None


def test_vitaldb_recorder_observability_route_preserves_support_axes(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/recorders/VR-001/observability",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["support"]["state"] == "supported"
    assert document["report"]["state"] == "current"
    assert "resources" not in document


def test_vitaldb_recorders_visibility_routes_require_hidden_before_delete(
    usecases: GuestControlUseCases,
) -> None:
    _, delete_without_hide = route_request(
        method="POST",
        path="/runtime/vitaldb/recorders/delete",
        body=json.dumps({"vrcodes": ["VR-001"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, hidden = route_request(
        method="POST",
        path="/runtime/vitaldb/recorders/hide",
        body=json.dumps({"vrcodes": ["VR-001"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, deleted = route_request(
        method="POST",
        path="/runtime/vitaldb/recorders/delete",
        body=json.dumps({"vrcodes": ["VR-001"]}).encode("utf-8"),
        usecases=usecases,
    )

    assert delete_without_hide["readError"] == (
        "VitalDB entity must be hidden before delete: VR-001"
    )
    assert hidden["recorders"][0]["visibility"] == "hidden"
    assert deleted["recorders"] == []


def test_vitaldb_recorder_detail_distinguishes_loaded_and_missing(
    usecases: GuestControlUseCases,
) -> None:
    status, recorder = route_request(
        method="GET",
        path="/runtime/vitaldb/recorders/VR-001",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert recorder["vrcode"] == "VR-001"

    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="GET",
            path="/runtime/vitaldb/recorders/VR-missing",
            usecases=usecases,
        )
    assert error.value.status == HTTPStatus.NOT_FOUND
    assert error.value.code == "vitalDBRecorderNotFound"


def test_vitaldb_recorder_vital_files_route_resolves_explicit_bed_assignment(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/recorders/VR-001/vital-files",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["vrcode"] == "VR-001"
    assert document["files"][0]["origin"] == "nativeRecorderUpload"
    assert document["files"][0]["attribution"]["state"] == ("bedAssignmentResolved")


def test_vitaldb_recorders_route_reports_unavailable_without_adapter() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/recorders",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "readFailed"
    assert document["recorders"] == []
    assert document["updatedAt"] is None
    assert document["readError"] == (
        "VitalDB recorder read model adapter is unavailable."
    )


def test_vitaldb_recorder_detail_reports_read_model_failure_as_unavailable() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = handle_with_test_handler(
        method="GET",
        path="/runtime/vitaldb/recorders/VR-001",
        body=b"",
        usecases=usecases,
    )

    assert status == HTTPStatus.SERVICE_UNAVAILABLE
    assert document == {
        "code": "vitaldb-read-model-unavailable",
        "detail": "VitalDB read model adapter is unavailable.",
    }


def test_vitaldb_recorder_activity_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/recorders/VR-001/activity",
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
        path="/runtime/vitaldb/beds",
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
        path="/runtime/vitaldb/beds/delete",
        body=json.dumps({"bedIDs": ["bed-a"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, hidden = route_request(
        method="POST",
        path="/runtime/vitaldb/beds/hide",
        body=json.dumps({"bedIDs": ["bed-a"]}).encode("utf-8"),
        usecases=usecases,
    )
    _, deleted = route_request(
        method="POST",
        path="/runtime/vitaldb/beds/delete",
        body=json.dumps({"bedIDs": ["bed-a"]}).encode("utf-8"),
        usecases=usecases,
    )

    assert delete_without_hide["readError"] == (
        "VitalDB entity must be hidden before delete: bed-a"
    )
    assert hidden["beds"][0]["visibility"] == "hidden"
    assert deleted["beds"] == []


def test_vitaldb_bed_detail_distinguishes_loaded_and_missing(
    usecases: GuestControlUseCases,
) -> None:
    status, bed = route_request(
        method="GET",
        path="/runtime/vitaldb/beds/bed-a",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert bed["bedID"] == "bed-a"

    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="GET",
            path="/runtime/vitaldb/beds/bed-missing",
            usecases=usecases,
        )
    assert error.value.status == HTTPStatus.NOT_FOUND
    assert error.value.code == "vitalDBBedNotFound"


def test_vitaldb_beds_route_reports_unavailable_without_adapter() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/beds",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "readFailed"
    assert document["beds"] == []
    assert document["updatedAt"] is None
    assert document["readError"] == "VitalDB bed read model adapter is unavailable."


def test_vitaldb_relationships_route_returns_product_read_model(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/relationships",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["state"] == "loaded"
    assert document["assignments"][0]["assignmentID"] == "assignment-1"
    assert document["events"] == []
    assert document["eventTotalCount"] == 0
    assert document["eventLimit"] == 100
    assert document["readError"] is None


def test_vitaldb_relationships_route_passes_explicit_event_limit(
    usecases: GuestControlUseCases,
) -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/relationships",
        query={"eventLimit": ["7"]},
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document["eventLimit"] == 7


def test_vitaldb_relationships_route_reports_unavailable_without_adapter() -> None:
    usecases = build_usecases(
        service_control=FakeServiceControl(),
        operations=FakeOperations(),
        operation_ids=FakeOperationIds(),
        clock=FakeClock(),
        product_lab=FakeProductLab(),
    )

    status, document = route_request(
        method="GET",
        path="/runtime/vitaldb/relationships",
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert document == {
        "state": "unavailable",
        "assignments": [],
        "events": [],
        "eventTotalCount": 0,
        "eventLimit": 100,
        "readError": "VitalDB relationship read model adapter is unavailable.",
    }


def test_lab_post_route_rejects_missing_json_body(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(Exception) as error:
        route_request(
            method="POST",
            path="/runtime/lab/sessions",
            usecases=usecases,
        )

    assert "JSON request body is required" in str(error.value)


def test_recorder_expectation_route_forwards_command(
    usecases: GuestControlUseCases,
) -> None:
    command = {
        "commandId": "command-001",
        "vrcode": "VR-001",
        "expectedRevision": 0,
        "action": "clear",
    }

    status, receipt = route_request(
        method="POST",
        path=(
            "/runtime/vitaldb/recorders/VR-001/"
            "observability/expectation"
        ),
        body=json.dumps(command).encode("utf-8"),
        usecases=usecases,
    )

    assert status == HTTPStatus.OK
    assert receipt["state"] == "accepted"
    assert receipt["commandId"] == "command-001"


def test_recorder_expectation_route_rejects_vrcode_mismatch(
    usecases: GuestControlUseCases,
) -> None:
    with pytest.raises(guest_control_api.GuestControlAPIError) as error:
        route_request(
            method="POST",
            path=(
                "/runtime/vitaldb/recorders/VR-001/"
                "observability/expectation"
            ),
            body=json.dumps(
                {
                    "commandId": "command-001",
                    "vrcode": "VR-002",
                    "expectedRevision": 0,
                    "action": "clear",
                }
            ).encode("utf-8"),
            usecases=usecases,
        )

    assert error.value.status == HTTPStatus.BAD_REQUEST
    assert error.value.code == "recorderExpectationVrcodeMismatch"


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
