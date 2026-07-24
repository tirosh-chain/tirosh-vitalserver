from __future__ import annotations

from collections.abc import Callable
from datetime import datetime

from tirosh_guest_tools.application.guest_control.ports import (
    Clock,
    DatastoreRepairPort,
    GuestServiceResourceRepository,
    OperationIdFactory,
    OperationRepository,
    PostgresBackupPort,
    ProductLabPort,
    RecorderIngressReadModelPort,
    RecorderRecoveryReadModelPort,
    RedisBackupPort,
    RedisRelayReadModelPort,
    RedisRelaySettingsPort,
    RuntimeAdminPort,
    RuntimeSettingsPort,
    ServiceControlPort,
    ServiceStatusSnapshotRepository,
    UpdateActivationPort,
    UpdateShutdownPort,
    VitalDBReadModelPort,
    VitalFileLibraryPort,
    VitalFileUploadSource,
)
from tirosh_guest_tools.domain.guest_control.models import (
    GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY,
    DatastoreRepairDependencyError,
    GuestControlDependencyError,
    GuestServiceCondition,
    GuestServiceDesiredState,
    GuestServiceObservedState,
    GuestServiceResource,
    GuestServiceSpec,
    GuestServiceSpecState,
    GuestServiceStatusRead,
    OperationFailure,
    OperationLease,
    PostgresBackupDependencyError,
    PostgresRestoreDependencyError,
    ProductLabDependencyError,
    ProductLabReadModelResult,
    ProductLabRecorderResult,
    ProductLabSessionResult,
    RecorderIngressDependencyError,
    RecorderRecoveryDependencyError,
    RedisBackupDependencyError,
    RedisRelayDependencyError,
    RedisRestoreDependencyError,
    ServiceCommand,
    ServiceNotFoundError,
    ServiceOperation,
    ServiceStatus,
    StackStatus,
    UpdateActivationDependencyError,
    UpdateShutdownDependencyError,
    UpdateShutdownResult,
    VitalDBReadModelDependencyError,
    validate_redis_relay_status_document,
)
from tirosh_guest_tools.domain.guest_control.operation_policy import (
    accept_service_operation,
    fail_operation,
    finish_operation,
    interrupt_operation,
    start_operation,
)
from tirosh_guest_tools.domain.guest_control.service_reconcile_policy import (
    GuestServiceReconcileEffect,
    reconcile_guest_service,
)
from tirosh_guest_tools.domain.recorder_vital_files import (
    RecorderVitalFileProjectionError,
    native_uploads_for_recorder,
    recovery_artifacts_for_recorder,
)
from tirosh_guest_tools.domain.vitaldb_deletion import (
    VitalDBDeletionPolicyError,
    plan_bed_deletion,
    plan_recorder_deletion,
)
from tirosh_guest_tools.domain.vitaldb_history import (
    attach_recorder_ingress_status,
    attach_recorder_observability,
)


