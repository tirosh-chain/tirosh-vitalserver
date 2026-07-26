from __future__ import annotations

import subprocess
from typing import Any

from tirosh_guest_tools.application import redis_repair


def test_repair_datastore_runs_compose_repair_without_request_result_contract(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(redis_repair, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(
        redis_repair,
        "restart_runtime_compose",
        lambda: events.append("restart-compose"),
    )

    redis_repair.run_repair_datastore()

    assert events == ["restart-compose"]


def test_repair_appendonly_file_uses_the_declared_redis_compose_service(
    monkeypatch: Any,
) -> None:
    commands: list[list[str]] = []

    monkeypatch.setattr(
        redis_repair,
        "compose_command",
        lambda arguments: ["docker", "compose", *arguments],
    )

    def fake_run(
        command: list[str],
        *,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(command)
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(redis_repair, "run", fake_run)

    redis_repair.repair_appendonly_file()

    assert commands[0] == [
        "docker",
        "volume",
        "inspect",
        redis_repair.REDIS_VOLUME,
    ]
    assert commands[1][:11] == [
        "docker",
        "compose",
        "run",
        "--rm",
        "--no-deps",
        "--pull",
        "never",
        "--entrypoint",
        "sh",
        "redis",
        "-c",
    ]
    assert "redis:3.2.12-alpine" not in commands[1]
    repair_script = commands[1][11]
    assert 'cp /data/appendonly.aof "$backup"' in repair_script
    assert "redis-check-aof --fix /data/appendonly.aof" in repair_script
    assert "|| true" not in repair_script
