from __future__ import annotations

from typing import Any

import pytest

from tirosh_guest_tools.adapters.outbound.compose import guest_control
from tirosh_guest_tools.adapters.outbound.compose.guest_control import (
    ComposeGuestControlAdapter,
)
from tirosh_guest_tools.application import compose as compose_app
from tirosh_guest_tools.domain.guest_control.models import ServiceNotFoundError
from tirosh_guest_tools.domain.operations import ComposeAction
from tirosh_guest_tools.domain.runtime_state import RuntimeResourceUsage


def test_compose_adapter_maps_service_status(monkeypatch: Any) -> None:
    monkeypatch.setattr(compose_app, "compose_services", lambda: {"app", "redis"})
    monkeypatch.setattr(
        compose_app,
        "inspect_compose_service_states",
        lambda: [
            compose_app.ComposeServiceState(
                service="app",
                container="vitalserver-app-1",
                state="running",
                health="healthy",
                exit_code=0,
            )
        ],
    )

    status = ComposeGuestControlAdapter().get_service_status("app")

    assert status.service == "app"
    assert status.container == "vitalserver-app-1"
    assert status.state == "running"
    assert status.health == "healthy"
    assert status.exit_code == 0


def test_compose_adapter_maps_stack_status_with_absent_services(
    monkeypatch: Any,
) -> None:
    monkeypatch.setattr(compose_app, "compose_services", lambda: {"app", "redis"})
    monkeypatch.setattr(
        compose_app,
        "inspect_compose_service_states",
        lambda: [
            compose_app.ComposeServiceState(
                service="app",
                container="vitalserver-app-1",
                state="running",
                health="healthy",
                exit_code=0,
            )
        ],
    )

    status = ComposeGuestControlAdapter().get_stack_status()

    assert status.state == "loaded"
    assert [service.service for service in status.services] == ["app", "redis"]
    assert status.services[0].state == "running"
    assert status.services[0].health == "healthy"
    assert status.services[1].state == "absent"
    assert status.services[1].health == "not_reported"


def test_compose_adapter_reports_stack_resource_usage(monkeypatch: Any) -> None:
    monkeypatch.setattr(compose_app, "compose_services", lambda: {"app", "redis"})
    monkeypatch.setattr(
        compose_app,
        "inspect_compose_service_states",
        lambda: [
            compose_app.ComposeServiceState(
                service="app",
                container="vitalserver-app-1",
                state="running",
                health="healthy",
                exit_code=0,
            )
        ],
    )
    monkeypatch.setattr(
        guest_control,
        "container_memory_usages",
        lambda: {
            "vitalserver-app-1": RuntimeResourceUsage(
                used_bytes=256,
                total_bytes=1024,
            )
        },
    )
    monkeypatch.setattr(
        guest_control.runtime_collector,
        "cpu_usage_percent",
        lambda errors: 12.5,
    )
    monkeypatch.setattr(
        guest_control.runtime_collector,
        "memory_usage",
        lambda errors: RuntimeResourceUsage(used_bytes=1, total_bytes=2),
    )
    monkeypatch.setattr(
        guest_control.runtime_collector,
        "disk_usage",
        lambda path, errors: RuntimeResourceUsage(
            used_bytes=3 if path == "/" else 5,
            total_bytes=4 if path == "/" else 6,
        ),
    )

    status = ComposeGuestControlAdapter().get_stack_status()
    document = status.as_json()

    assert document["cpuUsagePercent"] == 12.5
    assert document["memory"] == {"usedBytes": 1, "totalBytes": 2}
    assert document["systemDisk"] == {"usedBytes": 3, "totalBytes": 4}
    assert document["vitalFilesDisk"] == {"usedBytes": 5, "totalBytes": 6}
    assert document["services"][0]["memory"] == {
        "usedBytes": 256,
        "totalBytes": 1024,
    }


def test_docker_stats_memory_usage_parser_preserves_units() -> None:
    usage = guest_control.resource_usage_from_docker_mem_usage(
        "128MiB / 1GiB"
    )

    assert usage == RuntimeResourceUsage(
        used_bytes=128 * 1024 * 1024,
        total_bytes=1024 * 1024 * 1024,
    )


def test_compose_adapter_reports_missing_service(monkeypatch: Any) -> None:
    monkeypatch.setattr(compose_app, "compose_services", lambda: {"redis"})

    with pytest.raises(ServiceNotFoundError) as error:
        ComposeGuestControlAdapter().get_service_status("app")

    assert error.value.kind == "serviceNotFound"
    assert error.value.available_services == ["redis"]


@pytest.mark.parametrize(
    ("method_name", "compose_command"),
    [
        ("start_service", "start"),
        ("stop_service", "stop"),
        ("restart_service", "restart"),
    ],
)
def test_compose_adapter_runs_service_command_with_compose(
    monkeypatch: Any,
    method_name: str,
    compose_command: str,
) -> None:
    calls: list[list[str]] = []
    monkeypatch.setattr(compose_app, "compose_services", lambda: {"app", "redis"})
    monkeypatch.setattr(
        compose_app,
        "checked_compose",
        lambda arguments, *, stage: calls.append(arguments),
    )

    getattr(ComposeGuestControlAdapter(), method_name)("app")

    assert calls == [[compose_command, "app"]]


def test_compose_adapter_reconciles_guest_services(monkeypatch: Any) -> None:
    actions: list[ComposeAction] = []
    systemctl_calls: list[tuple[str, str]] = []
    wrote_state: list[bool] = []
    monkeypatch.setattr(
        compose_app,
        "run_compose_action",
        lambda action: actions.append(action),
    )
    monkeypatch.setattr(
        guest_control,
        "systemctl",
        lambda command, service, *, check: systemctl_calls.append((command, service)),
    )
    monkeypatch.setattr(
        guest_control,
        "write_current_state",
        lambda: wrote_state.append(True),
    )

    ComposeGuestControlAdapter().reconcile_services()

    assert actions == [ComposeAction.UP]
    assert systemctl_calls == [
        ("restart", "tirosh-vitalserver-container-logs.service"),
        ("restart", "tirosh-runtime-state.service"),
    ]
    assert wrote_state == [True]