class GuestControlUseCases:
    def __init__(
        self,
        *,
        service_control: ServiceControlPort,
        operations: OperationRepository,
        service_status_snapshots: ServiceStatusSnapshotRepository,
        guest_service_resources: GuestServiceResourceRepository,
        operation_ids: OperationIdFactory,
        clock: Clock,
        product_lab: ProductLabPort | None = None,
        vitaldb_read_model: VitalDBReadModelPort | None = None,
        recorder_ingress: RecorderIngressReadModelPort | None = None,
        recorder_recovery: RecorderRecoveryReadModelPort | None = None,
        redis_relay: RedisRelayReadModelPort | None = None,
        runtime_settings: RuntimeSettingsPort | None = None,
        runtime_admin: RuntimeAdminPort | None = None,
        redis_relay_settings: RedisRelaySettingsPort | None = None,
        redis_backup: RedisBackupPort | None = None,
        postgres_backup: PostgresBackupPort | None = None,
        datastore_repair: DatastoreRepairPort | None = None,
        update_activation: UpdateActivationPort | None = None,
        update_shutdown: UpdateShutdownPort | None = None,
        vital_file_library: VitalFileLibraryPort | None = None,
    ) -> None:
        self._service_control = service_control
        self._product_lab = product_lab
        self._vitaldb_read_model = vitaldb_read_model
        self._recorder_ingress = recorder_ingress
        self._recorder_recovery = recorder_recovery
        self._redis_relay = redis_relay
        self._runtime_settings = runtime_settings
        self._runtime_admin = runtime_admin
        self._redis_relay_settings = redis_relay_settings
        self._redis_backup = redis_backup
        self._postgres_backup = postgres_backup
        self._datastore_repair = datastore_repair
        self._update_activation = update_activation
        self._update_shutdown = update_shutdown
        self._vital_file_library = vital_file_library
        self._operations = operations
        self._service_status_snapshots = service_status_snapshots
        self._guest_service_resources = guest_service_resources
        self._operation_ids = operation_ids
        self._clock = clock

    def recover_interrupted_operations(self) -> None:
        for operation in self._operations.list_unfinished_operations():
            interrupted = interrupt_operation(
                operation,
                failure=OperationFailure(
                    kind="controllerRestarted",
                    message=(
                        "Runtime Controller restarted before the operation outcome "
                        "was known."
                    ),
                ),
                now=self._clock.now(),
            )
            self._operations.record_transition(interrupted)

    def initialize_guest_service_specs(
        self,
        defaults: dict[str, GuestServiceDesiredState],
    ) -> None:
        available_services = self._service_control.list_services()
        available_service_set = set(available_services)
        for service, desired_state in defaults.items():
            if service not in available_service_set:
                raise ServiceNotFoundError(
                    service,
                    available_services=available_services,
                )
            existing = self._guest_service_resources.get_guest_service_resource(service)
            if (
                existing is not None
                and existing.spec.state == GuestServiceSpecState.CONFIGURED
            ):
                continue
            previous = existing or self._missing_guest_service_resource(service)
            spec = GuestServiceSpec.configured(
                desired_state=desired_state,
                updated_at=self._clock.now(),
            )
            initialized = GuestServiceResource(
                service=service,
                spec=spec,
                status=previous.status,
                conditions=self._guest_service_conditions(spec, previous.status),
                last_operation_id=previous.last_operation_id,
            )
            self._guest_service_resources.save_guest_service_resource(initialized)

    def capabilities(self) -> dict[str, object]:
        capabilities = [
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

        if self._product_lab is not None:
            capabilities.extend(
                [
                    "lab:scenarios",
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
                    "lab:sessions:finish",
                    "lab:vital-files:replay",
                ]
            )

        if self._vital_file_library is not None:
            capabilities.extend(
                [
                    "lab:vital-files",
                    "lab:vital-files:upload",
                ]
            )

        if self._redis_backup is not None:
            capabilities.extend(
                [
                    "maintenance:redis-backup:create",
                    "maintenance:redis-restore:create",
                ]
            )

        if self._postgres_backup is not None:
            capabilities.extend(
                [
                    "maintenance:postgres-backup:create",
                    "maintenance:postgres-restore:create",
                ]
            )

        if self._datastore_repair is not None:
            capabilities.append("maintenance:datastore-repair:create")

        if self._update_activation is not None:
            capabilities.append("maintenance:update-activation:create")

        if self._update_shutdown is not None:
            capabilities.extend(
                [
                    "maintenance:update-shutdown:create",
                    "maintenance:guest-poweroff:create",
                ]
            )

        if self._recorder_ingress is not None:
            capabilities.extend(
                [
                    "recorder-ingress:status:get",
                    "vitaldb:recorders:observability-expectation:apply",
                ]
            )
        if (
            self._recorder_ingress is not None
            and self._recorder_recovery is not None
            and self._vitaldb_read_model is not None
        ):
            capabilities.append("vitaldb:recorders:vital-files")
        if self._runtime_settings is not None:
            capabilities.extend(["settings:get", "settings:apply"])
        if self._runtime_admin is not None:
            capabilities.append("admin-password:apply")
        if self._redis_relay_settings is not None:
            capabilities.extend(
                ["redis-relay:settings:get", "redis-relay:settings:apply"]
            )

        if self._redis_relay is not None:
            capabilities.append("redis-relay:status:get")

        if self._vitaldb_read_model is not None:
            capabilities.extend(
                [
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
            )

        return {
            "schemaVersion": 1,
            "capabilities": capabilities,
        }

    def readiness(self) -> dict[str, object]:
        required_dependencies = [
            _required_readiness_dependency(
                "operationRepository",
                self._operations.check_ready,
            )
        ]

        status = (
            "ready"
            if all(
                dependency["state"] == "ready" for dependency in required_dependencies
            )
            else "unavailable"
        )
        return {
            "status": status,
            "dependencies": required_dependencies,
        }

    def list_services(self) -> list[str]:
        return self._service_control.list_services()

    def get_service_status(self, service: str) -> ServiceStatus:
        status = self._service_control.get_service_status(service)
        self._service_status_snapshots.save_service_status_snapshot(status)
        return status

    def get_guest_service_resource(self, service: str) -> dict[str, object]:
        self._ensure_guest_service_exists(service)
        return self._load_guest_service_resource(service).as_json()

    def observe_guest_service(self, service: str) -> dict[str, object]:
        self._ensure_guest_service_exists(service)
        resource = self._load_guest_service_resource(service)
        status_read = self._read_guest_service_status(service)
        if status_read.service_status is not None:
            self._service_status_snapshots.save_service_status_snapshot(
                status_read.service_status
            )
        observed = self._guest_service_resource_with_status(resource, status_read)
        self._guest_service_resources.save_guest_service_resource(observed)
        return observed.as_json()

    def update_guest_service_spec(
        self,
        service: str,
        request: dict[str, object],
    ) -> dict[str, object]:
        self._ensure_guest_service_exists(service)
        desired_state_value = request.get("desiredState")
        if not isinstance(desired_state_value, str):
            raise GuestControlDependencyError(
                "guest service desiredState is required",
                kind="guestServiceSpecInvalid",
            )
        desired_state = self._guest_service_desired_state_from_request(
            desired_state_value
        )
        spec = GuestServiceSpec.configured(
            desired_state=desired_state,
            updated_at=self._clock.now(),
        )
        resource = self._load_guest_service_resource(service)
        resource = GuestServiceResource(
            service=service,
            spec=spec,
            status=resource.status,
            conditions=resource.conditions,
            last_operation_id=resource.last_operation_id,
        )
        self._guest_service_resources.save_guest_service_resource(resource)
        return resource.as_json()

    def get_stack_status(self) -> StackStatus:
        status = self._service_control.get_stack_status()
        for service_status in status.services:
            self._service_status_snapshots.save_service_status_snapshot(service_status)
            self._sync_guest_service_resource_status(service_status)
        return status

    def get_operation(self, operation_id: str) -> ServiceOperation | None:
        return self._operations.get(operation_id)

    def start_service(self, service: str) -> ServiceOperation:
        return self._run_guest_service_reconcile_operation(
            service=service,
            command=ServiceCommand.START,
            requested_command=ServiceCommand.START,
            desired_state=GuestServiceDesiredState.RUNNING,
        )

    def stop_service(self, service: str) -> ServiceOperation:
        return self._run_guest_service_reconcile_operation(
            service=service,
            command=ServiceCommand.STOP,
            requested_command=ServiceCommand.STOP,
            desired_state=GuestServiceDesiredState.STOPPED,
        )

    def restart_service(self, service: str) -> ServiceOperation:
        return self._run_guest_service_reconcile_operation(
            service=service,
            command=ServiceCommand.RESTART,
            requested_command=ServiceCommand.RESTART,
            desired_state=GuestServiceDesiredState.RUNNING,
        )

    def reconcile_guest_service(self, service: str) -> ServiceOperation:
        return self._run_guest_service_reconcile_operation(
            service=service,
            command=ServiceCommand.RECONCILE,
            requested_command=None,
            desired_state=None,
        )

    def reconcile_services(self) -> ServiceOperation:
        return self._run_service_operation(
            service="guest-stack",
            command=ServiceCommand.RECONCILE,
            action=self._service_control.reconcile_services,
        )

    def _run_service_operation(
        self,
        *,
        service: str,
        command: ServiceCommand,
        action: Callable[[], None],
    ) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service=service,
                command=command.value,
            ),
            service=service,
            command=command,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            action()
            self._save_operation_status_snapshot(service=service, command=command)
        except GuestControlDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(
                    kind=error.kind,
                    message=error.message,
                ),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return completed

    def _save_operation_status_snapshot(
        self,
        *,
        service: str,
        command: ServiceCommand,
    ) -> None:
        if command == ServiceCommand.RECONCILE:
            stack_status = self._service_control.get_stack_status()
            for service_status in stack_status.services:
                self._service_status_snapshots.save_service_status_snapshot(
                    service_status
                )
                self._sync_guest_service_resource_status(service_status)
            return

        service_status = self._service_control.get_service_status(service)
        self._service_status_snapshots.save_service_status_snapshot(service_status)
        self._sync_guest_service_resource_status(service_status)

    def _save_guest_service_spec(
        self,
        service: str,
        *,
        desired_state: GuestServiceDesiredState,
    ) -> None:
        self._ensure_guest_service_exists(service)
        previous = self._load_guest_service_resource(service)
        spec = GuestServiceSpec.configured(
            desired_state=desired_state,
            updated_at=self._clock.now(),
        )
        resource = GuestServiceResource(
            service=service,
            spec=spec,
            status=previous.status,
            conditions=previous.conditions,
            last_operation_id=previous.last_operation_id,
        )
        self._guest_service_resources.save_guest_service_resource(resource)

    def _load_guest_service_resource(self, service: str) -> GuestServiceResource:
        resource = self._guest_service_resources.get_guest_service_resource(service)
        if resource is not None:
            return resource
        return self._missing_guest_service_resource(service)

    def _sync_guest_service_resource_status(
        self,
        service_status: ServiceStatus,
    ) -> GuestServiceResource:
        status_read = GuestServiceStatusRead.loaded(
            service_status,
            observed_state=_guest_service_observed_state(service_status.state),
        )
        resource = self._load_guest_service_resource(service_status.service)
        resource = self._guest_service_resource_with_status(resource, status_read)
        self._guest_service_resources.save_guest_service_resource(resource)
        return resource

    def _missing_guest_service_resource(
        self,
        service: str,
    ) -> GuestServiceResource:
        resource = GuestServiceResource(
            service=service,
            spec=GuestServiceSpec.missing(),
            status=GuestServiceStatusRead.failed(
                OperationFailure(
                    kind="guestServiceStatusNotObserved",
                    message="Guest service status has not been observed.",
                )
            ),
            conditions=[],
            last_operation_id=None,
        )
        return resource

    def _guest_service_resource_with_status(
        self,
        resource: GuestServiceResource,
        status_read: GuestServiceStatusRead,
    ) -> GuestServiceResource:
        return GuestServiceResource(
            service=resource.service,
            spec=resource.spec,
            status=status_read,
            conditions=self._guest_service_conditions(resource.spec, status_read),
            last_operation_id=resource.last_operation_id,
        )

    def _guest_service_conditions(
        self,
        spec: GuestServiceSpec,
        status_read: GuestServiceStatusRead,
    ) -> list[GuestServiceCondition]:
        return reconcile_guest_service(
            spec=spec,
            status=status_read,
            requested_command=None,
            now=self._clock.now(),
        ).conditions

    def _read_guest_service_status(self, service: str) -> GuestServiceStatusRead:
        try:
            status = self._service_control.get_service_status(service)
        except ServiceNotFoundError:
            raise
        except GuestControlDependencyError as error:
            return GuestServiceStatusRead.failed(
                OperationFailure(
                    kind=error.kind,
                    message=error.message,
                )
            )
        return GuestServiceStatusRead.loaded(
            status,
            observed_state=_guest_service_observed_state(status.state),
        )

    def _run_guest_service_reconcile_operation(
        self,
        *,
        service: str,
        command: ServiceCommand,
        requested_command: ServiceCommand | None,
        desired_state: GuestServiceDesiredState | None,
    ) -> ServiceOperation:
        self._ensure_guest_service_exists(service)
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service=service,
                command=command.value,
            ),
            service=service,
            command=command,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        if desired_state is not None:
            try:
                self._save_guest_service_spec(service, desired_state=desired_state)
            except GuestControlDependencyError as error:
                failed = fail_operation(
                    running,
                    failure=OperationFailure(kind=error.kind, message=error.message),
                    now=self._clock.now(),
                )
                self._save_operation_transition(failed)
                return failed

        resource = self._load_guest_service_resource(service)
        status_read = self._read_guest_service_status(service)
        if status_read.service_status is not None:
            self._service_status_snapshots.save_service_status_snapshot(
                status_read.service_status
            )

        decision = reconcile_guest_service(
            spec=resource.spec,
            status=status_read,
            requested_command=requested_command,
            now=self._clock.now(),
        )
        resource = GuestServiceResource(
            service=service,
            spec=resource.spec,
            status=status_read,
            conditions=decision.conditions,
            last_operation_id=operation.operation_id,
        )
        self._guest_service_resources.save_guest_service_resource(resource)

        if decision.blocked:
            failed = fail_operation(
                running,
                failure=OperationFailure(
                    kind="guestServiceReconcileBlocked",
                    message=decision.message,
                ),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        try:
            self._execute_guest_service_effect(service, decision.effect)
            final_status = self._read_guest_service_status(service)
            if final_status.service_status is not None:
                self._service_status_snapshots.save_service_status_snapshot(
                    final_status.service_status
                )
            final_decision = reconcile_guest_service(
                spec=resource.spec,
                status=final_status,
                requested_command=None,
                now=self._clock.now(),
            )
            final_resource = GuestServiceResource(
                service=service,
                spec=resource.spec,
                status=final_status,
                conditions=final_decision.conditions,
                last_operation_id=operation.operation_id,
            )
            self._guest_service_resources.save_guest_service_resource(final_resource)
        except GuestControlDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(
                    kind=error.kind,
                    message=error.message,
                ),
                now=self._clock.now(),
            )
            failed_resource = GuestServiceResource(
                service=service,
                spec=resource.spec,
                status=status_read,
                conditions=[
                    _guest_service_condition(
                        type="Reconciled",
                        status="false",
                        reason=error.kind,
                        message=error.message,
                        observed_at=failed.updated_at,
                    )
                ],
                last_operation_id=operation.operation_id,
            )
            self._guest_service_resources.save_guest_service_resource(failed_resource)
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(
            running,
            now=self._clock.now(),
            result=decision.result_json(),
        )
        self._save_operation_transition(completed)
        return completed

    def _execute_guest_service_effect(
        self,
        service: str,
        effect: GuestServiceReconcileEffect,
    ) -> None:
        if effect == GuestServiceReconcileEffect.NONE:
            return
        if effect == GuestServiceReconcileEffect.START:
            self._service_control.start_service(service)
            return
        if effect == GuestServiceReconcileEffect.STOP:
            self._service_control.stop_service(service)
            return
        if effect == GuestServiceReconcileEffect.RESTART:
            self._service_control.restart_service(service)
            return
        raise GuestControlDependencyError(
            f"guest service reconcile effect is not executable: {effect.value}",
            kind="guestServiceReconcileEffectInvalid",
        )

    def _ensure_guest_service_exists(self, service: str) -> None:
        available_services = self._service_control.list_services()
        if service not in available_services:
            raise ServiceNotFoundError(
                service,
                available_services=available_services,
            )

    def _guest_service_desired_state_from_request(
        self,
        value: str,
    ) -> GuestServiceDesiredState:
        try:
            return GuestServiceDesiredState(value)
        except ValueError as error:
            raise GuestControlDependencyError(
                "guest service desiredState must be running or stopped",
                kind="guestServiceSpecInvalid",
            ) from error

    def list_lab_scenarios(self) -> dict[str, object]:
        if self._product_lab is None:
            return {
                "state": "unavailable",
                "scenarios": [],
                "readError": "Product Lab adapter is unavailable.",
            }

        try:
            return self._product_lab.list_scenarios()
        except ProductLabDependencyError as error:
            return _lab_failed_document(error)

    def list_lab_vital_files(self) -> dict[str, object]:
        if self._vital_file_library is None:
            return {
                "state": "unavailable",
                "vitalFiles": [],
                "readError": "VitalServer file library adapter is unavailable.",
            }

        try:
            return {
                "state": "loaded",
                "vitalFiles": self._vital_file_library.list_files(),
                "readError": None,
            }
        except GuestControlDependencyError as error:
            state = (
                "unavailable"
                if error.kind
                in {
                    "vitalFileLibraryUnavailable",
                    "vitalFileLibraryAuthenticationUnavailable",
                }
                else "failed"
            )
            return {
                "state": state,
                "vitalFiles": [],
                "readError": error.message,
            }

    def list_lab_beds(self) -> dict[str, object]:
        if self._product_lab is None:
            return {
                "state": "unavailable",
                "beds": [],
                "readError": "Product Lab adapter is unavailable.",
            }

        try:
            return self._product_lab.list_beds()
        except ProductLabDependencyError as error:
            return _lab_read_model_failed_document(error, collection="beds")

    def list_lab_recorders(self) -> dict[str, object]:
        if self._product_lab is None:
            return {
                "state": "unavailable",
                "recorders": [],
                "readError": "Product Lab adapter is unavailable.",
            }

        try:
            return self._product_lab.list_recorders()
        except ProductLabDependencyError as error:
            return _lab_read_model_failed_document(error, collection="recorders")

    def list_lab_sessions(self) -> dict[str, object]:
        if self._product_lab is None:
            return {
                "state": "unavailable",
                "sessions": [],
                "readError": "Product Lab adapter is unavailable.",
            }

        try:
            return self._product_lab.list_sessions()
        except ProductLabDependencyError as error:
            return _lab_read_model_failed_document(error, collection="sessions")

    def create_lab_session(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_session_operation(
            command=ServiceCommand.LAB_CREATE_SESSION,
            action=lambda: self._require_product_lab().create_session(request),
        )

    def get_lab_session(self, session_id: str) -> dict[str, object]:
        if self._product_lab is None:
            return _lab_session_unavailable_document(
                "Product Lab adapter is unavailable."
            )

        try:
            session_document = self._product_lab.get_session(session_id)
        except ProductLabDependencyError as error:
            return _lab_session_failed_document(error)
        return _lab_session_loaded_document(session_document)

    def start_lab_session(self, session_id: str) -> dict[str, object]:
        return self._run_lab_session_operation(
            command=ServiceCommand.LAB_START_SESSION,
            action=lambda: self._require_product_lab().start_session(session_id),
        )

    def stop_lab_session(self, session_id: str) -> dict[str, object]:
        return self._run_lab_session_operation(
            command=ServiceCommand.LAB_STOP_SESSION,
            action=lambda: self._require_product_lab().stop_session(session_id),
        )

    def finish_lab_session(self, session_id: str) -> dict[str, object]:
        return self._run_lab_session_operation(
            command=ServiceCommand.LAB_FINISH_SESSION,
            action=lambda: self._require_product_lab().finish_session(session_id),
        )

    def start_lab_recorder(
        self, session_id: str, recorder_id: str
    ) -> dict[str, object]:
        return self._run_lab_recorder_operation(
            command=ServiceCommand.LAB_START_RECORDER,
            action=lambda: self._require_product_lab().start_recorder(
                session_id, recorder_id
            ),
        )

    def stop_lab_recorder(self, session_id: str, recorder_id: str) -> dict[str, object]:
        return self._run_lab_recorder_operation(
            command=ServiceCommand.LAB_STOP_RECORDER,
            action=lambda: self._require_product_lab().stop_recorder(
                session_id, recorder_id
            ),
        )

    def replay_lab_vital_file(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_session_operation(
            command=ServiceCommand.LAB_REPLAY_VITAL_FILE,
            action=lambda: self._require_product_lab().replay_vital_file(request),
        )

    def import_lab_vital_files(
        self, sources: list[VitalFileUploadSource]
    ) -> dict[str, object]:
        if self._vital_file_library is None:
            raise GuestControlDependencyError(
                "Vital Files library adapter is unavailable.",
                kind="vitalFileLibraryUnavailable",
            )
        return self._vital_file_library.import_sources(sources).as_json()

    def create_lab_beds(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_read_model_operation(
            command=ServiceCommand.LAB_CREATE_BEDS,
            collection="beds",
            action=lambda: self._require_product_lab().create_beds(request),
        )

    def delete_lab_beds(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_read_model_operation(
            command=ServiceCommand.LAB_DELETE_BEDS,
            collection="beds",
            action=lambda: self._require_product_lab().delete_beds(request),
        )

    def reset_lab_beds(self) -> dict[str, object]:
        return self._run_lab_read_model_operation(
            command=ServiceCommand.LAB_RESET_BEDS,
            collection="beds",
            action=lambda: self._require_product_lab().reset_beds(),
        )

    def create_lab_recorders(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_read_model_operation(
            command=ServiceCommand.LAB_CREATE_RECORDERS,
            collection="recorders",
            action=lambda: self._require_product_lab().create_recorders(request),
        )

    def delete_lab_recorders(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_read_model_operation(
            command=ServiceCommand.LAB_DELETE_RECORDERS,
            collection="recorders",
            action=lambda: self._require_product_lab().delete_recorders(request),
        )

    def reset_lab_recorders(self) -> dict[str, object]:
        return self._run_lab_read_model_operation(
            command=ServiceCommand.LAB_RESET_RECORDERS,
            collection="recorders",
            action=lambda: self._require_product_lab().reset_recorders(),
        )

    def get_latest_vitaldb_observation(self) -> dict[str, object]:
        if self._vitaldb_read_model is None:
            return _vitaldb_observation_unavailable_document(
                "VitalDB read model adapter is unavailable."
            )

        try:
            return self._vitaldb_read_model.latest_observation()
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_observation_failed_document(error)

    def get_runtime_events(
        self,
        *,
        limit: int,
        event_type: str | None,
        since: datetime | None,
        cursor: str | None,
    ) -> dict[str, object]:
        return self._operations.query_events(
            limit=limit,
            event_type=event_type,
            since=since,
            cursor=cursor,
        )

    def get_runtime_settings(self) -> dict[str, object]:
        if self._runtime_settings is None:
            return {
                "state": "unavailable",
                "settings": None,
                "readError": "Runtime settings adapter is unavailable.",
            }
        try:
            return {
                "state": "loaded",
                "settings": self._runtime_settings.read(),
                "readError": None,
            }
        except GuestControlDependencyError as error:
            return {
                "state": "failed",
                "settings": None,
                "readError": error.message,
            }

    def apply_runtime_settings(self, settings: dict[str, object]) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="runtime-settings",
                command=ServiceCommand.APPLY_SETTINGS.value,
            ),
            service="runtime-settings",
            command=ServiceCommand.APPLY_SETTINGS,
            now=self._clock.now(),
        )
        self._create_operation(operation)
        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)
        try:
            if self._runtime_settings is None:
                raise GuestControlDependencyError(
                    "Runtime settings adapter is unavailable.",
                    kind="runtimeSettingsUnavailable",
                )
            self._runtime_settings.save(settings)
            self._service_control.reconcile_services()
        except GuestControlDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed
        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return completed

    def apply_admin_password(self, password: str) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="runtime-admin",
                command=ServiceCommand.APPLY_ADMIN_PASSWORD.value,
            ),
            service="runtime-admin",
            command=ServiceCommand.APPLY_ADMIN_PASSWORD,
            now=self._clock.now(),
        )
        self._create_operation(operation)
        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)
        try:
            if self._runtime_admin is None:
                raise GuestControlDependencyError(
                    "Runtime admin adapter is unavailable.",
                    kind="runtimeAdminUnavailable",
                )
            self._runtime_admin.replace_admin_password(password)
            self._service_control.reconcile_services()
        except GuestControlDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed
        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return completed

    def get_redis_relay_settings(self) -> dict[str, object]:
        if self._redis_relay_settings is None:
            return {
                "state": "unavailable",
                "settings": None,
                "readError": "Redis Relay settings adapter is unavailable.",
            }
        try:
            return {
                "state": "loaded",
                "settings": self._redis_relay_settings.read(),
                "readError": None,
            }
        except GuestControlDependencyError as error:
            return {
                "state": "failed",
                "settings": None,
                "readError": error.message,
            }

    def apply_redis_relay_settings(
        self, settings: dict[str, object]
    ) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="redis-relay-settings",
                command=ServiceCommand.APPLY_REDIS_RELAY_SETTINGS.value,
            ),
            service="redis-relay-settings",
            command=ServiceCommand.APPLY_REDIS_RELAY_SETTINGS,
            now=self._clock.now(),
        )
        self._create_operation(operation)
        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)
        try:
            if self._redis_relay_settings is None:
                raise GuestControlDependencyError(
                    "Redis Relay settings adapter is unavailable.",
                    kind="redisRelaySettingsUnavailable",
                )
            self._redis_relay_settings.save(settings)
            self._service_control.reconcile_services()
        except GuestControlDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed
        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return completed

    def list_vitaldb_recorders(self) -> dict[str, object]:
        if self._vitaldb_read_model is None:
            return _vitaldb_read_model_unavailable_document(
                collection="recorders",
                message="VitalDB recorder read model adapter is unavailable.",
            )

        try:
            return self._with_recorder_ingress(self._vitaldb_read_model.recorders())
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_read_model_failed_document(error, collection="recorders")

    def get_vitaldb_recorder(self, vrcode: str) -> dict[str, object] | None:
        read_model = self._require_vitaldb_read_model()
        document = self._with_recorder_ingress(read_model.recorders())
        recorders = document.get("recorders")
        if not isinstance(recorders, list):
            raise VitalDBReadModelDependencyError(
                "VitalDB recorder read model recorders field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        for recorder in recorders:
            if not isinstance(recorder, dict):
                raise VitalDBReadModelDependencyError(
                    "VitalDB recorder read model item is invalid.",
                    kind="vitaldb-read-model-invalid",
                )
            if recorder.get("vrcode") == vrcode:
                return recorder
        return None

    def hide_vitaldb_recorders(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_vitaldb_read_model_command(
            collection="recorders",
            action=lambda: self._require_vitaldb_read_model().hide_recorders(request),
        )

    def unhide_vitaldb_recorders(
        self,
        request: dict[str, object],
    ) -> dict[str, object]:
        return self._run_vitaldb_read_model_command(
            collection="recorders",
            action=lambda: self._require_vitaldb_read_model().unhide_recorders(request),
        )

    def delete_vitaldb_recorders(
        self,
        request: dict[str, object],
    ) -> dict[str, object]:
        return self._run_vitaldb_read_model_command(
            collection="recorders",
            action=lambda: self._delete_vitaldb_recorders(request),
        )

    def _delete_vitaldb_recorders(
        self,
        request: dict[str, object],
    ) -> dict[str, object]:
        read_model = self._require_vitaldb_read_model()
        vrcodes = _required_command_ids(request, field="vrcodes")
        try:
            plan = plan_recorder_deletion(read_model.recorders(), vrcodes)
        except VitalDBDeletionPolicyError as error:
            raise VitalDBReadModelDependencyError(
                error.message,
                kind=error.kind,
            ) from error
        self._delete_owning_lab_sessions(set(plan.lab_vrcodes))
        return read_model.delete_recorders(request)

    def get_vitaldb_recorder_activity(self, vrcode: str) -> dict[str, object]:
        if self._vitaldb_read_model is None:
            return {
                "state": "unavailable",
                "vrcode": vrcode,
                "buckets": [],
                "readError": (
                    "VitalDB recorder activity read model adapter is unavailable."
                ),
            }

        try:
            return self._vitaldb_read_model.recorder_activity(vrcode)
        except VitalDBReadModelDependencyError as error:
            return {
                "state": "unavailable",
                "vrcode": vrcode,
                "buckets": [],
                "readError": error.message,
            }

    def get_vitaldb_recorder_vital_files(
        self,
        vrcode: str,
    ) -> dict[str, object]:
        native_files: list[dict[str, object]] = []
        recovery_files: list[dict[str, object]] = []
        native_state = "readFailed"
        recovery_state = "readFailed"
        native_error: str | None = None
        recovery_error: str | None = None
        unattributed_count = 0

        if self._recorder_ingress is None:
            native_error = "Recorder ingress native upload adapter is unavailable."
        elif self._vitaldb_read_model is None:
            native_error = "VitalDB relationship read model adapter is unavailable."
        else:
            try:
                upload_document = self._recorder_ingress.native_vital_uploads()
                if upload_document.get("state") != "loaded":
                    raise RecorderVitalFileProjectionError(
                        _required_read_error(
                            upload_document,
                            "Recorder ingress native upload read failed.",
                        )
                    )
                uploads = upload_document.get("uploads")
                if not isinstance(uploads, list):
                    raise RecorderVitalFileProjectionError(
                        "Recorder ingress native uploads field is invalid."
                    )
                try:
                    relationships = self._vitaldb_read_model.relationships(
                        event_limit=1
                    )
                except VitalDBReadModelDependencyError as error:
                    relationships = {
                        "state": "readFailed",
                        "assignments": [],
                        "events": [],
                        "readError": error.message,
                    }
                native = native_uploads_for_recorder(
                    vrcode,
                    uploads=uploads,
                    relationships=relationships,
                )
                native_state = str(native["state"])
                native_files = list(native["files"])
                unattributed_count = int(native["unattributedCount"])
                native_error = (
                    str(native["readError"])
                    if native["readError"] is not None
                    else None
                )
            except (
                RecorderIngressDependencyError,
                RecorderVitalFileProjectionError,
            ) as error:
                native_error = _dependency_message(error)

        if self._recorder_recovery is None:
            recovery_error = "Recorder recovery artifact adapter is unavailable."
        else:
            try:
                artifact_document = self._recorder_recovery.list_artifacts()
                if artifact_document.get("state") != "loaded":
                    raise RecorderVitalFileProjectionError(
                        _required_read_error(
                            artifact_document,
                            "Recorder recovery artifact read failed.",
                        )
                    )
                artifacts = artifact_document.get("artifacts")
                if not isinstance(artifacts, list):
                    raise RecorderVitalFileProjectionError(
                        "Recorder recovery artifacts field is invalid."
                    )
                recovery = recovery_artifacts_for_recorder(
                    vrcode,
                    artifacts=artifacts,
                )
                recovery_state = str(recovery["state"])
                recovery_files = list(recovery["files"])
            except (
                RecorderRecoveryDependencyError,
                RecorderVitalFileProjectionError,
            ) as error:
                recovery_error = _dependency_message(error)

        states = {native_state, recovery_state}
        if states == {"loaded"}:
            state = "loaded"
        elif states == {"readFailed"}:
            state = "readFailed"
        else:
            state = "partiallyLoaded"
        files = native_files + recovery_files
        files.sort(
            key=lambda item: _vital_file_sort_key(item),
            reverse=True,
        )
        errors = [
            f"nativeUpload={native_error}" if native_error else None,
            f"coldPathRecovery={recovery_error}" if recovery_error else None,
        ]
        return {
            "state": state,
            "vrcode": vrcode,
            "files": files,
            "unattributedCount": unattributed_count,
            "sources": {
                "nativeUpload": {
                    "state": native_state,
                    "readError": native_error,
                },
                "coldPathRecovery": {
                    "state": recovery_state,
                    "readError": recovery_error,
                },
            },
            "readError": "; ".join(value for value in errors if value is not None)
            or None,
        }

    def list_vitaldb_beds(self) -> dict[str, object]:
        if self._vitaldb_read_model is None:
            return _vitaldb_read_model_unavailable_document(
                collection="beds",
                message="VitalDB bed read model adapter is unavailable.",
            )

        try:
            return self._vitaldb_read_model.beds()
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_read_model_failed_document(error, collection="beds")

    def get_vitaldb_bed(self, bed_id: str) -> dict[str, object] | None:
        read_model = self._require_vitaldb_read_model()
        document = read_model.beds()
        beds = document.get("beds")
        if not isinstance(beds, list):
            raise VitalDBReadModelDependencyError(
                "VitalDB bed read model beds field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        for bed in beds:
            if not isinstance(bed, dict):
                raise VitalDBReadModelDependencyError(
                    "VitalDB bed read model item is invalid.",
                    kind="vitaldb-read-model-invalid",
                )
            if bed.get("bedID") == bed_id:
                return bed
        return None

    def hide_vitaldb_beds(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_vitaldb_read_model_command(
            collection="beds",
            action=lambda: self._require_vitaldb_read_model().hide_beds(request),
        )

    def unhide_vitaldb_beds(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_vitaldb_read_model_command(
            collection="beds",
            action=lambda: self._require_vitaldb_read_model().unhide_beds(request),
        )

    def delete_vitaldb_beds(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_vitaldb_read_model_command(
            collection="beds",
            action=lambda: self._delete_vitaldb_beds(request),
        )

    def _delete_vitaldb_beds(
        self,
        request: dict[str, object],
    ) -> dict[str, object]:
        read_model = self._require_vitaldb_read_model()
        bed_ids = _required_command_ids(request, field="bedIDs")
        try:
            plan = plan_bed_deletion(read_model.beds(), bed_ids)
        except VitalDBDeletionPolicyError as error:
            raise VitalDBReadModelDependencyError(
                error.message,
                kind=error.kind,
            ) from error
        self._delete_owning_lab_sessions(set(plan.lab_vrcodes))
        return read_model.delete_beds(request)

    def _delete_owning_lab_sessions(self, lab_vrcodes: set[str]) -> None:
        if not lab_vrcodes:
            return
        try:
            product_lab = self._require_product_lab()
            document = product_lab.list_recorders()
            recorders = document.get("recorders")
            if document.get("state") != "loaded" or not isinstance(recorders, list):
                raise ProductLabDependencyError(
                    "Product Lab recorder read model contract is invalid.",
                    kind="product-lab-contract-invalid",
                )
            session_ids: set[str] = set()
            for recorder in recorders:
                if not isinstance(recorder, dict):
                    raise ProductLabDependencyError(
                        "Product Lab recorder read model item is invalid.",
                        kind="product-lab-contract-invalid",
                    )
                if recorder.get("vrcode") not in lab_vrcodes:
                    continue
                session_id = recorder.get("sessionId")
                if not isinstance(session_id, str) or not session_id:
                    raise ProductLabDependencyError(
                        "Product Lab recorder sessionId is invalid.",
                        kind="product-lab-contract-invalid",
                    )
                session_ids.add(session_id)
            for session_id in sorted(session_ids):
                result = product_lab.delete_session(session_id)
                sessions = result.document.get("sessions")
                if result.document.get("state") != "loaded" or not isinstance(
                    sessions, list
                ):
                    raise ProductLabDependencyError(
                        "Product Lab session delete result is invalid.",
                        kind="product-lab-contract-invalid",
                    )
        except ProductLabDependencyError as error:
            raise VitalDBReadModelDependencyError(
                f"Product Lab session cleanup failed: {error.message}",
                kind="vitaldb-delete-lab-cleanup-failed",
            ) from error

    def get_vitaldb_relationships(self, *, event_limit: int) -> dict[str, object]:
        if self._vitaldb_read_model is None:
            return _vitaldb_relationship_unavailable_document(
                "VitalDB relationship read model adapter is unavailable.",
                event_limit=event_limit,
            )

        try:
            return self._vitaldb_read_model.relationships(event_limit=event_limit)
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_relationship_failed_document(
                error,
                event_limit=event_limit,
            )

    def get_recorder_ingress_status(self) -> dict[str, object]:
        if self._recorder_ingress is None:
            return _recorder_ingress_unavailable_document(
                "Recorder ingress status adapter is unavailable."
            )

        try:
            return self._recorder_ingress.status()
        except RecorderIngressDependencyError as error:
            return _recorder_ingress_failed_document(error)

    def get_recorder_observability(self, vrcode: str) -> dict[str, object]:
        if self._recorder_ingress is None:
            return _recorder_observability_detail_unavailable_document(
                vrcode,
                "Recorder ingress observability adapter is unavailable.",
            )
        try:
            return self._recorder_ingress.recorder_observability_detail(vrcode)
        except RecorderIngressDependencyError as error:
            return _recorder_observability_detail_unavailable_document(
                vrcode,
                error.message,
            )

    def get_recorder_observability_timeline(
        self,
        vrcode: str,
        query: dict[str, str],
    ) -> dict[str, object]:
        return self._get_recorder_observability_history(
            vrcode,
            "timeline",
            query,
        )

    def get_recorder_observability_incidents(
        self,
        vrcode: str,
        query: dict[str, str],
    ) -> dict[str, object]:
        return self._get_recorder_observability_history(
            vrcode,
            "incidents",
            query,
        )

    def _get_recorder_observability_history(
        self,
        vrcode: str,
        resource: str,
        query: dict[str, str],
    ) -> dict[str, object]:
        if self._recorder_ingress is None:
            return _recorder_observability_history_unavailable_document(
                vrcode,
                resource,
                "Recorder ingress observability adapter is unavailable.",
            )
        try:
            if resource == "timeline":
                return self._recorder_ingress.recorder_observability_timeline(
                    vrcode,
                    query,
                )
            return self._recorder_ingress.recorder_observability_incidents(
                vrcode,
                query,
            )
        except RecorderIngressDependencyError as error:
            return _recorder_observability_history_unavailable_document(
                vrcode,
                resource,
                error.message,
            )

    def apply_recorder_observability_expectation(
        self,
        *,
        vrcode: str,
        command: dict[str, object],
    ) -> dict[str, object]:
        if self._recorder_ingress is None:
            raise GuestControlDependencyError(
                "Recorder ingress expectation command adapter is unavailable.",
                kind="recorder-ingress-control-unavailable",
            )
        try:
            return self._recorder_ingress.apply_recorder_observability_expectation(
                command
            )
        except RecorderIngressDependencyError as error:
            raise GuestControlDependencyError(
                error.message,
                kind=error.kind,
            ) from error

    def get_redis_relay_status(self) -> dict[str, object]:
        if self._redis_relay is None:
            return _redis_relay_unavailable_document(
                "Redis relay status adapter is unavailable."
            )

        try:
            return self._redis_relay.status()
        except RedisRelayDependencyError as error:
            return _redis_relay_failed_document(error)

    def put_redis_relay_status(self, document: dict[str, object]) -> dict[str, object]:
        validate_redis_relay_status_document(document)
        if self._redis_relay is None:
            return _redis_relay_unavailable_document(
                "Redis relay status owner is unavailable."
            )

        try:
            self._redis_relay.save_status(document)
            return self._redis_relay.status()
        except RedisRelayDependencyError as error:
            return _redis_relay_failed_document(error)

    def create_redis_backup(self) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="redis-backup",
                command=ServiceCommand.REDIS_BACKUP.value,
            ),
            service="redis-backup",
            command=ServiceCommand.REDIS_BACKUP,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            backup_result = self._require_redis_backup().create_backup()
        except RedisBackupDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(
            running,
            now=self._clock.now(),
            result=backup_result.as_json(),
        )
        self._save_operation_transition(completed)
        return completed

    def create_postgres_backup(self) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="postgres-backup",
                command=ServiceCommand.POSTGRES_BACKUP.value,
            ),
            service="postgres-backup",
            command=ServiceCommand.POSTGRES_BACKUP,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            backup_result = self._require_postgres_backup().create_backup()
        except PostgresBackupDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(
            running,
            now=self._clock.now(),
            result=backup_result.as_json(),
        )
        self._save_operation_transition(completed)
        return completed

    def restore_postgres_backup(
        self,
        archive: str,
        *,
        restart_runtime: bool,
    ) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="postgres-restore",
                command=ServiceCommand.POSTGRES_RESTORE.value,
            ),
            service="postgres-restore",
            command=ServiceCommand.POSTGRES_RESTORE,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            restore_result = self._require_postgres_backup().restore_backup(
                archive,
                restart_runtime=restart_runtime,
            )
        except PostgresRestoreDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(
            running,
            now=self._clock.now(),
            result=restore_result.as_json(),
        )
        self._save_operation_transition(completed)
        return completed

    def restore_redis_backup(self, archive: str) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="redis-restore",
                command=ServiceCommand.REDIS_RESTORE.value,
            ),
            service="redis-restore",
            command=ServiceCommand.REDIS_RESTORE,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            restore_result = self._require_redis_backup().restore_backup(archive)
        except RedisRestoreDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(
            running,
            now=self._clock.now(),
            result=restore_result.as_json(),
        )
        self._save_operation_transition(completed)
        return completed

    def repair_datastore(self) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="datastore-repair",
                command=ServiceCommand.REPAIR_DATASTORE.value,
            ),
            service="datastore-repair",
            command=ServiceCommand.REPAIR_DATASTORE,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            self._require_datastore_repair().repair_datastore()
        except DatastoreRepairDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return completed

    def activate_update(self, *, request_id: str, version: str) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="update-activation",
                command=ServiceCommand.UPDATE_ACTIVATION.value,
            ),
            service="update-activation",
            command=ServiceCommand.UPDATE_ACTIVATION,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            activation_result = self._require_update_activation().activate_update(
                request_id=request_id,
                version=version,
            )
        except UpdateActivationDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(
            running,
            now=self._clock.now(),
            result=activation_result.as_json(),
        )
        self._save_operation_transition(completed)
        return completed

    def prepare_update_shutdown(
        self,
        *,
        request_id: str,
        version: str,
    ) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="update-shutdown",
                command=ServiceCommand.UPDATE_SHUTDOWN.value,
            ),
            service="update-shutdown",
            command=ServiceCommand.UPDATE_SHUTDOWN,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        def mark_ready(result: UpdateShutdownResult) -> None:
            completed = finish_operation(
                running,
                now=self._clock.now(),
                result=result.as_json(),
            )
            self._save_operation_transition(completed)

        def mark_failed(error: UpdateShutdownDependencyError) -> None:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)

        try:
            self._require_update_shutdown().prepare_update_shutdown(
                request_id=request_id,
                version=version,
                on_ready=mark_ready,
                on_failure=mark_failed,
            )
        except UpdateShutdownDependencyError as error:
            mark_failed(error)

        persisted = self._operations.get(operation.operation_id)
        if persisted is None:
            raise GuestControlDependencyError(
                "update shutdown operation state is missing after persistence "
                f"operationId={operation.operation_id}",
                kind="operationStateMissing",
            )
        return persisted

    def request_guest_poweroff(self) -> ServiceOperation:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="guest-poweroff",
                command=ServiceCommand.REQUEST_GUEST_POWEROFF.value,
            ),
            service="guest-poweroff",
            command=ServiceCommand.REQUEST_GUEST_POWEROFF,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            self._require_update_shutdown().request_poweroff()
        except UpdateShutdownDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return failed

        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return completed

    def _require_product_lab(self) -> ProductLabPort:
        if self._product_lab is None:
            raise ProductLabDependencyError(
                "Product Lab adapter is unavailable.",
                kind="product-lab-unavailable",
            )
        return self._product_lab

    def _require_vitaldb_read_model(self) -> VitalDBReadModelPort:
        if self._vitaldb_read_model is None:
            raise VitalDBReadModelDependencyError(
                "VitalDB read model adapter is unavailable.",
                kind="vitaldb-read-model-unavailable",
            )
        return self._vitaldb_read_model

    def _require_redis_backup(self) -> RedisBackupPort:
        if self._redis_backup is None:
            raise RedisBackupDependencyError(
                "Redis backup adapter is unavailable.",
                kind="redis-backup-unavailable",
            )
        return self._redis_backup

    def _require_postgres_backup(self) -> PostgresBackupPort:
        if self._postgres_backup is None:
            raise PostgresBackupDependencyError(
                "PostgreSQL backup adapter is unavailable",
                kind="postgres-backup-adapter-unavailable",
            )
        return self._postgres_backup

    def _require_datastore_repair(self) -> DatastoreRepairPort:
        if self._datastore_repair is None:
            raise DatastoreRepairDependencyError(
                "Datastore repair adapter is unavailable.",
                kind="datastore-repair-unavailable",
            )
        return self._datastore_repair

    def _require_update_activation(self) -> UpdateActivationPort:
        if self._update_activation is None:
            raise UpdateActivationDependencyError(
                "Update activation adapter is unavailable.",
                kind="update-activation-unavailable",
            )
        return self._update_activation

    def _require_update_shutdown(self) -> UpdateShutdownPort:
        if self._update_shutdown is None:
            raise UpdateShutdownDependencyError(
                "Update shutdown adapter is unavailable.",
                kind="update-shutdown-unavailable",
            )
        return self._update_shutdown

    def _run_lab_session_operation(
        self,
        *,
        command: ServiceCommand,
        action: Callable[[], ProductLabSessionResult],
    ) -> dict[str, object]:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="product-lab",
                command=command.value,
            ),
            service="product-lab",
            command=command,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            lab_result = action()
        except ProductLabDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return _lab_session_failed_document(error, operation=failed)

        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return _lab_session_loaded_document(lab_result, operation=completed)

    def _run_lab_recorder_operation(
        self,
        *,
        command: ServiceCommand,
        action: Callable[[], ProductLabRecorderResult],
    ) -> dict[str, object]:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="product-lab",
                command=command.value,
            ),
            service="product-lab",
            command=command,
            now=self._clock.now(),
        )
        self._create_operation(operation)
        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)
        try:
            lab_result = action()
        except ProductLabDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return _lab_recorder_failed_document(error, operation=failed)
        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return _lab_recorder_loaded_document(lab_result, operation=completed)

    def _run_lab_read_model_operation(
        self,
        *,
        command: ServiceCommand,
        collection: str,
        action: Callable[[], ProductLabReadModelResult],
    ) -> dict[str, object]:
        operation = accept_service_operation(
            operation_id=self._operation_ids.new_operation_id(
                service="product-lab",
                command=command.value,
            ),
            service="product-lab",
            command=command,
            now=self._clock.now(),
        )
        self._create_operation(operation)

        running = start_operation(operation, now=self._clock.now())
        self._save_operation_transition(running)

        try:
            lab_result = action()
        except ProductLabDependencyError as error:
            failed = fail_operation(
                running,
                failure=OperationFailure(kind=error.kind, message=error.message),
                now=self._clock.now(),
            )
            self._save_operation_transition(failed)
            return _lab_read_model_failed_document(error, collection=collection)

        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return _lab_read_model_loaded_document(
            lab_result,
            collection=collection,
            operation=completed,
        )

    def _run_vitaldb_read_model_command(
        self,
        *,
        collection: str,
        action: Callable[[], dict[str, object]],
    ) -> dict[str, object]:
        try:
            document = action()
            return (
                self._with_recorder_ingress(document)
                if collection == "recorders"
                else document
            )
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_read_model_failed_document(error, collection=collection)

    def _with_recorder_ingress(self, history: dict[str, object]) -> dict[str, object]:
        with_status = attach_recorder_ingress_status(
            history,
            self.get_recorder_ingress_status(),
        )
        if self._recorder_ingress is None:
            observability = {
                "state": "failed",
                "recorders": [],
                "readError": "Recorder ingress observability adapter is unavailable.",
            }
        else:
            try:
                observability = self._recorder_ingress.recorder_observability()
            except RecorderIngressDependencyError as error:
                observability = {
                    "state": "failed",
                    "recorders": [],
                    "readError": error.message,
                }
        return attach_recorder_observability(with_status, observability)

    def _create_operation(self, operation: ServiceOperation) -> None:
        self._operations.record_accepted(
            operation,
            lease=OperationLease(
                resource_key=GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY,
                operation_id=operation.operation_id,
                acquired_at=operation.created_at,
            ),
        )

    def _save_operation_transition(self, operation: ServiceOperation) -> None:
        self._operations.record_transition(operation)


