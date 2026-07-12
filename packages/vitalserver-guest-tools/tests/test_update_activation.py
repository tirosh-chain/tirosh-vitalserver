from __future__ import annotations

import subprocess
from typing import Any

import pytest

from tirosh_guest_tools.application import update_activation
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import ComposeAction, ObservationPhase


def test_run_activate_update_runs_activation_without_request_result_contract(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(update_activation, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(
        update_activation,
        "activate_runtime",
        lambda: events.append("activate-runtime"),
    )
    monkeypatch.setattr(
        update_activation,
        "collect_guest_observability",
        lambda phase: events.append(f"observe:{ObservationPhase(phase).value}"),
    )

    update_activation.run_activate_update()

    assert events == [
        "activate-runtime",
        "observe:activation-post",
    ]


def test_activate_runtime_quiesces_compose_units_before_recreating_stack(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    def migrate_control_store() -> None:
        events.append("migrate-control-store")

    monkeypatch.setattr(
        update_activation,
        "install_guest_tools_runtime",
        lambda: events.append("install"),
    )
    monkeypatch.setattr(
        update_activation,
        "migrate_guest_control_store",
        migrate_control_store,
    )
    monkeypatch.setattr(
        update_activation,
        "collect_guest_observability",
        lambda phase: events.append(f"observe:{ObservationPhase(phase).value}"),
    )
    monkeypatch.setattr(
        update_activation,
        "quiesce_compose_units",
        lambda: events.append("quiesce-compose"),
    )
    monkeypatch.setattr(
        update_activation,
        "load_bundled_docker_images",
        lambda: events.append("load-images"),
    )
    monkeypatch.setattr(
        update_activation,
        "run",
        lambda command, **kwargs: events.append("run:" + " ".join(command)),
    )
    monkeypatch.setattr(
        update_activation,
        "run_compose_action",
        lambda action: events.append(f"compose:{ComposeAction(action).value}"),
    )
    monkeypatch.setattr(
        update_activation,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(events, *args),
    )
    monkeypatch.setattr(
        update_activation,
        "write_runtime_observation_outputs",
        lambda: events.append("write-state"),
    )
    update_activation.activate_runtime()

    compose_down = (
        "run:docker compose --env-file /mnt/tirosh/deploy/.env "
        "--project-name vitalserver "
        "-f /mnt/tirosh/deploy/compose.yaml down --remove-orphans"
    )
    assert events == [
        "install",
        "migrate-control-store",
        "observe:activation-pre",
        "quiesce-compose",
        "load-images",
        compose_down,
        "compose:up",
        f"systemctl:restart:{RuntimeService.CONTAINER_LOGS.value}",
        f"systemctl:restart:{RuntimeService.RUNTIME_OBSERVATION.value}",
        "write-state",
        "run:sync",
    ]


def test_quiesce_compose_units_stops_compose(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(
        update_activation,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(events, *args),
    )
    monkeypatch.setattr(
        update_activation.subprocess,
        "run",
        lambda command, **kwargs: _record_service_state(events, command, {}),
    )

    update_activation.quiesce_compose_units()

    assert events == [
        f"systemctl:stop:{RuntimeService.COMPOSE.value}",
        f"state:{RuntimeService.COMPOSE.value}:inactive",
        f"systemctl:reset-failed:{RuntimeService.COMPOSE.value}",
    ]


def test_quiesce_compose_units_accepts_failed_unit_state(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(
        update_activation,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(events, *args),
    )
    monkeypatch.setattr(
        update_activation.subprocess,
        "run",
        lambda command, **kwargs: _record_service_state(
            events,
            command,
            {RuntimeService.COMPOSE.value: "failed"},
        ),
    )

    update_activation.quiesce_compose_units()

    assert events == [
        f"systemctl:stop:{RuntimeService.COMPOSE.value}",
        f"state:{RuntimeService.COMPOSE.value}:failed",
        f"systemctl:reset-failed:{RuntimeService.COMPOSE.value}",
    ]


def test_quiesce_compose_units_fails_when_unit_remains_active(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(update_activation, "COMPOSE_QUIESCE_TIMEOUT_SECONDS", 0.0)
    monkeypatch.setattr(
        update_activation,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(events, *args),
    )
    monkeypatch.setattr(
        update_activation.subprocess,
        "run",
        lambda command, **kwargs: _record_service_state(
            events,
            command,
            {RuntimeService.COMPOSE.value: "active"},
        ),
    )

    with pytest.raises(
        GuestDependencyError,
        match="guest systemd unit did not become inactive",
    ):
        update_activation.quiesce_compose_units()

    assert events == [
        f"systemctl:stop:{RuntimeService.COMPOSE.value}",
        f"state:{RuntimeService.COMPOSE.value}:active",
    ]


def _record_systemctl(
    events: list[str],
    *args: str,
) -> subprocess.CompletedProcess[str]:
    events.append("systemctl:" + ":".join(args))
    return subprocess.CompletedProcess(["systemctl", *args], 0, "", "")


def _record_service_state(
    events: list[str],
    command: list[str],
    states: dict[str, str],
) -> subprocess.CompletedProcess[str]:
    service = command[-1]
    active_state = states.get(service, "inactive")
    events.append(f"state:{service}:{active_state}")
    return subprocess.CompletedProcess(command, 0, active_state + "\n", "")
