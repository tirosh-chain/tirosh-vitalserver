from __future__ import annotations

import json
import socket
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from tirosh_guest_tools.common import DEPLOY_DIR, RUNTIME_DIR, VITAL_FILES_MOUNT_POINT
from tirosh_guest_tools.domain.operations import RuntimeFileName, RuntimeService
from tirosh_guest_tools.observability.commands import (
    CommandResult,
    run_command,
    run_shell,
)

OBSERVABILITY_DIR = RUNTIME_DIR / "guest-observability"
VITAL_FILES_DIR = VITAL_FILES_MOUNT_POINT


def collect_snapshot(
    *,
    phase: str | None = None,
    detail: str = "daemon",
) -> dict[str, Any]:
    errors: list[dict[str, str]] = []
    observed_at = utc_now()
    document: dict[str, Any] = {
        "schemaVersion": 1,
        "kind": "guest-observability",
        "detail": detail,
        "observedAt": observed_at,
        "hostname": socket.gethostname(),
        "bootID": read_text(Path("/proc/sys/kernel/random/boot_id"), errors),
        "uptimeSeconds": read_uptime_seconds(errors),
        "phase": phase,
        "systemd": collect_systemd(),
        "loadAverage": read_load_average(errors),
        "memory": read_meminfo(errors),
        "storage": collect_storage(errors),
        "mounts": collect_mounts(errors),
        "services": collect_services(),
        "docker": collect_docker(),
        "network": collect_network(),
        "runtime": collect_runtime_files(errors),
        "collectorErrors": errors,
    }
    if detail == "oneshot":
        document["commands"] = collect_diagnostic_commands()
    return document


def collect_text_report(snapshot: dict[str, Any]) -> str:
    lines = [
        f"observedAt={snapshot.get('observedAt', '')}",
        f"phase={snapshot.get('phase') or ''}",
        f"bootID={snapshot.get('bootID') or ''}",
        "",
    ]
    for name, value in snapshot.get("commands", {}).items():
        if not isinstance(value, dict):
            continue
        lines.append(f"===== {name} =====")
        lines.append(f"command={value.get('command', '')}")
        lines.append(f"exitCode={value.get('exitCode')}")
        lines.append(f"timedOut={value.get('timedOut')}")
        stdout = str(value.get("stdout") or "")
        stderr = str(value.get("stderr") or "")
        if stdout:
            lines.append(stdout.rstrip())
        if stderr:
            lines.append("--- stderr ---")
            lines.append(stderr.rstrip())
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def collect_systemd() -> dict[str, Any]:
    return {
        "systemState": compact_output(run_command(["systemctl", "is-system-running"])),
        "failedUnits": lines(
            run_command(
                [
                    "systemctl",
                    "list-units",
                    "--state=failed",
                    "--no-legend",
                    "--no-pager",
                ]
            )
        ),
        "jobs": lines(
            run_command(["systemctl", "list-jobs", "--no-legend", "--no-pager"])
        ),
    }


def collect_services() -> dict[str, str]:
    services = [
        "systemd-resolved.service",
        "systemd-networkd.service",
        "dbus.service",
        "docker.service",
        "containerd.service",
        RuntimeService.RUNTIME_STATE.value,
        RuntimeService.COMPOSE.value,
        RuntimeService.CONTAINER_LOGS.value,
    ]
    return {
        service: compact_output(run_command(["systemctl", "is-active", service]))
        for service in services
    }


def collect_docker() -> dict[str, Any]:
    return {
        "version": compact_output(run_command(["docker", "--version"])),
        "composeVersion": compact_output(run_command(["docker", "compose", "version"])),
        "containers": lines(
            run_command(
                [
                    "docker",
                    "ps",
                    "--all",
                    "--format",
                    "{{.Names}}\t{{.Status}}\t{{.Image}}",
                ]
            )
        ),
    }


def collect_network() -> dict[str, Any]:
    return {
        "addresses": lines(run_command(["ip", "-brief", "addr"])),
        "routes": lines(run_command(["ip", "route"])),
        "resolvConf": read_optional(Path("/etc/resolv.conf")),
    }


def collect_storage(errors: list[dict[str, str]]) -> dict[str, Any]:
    return {
        "df": lines(
            run_command(["df", "-PT", "/", str(RUNTIME_DIR), str(VITAL_FILES_DIR)])
        ),
        "inodes": lines(
            run_command(["df", "-Pi", "/", str(RUNTIME_DIR), str(VITAL_FILES_DIR)])
        ),
        "rootReadOnly": root_is_read_only(errors),
    }


def collect_mounts(errors: list[dict[str, str]]) -> dict[str, Any]:
    result = run_command(["findmnt", "-J", "/", str(RUNTIME_DIR), str(VITAL_FILES_DIR)])
    if result.exit_code == 0:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as error:
            errors.append({"collector": "findmnt", "message": str(error)})
    return {"text": lines(run_command(["findmnt"]))}