def _required_command_ids(
    request: dict[str, object],
    *,
    field: str,
) -> list[str]:
    values = request.get(field)
    if not isinstance(values, list) or not values:
        raise VitalDBReadModelDependencyError(
            f"VitalDB delete request {field} field is invalid.",
            kind="vitaldb-read-model-invalid",
        )
    if any(not isinstance(value, str) or not value for value in values):
        raise VitalDBReadModelDependencyError(
            f"VitalDB delete request {field} field is invalid.",
            kind="vitaldb-read-model-invalid",
        )
    return list(dict.fromkeys(values))


def _required_readiness_dependency(
    name: str,
    check: Callable[[], None],
) -> dict[str, object]:
    try:
        check()
    except GuestControlDependencyError as error:
        return {
            "name": name,
            "role": "required",
            "state": "failed",
            "kind": error.kind,
            "message": error.message,
        }
    return {
        "name": name,
        "role": "required",
        "state": "ready",
        "kind": None,
        "message": None,
    }


def _guest_service_condition(
    *,
    type: str,
    status: str,
    reason: str,
    message: str,
    observed_at: datetime,
) -> GuestServiceCondition:
    return GuestServiceCondition(
        type=type,
        status=status,
        reason=reason,
        message=message,
        observed_at=observed_at,
    )


