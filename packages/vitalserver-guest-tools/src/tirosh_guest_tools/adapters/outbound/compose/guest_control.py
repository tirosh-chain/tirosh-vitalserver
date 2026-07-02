from __future__ import annotations

from datetime import UTC, datetime

from tirosh_guest_tools.application import compose as compose_app
from tirosh_guest_tools.application.runtime_state import write_current_state
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    ServiceNotFoundError,
    ServiceStatus,
    StackStatus,
)
from tirosh_guest_tools.domain.operations import ComposeAction
from tirosh_guest_tools.infrastructure.common import systemctl


class ComposeGuestControlAdapter:
    def list_services(self) -> list[str]:
        return sorted(compose_app.compose_services())

    def get_service_status(self, service: str) -> ServiceStatus:
        available_services = self.list_services()
        if service not in available_services:
            raise ServiceNotFoundError(
                service,
                available_services=available_services,
            )

        try:
            states = compose_app.inspect_compose_service_states()
        except GuestDependencyError as error:
            raise GuestControlDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise GuestControlDependencyError(
                f"guest stack status read failed: {error}",
                kind="guest-stack-status-read-failed",
            ) from error

        for state in states:
            if state.service == service:
                return ServiceStatus(
                    service=state.service,
                    container=state.container,
                    state=state.state,
                    health=state.health,
                    exit_code=state.exit_code,
                    observed_at=datetime.now(UTC),
                )

        return ServiceStatus(
            service=service,
            state="absent",
            health="not_reported",
            observed_at=datetime.now(UTC),
        )

    def get_stack_status(self) -> StackStatus:
        available_services = self.list_services()
        observed_at = datetime.now(UTC)
        try:
            states = compose_app.inspect_compose_service_states()
        except GuestDependencyError as error:
            raise GuestControlDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise GuestControlDependencyError(
                f"guest stack status read failed: {error}",
                kind="guest-stack-status-read-failed",
            ) from error

        states_by_service = {state.service: state for state in states}
        service_statuses = [
            self._service_status_from_state(
                service,
                states_by_service.get(service),
                observed_at,
            )
            for service in sorted(available_services)
        ]
        return StackStatus(
            state="loaded",
            services=service_statuses,
            observed_at=observed_at,
        )

    def start_service(self, service: str) -> None:
        self._run_service_command(service, "start")

    def stop_service(self, service: str) -> None:
        self._run_service_command(service, "stop")

    def restart_service(self, service: str) -> None:
        self._run_service_command(service, "restart")

    def reconcile_services(self) -> None:
        try:
            compose_app.run_compose_action(ComposeAction.UP)
            systemctl("restart", RuntimeService.CONTAINER_LOGS.value, check=False)
            systemctl("restart", RuntimeService.RUNTIME_STATE.value, check=False)
            write_current_state()
        except GuestDependencyError as error:
            raise GuestControlDependencyError(
                error.message,
                kind=error.code,
            ) from error

    def _service_status_from_state(
        self,
        service: str,
        state: compose_app.ComposeServiceState | None,
        observed_at: datetime,
    ) -> ServiceStatus:
        if state is None:
            return ServiceStatus(
                service=service,
                state="absent",
                health="not_reported",
                observed_at=observed_at,
            )
        return ServiceStatus(
            service=state.service,
            container=state.container,
            state=state.state,
            health=state.health,
            exit_code=state.exit_code,
            observed_at=observed_at,
        )

    def _run_service_command(self, service: str, command: str) -> None:
        available_services = self.list_services()
        if service not in available_services:
            raise ServiceNotFoundError(
                service,
                available_services=available_services,
            )
        try:
            compose_app.checked_compose(
                [command, service],
                stage=f"{service} service {command}",
            )
        except GuestDependencyError as error:
            raise GuestControlDependencyError(
                error.message,
                kind=error.code,
            ) from error
