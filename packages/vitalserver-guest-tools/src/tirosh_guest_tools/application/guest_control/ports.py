from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from typing import Any, Protocol

from tirosh_guest_tools.domain.guest_control.models import (
    GuestServiceResource,
    OperationEvent,
    ProductLabReadModelResult,
    ProductLabSessionResult,
    ProductLabUploadResult,
    RedisBackupResult,
    RedisRestoreResult,
    ServiceOperation,
    ServiceStatus,
    StackStatus,
    UpdateActivationResult,
    UpdateShutdownDependencyError,
    UpdateShutdownResult,
)


class Clock(Protocol):
    def now(self) -> datetime:
        raise NotImplementedError


class OperationIdFactory(Protocol):
    def new_operation_id(self, *, service: str, command: str) -> str:
        raise NotImplementedError


class ServiceControlPort(Protocol):
    def list_services(self) -> list[str]:
        raise NotImplementedError

    def get_service_status(self, service: str) -> ServiceStatus:
        raise NotImplementedError

    def get_stack_status(self) -> StackStatus:
        raise NotImplementedError

    def start_service(self, service: str) -> None:
        raise NotImplementedError

    def stop_service(self, service: str) -> None:
        raise NotImplementedError

    def restart_service(self, service: str) -> None:
        raise NotImplementedError

    def reconcile_services(self) -> None:
        raise NotImplementedError


class ProductLabPort(Protocol):
    def list_scenarios(self) -> dict[str, Any]:
        raise NotImplementedError

    def list_vital_files(self) -> dict[str, Any]:
        raise NotImplementedError

    def list_beds(self) -> dict[str, Any]:
        raise NotImplementedError

    def list_recorders(self) -> dict[str, Any]:
        raise NotImplementedError

    def create_session(self, request: dict[str, Any]) -> ProductLabSessionResult:
        raise NotImplementedError

    def get_session(self, session_id: str) -> ProductLabSessionResult:
        raise NotImplementedError

    def start_session(self, session_id: str) -> ProductLabSessionResult:
        raise NotImplementedError

    def stop_session(self, session_id: str) -> ProductLabSessionResult:
        raise NotImplementedError

    def replay_vital_file(self, request: dict[str, Any]) -> ProductLabSessionResult:
        raise NotImplementedError

    def upload_vital_file(self, request: dict[str, Any]) -> ProductLabUploadResult:
        raise NotImplementedError

    def create_beds(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        raise NotImplementedError

    def delete_beds(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        raise NotImplementedError

    def reset_beds(self) -> ProductLabReadModelResult:
        raise NotImplementedError

    def create_recorders(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        raise NotImplementedError

    def delete_recorders(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        raise NotImplementedError

    def reset_recorders(self) -> ProductLabReadModelResult:
        raise NotImplementedError


class VitalDBReadModelPort(Protocol):
    def check_ready(self) -> None:
        raise NotImplementedError

    def latest_observation(self) -> dict[str, Any]:
        raise NotImplementedError

    def recorders(self) -> dict[str, Any]:
        raise NotImplementedError

    def hide_recorders(self, request: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def unhide_recorders(self, request: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def delete_recorders(self, request: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def recorder_activity(self, vrcode: str) -> dict[str, Any]:
        raise NotImplementedError

    def beds(self) -> dict[str, Any]:
        raise NotImplementedError

    def hide_beds(self, request: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def unhide_beds(self, request: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def delete_beds(self, request: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def relationships(self) -> dict[str, Any]:
        raise NotImplementedError


class RecorderIngressReadModelPort(Protocol):
    def status(self) -> dict[str, Any]:
        raise NotImplementedError


class RedisBackupPort(Protocol):
    def create_backup(self) -> RedisBackupResult:
        raise NotImplementedError

    def restore_backup(self, archive: str) -> RedisRestoreResult:
        raise NotImplementedError


class DatastoreRepairPort(Protocol):
    def repair_datastore(self) -> None:
        raise NotImplementedError


class UpdateActivationPort(Protocol):
    def activate_update(
        self,
        *,
        request_id: str,
        version: str,
    ) -> UpdateActivationResult:
        raise NotImplementedError


class UpdateShutdownPort(Protocol):
    def prepare_update_shutdown(
        self,
        *,
        request_id: str,
        version: str,
        on_ready: Callable[[UpdateShutdownResult], None],
        on_failure: Callable[[UpdateShutdownDependencyError], None],
    ) -> None:
        raise NotImplementedError

    def request_poweroff(self) -> None:
        raise NotImplementedError


class OperationRepository(Protocol):
    def check_ready(self) -> None:
        raise NotImplementedError

    def create(self, operation: ServiceOperation) -> None:
        raise NotImplementedError

    def save(self, operation: ServiceOperation) -> None:
        raise NotImplementedError

    def append_event(self, event: OperationEvent) -> None:
        raise NotImplementedError

    def save_service_status_snapshot(self, status: ServiceStatus) -> None:
        raise NotImplementedError

    def save_guest_service_resource(self, resource: GuestServiceResource) -> None:
        raise NotImplementedError

    def get_guest_service_resource(self, service: str) -> GuestServiceResource | None:
        raise NotImplementedError

    def get(self, operation_id: str) -> ServiceOperation | None:
        raise NotImplementedError
