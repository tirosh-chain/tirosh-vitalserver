from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any

from tirosh_guest_tools.domain.runtime_state import (
    ProbeError,
    RuntimeCapabilities,
    RuntimeContainerService,
    RuntimeHTTPProbeStatus,
)


@dataclass(frozen=True)
class ServiceStackHTTPProbes:
    """HTTP probe state owned by the Linux service stack."""

    edge: RuntimeHTTPProbeStatus | None
    redis_ui: RuntimeHTTPProbeStatus | None
    swagger_ui: RuntimeHTTPProbeStatus | None

    def as_json(self) -> dict[str, object]:
        return {
            "edge": http_probe_document(self.edge),
            "redisUI": http_probe_document(self.redis_ui),
            "swaggerUI": http_probe_document(self.swagger_ui),
        }


@dataclass(frozen=True)
class ServiceStackStatus:
    """Explicit service-stack status document produced inside the guest."""

    updated_at: str
    boot_id: str | None
    compose_services: Sequence[RuntimeContainerService] | None
    http_probes: ServiceStackHTTPProbes
    vitaldb_observation: Mapping[str, object] | None
    read_issues: Sequence[ProbeError]
    capabilities: RuntimeCapabilities = field(default_factory=RuntimeCapabilities)

    def as_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": 1,
            "owner": "service-stack",
            "updatedAt": self.updated_at,
            "bootID": self.boot_id,
            "capabilities": self.capabilities.as_json(),
            "composeServices": (
                None
                if self.compose_services is None
                else [service.as_json() for service in self.compose_services]
            ),
            "httpProbes": self.http_probes.as_json(),
            "vitalDBObservation": (
                None
                if self.vitaldb_observation is None
                else dict(self.vitaldb_observation)
            ),
            "readIssues": [issue.as_json() for issue in self.read_issues],
        }


def http_probe_document(
    status: RuntimeHTTPProbeStatus | None,
) -> dict[str, object] | None:
    return None if status is None else status.as_json()
