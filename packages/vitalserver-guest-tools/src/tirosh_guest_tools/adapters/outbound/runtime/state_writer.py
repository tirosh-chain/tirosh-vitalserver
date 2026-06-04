from __future__ import annotations

import json
import os
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.runtime.collector import collect_runtime_state
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    RuntimeHTTPProbeStatus,
)


def write_runtime_state(
    runtime_state: Path,
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
    write_runtime_state_document(runtime_state, state)


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
    runtime_state.parent.mkdir(parents=True, exist_ok=True)
    temporary = runtime_state.with_suffix(runtime_state.suffix + ".tmp")
    temporary.write_text(
        json.dumps(state.as_json(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, runtime_state)
