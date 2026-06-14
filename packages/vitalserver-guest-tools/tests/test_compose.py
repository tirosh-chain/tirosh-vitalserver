from __future__ import annotations

import subprocess
from typing import Any

import pytest

from tirosh_guest_tools.application import compose
from tirosh_guest_tools.contracts import ComposeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import ComposeAction


def test_stop_compose_action_stops_services_in_explicit_order(monkeypatch: Any) -> None:
    events: list[str] = []

    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())

    def compose_stub(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        events.append(
            "compose:"
            + " ".join(arguments)
            + f":timeout={kwargs.get('timeout_seconds')}"
        )
        if arguments == ["config", "--services"]:
            services = "\n".join(service.value for service in ComposeService)
            return subprocess.CompletedProcess(arguments, 0, services, "")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    monkeypatch.setattr(compose, "compose", compose_stub)
    monkeypatch.setattr(compose, "run", lambda arguments: events.append("sync"))

    compose.run_compose_action(ComposeAction.STOP)

    assert events == [
        "compose:config --services:timeout=None",
        "compose:stop --timeout 30 testkit:timeout=40",
        "compose:stop --timeout 30 edge:timeout=40",
        "compose:stop --timeout 30 swagger-ui:timeout=40",
        "compose:stop --timeout 30 redis-ui:timeout=40",
        "compose:stop --timeout 30 audit-proxy:timeout=40",
        "compose:stop --timeout 30 vitaldb-observer:timeout=40",
        "compose:stop --timeout 90 app:timeout=100",
        "compose:stop --timeout 60 redis:timeout=70",
        "sync",
    ]


def test_stop_compose_action_records_absent_services_without_stopping(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())

    def compose_stub(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        events.append("compose:" + " ".join(arguments))
        if arguments == ["config", "--services"]:
            return subprocess.CompletedProcess(arguments, 0, "app\nredis\n", "")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    monkeypatch.setattr(compose, "compose", compose_stub)
    monkeypatch.setattr(compose, "run", lambda arguments: events.append("sync"))

    compose.run_compose_action(ComposeAction.STOP)

    assert events == [
        "compose:config --services",
        "compose:stop --timeout 90 app",
        "compose:stop --timeout 60 redis",
        "sync",
    ]


def test_compose_services_captures_command_output(monkeypatch: Any) -> None:
    run_calls: list[dict[str, object]] = []

    def run_stub(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        run_calls.append(kwargs)
        return subprocess.CompletedProcess(arguments, 0, "app\nredis\n", "")

    monkeypatch.setattr(compose, "run", run_stub)

    assert compose.compose_services() == {"app", "redis"}
    assert run_calls == [
        {
            "check": True,
            "stdout": subprocess.PIPE,
            "stderr": subprocess.PIPE,
            "timeout_seconds": None,
        }
    ]


def test_compose_services_reports_missing_stdout(monkeypatch: Any) -> None:
    monkeypatch.setattr(
        compose,
        "compose",
        lambda *args, **kwargs: subprocess.CompletedProcess(args, 0, None, ""),
    )

    with pytest.raises(GuestDependencyError) as error:
        compose.compose_services()

    assert error.value.code == "guest-compose-services-output-missing"
    assert "docker compose config --services did not provide stdout" in str(error.value)


def test_compose_services_reports_empty_stdout(monkeypatch: Any) -> None:
    monkeypatch.setattr(
        compose,
        "compose",
        lambda *args, **kwargs: subprocess.CompletedProcess(args, 0, "\n", ""),
    )

    with pytest.raises(GuestDependencyError) as error:
        compose.compose_services()

    assert error.value.code == "guest-compose-services-output-empty"
    assert "docker compose config --services produced empty stdout" in str(error.value)


def test_stop_compose_action_reports_timeout_as_dependency_failure(
    monkeypatch: Any,
) -> None:
    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())

    def timeout_compose(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments == ["config", "--services"]:
            return subprocess.CompletedProcess(arguments, 0, "app\nredis\n", "")
        if arguments == ["ps", "--all", "--format", "json"]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                "\n".join(
                    [
                        '{"Service":"app","Name":"vitalserver-app-1","State":"running","Health":"healthy"}',
                        '{"Service":"redis","Name":"vitalserver-redis-1","State":"running","Health":"healthy"}',
                    ]
                ),
                "",
            )
        raise subprocess.TimeoutExpired(arguments, kwargs["timeout_seconds"])

    monkeypatch.setattr(compose, "compose", timeout_compose)

    with pytest.raises(GuestDependencyError) as error:
        compose.run_compose_action(ComposeAction.STOP)

    assert error.value.code == "compose-stop-timeout"
    assert (
        "docker compose stop timed out while stopping app after 100s"
        in error.value.message
    )
    assert error.value.details["remainingServices"] == ["app", "redis"]