def collect_runtime_files(errors: list[dict[str, str]]) -> dict[str, Any]:
    files = [
        RUNTIME_DIR / RuntimeFileName.RUNTIME_STATE.value,
        RUNTIME_DIR / RuntimeFileName.BOOTSTRAP_RESULT.value,
        RUNTIME_DIR / RuntimeFileName.ACTIVATE_UPDATE_REQUEST.value,
        RUNTIME_DIR / RuntimeFileName.ACTIVATE_UPDATE_RESULT.value,
        RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_REQUEST.value,
        RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_RESULT.value,
        DEPLOY_DIR / RuntimeFileName.RUNTIME_CONFIG.value,
    ]
    return {str(path): file_state(path, errors) for path in files}


def collect_diagnostic_commands() -> dict[str, dict[str, object]]:
    commands: dict[str, CommandResult] = {
        "systemdCriticalServices": run_command(
            [
                "systemctl",
                "status",
                "systemd-resolved",
                "systemd-networkd",
                "dbus",
                "docker",
                "containerd",
                "--no-pager",
            ],
            timeout_seconds=8,
        ),
        "selectedJournal": run_command(
            [
                "journalctl",
                "-b",
                "-u",
                "systemd-resolved",
                "-u",
                "systemd-networkd",
                "-u",
                "dbus",
                "-u",
                "docker",
                "-u",
                "containerd",
                "--no-pager",
            ],
            timeout_seconds=8,
        ),
        "processes": run_command(
            ["ps", "-eo", "pid,ppid,stat,wchan:32,comm,args"],
            timeout_seconds=8,
        ),
        "mounts": run_command(["mount"], timeout_seconds=8),
        "findmnt": run_command(["findmnt"], timeout_seconds=8),
        "filesystemUsers": run_shell(
            "for path in / /mnt/tirosh /mnt/tirosh-vital-files; do "
            'echo "--- fuser ${path}"; fuser -vm "${path}" 2>&1 || true; done',
            timeout_seconds=8,
        ),
        "blockedProcessStacks": run_shell(
            "for pid in $(ps -eo pid=,stat= | awk '$2 ~ /D|Z/ {print $1}'); do "
            'echo "--- /proc/${pid}/stack"; '
            'cat "/proc/${pid}/stack" 2>&1 || true; done',
            timeout_seconds=8,
        ),
        "dmesg": run_shell(
            "dmesg -T 2>/dev/null | tail -n 300 || "
            "dmesg 2>/dev/null | tail -n 300 || true",
            timeout_seconds=8,
        ),
        "lsblk": run_command(["lsblk", "-J"], timeout_seconds=8),
        "diskstats": run_shell("cat /proc/diskstats", timeout_seconds=8),
        "dockerPs": run_command(["docker", "ps", "--all"], timeout_seconds=8),
    }
    return {name: result.as_dict() for name, result in commands.items()}


def file_state(path: Path, errors: list[dict[str, str]]) -> dict[str, Any]:
    try:
        stat = path.stat()
    except FileNotFoundError:
        return {"exists": False}
    except OSError as error:
        errors.append({"collector": str(path), "message": str(error)})
        return {"exists": None, "error": str(error)}
    return {
        "exists": True,
        "sizeBytes": stat.st_size,
        "modifiedAt": datetime.fromtimestamp(stat.st_mtime, UTC)
        .isoformat()
        .replace("+00:00", "Z"),
        "ageSeconds": max(0, int(time.time() - stat.st_mtime)),
    }


def read_text(path: Path, errors: list[dict[str, str]]) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    except OSError as error:
        errors.append({"collector": str(path), "message": str(error)})
        return None


def read_optional(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def read_uptime_seconds(errors: list[dict[str, str]]) -> float | None:
    text = read_text(Path("/proc/uptime"), errors)
    if not text:
        return None
    try:
        return float(text.split()[0])
    except (IndexError, ValueError) as error:
        errors.append({"collector": "/proc/uptime", "message": str(error)})
        return None


def read_load_average(errors: list[dict[str, str]]) -> list[float]:
    text = read_text(Path("/proc/loadavg"), errors)
    if not text:
        return []
    values: list[float] = []
    for value in text.split()[:3]:
        try:
            values.append(float(value))
        except ValueError:
            errors.append({"collector": "/proc/loadavg", "message": value})
    return values


def read_meminfo(errors: list[dict[str, str]]) -> dict[str, int]:
    text = read_text(Path("/proc/meminfo"), errors)
    if not text:
        return {}
    output: dict[str, int] = {}
    for line in text.splitlines():
        key, _, value = line.partition(":")
        number = value.strip().split()[0] if value.strip() else ""
        if number.isdigit():
            output[key] = int(number) * 1024
    return output


def root_is_read_only(errors: list[dict[str, str]]) -> bool | None:
    text = read_text(Path("/proc/mounts"), errors)
    if not text:
        return None
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[1] == "/":
            return "ro" in parts[3].split(",")
    return None


def compact_output(result: CommandResult) -> str:
    text = result.stdout.strip() or result.stderr.strip()
    if result.timed_out:
        return "timed-out"
    if result.exit_code not in (0, None) and text:
        return text
    return text


def lines(result: CommandResult) -> list[str]:
    text = result.stdout if result.stdout else result.stderr
    return [line for line in text.splitlines() if line]


def utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")
