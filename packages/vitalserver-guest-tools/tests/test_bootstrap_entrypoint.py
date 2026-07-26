import importlib.util
import subprocess
import sys
from pathlib import Path
from types import ModuleType

import pytest

from tirosh_guest_tools.application.runtime_data_prepare import (
    VITALSERVER_DOCKER_CONSUMER_UNITS,
)


def test_bootstrap_quiesces_existing_consumers_before_guest_tools_install() -> None:
    repository_root = Path(__file__).parents[3]
    bootstrap = (
        repository_root / "apps/vitalserver-macos-runtime/Support/Guest/bootstrap.sh"
    ).read_text(encoding="utf-8")

    quiesce_call = 'python3 "${DEPLOY_DIR}/pre_bootstrap_quiesce.py"'
    install_call = "install_guest_tools_runtime"
    call_section = bootstrap[bootstrap.index('mount_share "${MOUNT_TAG}"') :]

    assert "systemctl " not in bootstrap
    assert call_section.index(quiesce_call) < call_section.index(install_call)


def test_pre_bootstrap_quiesce_requests_explicit_consumer_set_without_waiting() -> None:
    module = pre_bootstrap_quiesce_module()
    calls: list[list[str]] = []

    def run(
        arguments: list[str],
        **_kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        calls.append(arguments)
        if arguments[:3] == ["systemctl", "show", "--property=LoadState"]:
            return subprocess.CompletedProcess(arguments, 0, "loaded\n", "")
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            return subprocess.CompletedProcess(arguments, 0, "deactivating\n", "")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    states = module.request_consumer_stop(run=run)

    assert module.CONSUMER_UNITS == VITALSERVER_DOCKER_CONSUMER_UNITS
    assert calls[3] == [
        "systemctl",
        "stop",
        "--no-block",
        *VITALSERVER_DOCKER_CONSUMER_UNITS,
    ]
    assert {state.load_state for state in states.values()} == {"loaded"}
    assert {state.active_state for state in states.values()} == {"deactivating"}


def test_pre_bootstrap_quiesce_preserves_fresh_not_found_state() -> None:
    module = pre_bootstrap_quiesce_module()
    calls: list[list[str]] = []

    def run(
        arguments: list[str],
        **_kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        calls.append(arguments)
        return subprocess.CompletedProcess(arguments, 0, "not-found\n", "")

    states = module.request_consumer_stop(run=run)

    assert all(arguments[1] == "show" for arguments in calls)
    assert {state.load_state for state in states.values()} == {"not-found"}
    assert {state.active_state for state in states.values()} == {None}


def test_pre_bootstrap_quiesce_preserves_stop_request_failure() -> None:
    module = pre_bootstrap_quiesce_module()

    def run(
        arguments: list[str],
        **_kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments[:3] == ["systemctl", "show", "--property=LoadState"]:
            return subprocess.CompletedProcess(arguments, 0, "loaded\n", "")
        return subprocess.CompletedProcess(arguments, 5, "", "stop rejected")

    with pytest.raises(
        RuntimeError,
        match=r"pre-bootstrap consumer stop request failed:.*exit=5.*stop rejected",
    ):
        module.request_consumer_stop(run=run)


def test_pre_bootstrap_quiesce_rejects_missing_active_state() -> None:
    module = pre_bootstrap_quiesce_module()

    def run(
        arguments: list[str],
        **_kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments[:3] == ["systemctl", "show", "--property=LoadState"]:
            return subprocess.CompletedProcess(arguments, 0, "loaded\n", "")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    with pytest.raises(
        RuntimeError,
        match=(
            r"pre-bootstrap consumer property is invalid:.*"
            r"property=ActiveState.*value=''"
        ),
    ):
        module.request_consumer_stop(run=run)


def pre_bootstrap_quiesce_module() -> ModuleType:
    repository_root = Path(__file__).parents[3]
    path = (
        repository_root
        / "apps/vitalserver-macos-runtime/Support/Guest/pre_bootstrap_quiesce.py"
    )
    spec = importlib.util.spec_from_file_location("pre_bootstrap_quiesce", path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    finally:
        del sys.modules[spec.name]
    return module