def _guest_service_observed_state(state: str) -> GuestServiceObservedState:
    if state == "running":
        return GuestServiceObservedState.RUNNING
    if state == "stopped":
        return GuestServiceObservedState.STOPPED
    if state == "exited":
        return GuestServiceObservedState.EXITED
    if state == "absent":
        return GuestServiceObservedState.ABSENT
    return GuestServiceObservedState.UNKNOWN


def _lab_failed_document(error: ProductLabDependencyError) -> dict[str, object]:
    state = "unavailable" if error.kind == "product-lab-unavailable" else "failed"
    return {
        "state": state,
        "scenarios": [],
        "readError": error.message,
    }


def _lab_read_model_failed_document(
    error: ProductLabDependencyError,
    *,
    collection: str,
) -> dict[str, object]:
    state = "unavailable" if error.kind == "product-lab-unavailable" else "failed"
    return {
        "state": state,
        collection: [],
        "readError": error.message,
    }


def _lab_session_unavailable_document(message: str) -> dict[str, object]:
    return {
        "state": "unavailable",
        "session": None,
        "operationId": None,
        "labOperationId": None,
        "readError": message,
    }


def _lab_session_failed_document(
    error: ProductLabDependencyError,
    *,
    operation: ServiceOperation | None = None,
) -> dict[str, object]:
    state = "unavailable" if error.kind == "product-lab-unavailable" else "failed"
    return {
        "state": state,
        "session": None,
        "operationId": None if operation is None else operation.operation_id,
        "labOperationId": None,
        "readError": error.message,
    }


