from __future__ import annotations

import json
import socket
import time
from datetime import UTC, datetime
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.observability.commands import (
    CommandResult,
    run_command,
    run_shell,
)
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.observability import (
    DiagnosticCommandObservation,
    DockerObservation,
    GuestObservabilitySnapshot,
    MountObservation,
    NetworkObservation,
    ObservabilityCollectorError,
    ObservationDetail,
    RuntimeFileObservation,
    RuntimeFileStatus,
    StorageObservation,
    SystemdObservation,
    append_collector_error,
)
from tirosh_guest_tools.infrastructure.common import (
    DEPLOY_DIR,
    RUNTIME_DIR,
    VITAL_FILES_MOUNT_POINT,
)

OBSERVABILITY_DIR = RUNTIME_DIR / "guest-observability"
VITAL_FILES_DIR = VITAL_FILES_MOUNT_POINT


def collect_snapshot(
    *,
    phase: str | None = None,
    detail: str = "daemon",
) -> GuestObservabilitySnapshot:
    errors: list[ObservabilityCollectorError] = []
    observed_at = utc_now()
    detail_value = ObservationDetail(detail)
    return GuestObservabilitySnapshot(
        detail=detail_value,
        observed_at=observed_at,
        hostname=socket.gethostname(),
        boot_id=read_text(Path("/proc/sys/kernel/random/boot_id"), errors),
        uptime_seconds=read_uptime_seconds(errors),
        phase=phase,
        systemd=collect_systemd(),
        load_average=read_load_average(errors),
        memory=read_meminfo(errors),
        storage=collect_storage(errors),
        mounts=collect_mounts(errors),
        services=collect_services(),
        docker=collect_docker(),
        network=collect_network(),
        runtime=collect_runtime_files(errors),
        collector_errors=tuple(errors),
        commands=(
            collect_diagnostic_commands()
            if detail_value == ObservationDetail.ONESHOT
            else {}
        ),
    )


def collect_systemd() -> SystemdObservation:
    return SystemdObservation(
        system_state=compact_output(run_command(["systemctl", "is-system-running"])),
        failed_units=lines(
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
        jobs=lines(
            run_command(["systemctl", "list-jobs", "--no-legend", "--no-pager"])
        ),
    )


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
        RuntimeService.GUEST_CONTROL_API.value,
    ]
    return {
        service: compact_output(run_command(["systemctl", "is-active", service]))
        for service in services
    }


def collect_docker() -> DockerObservation:
    return DockerObservation(
        version=compact_output(run_command(["docker", "--version"])),
        compose_version=compact_output(
            run_command(["docker", "compose", "version"])
        ),
        containers=lines(
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
    )


def collect_network() -> NetworkObservation:
    return NetworkObservation(
        addresses=lines(run_command(["ip", "-brief", "addr"])),
        routes=lines(run_command(["ip", "route"])),
        resolv_conf=read_optional(Path("/etc/resolv.conf")),
    )


def collect_storage(errors: list[ObservabilityCollectorError]) -> StorageObservation:
    return StorageObservation(
        df=lines(
            run_command(["df", "-PT", "/", str(RUNTIME_DIR), str(VITAL_FILES_DIR)])
        ),
        inodes=lines(
            run_command(["df", "-Pi", "/", str(RUNTIME_DIR), str(VITAL_FILES_DIR)])
        ),
        root_read_only=root_is_read_only(errors),
    )


def collect_mounts(errors: list[ObservabilityCollectorError]) -> MountObservation:
    result = run_command(["findmnt", "-J", "/", str(RUNTIME_DIR), str(VITAL_FILES_DIR)])
    if result.exit_code == 0:
        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            append_collector_error(errors, "findmnt", error)
        else:
            if isinstance(parsed, dict):
                return MountObservation(source="findmnt-json", document=parsed)
            append_collector_error(errors, "findmnt", "expected JSON object")
    return MountObservation(
        source="findmnt-text",
        lines=lines(run_command(["findmnt"])),
    )


def collect_runtime_files(
    errors: list[ObservabilityCollectorError],
) -> dict[str, RuntimeFileObservation]:
    files = [
        RUNTIME_DIR / RuntimeFileName.RUNTIME_STATE.value,
        RUNTIME_DIR / RuntimeFileName.BOOTSTRAP_RESULT.value,
        DEPLOY_DIR / RuntimeFileName.RUNTIME_CONFIG.value,
    ]
    return {str(path): file_state(path, errors) for path in files}


def collect_diagnostic_commands() -> dict[str, DiagnosticCommandObservation]:
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
    return {name: result.as_observation() for name, result in commands.items()}


def file_state(
    path: Path,
    errors: list[ObservabilityCollectorError],
) -> RuntimeFileObservation:
    try:
        stat = path.stat()
    except FileNotFoundError:
        return RuntimeFileObservation(status=RuntimeFileStatus.MISSING)
    except OSError as error:
        append_collector_error(errors, str(path), error)
        return RuntimeFileObservation(
            status=RuntimeFileStatus.UNKNOWN,
            error=str(error),
        )
    return RuntimeFileObservation(
        status=RuntimeFileStatus.PRESENT,
        size_bytes=stat.st_size,
        modified_at=datetime.fromtimestamp(stat.st_mtime, UTC)
        .isoformat()
        .replace("+00:00", "Z"),
        age_seconds=max(0, int(time.time() - stat.st_mtime)),
    )


def read_text(
    path: Path,
    errors: list[ObservabilityCollectorError],
) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError as error:
        append_collector_error(errors, str(path), error)
        return None
    except OSError as error:
        append_collector_error(errors, str(path), error)
        return None


def read_optional(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def read_uptime_seconds(errors: list[ObservabilityCollectorError]) -> float | None:
    text = read_text(Path("/proc/uptime"), errors)
    if not text:
        return None
    try:
        return float(text.split()[0])
    except (IndexError, ValueError) as error:
        append_collector_error(errors, "/proc/uptime", error)
        return None


def read_load_average(errors: list[ObservabilityCollectorError]) -> list[float]:
    text = read_text(Path("/proc/loadavg"), errors)
    if not text:
        return []
    values: list[float] = []
    for value in text.split()[:3]:
        try:
            values.append(float(value))
        except ValueError:
            append_collector_error(errors, "/proc/loadavg", value)
    return values


def read_meminfo(errors: list[ObservabilityCollectorError]) -> dict[str, int]:
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


def root_is_read_only(errors: list[ObservabilityCollectorError]) -> bool | None:
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
