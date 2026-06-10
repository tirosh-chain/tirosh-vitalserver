from __future__ import annotations

import subprocess
from typing import Any

import pytest

from tirosh_guest_tools.application import compose
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import ComposeAction


def test_stop_compose_action_uses_bounded_command_timeout(monkeypatch: Any) -> None:
    events: list[str] = []

    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())
    monkeypatch.setattr(
        compose,
        "compose",
        lambda arguments, **kwargs: events.append(
            "compose:"
            + " ".join(arguments)
            + f":timeout={kwargs.get('timeout_seconds')}"
        ),
    )
    monkeypatch.setattr(compose, "run", lambda arguments: events.append("sync"))

    compose.run_compose_action(ComposeAction.STOP)

    assert events == ["compose:stop --timeout 120:timeout=180", "sync"]


def test_stop_compose_action_reports_timeout_as_dependency_failure(
    monkeypatch: Any,
) -> None:
    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())

    def timeout_compose(arguments: list[str], **kwargs: object) -> None:
        raise subprocess.TimeoutExpired(arguments, kwargs["timeout_seconds"])

    monkeypatch.setattr(compose, "compose", timeout_compose)

    with pytest.raises(GuestDependencyError) as error:
        compose.run_compose_action(ComposeAction.STOP)

    assert error.value.code == "compose-stop-timeout"
    assert "docker compose stop timed out after 180s" in error.value.message