def _lab_session_loaded_document(
    lab_result: ProductLabSessionResult,
    *,
    operation: ServiceOperation | None = None,
) -> dict[str, object]:
    return {
        "state": "loaded",
        "session": lab_result.session,
        "operationId": None if operation is None else operation.operation_id,
        "labOperationId": lab_result.lab_operation_id,
        "readError": None,
    }


def _lab_recorder_failed_document(
    error: ProductLabDependencyError,
    *,
    operation: ServiceOperation,
) -> dict[str, object]:
    state = "unavailable" if error.kind == "product-lab-unavailable" else "failed"
    return {
        "state": state,
        "recorder": None,
        "operationId": operation.operation_id,
        "labOperationId": None,
        "readError": error.message,
    }


def _lab_recorder_loaded_document(
    lab_result: ProductLabRecorderResult,
    *,
    operation: ServiceOperation,
) -> dict[str, object]:
    return {
        "state": "loaded",
        "recorder": lab_result.recorder,
        "operationId": operation.operation_id,
        "labOperationId": lab_result.lab_operation_id,
        "readError": None,
    }


def _lab_read_model_loaded_document(
    lab_result: ProductLabReadModelResult,
    *,
    collection: str,
    operation: ServiceOperation,
) -> dict[str, object]:
    document = dict(lab_result.document)
    document["operationId"] = operation.operation_id
    document["labOperationId"] = lab_result.lab_operation_id
    if collection not in document:
        document[collection] = []
    return document


