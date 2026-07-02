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

from tirosh_guest_tools.adapters.outbound.runtime.probes import append_probe_error
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    ProbeError,
    RuntimeDiskHealth,
    RuntimeHTTPProbeStatus,
    RuntimeResourceUsage,
)
from tirosh_guest_tools.infrastructure.settings import SETTINGS

VITALDB_OBSERVER_ENDPOINT = SETTINGS.observability.vitaldb_observer_url
GUEST_READY_URL = "http://127.0.0.1/ready"
REDIS_UI_URL = "http://127.0.0.1/redis-ui/"
SWAGGER_UI_URL = "http://127.0.0.1/swagger/"


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
