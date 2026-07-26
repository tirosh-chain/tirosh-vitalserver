from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from typing import Any, BinaryIO, Protocol

from tirosh_guest_tools.domain.guest_control.models import (
    GuestServiceResource,
    OperationLease,
    PostgresBackupResult,
    PostgresRestoreResult,
    ProductLabReadModelResult,
    ProductLabRecorderResult,
    ProductLabSessionResult,
    RedisBackupResult,
    RedisRestoreResult,
    ServiceOperation,
    ServiceStatus,
    StackStatus,
    UpdateActivationResult,
    UpdateShutdownDependencyError,
    UpdateShutdownResult,
    VitalFileUploadResult,
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

    def list_sessions(self) -> dict[str, Any]:
        raise NotImplementedError

    def create_session(self, request: dict[str, Any]) -> ProductLabSessionResult:
        raise NotImplementedError

    def get_session(self, session_id: str) -> ProductLabSessionResult:
        raise NotImplementedError

    def start_session(self, session_id: str) -> ProductLabSessionResult:
        raise NotImplementedError

    def stop_session(self, session_id: str) -> ProductLabSessionResult:
        raise NotImplementedError

    def finish_session(self, session_id: str) -> ProductLabSessionResult:
        raise NotImplementedError

    def delete_session(self, session_id: str) -> ProductLabReadModelResult:
        raise NotImplementedError

    def replay_vital_file(self, request: dict[str, Any]) -> ProductLabSessionResult:
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

    def start_recorder(
        self, session_id: str, recorder_id: str
    ) -> ProductLabRecorderResult:
        raise NotImplementedError

    def stop_recorder(
        self, session_id: str, recorder_id: str
    ) -> ProductLabRecorderResult:
        raise NotImplementedError


class VitalFileUploadSource(Protocol):
    @property
    def file_name(self) -> str:
        """Return the untrusted client-supplied basename."""
        raise NotImplementedError

    @property
    def size_bytes(self) -> int:
        """Return the explicit compressed source size."""
        raise NotImplementedError

    def open(self) -> BinaryIO:
        """Open a new binary stream owned by the caller."""
        raise NotImplementedError


class VitalFileLibraryPort(Protocol):
    def list_files(self) -> list[dict[str, object]]:
        """Read the authoritative VitalServer indexed file collection."""
        raise NotImplementedError

    def import_sources(
        self,
        sources: list[VitalFileUploadSource],
    ) -> VitalFileUploadResult:
        """Upload every independently valid file and report per-file outcomes."""
        raise NotImplementedError


class VitalDBReadModelPort(Protocol):
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

    def relationships(self, *, event_limit: int) -> dict[str, Any]:
        raise NotImplementedError


class RecorderIngressReadModelPort(Protocol):
    def status(self) -> dict[str, Any]:
        raise NotImplementedError

    def native_vital_uploads(self) -> dict[str, Any]:
        raise NotImplementedError

    def recorder_observability(self) -> dict[str, Any]:
        raise NotImplementedError

    def recorder_observability_detail(self, vrcode: str) -> dict[str, Any]:
        raise NotImplementedError

    def recorder_observability_timeline(
        self,
        vrcode: str,
        query: dict[str, str],
    ) -> dict[str, Any]:
        raise NotImplementedError

    def recorder_observability_incidents(
        self,
        vrcode: str,
        query: dict[str, str],
    ) -> dict[str, Any]:
        raise NotImplementedError

    def apply_recorder_observability_expectation(
        self,
        command: dict[str, Any],
    ) -> dict[str, Any]:
        raise NotImplementedError


class RecorderRecoveryReadModelPort(Protocol):
    def list_artifacts(self) -> dict[str, Any]:
        raise NotImplementedError


class RedisRelayReadModelPort(Protocol):
    def status(self) -> dict[str, Any]:
        raise NotImplementedError

    def save_status(self, document: dict[str, Any]) -> None:
        raise NotImplementedError


class RuntimeSettingsPort(Protocol):
    def read(self) -> dict[str, Any]:
        raise NotImplementedError

    def save(self, settings: dict[str, Any]) -> None:
        raise NotImplementedError


class RuntimeAdminPort(Protocol):
    def replace_admin_password(self, password: str) -> None:
        raise NotImplementedError


class RedisRelaySettingsPort(Protocol):
    def read(self) -> dict[str, object]:
        raise NotImplementedError

    def save(self, settings: dict[str, object]) -> None:
        raise NotImplementedError


class RedisBackupPort(Protocol):
    def create_backup(self) -> RedisBackupResult:
        raise NotImplementedError

    def restore_backup(self, archive: str) -> RedisRestoreResult:
        raise NotImplementedError


class PostgresBackupPort(Protocol):
    def create_backup(self) -> PostgresBackupResult:
        raise NotImplementedError

    def restore_backup(
        self,
        archive: str,
        *,
        restart_runtime: bool,
    ) -> PostgresRestoreResult:
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


class ServiceStatusSnapshotRepository(Protocol):
    def save_service_status_snapshot(self, status: ServiceStatus) -> None:
        raise NotImplementedError


class GuestServiceResourceRepository(Protocol):
    def save_guest_service_resource(self, resource: GuestServiceResource) -> None:
        raise NotImplementedError

    def get_guest_service_resource(self, service: str) -> GuestServiceResource | None:
        raise NotImplementedError


class OperationRepository(Protocol):
    def check_ready(self) -> None:
        raise NotImplementedError

    def record_accepted(
        self,
        operation: ServiceOperation,
        *,
        lease: OperationLease,
    ) -> None:
        raise NotImplementedError

    def record_transition(
        self,
        operation: ServiceOperation,
    ) -> None:
        raise NotImplementedError

    def list_unfinished_operations(self) -> list[ServiceOperation]:
        raise NotImplementedError

    def get(self, operation_id: str) -> ServiceOperation | None:
        raise NotImplementedError

    def query_events(
        self,
        *,
        limit: int,
        event_type: str | None,
        since: datetime | None,
        cursor: str | None,
    ) -> dict[str, Any]:
        raise NotImplementedError