def _vitaldb_observation_unavailable_document(message: str) -> dict[str, object]:
    return {
        "state": "unavailable",
        "observation": None,
        "readError": message,
    }


def _vitaldb_observation_failed_document(
    error: VitalDBReadModelDependencyError,
) -> dict[str, object]:
    state = (
        "unavailable" if error.kind == "vitaldb-read-model-unavailable" else "failed"
    )
    return {
        "state": state,
        "observation": None,
        "readError": error.message,
    }


def _vitaldb_read_model_unavailable_document(
    *,
    collection: str,
    message: str,
) -> dict[str, object]:
    if collection == "recorders":
        return _failed_recorder_history(message)
    if collection == "beds":
        return _failed_bed_history(message)
    return {
        "state": "unavailable",
        collection: [],
        "observedAt": None,
        "readError": message,
    }


def _vitaldb_read_model_failed_document(
    error: VitalDBReadModelDependencyError,
    *,
    collection: str,
) -> dict[str, object]:
    if collection == "recorders":
        return _failed_recorder_history(error.message)
    if collection == "beds":
        return _failed_bed_history(error.message)
    state = (
        "unavailable" if error.kind == "vitaldb-read-model-unavailable" else "failed"
    )
    return {
        "state": state,
        collection: [],
        "observedAt": None,
        "readError": error.message,
    }


