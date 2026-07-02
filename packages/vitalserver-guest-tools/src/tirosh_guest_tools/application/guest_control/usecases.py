from __future__ import annotations

from collections.abc import Callable

from tirosh_guest_tools.application.guest_control.ports import (
    Clock,
    DatastoreRepairPort,
    OperationIdFactory,
    OperationRepository,
    ProductLabPort,
    RecorderIngressReadModelPort,
    RedisBackupPort,
    ServiceControlPort,
    UpdateActivationPort,
    UpdateShutdownPort,
    VitalDBReadModelPort,
)
from tirosh_guest_tools.domain.guest_control.models import (
    DatastoreRepairDependencyError,
    GuestControlDependencyError,
    OperationEvent,
    OperationFailure,
    ProductLabDependencyError,
    ProductLabReadModelResult,
    ProductLabSessionResult,
    ProductLabUploadResult,
    RecorderIngressDependencyError,
    RedisBackupDependencyError,
    RedisRestoreDependencyError,
    ServiceCommand,
    ServiceOperation,
    ServiceStatus,
    StackStatus,
    UpdateActivationDependencyError,
    UpdateShutdownDependencyError,
    UpdateShutdownResult,
    VitalDBReadModelDependencyError,
)
from tirosh_guest_tools.domain.guest_control.operation_policy import (
    accept_service_operation,
    fail_operation,
    finish_operation,
    start_operation,
)


