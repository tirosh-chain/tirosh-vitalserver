from __future__ import annotations

from typing import Any

from tirosh_guest_tools.adapters.outbound.observability import collectors
from tirosh_guest_tools.adapters.outbound.observability.commands import CommandResult
from tirosh_guest_tools.contracts import RuntimeService


def test_collect_services_includes_guest_control_api(monkeypatch: Any) -> None:
    observed_commands: list[list[str]] = []

    def run_command(argv: list[str]) -> CommandResult:
        observed_commands.append(argv)
        return CommandResult(
            command=" ".join(argv),
            exit_code=0,
            stdout="active\n",
            stderr="",
            timed_out=False,
        )

    monkeypatch.setattr(collectors, "run_command", run_command)

    services = collectors.collect_services()

    assert services[RuntimeService.GUEST_CONTROL_API.value] == "active"
    assert [
        "systemctl",
        "is-active",
        RuntimeService.GUEST_CONTROL_API.value,
    ] in observed_commands