def _failed_recorder_history(message: str) -> dict[str, object]:
    return {
        "state": "readFailed",
        "updatedAt": None,
        "recorders": [],
        "beds": [],
        "summary": {
            "knownRecorders": 0,
            "currentRecorders": 0,
            "onlineRecorders": 0,
            "staleRecorders": 0,
            "recorderAnomalies": 0,
            "knownBeds": 0,
            "onlineBeds": 0,
            "staleBeds": 0,
            "bedAssignments": 0,
            "bedAnomalies": 0,
        },
        "activityHistory": {
            "source": "unavailable",
            "bucketCount": 0,
            "earliestBucketStartedAt": None,
            "latestBucketStartedAt": None,
            "readError": message,
        },
        "recorderIngressStatusRead": None,
        "readError": message,
    }


def _failed_bed_history(message: str) -> dict[str, object]:
    return {
        "state": "readFailed",
        "updatedAt": None,
        "beds": [],
        "summary": {
            "knownBeds": 0,
            "onlineBeds": 0,
            "staleBeds": 0,
            "bedAssignments": 0,
            "bedAnomalies": 0,
        },
        "readError": message,
    }


def _vitaldb_relationship_unavailable_document(
    message: str,
    *,
    event_limit: int,
) -> dict[str, object]:
    return {
        "state": "unavailable",
        "assignments": [],
        "events": [],
        "eventTotalCount": 0,
        "eventLimit": event_limit,
        "readError": message,
    }


