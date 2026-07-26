from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ProbeError:
    source: str
    message: str

    def as_json(self) -> dict[str, str]:
        return {"source": self.source, "message": self.message}


@dataclass(frozen=True)
class RuntimeResourceUsage:
    used_bytes: int
    total_bytes: int

    def as_json(self) -> dict[str, int]:
        return {
            "usedBytes": self.used_bytes,
            "totalBytes": self.total_bytes,
        }


@dataclass(frozen=True)
class RuntimeDiskHealth:
    root_filesystem_read_only: bool | None
    kernel_errors: Sequence[str] | None

    def as_json(self) -> dict[str, object]:
        return {
            "rootFilesystemReadOnly": self.root_filesystem_read_only,
            "kernelErrors": (
                None if self.kernel_errors is None else list(self.kernel_errors)
            ),
        }


@dataclass(frozen=True)
class RuntimeHTTPProbeStatus:
    status: str | None
    failed: bool = False
    message: str = ""
    exit_code: int | None = None

    @classmethod
    def from_status_text(cls, value: str | None) -> RuntimeHTTPProbeStatus | None:
        if value is None or value == "":
            return None
        return cls(status=value)

    def as_status_text(self) -> str | None:
        return self.status

    def as_json(self) -> dict[str, object]:
        return {
            "status": self.status,
            "failed": self.failed,
            "message": self.message,
            "exitCode": self.exit_code,
        }


@dataclass(frozen=True)
class GuestRuntimeObservation:
    updated_at: str
    vm_ip: str | None
    boot_id: str | None
    cpu_usage_percent: float | None
    guest_http: RuntimeHTTPProbeStatus | None
    memory: RuntimeResourceUsage | None
    probe_errors: Sequence[ProbeError]
    redis_ui_http: RuntimeHTTPProbeStatus | None
    system_disk: RuntimeResourceUsage | None
    disk_health: RuntimeDiskHealth | None
    swagger_ui_http: RuntimeHTTPProbeStatus | None
    vital_files_disk: RuntimeResourceUsage | None

    def as_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": 1,
            "vmIP": self.vm_ip,
            "bootID": self.boot_id,
            "cpuUsagePercent": self.cpu_usage_percent,
            "guestHTTP": http_status_text(self.guest_http),
            "httpProbes": {
                "guestHTTP": http_probe_document(self.guest_http),
                "redisUIHTTP": http_probe_document(self.redis_ui_http),
                "swaggerUIHTTP": http_probe_document(self.swagger_ui_http),
            },
            "memory": (
                None if self.memory is None else self.memory.as_json()
            ),
            "probeErrors": [error.as_json() for error in self.probe_errors],
            "redisUIHTTP": http_status_text(self.redis_ui_http),
            "systemDisk": (
                None if self.system_disk is None else self.system_disk.as_json()
            ),
            "diskHealth": (
                None if self.disk_health is None else self.disk_health.as_json()
            ),
            "swaggerUIHTTP": http_status_text(self.swagger_ui_http),
            "updatedAt": self.updated_at,
            "vitalFilesDisk": (
                None
                if self.vital_files_disk is None
                else self.vital_files_disk.as_json()
            ),
        }


def http_status_text(status: RuntimeHTTPProbeStatus | None) -> str | None:
    return None if status is None else status.as_status_text()


def http_probe_document(
    status: RuntimeHTTPProbeStatus | None,
) -> dict[str, object] | None:
    return None if status is None else status.as_json()
