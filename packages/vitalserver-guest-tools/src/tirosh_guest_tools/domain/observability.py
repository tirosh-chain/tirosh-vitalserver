from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any


class ObservationDetail(StrEnum):
    DAEMON = "daemon"
    ONESHOT = "oneshot"


class RuntimeFileStatus(StrEnum):
    PRESENT = "present"
    MISSING = "missing"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class ObservabilityCollectorError:
    source: str
    message: str

    def as_json(self) -> dict[str, str]:
        return {"source": self.source, "message": self.message}


@dataclass(frozen=True)
class SystemdObservation:
    system_state: str
    failed_units: Sequence[str]
    jobs: Sequence[str]

    def as_json(self) -> dict[str, object]:
        return {
            "systemState": self.system_state,
            "failedUnits": list(self.failed_units),
            "jobs": list(self.jobs),
        }


@dataclass(frozen=True)
class DockerObservation:
    version: str
    compose_version: str
    containers: Sequence[str]

    def as_json(self) -> dict[str, object]:
        return {
            "version": self.version,
            "composeVersion": self.compose_version,
            "containers": list(self.containers),
        }


@dataclass(frozen=True)
class NetworkObservation:
    addresses: Sequence[str]
    routes: Sequence[str]
    resolv_conf: str | None

    def as_json(self) -> dict[str, object]:
        return {
            "addresses": list(self.addresses),
            "routes": list(self.routes),
            "resolvConf": self.resolv_conf,
        }


@dataclass(frozen=True)
class StorageObservation:
    df: Sequence[str]
    inodes: Sequence[str]
    root_read_only: bool | None

    def as_json(self) -> dict[str, object]:
        return {
            "df": list(self.df),
            "inodes": list(self.inodes),
            "rootReadOnly": self.root_read_only,
        }


@dataclass(frozen=True)
class MountObservation:
    source: str
    document: Mapping[str, Any] | None = None
    lines: Sequence[str] = ()

    def as_json(self) -> dict[str, object]:
        if self.document is not None:
            return {"source": self.source, "document": dict(self.document)}
        return {"source": self.source, "lines": list(self.lines)}


@dataclass(frozen=True)
class RuntimeFileObservation:
    status: RuntimeFileStatus
    size_bytes: int | None = None
    modified_at: str = ""
    age_seconds: int | None = None
    error: str = ""

    def as_json(self) -> dict[str, object]:
        if self.status == RuntimeFileStatus.PRESENT:
            return {
                "status": self.status.value,
                "exists": True,
                "sizeBytes": self.size_bytes,
                "modifiedAt": self.modified_at,
                "ageSeconds": self.age_seconds,
            }
        if self.status == RuntimeFileStatus.MISSING:
            return {"status": self.status.value, "exists": False}
        return {
            "status": self.status.value,
            "exists": None,
            "error": self.error,
        }


@dataclass(frozen=True)
class DiagnosticCommandObservation:
    command: str
    exit_code: int | None
    stdout: str
    stderr: str
    timed_out: bool

    def as_json(self) -> dict[str, object]:
        return {
            "command": self.command,
            "exitCode": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "timedOut": self.timed_out,
        }


@dataclass(frozen=True)
class GuestObservabilitySnapshot:
    detail: ObservationDetail
    observed_at: str
    hostname: str
    boot_id: str | None
    uptime_seconds: float | None
    phase: str | None
    systemd: SystemdObservation
    load_average: Sequence[float]
    memory: Mapping[str, int]
    storage: StorageObservation
    mounts: MountObservation
    services: Mapping[str, str]
    docker: DockerObservation
    network: NetworkObservation
    runtime: Mapping[str, RuntimeFileObservation]
    collector_errors: Sequence[ObservabilityCollectorError]
    commands: Mapping[str, DiagnosticCommandObservation] = field(default_factory=dict)

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "schemaVersion": 1,
            "kind": "guest-observability",
            "detail": self.detail.value,
            "observedAt": self.observed_at,
            "hostname": self.hostname,
            "bootID": self.boot_id,
            "uptimeSeconds": self.uptime_seconds,
            "phase": self.phase,
            "systemd": self.systemd.as_json(),
            "loadAverage": list(self.load_average),
            "memory": dict(self.memory),
            "storage": self.storage.as_json(),
            "mounts": self.mounts.as_json(),
            "services": dict(self.services),
            "docker": self.docker.as_json(),
            "network": self.network.as_json(),
            "runtime": {
                path: state.as_json() for path, state in self.runtime.items()
            },
            "collectorErrors": [
                error.as_json() for error in self.collector_errors
            ],
        }
        if self.commands:
            document["commands"] = {
                name: command.as_json() for name, command in self.commands.items()
            }
        return document

    def text_report(self) -> str:
        lines = [
            f"observedAt={self.observed_at}",
            f"phase={self.phase or ''}",
            f"bootID={self.boot_id or ''}",
            "",
        ]
        for name, command in self.commands.items():
            lines.append(f"===== {name} =====")
            lines.append(f"command={command.command}")
            lines.append(f"exitCode={command.exit_code}")
            lines.append(f"timedOut={command.timed_out}")
            if command.stdout:
                lines.append(command.stdout.rstrip())
            if command.stderr:
                lines.append("--- stderr ---")
                lines.append(command.stderr.rstrip())
            lines.append("")
        return "\n".join(lines).rstrip() + "\n"


def append_collector_error(
    collector_errors: list[ObservabilityCollectorError],
    source: str,
    error: object,
) -> None:
    collector_errors.append(
        ObservabilityCollectorError(source=source, message=str(error))
    )
