from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_state import (
    RuntimeStateReadError,
    read_runtime_state,
    read_runtime_state_guest_http,
    read_runtime_state_vm_ip,
    runtime_state_file,
)


def test_reads_runtime_state_contract_fields(tmp_path: Path) -> None:
    vm_home = tmp_path / "vm"
    state_file = runtime_state_file(vm_home)
    state_file.parent.mkdir(parents=True)
    state_file.write_text(
        json.dumps({"vmIP": "192.168.64.2", "guestHTTP": "200"})
    )

    assert read_runtime_state(vm_home)["vmIP"] == "192.168.64.2"
    assert read_runtime_state_vm_ip(vm_home) == "192.168.64.2"
    assert read_runtime_state_guest_http(vm_home) == "200"


def test_reports_missing_runtime_state(tmp_path: Path) -> None:
    with pytest.raises(RuntimeStateReadError, match="missing runtime state"):
        read_runtime_state_vm_ip(tmp_path / "vm")


def test_reports_invalid_runtime_state(tmp_path: Path) -> None:
    state_file = runtime_state_file(tmp_path / "vm")
    state_file.parent.mkdir(parents=True)
    state_file.write_text("{invalid-json")

    with pytest.raises(RuntimeStateReadError, match="invalid runtime state JSON"):
        read_runtime_state_vm_ip(tmp_path / "vm")


def test_reports_missing_required_runtime_state_field(tmp_path: Path) -> None:
    state_file = runtime_state_file(tmp_path / "vm")
    state_file.parent.mkdir(parents=True)
    state_file.write_text(json.dumps({"guestHTTP": "200"}))

    with pytest.raises(RuntimeStateReadError, match="missing non-empty string"):
        read_runtime_state_vm_ip(tmp_path / "vm")
