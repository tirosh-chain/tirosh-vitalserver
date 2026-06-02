from __future__ import annotations

import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

from tirosh_guest_tools.common import DEPLOY_DIR, PROJECT_NAME
from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.runtime.probes import ProbeError, append_probe_error
from tirosh_guest_tools.settings import SETTINGS

VITALDB_OBSERVER_ENDPOINT = SETTINGS.observability.vitaldb_observer_url


def write_runtime_state(
    runtime_state: Path,
    *,
    guest_http: str | None = None,
    redis_ui_http: str | None = None,
    swagger_ui_http: str | None = None,
) -> None:
    document = runtime_state_document(
        guest_http=guest_http,
        redis_ui_http=redis_ui_http,
        swagger_ui_http=swagger_ui_http,
    )
    runtime_state.parent.mkdir(parents=True, exist_ok=True)
    runtime_state.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def runtime_state_document(
    *,
    guest_http: str | None = None,
    redis_ui_http: str | None = None,
    swagger_ui_http: str | None = None,
) -> dict[str, object]:
    probe_errors: list[ProbeError] = []
    return {
        "capabilities": {
            "activateUpdate": True,
            "prepareUpdateShutdown": True,
            "redisBackup": True,
            "repairDatastore": True,
        },
        "schemaVersion": 1,
        "vmIP": first_non_loopback_ip(probe_errors),
        "bootID": boot_id(probe_errors),
        "containerServices": compose_services(probe_errors),
        "cpuUsagePercent": cpu_usage_percent(probe_errors),
        "guestHTTP": optional_value(guest_http),
        "memory": memory_usage(probe_errors),
        "probeErrors": [error.as_json() for error in probe_errors],
        "redisUIHTTP": optional_value(redis_ui_http),
        "systemDisk": disk_usage("/", probe_errors),
        "swaggerUIHTTP": optional_value(swagger_ui_http),
        "updatedAt": datetime.now(UTC).isoformat(),
        "vitalFilesDisk": disk_usage("/mnt/tirosh-vital-files", probe_errors),
        "vitalDBObservation": vitaldb_observation(probe_errors),
    }


def optional_value(value: str | None) -> str | None:
    return value if value else None


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


def memory_usage(probe_errors: list[ProbeError]) -> dict[str, int] | None:
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
    return {"usedBytes": max(total - available, 0), "totalBytes": total}


def disk_usage(path: str, probe_errors: list[ProbeError]) -> dict[str, int] | None:
    try:
        stats = os.statvfs(path)
    except OSError as error:
        append_probe_error(probe_errors, path, error)
        return None
    total = stats.f_frsize * stats.f_blocks
    available = stats.f_frsize * stats.f_bavail
    return {"usedBytes": max(total - available, 0), "totalBytes": total}


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
) -> list[dict[str, object]] | None:
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
        "--format",
        "json",
    ]
    try:
        output = subprocess.check_output(command, stderr=subprocess.DEVNULL, text=True)
    except (OSError, subprocess.CalledProcessError) as error:
        append_probe_error(probe_errors, "docker compose ps", error)
        return None
    documents = parse_compose_documents(output)
    services: list[dict[str, object]] = []
    now = datetime.now(UTC)
    for item in documents:
        service = str(item.get("Service") or item.get("Name") or "")
        if not service:
            continue
        started_at = container_started_at(item, probe_errors)
        services.append(
            {
                "exitCode": normalized_exit_code(item.get("ExitCode")),
                "health": item.get("Health"),
                "name": item.get("Name"),
                "service": service,
                "startedAt": started_at,
                "state": item.get("State"),
                "uptimeSeconds": uptime_seconds(started_at, now),
            }
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


def container_started_at(
    item: dict[str, object],
    probe_errors: list[ProbeError],
) -> str | None:
    identifier = str(item.get("ID") or item.get("Name") or "")
    if not identifier:
        append_probe_error(
            probe_errors,
            "docker inspect",
            "missing container identifier",
        )
        return None
    try:
        output = subprocess.check_output(
            ["docker", "inspect", "--format", "{{.State.StartedAt}}", identifier],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        append_probe_error(probe_errors, f"docker inspect {identifier}", error)
        return None
    if not output or output.startswith("0001-01-01"):
        return None
    return output


def uptime_seconds(started_at: str | None, now: datetime) -> int | None:
    if not started_at:
        return None
    try:
        started = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
    except ValueError:
        return None
    return max(int((now - started).total_seconds()), 0)
