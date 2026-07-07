from __future__ import annotations

import json
import re
import subprocess
from datetime import UTC, datetime

from tirosh_guest_tools.adapters.outbound.runtime import collector as runtime_collector
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
from tirosh_guest_tools.domain.runtime_state import ProbeError, RuntimeResourceUsage
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

        container_memory = container_memory_usages()
        for state in states:
            if state.service == service:
                return ServiceStatus(
                    service=state.service,
                    container=state.container,
                    state=state.state,
                    health=state.health,
                    exit_code=state.exit_code,
                    observed_at=datetime.now(UTC),
                    memory=container_memory.get(state.container),
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
        probe_errors: list[ProbeError] = []
        container_memory = container_memory_usages()
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
                container_memory,
            )
            for service in sorted(available_services)
        ]
        return StackStatus(
            state="loaded",
            services=service_statuses,
            observed_at=observed_at,
            cpu_usage_percent=runtime_collector.cpu_usage_percent(probe_errors),
            memory=runtime_collector.memory_usage(probe_errors),
            system_disk=runtime_collector.disk_usage("/", probe_errors),
            vital_files_disk=runtime_collector.disk_usage(
                "/mnt/tirosh-vital-files",
                probe_errors,
            ),
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
        container_memory: dict[str, RuntimeResourceUsage],
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
            memory=container_memory.get(state.container),
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


def container_memory_usages() -> dict[str, RuntimeResourceUsage]:
    try:
        completed = subprocess.run(
            ["docker", "stats", "--no-stream", "--format", "{{json .}}"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if completed.returncode != 0:
        return {}

    usages: dict[str, RuntimeResourceUsage] = {}
    for line in completed.stdout.splitlines():
        if not line.strip():
            continue
        try:
            document = json.loads(line)
        except json.JSONDecodeError:
            continue
        name = str(document.get("Name") or "").strip()
        usage = resource_usage_from_docker_mem_usage(
            str(document.get("MemUsage") or "")
        )
        if name and usage is not None:
            usages[name] = usage
    return usages


def resource_usage_from_docker_mem_usage(value: str) -> RuntimeResourceUsage | None:
    parts = [part.strip() for part in value.split("/", maxsplit=1)]
    if len(parts) != 2:
        return None
    used = docker_size_to_bytes(parts[0])
    total = docker_size_to_bytes(parts[1])
    if used is None or total is None:
        return None
    return RuntimeResourceUsage(used_bytes=used, total_bytes=total)


def docker_size_to_bytes(value: str) -> int | None:
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B)", value.strip())
    if match is None:
        return None
    amount = float(match.group(1))
    unit = match.group(2)
    multipliers = {
        "B": 1,
        "kB": 1000,
        "KB": 1000,
        "KiB": 1024,
        "MB": 1000**2,
        "MiB": 1024**2,
        "GB": 1000**3,
        "GiB": 1024**3,
        "TB": 1000**4,
        "TiB": 1024**4,
        "PB": 1000**5,
        "PiB": 1024**5,
        "EB": 1000**6,
        "EiB": 1024**6,
    }
    multiplier = multipliers.get(unit)
    if multiplier is None:
        return None
    return int(amount * multiplier)