class GuestControlUseCases:
    def __init__(
        self,
        *,
        service_control: ServiceControlPort,
        operations: OperationRepository,
        operation_ids: OperationIdFactory,
        clock: Clock,
        product_lab: ProductLabPort | None = None,
        vitaldb_read_model: VitalDBReadModelPort | None = None,
        recorder_ingress: RecorderIngressReadModelPort | None = None,
        redis_backup: RedisBackupPort | None = None,
        datastore_repair: DatastoreRepairPort | None = None,
        update_activation: UpdateActivationPort | None = None,
        update_shutdown: UpdateShutdownPort | None = None,
    ) -> None:
        self._service_control = service_control
        self._product_lab = product_lab
        self._vitaldb_read_model = vitaldb_read_model
        self._recorder_ingress = recorder_ingress
        self._redis_backup = redis_backup
        self._datastore_repair = datastore_repair
        self._update_activation = update_activation
        self._update_shutdown = update_shutdown
        self._operations = operations
        self._operation_ids = operation_ids
        self._clock = clock

    def capabilities(self) -> dict[str, object]:
        capabilities = [
            "services:list",
            "stack:status",
            "services:status",
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
                    "lab:vital-files",
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
            capabilities.append("recorder-ingress:status:get")

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
        dependencies = [
            _readiness_dependency(
                "operationRepository",
                "required",
                self._operations.check_ready,
            )
        ]

        if self._vitaldb_read_model is not None:
            dependencies.append(
                _readiness_dependency(
                    "vitaldbReadModel",
                    "configured",
                    self._vitaldb_read_model.check_ready,
                )
            )

        status = (
            "ready"
            if all(dependency["state"] == "ready" for dependency in dependencies)
            else "unavailable"
        )
        return {
            "status": status,
            "dependencies": dependencies,
        }

    def list_services(self) -> list[str]:
        return self._service_control.list_services()

    def get_service_status(self, service: str) -> ServiceStatus:
        status = self._service_control.get_service_status(service)
        self._operations.save_service_status_snapshot(status)
        return status

    def get_stack_status(self) -> StackStatus:
        status = self._service_control.get_stack_status()
        for service_status in status.services:
            self._operations.save_service_status_snapshot(service_status)
        return status

    def get_operation(self, operation_id: str) -> ServiceOperation | None:
        return self._operations.get(operation_id)

    def start_service(self, service: str) -> ServiceOperation:
        return self._run_service_operation(
            service=service,
            command=ServiceCommand.START,
            action=lambda: self._service_control.start_service(service),
        )

    def stop_service(self, service: str) -> ServiceOperation:
        return self._run_service_operation(
            service=service,
            command=ServiceCommand.STOP,
            action=lambda: self._service_control.stop_service(service),
        )

    def restart_service(self, service: str) -> ServiceOperation:
        return self._run_service_operation(
            service=service,
            command=ServiceCommand.RESTART,
            action=lambda: self._service_control.restart_service(service),
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
                self._operations.save_service_status_snapshot(service_status)
            return

        service_status = self._service_control.get_service_status(service)
        self._operations.save_service_status_snapshot(service_status)

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
        if self._product_lab is None:
            return {
                "state": "unavailable",
                "vitalFiles": [],
                "readError": "Product Lab adapter is unavailable.",
            }

        try:
            return self._product_lab.list_vital_files()
        except ProductLabDependencyError as error:
            return _lab_read_model_failed_document(error, collection="vitalFiles")

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

    def replay_lab_vital_file(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_session_operation(
            command=ServiceCommand.LAB_REPLAY_VITAL_FILE,
            action=lambda: self._require_product_lab().replay_vital_file(request),
        )

    def upload_lab_vital_file(self, request: dict[str, object]) -> dict[str, object]:
        return self._run_lab_upload_operation(
            command=ServiceCommand.LAB_UPLOAD_VITAL_FILE,
            action=lambda: self._require_product_lab().upload_vital_file(request),
        )

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

    def list_vitaldb_recorders(self) -> dict[str, object]:
        if self._vitaldb_read_model is None:
            return _vitaldb_read_model_unavailable_document(
                collection="recorders",
                message="VitalDB recorder read model adapter is unavailable.",
            )

        try:
            return self._vitaldb_read_model.recorders()
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_read_model_failed_document(error, collection="recorders")

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
            action=lambda: self._require_vitaldb_read_model().unhide_recorders(
                request
            ),
        )

    def delete_vitaldb_recorders(
        self,
        request: dict[str, object],
    ) -> dict[str, object]:
        return self._run_vitaldb_read_model_command(
            collection="recorders",
            action=lambda: self._require_vitaldb_read_model().delete_recorders(
                request
            ),
        )

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
            action=lambda: self._require_vitaldb_read_model().delete_beds(request),
        )

    def get_vitaldb_relationships(self) -> dict[str, object]:
        if self._vitaldb_read_model is None:
            return _vitaldb_relationship_unavailable_document(
                "VitalDB relationship read model adapter is unavailable."
            )

        try:
            return self._vitaldb_read_model.relationships()
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_relationship_failed_document(error)

    def get_recorder_ingress_status(self) -> dict[str, object]:
        if self._recorder_ingress is None:
            return _recorder_ingress_unavailable_document(
                "Recorder ingress status adapter is unavailable."
            )

        try:
            return self._recorder_ingress.status()
        except RecorderIngressDependencyError as error:
            return _recorder_ingress_failed_document(error)

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

        return self._operations.get(operation.operation_id) or running

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

    def _run_lab_upload_operation(
        self,
        *,
        command: ServiceCommand,
        action: Callable[[], ProductLabUploadResult],
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
            return _lab_upload_failed_document(error, operation=failed)

        completed = finish_operation(running, now=self._clock.now())
        self._save_operation_transition(completed)
        return _lab_upload_loaded_document(lab_result, operation=completed)

    def _run_vitaldb_read_model_command(
        self,
        *,
        collection: str,
        action: Callable[[], dict[str, object]],
    ) -> dict[str, object]:
        try:
            return action()
        except VitalDBReadModelDependencyError as error:
            return _vitaldb_read_model_failed_document(error, collection=collection)

    def _create_operation(self, operation: ServiceOperation) -> None:
        self._operations.create(operation)
        self._append_operation_event(operation)

    def _save_operation_transition(self, operation: ServiceOperation) -> None:
        self._operations.save(operation)
        self._append_operation_event(operation)

    def _append_operation_event(self, operation: ServiceOperation) -> None:
        self._operations.append_event(
            OperationEvent(
                operation_id=operation.operation_id,
                state=operation.state,
                observed_at=operation.updated_at,
                failure=operation.failure,
                result=operation.result,
            )
        )


def _readiness_dependency(
    name: str,
    role: str,
    check: Callable[[], None],
) -> dict[str, object]:
    try:
        check()
    except (GuestControlDependencyError, VitalDBReadModelDependencyError) as error:
        return {
            "name": name,
            "role": role,
            "state": "failed",
            "kind": error.kind,
            "message": error.message,
        }
    return {
        "name": name,
        "role": role,
        "state": "ready",
        "kind": None,
        "message": None,
    }


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


def _lab_upload_failed_document(
    error: ProductLabDependencyError,
    *,
    operation: ServiceOperation,
) -> dict[str, object]:
    state = "unavailable" if error.kind == "product-lab-unavailable" else "failed"
    return {
        "state": state,
        "upload": None,
        "operationId": operation.operation_id,
        "labOperationId": None,
        "readError": error.message,
    }


def _lab_upload_loaded_document(
    lab_result: ProductLabUploadResult,
    *,
    operation: ServiceOperation,
) -> dict[str, object]:
    document = dict(lab_result.document)
    document["operationId"] = operation.operation_id
    document["labOperationId"] = lab_result.lab_operation_id
    if "upload" not in document:
        document["upload"] = None
    return document


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
        "unavailable"
        if error.kind == "vitaldb-read-model-unavailable"
        else "failed"
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
    state = (
        "unavailable"
        if error.kind == "vitaldb-read-model-unavailable"
        else "failed"
    )
    return {
        "state": state,
        collection: [],
        "observedAt": None,
        "readError": error.message,
    }


def _vitaldb_relationship_unavailable_document(message: str) -> dict[str, object]:
    return {
        "state": "unavailable",
        "assignments": [],
        "events": [],
        "readError": message,
    }


def _vitaldb_relationship_failed_document(
    error: VitalDBReadModelDependencyError,
) -> dict[str, object]:
    state = (
        "unavailable"
        if error.kind == "vitaldb-read-model-unavailable"
        else "failed"
    )
    return {
        "state": state,
        "assignments": [],
        "events": [],
        "readError": error.message,
    }


def _recorder_ingress_unavailable_document(message: str) -> dict[str, object]:
    return {
        "readState": "readFailed",
        "httpStatus": "unavailable",
        "document": None,
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
