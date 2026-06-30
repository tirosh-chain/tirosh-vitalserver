from __future__ import annotations

import json
import os
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.runtime.collector import collect_runtime_state
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    RuntimeHTTPProbeStatus,
)
from tirosh_guest_tools.domain.service_stack_status import (
    ServiceStackHTTPProbes,
    ServiceStackStatus,
)


def write_runtime_state(
    runtime_state: Path,
    *,
    service_stack_status: Path | None = None,
    guest_http: RuntimeHTTPProbeStatus | str | None = None,
    redis_ui_http: RuntimeHTTPProbeStatus | str | None = None,
    swagger_ui_http: RuntimeHTTPProbeStatus | str | None = None,
) -> None:
    state = runtime_state_document(
        guest_http=guest_http,
        redis_ui_http=redis_ui_http,
        swagger_ui_http=swagger_ui_http,
    )
    write_runtime_state_document(runtime_state, state)
    if service_stack_status is not None:
        write_service_stack_status_document(
            service_stack_status,
            service_stack_status_document(state),
        )


def runtime_state_document(
    *,
    guest_http: RuntimeHTTPProbeStatus | str | None = None,
    redis_ui_http: RuntimeHTTPProbeStatus | str | None = None,
    swagger_ui_http: RuntimeHTTPProbeStatus | str | None = None,
) -> GuestRuntimeState:
    return collect_runtime_state(
        guest_http=guest_http,
        redis_ui_http=redis_ui_http,
        swagger_ui_http=swagger_ui_http,
    )


def write_runtime_state_document(
    runtime_state: Path,
    state: GuestRuntimeState,
) -> None:
    write_json_document(runtime_state, state.as_json())


def service_stack_status_document(state: GuestRuntimeState) -> ServiceStackStatus:
    return ServiceStackStatus(
        updated_at=state.updated_at,
        boot_id=state.boot_id,
        compose_services=state.container_services,
        http_probes=ServiceStackHTTPProbes(
            edge=state.guest_http,
            redis_ui=state.redis_ui_http,
            swagger_ui=state.swagger_ui_http,
        ),
        vitaldb_observation=state.vitaldb_observation,
        read_issues=state.probe_errors,
        capabilities=state.capabilities,
    )


def write_service_stack_status(
    service_stack_status: Path,
    *,
    guest_http: RuntimeHTTPProbeStatus | str | None = None,
    redis_ui_http: RuntimeHTTPProbeStatus | str | None = None,
    swagger_ui_http: RuntimeHTTPProbeStatus | str | None = None,
) -> None:
    state = runtime_state_document(
        guest_http=guest_http,
        redis_ui_http=redis_ui_http,
        swagger_ui_http=swagger_ui_http,
    )
    write_service_stack_status_document(
        service_stack_status,
        service_stack_status_document(state),
    )


def write_service_stack_status_document(
    service_stack_status: Path,
    status: ServiceStackStatus,
) -> None:
    write_json_document(service_stack_status, status.as_json())


def write_json_document(path: Path, document: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)
