from __future__ import annotations

from tirosh_guest_tools.adapters.outbound.observability.container_logs import (
    docker_compose_logs_command,
)


def test_docker_compose_logs_command_targets_vitalserver_project() -> None:
    command = docker_compose_logs_command(["--tail", "10"])

    assert command[:8] == [
        "docker",
        "compose",
        "--env-file",
        "/mnt/tirosh/deploy/.env",
        "--project-name",
        "vitalserver",
        "-f",
        "/mnt/tirosh/deploy/compose.yaml",
    ]
    assert command[-3:] == ["--no-color", "--tail", "10"]
