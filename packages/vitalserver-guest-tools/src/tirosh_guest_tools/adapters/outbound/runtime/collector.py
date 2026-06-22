from __future__ import annotations

import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.runtime.probes import append_probe_error
from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    ProbeError,
    RuntimeContainerService,
    RuntimeDiskHealth,
    RuntimeHTTPProbeStatus,
    RuntimeResourceUsage,
)
from tirosh_guest_tools.infrastructure.common import DEPLOY_DIR, PROJECT_NAME
from tirosh_guest_tools.infrastructure.settings import SETTINGS

VITALDB_OBSERVER_ENDPOINT = SETTINGS.observability.vitaldb_observer_url
GUEST_READY_URL = "http://127.0.0.1/ready"
REDIS_UI_URL = "http://127.0.0.1/redis-ui/"
SWAGGER_UI_URL = "http://127.0.0.1/swagger/"


@dataclass(frozen=True)
class ContainerInspection:
    container_id: str | None
    error: str | None
    finished_at: str | None
    memory_limit_bytes: int | None
    oom_killed: bool | None
    restart_count: int | None
    started_at: str | None


def collect_runtime_state(
    *,
    guest_http: RuntimeHTTPProbeStatus | str | None = None,
    redis_ui_http: RuntimeHTTPProbeStatus | str | None = None,
    swagger_ui_http: RuntimeHTTPProbeStatus | str | None = None,
) -> GuestRuntimeState:
    probe_errors: list[ProbeError] = []
    return GuestRuntimeState(
        updated_at=datetime.now(UTC).isoformat(),
        vm_ip=first_non_loopback_ip(probe_errors),
        boot_id=boot_id(probe_errors),
        container_services=compose_services(probe_errors),
        cpu_usage_percent=cpu_usage_percent(probe_errors),
        guest_http=runtime_http_status(
            guest_http,
            "guestHTTP",
            GUEST_READY_URL,
            probe_errors,
        ),
        memory=memory_usage(probe_errors),
        probe_errors=tuple(probe_errors),
        redis_ui_http=runtime_http_status(
            redis_ui_http,
            "redisUIHTTP",
            REDIS_UI_URL,
            probe_errors,
        ),
        system_disk=disk_usage("/", probe_errors),
        disk_health=disk_health(probe_errors),
        swagger_ui_http=runtime_http_status(
            swagger_ui_http,
            "swaggerUIHTTP",
            SWAGGER_UI_URL,
            probe_errors,
        ),
        vital_files_disk=disk_usage("/mnt/tirosh-vital-files", probe_errors),
        vitaldb_observation=vitaldb_observation(probe_errors),
    )


def runtime_http_status(
    provided: RuntimeHTTPProbeStatus | str | None,
    source: str,
    url: str,
    probe_errors: list[ProbeError],
) -> RuntimeHTTPProbeStatus | None:
    if isinstance(provided, RuntimeHTTPProbeStatus):
        return provided
    if provided is not None:
        return RuntimeHTTPProbeStatus.from_status_text(provided)
    return http_status(source, url, probe_errors)


