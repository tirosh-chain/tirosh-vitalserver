from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tirosh_guest_tools.application import update_shutdown
from tirosh_guest_tools.application.contexts import PrepareUpdateShutdownContext
from tirosh_guest_tools.domain.operations import ShutdownPhase


def test_prepare_update_shutdown_writes_poweroff_requested_phase(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    request_file = tmp_path / "prepare-update-shutdown.request"
    result_file = tmp_path / "prepare-update-shutdown-result.json"
    request_file.write_text(
        json.dumps({"requestId": "req-1", "version": "1.2.3"}),
        encoding="utf-8",
    )
    events: list[str] = []

    monkeypatch.setattr(update_shutdown, "REQUEST_FILE", request_file)
    monkeypatch.setattr(update_shutdown, "RESULT_FILE", result_file)
    monkeypatch.setattr(update_shutdown, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(update_shutdown, "utc_now", lambda: "2026-06-01T00:00:00Z")
    monkeypatch.setattr(
        update_shutdown,
        "collect_guest_observability",
        lambda phase: events.append(f"observe:{phase.value}"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_redis",
        lambda context: _record_backup(context, events),
    )
    monkeypatch.setattr(
        update_shutdown,
        "stop_runtime_services",
        lambda: events.append("stop-services"),
    )
    monkeypatch.setattr(
        update_shutdown.subprocess,
        "run",
        lambda command, check: events.append(":".join(command)),
    )
    monkeypatch.setattr(
        update_shutdown,
        "request_guest_poweroff",
        lambda: events.append("poweroff"),
    )

    update_shutdown.run_prepare_update_shutdown()

    document = json.loads(result_file.read_text(encoding="utf-8"))
    assert document["schemaVersion"] == 2
    assert document["status"] == "ready"
    assert document["shutdownPhase"] == ShutdownPhase.POWEROFF_REQUESTED.value
    assert document["redisBackupPath"] == "/tmp/redis.tar.gz"
    assert not request_file.exists()
    assert events == [
        "observe:shutdown-pre-stop",
        "backup",
        "stop-services",
        "sync",
        "observe:shutdown-post-sync",
        "observe:shutdown-poweroff-requested",
        "poweroff",
    ]


def _record_backup(
    context: PrepareUpdateShutdownContext,
    events: list[str],
) -> None:
    context.redis_backup_path = "/tmp/redis.tar.gz"
    events.append("backup")
