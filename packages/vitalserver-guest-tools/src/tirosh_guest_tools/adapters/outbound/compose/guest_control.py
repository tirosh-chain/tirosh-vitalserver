from __future__ import annotations

import json
import re
import subprocess
from datetime import UTC, datetime
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.runtime import collector as runtime_collector
from tirosh_guest_tools.adapters.outbound.runtime.probes import append_probe_error
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

DOCKER_INSPECT_TIMEOUT_SECONDS = 1
CGROUP_ROOT = Path("/sys/fs/cgroup")


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
                container_memory = container_memory_usages([], [state.container])
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
        container_names = [
            state.container
            for state in states
            if state.container
        ]
        container_memory = container_memory_usages(probe_errors, container_names)

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
            probe_errors=probe_errors,
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


def container_memory_usages(
    probe_errors: list[ProbeError],
    container_names: list[str],
) -> dict[str, RuntimeResourceUsage]:
    if not container_names:
        return {}
    try:
        completed = subprocess.run(
            [
                "docker",
                "inspect",
                "--format",
                "{{json .}}",
                *container_names,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=DOCKER_INSPECT_TIMEOUT_SECONDS,
        )
    except OSError as error:
        append_probe_error(probe_errors, "docker inspect memory", error)
        return {}
    except subprocess.TimeoutExpired as error:
        append_probe_error(probe_errors, "docker inspect memory", error)
        return {}
    if completed.returncode != 0:
        append_probe_error(
            probe_errors,
            "docker inspect memory",
            completed.stderr.strip() or f"exit code {completed.returncode}",
        )
        return {}

    usages: dict[str, RuntimeResourceUsage] = {}
    for line in completed.stdout.splitlines():
        if not line.strip():
            continue
        try:
            document = json.loads(line)
        except json.JSONDecodeError as error:
            append_probe_error(probe_errors, "docker inspect memory", error)
            continue
        name = docker_inspect_container_name(document)
        if not name:
            append_probe_error(
                probe_errors,
                "docker inspect memory",
                "container name missing",
            )
            continue
        usage = resource_usage_from_docker_inspect(document)
        if usage is None:
            continue
        usages[name] = usage
    return usages


def docker_inspect_container_name(document: dict[str, object]) -> str:
    name = str(document.get("Name") or "").strip().lstrip("/")
    if name:
        return name
    config = document.get("Config")
    if isinstance(config, dict):
        hostname = str(config.get("Hostname") or "").strip()
        if hostname:
            return hostname
    return ""


def resource_usage_from_docker_inspect(
    document: dict[str, object],
) -> RuntimeResourceUsage | None:
    state = document.get("State")
    if not isinstance(state, dict):
        return None
    pid = state.get("Pid")
    if not isinstance(pid, int) or pid <= 0:
        return None

    cgroup_path = memory_cgroup_path(pid)
    if cgroup_path is None:
        return None

    used = read_cgroup_int(cgroup_path / "memory.current")
    if used is None:
        return None
    total = read_cgroup_memory_limit(cgroup_path / "memory.max")
    if total is None:
        total = docker_inspect_memory_limit(document)
    if total is None:
        return None
    return RuntimeResourceUsage(used_bytes=used, total_bytes=total)


def memory_cgroup_path(pid: int) -> Path | None:
    try:
        cgroup_lines = Path(f"/proc/{pid}/cgroup").read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for line in cgroup_lines:
        parts = line.split(":", maxsplit=2)
        if len(parts) != 3:
            continue
        controllers = parts[1].split(",")
        if parts[1] == "" or "memory" in controllers:
            relative = parts[2].lstrip("/")
            path = CGROUP_ROOT / relative
            if (path / "memory.current").exists():
                return path
    return None


def read_cgroup_int(path: Path) -> int | None:
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def read_cgroup_memory_limit(path: Path) -> int | None:
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if value == "max":
        return None
    try:
        return int(value)
    except ValueError:
        return None


def docker_inspect_memory_limit(document: dict[str, object]) -> int | None:
    host_config = document.get("HostConfig")
    if not isinstance(host_config, dict):
        return None
    memory = host_config.get("Memory")
    if isinstance(memory, int) and memory > 0:
        return memory
    return None


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
