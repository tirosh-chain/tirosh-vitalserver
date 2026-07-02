from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Protocol

from tirosh_guest_tools.adapters.outbound.postgres import (
    PostgresVitalDBReadModelRepository,
)
from tirosh_guest_tools.adapters.outbound.runtime import collector
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    ProbeError,
    RuntimeHTTPProbeStatus,
)
from tirosh_guest_tools.domain.vitaldb_relationships import (
    relationship_history_from_observation,
)


class VitalDBReadModelWriter(Protocol):
    def ensure_schema(self) -> None:
        raise NotImplementedError

    def previous_relationship_history(self) -> dict[str, object] | None:
        raise NotImplementedError

    def save_latest_observation(
        self,
        observation: dict[str, object],
        *,
        observed_at: datetime,
    ) -> None:
        raise NotImplementedError

    def save_relationship_history(
        self,
        relationship_history: dict[str, object],
        *,
        observed_at: datetime,
    ) -> None:
        raise NotImplementedError


def write_runtime_state(
    runtime_state: Path,
    *,
    guest_http: RuntimeHTTPProbeStatus | str | None = None,
    redis_ui_http: RuntimeHTTPProbeStatus | str | None = None,
    swagger_ui_http: RuntimeHTTPProbeStatus | str | None = None,
    vitaldb_read_model: VitalDBReadModelWriter | None = None,
) -> None:
    state = runtime_state_document(
        guest_http=guest_http,
        redis_ui_http=redis_ui_http,
        swagger_ui_http=swagger_ui_http,
    )
    vitaldb_probe_errors: list[ProbeError] = []
    vitaldb_observation = collector.vitaldb_observation(vitaldb_probe_errors)
    write_runtime_state_document(
        runtime_state,
        state,
        vitaldb_read_model=vitaldb_read_model,
        vitaldb_observation=vitaldb_observation,
    )


def runtime_state_document(
    *,
    guest_http: RuntimeHTTPProbeStatus | str | None = None,
    redis_ui_http: RuntimeHTTPProbeStatus | str | None = None,
    swagger_ui_http: RuntimeHTTPProbeStatus | str | None = None,
) -> GuestRuntimeState:
    return collector.collect_runtime_state(
        guest_http=guest_http,
        redis_ui_http=redis_ui_http,
        swagger_ui_http=swagger_ui_http,
    )


def write_runtime_state_document(
    runtime_state: Path,
    state: GuestRuntimeState,
    *,
    vitaldb_read_model: VitalDBReadModelWriter | None = None,
    vitaldb_observation: dict[str, object] | None = None,
) -> None:
    runtime_state.parent.mkdir(parents=True, exist_ok=True)
    temporary = runtime_state.with_suffix(runtime_state.suffix + ".tmp")
    temporary.write_text(
        json.dumps(state.as_json(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, runtime_state)
    save_vitaldb_read_models(
        vitaldb_observation,
        vitaldb_read_model=vitaldb_read_model,
    )


def save_vitaldb_read_models(
    observation: dict[str, object] | None,
    *,
    vitaldb_read_model: VitalDBReadModelWriter | None = None,
) -> None:
    if observation is None:
        return
    observed_at = observed_at_datetime(observation)
    observation_document = dict(observation)
    repository = vitaldb_read_model or PostgresVitalDBReadModelRepository()
    repository.ensure_schema()
    previous_relationship_history = repository.previous_relationship_history()
    relationship_history = relationship_history_from_observation(
        observation_document,
        previous_history=previous_relationship_history,
    )
    repository.save_latest_observation(
        observation_document,
        observed_at=observed_at,
    )
    repository.save_relationship_history(
        relationship_history,
        observed_at=observed_at,
    )


def observed_at_datetime(observation: dict[str, object]) -> datetime:
    value = observation.get("observedAt")
    if not isinstance(value, str) or not value:
        raise ValueError("VitalDB observation observedAt field is invalid.")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))
