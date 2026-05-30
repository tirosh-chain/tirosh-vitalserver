from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root


class RuntimeStateReadError(Exception):
    pass


def vm_home_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else repo_root() / path


def runtime_state_file(value: str | Path) -> Path:
    return vm_home_path(value) / "data/run/runtime-state.json"


def read_runtime_state(vm_home: str | Path) -> dict[str, Any]:
    state_file = runtime_state_file(vm_home)
    if not state_file.is_file() or state_file.stat().st_size == 0:
        raise RuntimeStateReadError(f"missing runtime state: {state_file}")
    try:
        data = json.loads(state_file.read_text())
    except json.JSONDecodeError as error:
        raise RuntimeStateReadError(
            f"invalid runtime state JSON: {state_file}: {error}"
        ) from error
    if not isinstance(data, dict):
        raise RuntimeStateReadError(f"invalid runtime state object: {state_file}")
    return data


def read_runtime_state_string(
    state: dict[str, Any], key: str, vm_home: str | Path
) -> str:
    value = state.get(key)
    if not isinstance(value, str) or not value.strip():
        raise RuntimeStateReadError(
            f"runtime state is missing non-empty string field {key!r}: "
            f"{runtime_state_file(vm_home)}"
        )
    return value.strip()


def read_runtime_state_vm_ip(vm_home: str | Path) -> str:
    return read_runtime_state_string(read_runtime_state(vm_home), "vmIP", vm_home)


def read_runtime_state_guest_http(vm_home: str | Path) -> str:
    return read_runtime_state_string(
        read_runtime_state(vm_home), "guestHTTP", vm_home
    )