def http_status(
    source: str,
    url: str,
    probe_errors: list[ProbeError],
) -> RuntimeHTTPProbeStatus:
    completed = subprocess.run(
        [
            "curl",
            "-sS",
            "-I",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "--max-time",
            "5",
            url,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    status = completed.stdout.strip()
    if completed.returncode == 0:
        return RuntimeHTTPProbeStatus(status=status or None)
    message = completed.stderr.strip() or f"curl exited with {completed.returncode}"
    append_probe_error(probe_errors, source, message)
    return RuntimeHTTPProbeStatus(
        status="failed",
        failed=True,
        message=message,
        exit_code=completed.returncode,
    )


def first_non_loopback_ip(probe_errors: list[ProbeError]) -> str | None:
    try:
        output = subprocess.check_output(
            ["hostname", "-I"], stderr=subprocess.DEVNULL, text=True
        )
        for candidate in output.split():
            if not candidate.startswith(("127.", "169.254.")):
                return candidate
    except (OSError, subprocess.CalledProcessError) as error:
        append_probe_error(probe_errors, "hostname -I", error)
    try:
        for candidate in socket.gethostbyname_ex(socket.gethostname())[2]:
            if not candidate.startswith(("127.", "169.254.")):
                return candidate
    except socket.gaierror as error:
        append_probe_error(probe_errors, "socket.gethostbyname_ex", error)
    append_probe_error(probe_errors, "vmIP", "no non-loopback IP address found")
    return None


def boot_id(probe_errors: list[ProbeError]) -> str | None:
    path = Path("/proc/sys/kernel/random/boot_id")
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        append_probe_error(probe_errors, str(path), "missing")
        return None
    except OSError as error:
        append_probe_error(probe_errors, str(path), error)
        return None


def read_proc_stat(probe_errors: list[ProbeError]) -> tuple[int, int] | None:
    try:
        fields = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0]
        values = [int(value) for value in fields.split()[1:]]
    except (OSError, IndexError, ValueError) as error:
        append_probe_error(probe_errors, "/proc/stat", error)
        return None
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return idle, sum(values)


def cpu_usage_percent(probe_errors: list[ProbeError]) -> float | None:
    first = read_proc_stat(probe_errors)
    if first is None:
        return None
    time.sleep(0.1)
    second = read_proc_stat(probe_errors)
    if second is None:
        return None
    idle_delta = second[0] - first[0]
    total_delta = second[1] - first[1]
    if total_delta <= 0:
        return None
    return round(max(0.0, min(100.0, (1.0 - (idle_delta / total_delta)) * 100.0)), 1)


def memory_usage(probe_errors: list[ProbeError]) -> RuntimeResourceUsage | None:
    values: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            key, raw_value = line.split(":", 1)
            values[key] = int(raw_value.strip().split()[0]) * 1024
    except (OSError, IndexError, ValueError) as error:
        append_probe_error(probe_errors, "/proc/meminfo", error)
        return None
    total = values.get("MemTotal")
    available = values.get("MemAvailable")
    if total is None or available is None:
        append_probe_error(
            probe_errors,
            "/proc/meminfo",
            "missing MemTotal or MemAvailable",
        )
        return None
    return RuntimeResourceUsage(used_bytes=max(total - available, 0), total_bytes=total)


def disk_usage(
    path: str,
    probe_errors: list[ProbeError],
) -> RuntimeResourceUsage | None:
    try:
        stats = os.statvfs(path)
    except OSError as error:
        append_probe_error(probe_errors, path, error)
        return None
    total = stats.f_frsize * stats.f_blocks
    available = stats.f_frsize * stats.f_bavail
    return RuntimeResourceUsage(used_bytes=max(total - available, 0), total_bytes=total)


def disk_health(probe_errors: list[ProbeError]) -> RuntimeDiskHealth:
    return RuntimeDiskHealth(
        root_filesystem_read_only=root_filesystem_read_only(probe_errors),
        kernel_errors=kernel_disk_errors(probe_errors),
    )


def root_filesystem_read_only(probe_errors: list[ProbeError]) -> bool | None:
    try:
        text = Path("/proc/mounts").read_text(encoding="utf-8")
    except OSError as error:
        append_probe_error(probe_errors, "/proc/mounts", error)
        return None
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[1] == "/":
            return "ro" in parts[3].split(",")
    append_probe_error(probe_errors, "/proc/mounts", "root mount missing")
    return None


def kernel_disk_errors(probe_errors: list[ProbeError]) -> tuple[str, ...] | None:
    try:
        completed = subprocess.run(
            ["dmesg", "--ctime"],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        append_probe_error(probe_errors, "dmesg", error)
        return None
    if completed.returncode != 0:
        append_probe_error(
            probe_errors,
            "dmesg",
            completed.stderr.strip() or f"exit {completed.returncode}",
        )
        return None
    return tuple(
        line
        for line in completed.stdout.splitlines()[-300:]
        if kernel_disk_error_line(line)
    )


def kernel_disk_error_line(line: str) -> bool:
    lowered = line.lower()
    return (
        "ext4-fs error" in lowered
        or "buffer i/o error" in lowered
        or "metadata checksum" in lowered
        or "checksum invalid" in lowered
        or "remounting filesystem read-only" in lowered
    )


def vitaldb_observation(probe_errors: list[ProbeError]) -> dict[str, object] | None:
    try:
        with urllib.request.urlopen(VITALDB_OBSERVER_ENDPOINT, timeout=5) as response:
            payload = response.read().decode("utf-8")
    except (OSError, urllib.error.URLError) as error:
        append_probe_error(probe_errors, "vitalDBObservation", error)
        return None
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        append_probe_error(probe_errors, "vitalDBObservation", error)
        return None
    if not isinstance(value, dict):
        append_probe_error(probe_errors, "vitalDBObservation", "expected JSON object")
        return None
    return value


def compose_services(
    probe_errors: list[ProbeError],
) -> list[RuntimeContainerService] | None:
    compose_path = DEPLOY_DIR / RuntimeFileName.COMPOSE.value
    if not compose_path.is_file():
        append_probe_error(probe_errors, str(compose_path), "missing")
        return None
    command = [
        "docker",
        "compose",
        "--project-name",
        PROJECT_NAME,
        "-f",
        str(compose_path),
        "ps",
        "--all",
        "--format",
        "json",
    ]
    try:
        output = subprocess.check_output(command, stderr=subprocess.DEVNULL, text=True)
    except (OSError, subprocess.CalledProcessError) as error:
        append_probe_error(probe_errors, "docker compose ps", error)
        return None
    documents = parse_compose_documents(output)
    if not documents:
        append_probe_error(
            probe_errors,
            "docker compose ps",
            "no service documents reported",
        )
        return None
    services: list[RuntimeContainerService] = []
    now = datetime.now(UTC)
    for item in documents:
        service = string_value(item.get("Service")) or string_value(item.get("Name"))
        if service is None:
            continue
        inspection = container_inspection(item, probe_errors)
        started_at = None if inspection is None else inspection.started_at
        services.append(
            RuntimeContainerService(
                service=service,
                container_id=container_id(item, inspection),
                exit_code=normalized_exit_code(item.get("ExitCode")),
                error=None if inspection is None else inspection.error,
                finished_at=None if inspection is None else inspection.finished_at,
                health=string_value(item.get("Health")),
                memory_limit_bytes=(
                    None if inspection is None else inspection.memory_limit_bytes
                ),
                name=string_value(item.get("Name")),
                oom_killed=None if inspection is None else inspection.oom_killed,
                restart_count=None if inspection is None else inspection.restart_count,
                started_at=started_at,
                state=string_value(item.get("State")),
                uptime_seconds=uptime_seconds(started_at, now),
            )
        )
    return services


def parse_compose_documents(output: str) -> list[dict[str, object]]:
    try:
        parsed = json.loads(output)
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
        if isinstance(parsed, dict):
            return [parsed]
    except json.JSONDecodeError:
        pass
    documents: list[dict[str, object]] = []
    for line in output.splitlines():
        try:
            parsed_line = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed_line, dict):
            documents.append(parsed_line)
    return documents


def normalized_exit_code(value: object) -> int | None:
    if value in (None, ""):
        return None
    if not isinstance(value, str | int | float | bytes | bytearray):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def string_value(value: object) -> str | None:
    if value is None:
        return None
    return str(value)


def container_inspection(
    item: dict[str, object],
    probe_errors: list[ProbeError],
) -> ContainerInspection | None:
    identifier = string_value(item.get("ID")) or string_value(item.get("Name"))
    if identifier is None:
        append_probe_error(
            probe_errors,
            "docker inspect",
            "missing container identifier",
        )
        return None
    try:
        output = subprocess.check_output(
            ["docker", "inspect", identifier],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        append_probe_error(probe_errors, f"docker inspect {identifier}", error)
        return None
    try:
        documents = json.loads(output)
    except json.JSONDecodeError as error:
        append_probe_error(probe_errors, f"docker inspect {identifier}", error)
        return None
    if not isinstance(documents, list) or not documents:
        append_probe_error(
            probe_errors,
            f"docker inspect {identifier}",
            "expected non-empty JSON list",
        )
        return None
    document = documents[0]
    if not isinstance(document, dict):
        append_probe_error(
            probe_errors,
            f"docker inspect {identifier}",
            "expected JSON object",
        )
        return None
    state = document.get("State")
    host_config = document.get("HostConfig")
    state_document = state if isinstance(state, dict) else {}
    host_config_document = host_config if isinstance(host_config, dict) else {}
    return ContainerInspection(
        container_id=string_value(document.get("Id")),
        error=string_value(state_document.get("Error")),
        finished_at=timestamp_value(state_document.get("FinishedAt")),
        memory_limit_bytes=normalized_integer(host_config_document.get("Memory")),
        oom_killed=bool_value(state_document.get("OOMKilled")),
        restart_count=normalized_integer(document.get("RestartCount")),
        started_at=timestamp_value(state_document.get("StartedAt")),
    )


def container_id(
    item: dict[str, object],
    inspection: ContainerInspection | None,
) -> str | None:
    if inspection is not None and inspection.container_id is not None:
        return inspection.container_id
    return string_value(item.get("ID"))


def timestamp_value(value: object) -> str | None:
    text = string_value(value)
    if not text or text.startswith("0001-01-01"):
        return None
    return text


def normalized_integer(value: object) -> int | None:
    if value in (None, ""):
        return None
    if not isinstance(value, str | int | float | bytes | bytearray):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def bool_value(value: object) -> bool | None:
    if isinstance(value, bool):
        return value
    return None


def uptime_seconds(started_at: str | None, now: datetime) -> int | None:
    if not started_at:
        return None
    try:
        started = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
    except ValueError:
        return None
    return max(int((now - started).total_seconds()), 0)