def _vitaldb_relationship_failed_document(
    error: VitalDBReadModelDependencyError,
    *,
    event_limit: int,
) -> dict[str, object]:
    state = (
        "unavailable" if error.kind == "vitaldb-read-model-unavailable" else "failed"
    )
    return {
        "state": state,
        "assignments": [],
        "events": [],
        "eventTotalCount": 0,
        "eventLimit": event_limit,
        "readError": error.message,
    }


def _recorder_ingress_unavailable_document(message: str) -> dict[str, object]:
    return {
        "readState": "readFailed",
        "httpStatus": "unavailable",
        "document": None,
        "readError": message,
    }


def _recorder_observability_detail_unavailable_document(
    vrcode: str,
    message: str,
) -> dict[str, object]:
    missing: dict[str, object] = {
        "state": "missing",
        "value": None,
        "detail": "health observation is unavailable",
        "observedAt": None,
    }
    return {
        "state": "unavailable",
        "vrcode": vrcode,
        "support": {
            "state": "unknown",
            "source": None,
            "expectedSince": None,
            "recorderVersion": None,
            "producerVersion": None,
            "protocolVersion": None,
        },
        "report": {
            "state": "readFailed",
            "receivedAt": None,
            "deviceObservedAt": None,
            "collectionState": None,
            "readIssueCount": 0,
        },
        "profile": {
            "state": "missing",
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
        "operationalHealth": {
            "state": "unknown",
            "evaluatedAt": None,
            "issueCount": 0,
            "issues": [],
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
        "readError": message,
    }


def _recorder_observability_history_unavailable_document(
    vrcode: str,
    resource: str,
    message: str,
) -> dict[str, object]:
    return {
        "state": "unavailable",
        "vrcode": vrcode,
        "timeBasis": "receivedAt",
        ("buckets" if resource == "timeline" else "incidents"): [],
        **({"nextCursor": None} if resource == "incidents" else {}),
        "readError": message,
    }


def _recorder_ingress_failed_document(
    error: RecorderIngressDependencyError,
) -> dict[str, object]:
    return {
        "readState": _recorder_ingress_read_state(error.kind),
        "httpStatus": "failed",
        "document": None,
        "readError": error.message,
    }


def _recorder_ingress_read_state(kind: str) -> str:
    if kind == "recorder-ingress-timeout":
        return "readFailed"
    if kind == "recorder-ingress-contract-invalid":
        return "invalidResponse"
    if kind == "recorder-ingress-http-error":
        return "commandFailed"
    return "readFailed"


def _redis_relay_unavailable_document(message: str) -> dict[str, object]:
    return {
        "readState": "readFailed",
        "document": None,
        "readError": message,
    }


def _redis_relay_failed_document(
    error: RedisRelayDependencyError,
) -> dict[str, object]:
    return {
        "readState": _redis_relay_read_state(error.kind),
        "document": None,
        "readError": error.message,
    }


def _redis_relay_read_state(kind: str) -> str:
    if kind == "redis-relay-contract-invalid":
        return "invalidResponse"
    if kind == "redis-relay-status-missing":
        return "readFailed"
    return "readFailed"


def _required_read_error(
    document: dict[str, object],
    default: str,
) -> str:
    value = document.get("readError")
    return value if isinstance(value, str) and value else default


def _dependency_message(error: Exception) -> str:
    value = getattr(error, "message", None)
    return value if isinstance(value, str) and value else str(error)


def _vital_file_sort_key(
    item: dict[str, object],
) -> tuple[float, str]:
    value = item.get("uploadedAt")
    if value is None:
        value = item.get("receivedAt")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        timestamp = float(value)
    elif isinstance(value, str):
        try:
            timestamp = datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            timestamp = 0.0
    else:
        timestamp = 0.0
    return timestamp, str(item.get("fileID", ""))
