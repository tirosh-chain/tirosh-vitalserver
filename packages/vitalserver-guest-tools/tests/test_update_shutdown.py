from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

from tirosh_guest_tools.application import update_shutdown
from tirosh_guest_tools.application.contexts import PrepareUpdateShutdownContext
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import ComposeAction, ShutdownPhase


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
    write_result = update_shutdown.write_result

    monkeypatch.setattr(update_shutdown, "REQUEST_FILE", request_file)
    monkeypatch.setattr(update_shutdown, "RESULT_FILE", result_file)
    monkeypatch.setattr(update_shutdown, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(update_shutdown, "utc_now", lambda: "2026-06-01T00:00:00Z")
    monkeypatch.setattr(
        update_shutdown,
        "write_result",
        lambda *args, **kwargs: _record_write_result(
            write_result,
            events,
            *args,
            **kwargs,
        ),
    )
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
        "quiesce_shutdown_sidecars",
        lambda: events.append("quiesce"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "stop_runtime_services",
        lambda: events.append("stop-services"),
    )
    monkeypatch.setattr(
        update_shutdown.subprocess,
        "run",
        lambda command, **kwargs: events.append(":".join(command)),
    )
    monkeypatch.setattr(
        update_shutdown,
        "run",
        lambda command, **kwargs: events.append(":".join(command)),
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
        "write:running:starting",
        "observe:shutdown-pre-stop",
        "quiesce",
        "backup",
        "write:running:redis-backup",
        "write:running:guest-services-stop",
        "stop-services",
        "observe:shutdown-post-sync",
        "write:running:prepared",
        "sync",
        "poweroff",
        "observe:shutdown-poweroff-requested",
        "write:ready:poweroff-requested",
    ]


def test_prepare_update_shutdown_reports_poweroff_request_failure_before_ready(
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
    write_result = update_shutdown.write_result

    monkeypatch.setattr(update_shutdown, "REQUEST_FILE", request_file)
    monkeypatch.setattr(update_shutdown, "RESULT_FILE", result_file)
    monkeypatch.setattr(update_shutdown, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(update_shutdown, "utc_now", lambda: "2026-06-01T00:00:00Z")
    monkeypatch.setattr(
        update_shutdown,
        "write_result",
        lambda *args, **kwargs: _record_write_result(
            write_result,
            events,
            *args,
            **kwargs,
        ),
    )
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
        "quiesce_shutdown_sidecars",
        lambda: events.append("quiesce"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "stop_runtime_services",
        lambda: events.append("stop-services"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "run",
        lambda command, **kwargs: events.append(":".join(command)),
    )
    monkeypatch.setattr(
        update_shutdown,
        "request_guest_poweroff",
        lambda: (_ for _ in ()).throw(
            update_shutdown.GuestPoweroffRequestError(
                "systemctl poweroff failed",
                code="guest-poweroff-request-failed",
            )
        ),
    )

    with pytest.raises(update_shutdown.GuestPoweroffRequestError):
        update_shutdown.run_prepare_update_shutdown()

    document = json.loads(result_file.read_text(encoding="utf-8"))
    assert document["status"] == "failed"
    assert document["shutdownPhase"] == ShutdownPhase.POWEROFF_FAILED.value
    assert "systemctl poweroff failed" in document["message"]
    assert "write:ready:poweroff-requested" not in events
    assert not request_file.exists()


def test_prepare_update_shutdown_consumes_request_before_guest_side_effects(
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
    write_result = update_shutdown.write_result

    monkeypatch.setattr(update_shutdown, "REQUEST_FILE", request_file)
    monkeypatch.setattr(update_shutdown, "RESULT_FILE", result_file)
    monkeypatch.setattr(update_shutdown, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(update_shutdown, "utc_now", lambda: "2026-06-01T00:00:00Z")
    monkeypatch.setattr(
        update_shutdown,
        "write_result",
        lambda *args, **kwargs: _record_write_result(
            write_result,
            events,
            *args,
            **kwargs,
        ),
    )
    monkeypatch.setattr(
        update_shutdown,
        "collect_guest_observability",
        lambda phase: events.append(f"observe:{phase.value}"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "quiesce_shutdown_sidecars",
        lambda: events.append(f"quiesce:requestExists={request_file.exists()}"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_redis",
        lambda context: (_ for _ in ()).throw(
            GuestDependencyError("backup failed", code="redis-backup-failed")
        ),
    )

    with pytest.raises(GuestDependencyError):
        update_shutdown.run_prepare_update_shutdown()

    document = json.loads(result_file.read_text(encoding="utf-8"))
    assert document["status"] == "failed"
    assert document["requestId"] == "req-1"
    assert not request_file.exists()
    assert events[:3] == [
        "write:running:starting",
        "observe:shutdown-pre-stop",
        "quiesce:requestExists=False",
    ]


def test_prepare_update_shutdown_reports_ordered_stop_failure_details(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    request_file = tmp_path / "prepare-update-shutdown.request"
    result_file = tmp_path / "prepare-update-shutdown-result.json"
    request_file.write_text(
        json.dumps({"requestId": "req-1", "version": "1.2.3"}),
        encoding="utf-8",
    )

    stop_error = GuestDependencyError(
        "docker compose stop timed out while stopping app after 100s",
        code="compose-stop-timeout",
    )
    stop_error.details = {
        "stopAction": "ordered-compose-stop",
        "failedService": "app",
        "remainingServices": ["app", "redis"],
        "serviceStates": [
            {"service": "app", "container": "vitalserver-app-1", "state": "running"},
            {
                "service": "redis",
                "container": "vitalserver-redis-1",
                "state": "running",
            },
        ],
    }

    monkeypatch.setattr(update_shutdown, "REQUEST_FILE", request_file)
    monkeypatch.setattr(update_shutdown, "RESULT_FILE", result_file)
    monkeypatch.setattr(update_shutdown, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(update_shutdown, "utc_now", lambda: "2026-06-01T00:00:00Z")
    monkeypatch.setattr(update_shutdown, "quiesce_shutdown_sidecars", lambda: None)
    monkeypatch.setattr(
        update_shutdown,
        "backup_redis",
        lambda context: _record_backup(context, []),
    )
    snapshot_path = (
        "/mnt/tirosh/run/guest-observability/shutdown-failure.latest.json"
    )
    monkeypatch.setattr(
        update_shutdown,
        "collect_guest_observability",
        lambda phase: snapshot_path,
    )
    monkeypatch.setattr(
        update_shutdown,
        "stop_runtime_services",
        lambda: (_ for _ in ()).throw(stop_error),
    )

    with pytest.raises(GuestDependencyError):
        update_shutdown.run_prepare_update_shutdown()

    document = json.loads(result_file.read_text(encoding="utf-8"))
    assert document["status"] == "failed"
    assert document["message"] == (
        "Guest update shutdown failed at guest-services-stop: "
        "service app did not stop; remaining services: app, redis"
    )
    assert document["details"]["stopAction"] == "ordered-compose-stop"
    assert document["details"]["failedService"] == "app"
    assert document["details"]["remainingServices"] == ["app", "redis"]
    assert document["details"]["failureSnapshotPath"] == snapshot_path


def test_quiesce_shutdown_sidecars_stops_dispatchers_and_waits_for_redis_backup(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(
        update_shutdown,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(events, *args),
    )
    monkeypatch.setattr(
        update_shutdown.subprocess,
        "run",
        lambda command, **kwargs: _record_service_state(
            events,
            command,
            {},
        ),
    )

    update_shutdown.quiesce_shutdown_sidecars()

    assert events == [
        f"systemctl:stop:{RuntimeService.COMMAND_POLLER.value}",
        f"state:{RuntimeService.COMMAND_POLLER.value}:inactive",
        f"systemctl:stop:{RuntimeService.RUNTIME_STATE.value}",
        f"state:{RuntimeService.RUNTIME_STATE.value}:inactive",
        f"systemctl:stop:{RuntimeService.CONTAINER_LOGS.value}",
        f"state:{RuntimeService.CONTAINER_LOGS.value}:inactive",
        f"systemctl:stop:{RuntimeService.REDIS_BACKUP_TIMER.value}",
        f"state:{RuntimeService.REDIS_BACKUP_TIMER.value}:inactive",
        f"state:{RuntimeService.REDIS_BACKUP.value}:inactive",
    ]


def test_quiesce_shutdown_sidecars_fails_when_sidecar_remains_active(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(update_shutdown, "SIDECAR_STOP_TIMEOUT_SECONDS", 0.0)
    monkeypatch.setattr(
        update_shutdown,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(events, *args),
    )
    monkeypatch.setattr(
        update_shutdown.subprocess,
        "run",
        lambda command, **kwargs: _record_service_state(
            events,
            command,
            {RuntimeService.COMMAND_POLLER.value: "active"},
        ),
    )

    with pytest.raises(
        GuestDependencyError,
        match="guest systemd unit did not become inactive",
    ):
        update_shutdown.quiesce_shutdown_sidecars()

    assert events == [
        f"systemctl:stop:{RuntimeService.COMMAND_POLLER.value}",
        f"state:{RuntimeService.COMMAND_POLLER.value}:active",
    ]


def test_quiesce_shutdown_sidecars_waits_for_existing_redis_backup(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(
        update_shutdown,
        "REDIS_BACKUP_ACTIVE_WAIT_TIMEOUT_SECONDS",
        0.0,
    )
    monkeypatch.setattr(
        update_shutdown,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(events, *args),
    )
    monkeypatch.setattr(
        update_shutdown.subprocess,
        "run",
        lambda command, **kwargs: _record_service_state(
            events,
            command,
            {RuntimeService.REDIS_BACKUP.value: "active"},
        ),
    )

    with pytest.raises(
        GuestDependencyError,
        match="guest systemd unit did not become inactive",
    ):
        update_shutdown.quiesce_shutdown_sidecars()

    assert events == [
        f"systemctl:stop:{RuntimeService.COMMAND_POLLER.value}",
        f"state:{RuntimeService.COMMAND_POLLER.value}:inactive",
        f"systemctl:stop:{RuntimeService.RUNTIME_STATE.value}",
        f"state:{RuntimeService.RUNTIME_STATE.value}:inactive",
        f"systemctl:stop:{RuntimeService.CONTAINER_LOGS.value}",
        f"state:{RuntimeService.CONTAINER_LOGS.value}:inactive",
        f"systemctl:stop:{RuntimeService.REDIS_BACKUP_TIMER.value}",
        f"state:{RuntimeService.REDIS_BACKUP_TIMER.value}:inactive",
        f"state:{RuntimeService.REDIS_BACKUP.value}:active",
    ]


def test_stop_runtime_services_stops_compose_stack(monkeypatch: Any) -> None:
    events: list[str] = []

    monkeypatch.setattr(
        update_shutdown,
        "run_compose_action",
        lambda action: events.append(f"compose:{ComposeAction(action).value}"),
    )

    update_shutdown.stop_runtime_services()

    assert events == ["compose:stop"]


def _record_write_result(
    write_result: Any,
    events: list[str],
    *args: Any,
    **kwargs: Any,
) -> None:
    status = args[1]
    step = kwargs.get("step", "")
    events.append(f"write:{status.value}:{step}")
    write_result(*args, **kwargs)


def _record_backup(
    context: PrepareUpdateShutdownContext,
    events: list[str],
) -> None:
    context.redis_backup_path = "/tmp/redis.tar.gz"
    events.append("backup")


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
