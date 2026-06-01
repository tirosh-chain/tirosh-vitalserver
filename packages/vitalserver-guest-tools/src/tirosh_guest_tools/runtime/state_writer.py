from __future__ import annotations

import argparse
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

VITALDB_OBSERVER_URL = os.environ.get(
    "VITALDB_OBSERVER_URL",
    "http://127.0.0.1:18084/api/v1/observations",
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Write guest runtime state JSON.")
    parser.add_argument("runtime_state", type=Path)
    parser.add_argument("guest_http", nargs="?")
    parser.add_argument("redis_ui_http", nargs="?")
    parser.add_argument("swagger_ui_http", nargs="?")
    args = parser.parse_args()

    document = {
        "capabilities": {
            "activateUpdate": True,
            "prepareUpdateShutdown": True,
            "redisBackup": True,
            "repairDatastore": True,
        },
        "schemaVersion": 1,
        "vmIP": first_non_loopback_ip(),
        "bootID": boot_id(),
        "containerServices": compose_services(),
        "cpuUsagePercent": cpu_usage_percent(),
        "guestHTTP": optional_value(args.guest_http),
        "memory": memory_usage(),
        "redisUIHTTP": optional_value(args.redis_ui_http),
        "systemDisk": disk_usage("/"),
        "swaggerUIHTTP": optional_value(args.swagger_ui_http),
        "updatedAt": datetime.now(UTC).isoformat(),
        "vitalFilesDisk": disk_usage("/mnt/tirosh-vital-files"),
        "vitalDBObservation": vitaldb_observation(),
    }
    args.runtime_state.parent.mkdir(parents=True, exist_ok=True)
    args.runtime_state.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


def optional_value(value: str | None) -> str | None:
    return value if value else None


def first_non_loopback_ip() -> str:
    try:
        output = subprocess.check_output(
            ["hostname", "-I"], stderr=subprocess.DEVNULL, text=True
        )
        for candidate in output.split():
            if not candidate.startswith(("127.", "169.254.")):
                return candidate
    except Exception:
        pass
    try:
        for candidate in socket.gethostbyname_ex(socket.gethostname())[2]:
            if not candidate.startswith(("127.", "169.254.")):
                return candidate
    except socket.gaierror:
        pass
    return ""


def boot_id() -> str | None:
    path = Path("/proc/sys/kernel/random/boot_id")
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8").strip()


def read_proc_stat() -> tuple[int, int] | None:
    try:
        fields = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0]
        values = [int(value) for value in fields.split()[1:]]
    except Exception:
        return None
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return idle, sum(values)


def cpu_usage_percent() -> float | None:
    first = read_proc_stat()
    if first is None:
        return None
    time.sleep(0.1)
    second = read_proc_stat()
    if second is None:
        return None
    idle_delta = second[0] - first[0]
    total_delta = second[1] - first[1]
    if total_delta <= 0:
        return None
    return round(max(0.0, min(100.0, (1.0 - (idle_delta / total_delta)) * 100.0)), 1)


def memory_usage() -> dict[str, int] | None:
    values: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            key, raw_value = line.split(":", 1)
            values[key] = int(raw_value.strip().split()[0]) * 1024
    except Exception:
        return None
    total = values.get("MemTotal")
    available = values.get("MemAvailable")
    if total is None or available is None:
        return None
    return {"usedBytes": max(total - available, 0), "totalBytes": total}


def disk_usage(path: str) -> dict[str, int] | None:
    try:
        stats = os.statvfs(path)
    except OSError:
        return None
    total = stats.f_frsize * stats.f_blocks
    available = stats.f_frsize * stats.f_bavail
    return {"usedBytes": max(total - available, 0), "totalBytes": total}


def vitaldb_observation() -> dict[str, object] | None:
    try:
        with urllib.request.urlopen(VITALDB_OBSERVER_URL, timeout=5) as response:
            payload = response.read().decode("utf-8")
    except (OSError, urllib.error.URLError):
        return None
    try:
        value = json.loads(payload)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def compose_services() -> list[dict[str, object]]:
    compose_path = DEPLOY_DIR / "compose.yaml"
    if not compose_path.is_file():
        return []
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
    except Exception:
        return []
    documents = parse_compose_documents(output)
    services: list[dict[str, object]] = []
    now = datetime.now(UTC)
    for item in documents:
        service = str(item.get("Service") or item.get("Name") or "")
        if not service:
            continue
        started_at = container_started_at(item)
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


def container_started_at(item: dict[str, object]) -> str | None:
    identifier = str(item.get("ID") or item.get("Name") or "")
    if not identifier:
        return None
    try:
        output = subprocess.check_output(
            ["docker", "inspect", "--format", "{{.State.StartedAt}}", identifier],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except Exception:
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


if __name__ == "__main__":
    raise SystemExit(main())
