from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

import pytest

from tirosh_guest_tools.application import update_shutdown
from tirosh_guest_tools.application.contexts import (
    PostgresBackupOutcome,
    PrepareUpdateShutdownContext,
)
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import ComposeAction


def test_prepare_update_shutdown_for_request_uses_explicit_context(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(
        update_shutdown,
        "mount_runtime_share",
        lambda: events.append("mount"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "run_prepare",
        lambda context, *, create_postgres_backup: events.append(
            f"prepare:{context.request_id}:{context.version}"
        ),
    )

    update_shutdown.run_prepare_update_shutdown_for_request(
        request_id="req-1",
        version="1.2.3",
        create_postgres_backup=_postgres_backup_outcome,
    )

    assert events == ["mount", "prepare:req-1:1.2.3"]


def test_run_prepare_records_poweroff_ready_before_poweroff(
    monkeypatch: Any,
) -> None:
    events: list[str] = []
    context = PrepareUpdateShutdownContext(request_id="req-1", version="1.2.3")

    monkeypatch.setattr(
        update_shutdown,
        "collect_guest_observability",
        lambda phase: events.append(f"observe:{phase.value}"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_redis",
        lambda context: _record_redis_backup(context, events),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_postgres",
        lambda context, *, create_backup: _record_postgres_backup(context, events),
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

    update_shutdown.run_prepare(
        context,
        create_postgres_backup=_postgres_backup_outcome,
        on_poweroff_ready=lambda ready_context: events.append(
            f"ready:{ready_context.redis_backup_path}"
        ),
    )

    assert events == [
        "observe:shutdown-pre-stop",
        "quiesce",
        "redis-backup",
        "postgres-backup",
        "stop-services",
        "observe:shutdown-post-sync",
        "sync",
        "ready:/tmp/redis.tar.gz",
        "poweroff",
        "observe:shutdown-poweroff-requested",
    ]


def test_prepare_update_shutdown_reports_poweroff_request_failure_after_ready_handoff(
    monkeypatch: Any,
) -> None:
    events: list[str] = []
    context = PrepareUpdateShutdownContext(request_id="req-1", version="1.2.3")

    monkeypatch.setattr(
        update_shutdown,
        "collect_guest_observability",
        lambda phase: events.append(f"observe:{phase.value}"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_redis",
        lambda context: _record_redis_backup(context, events),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_postgres",
        lambda context, *, create_backup: _record_postgres_backup(context, events),
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
        update_shutdown.run_prepare(
            context,
            create_postgres_backup=_postgres_backup_outcome,
            on_poweroff_ready=lambda ready_context: events.append(
                f"ready:{ready_context.redis_backup_path}"
            ),
        )

    assert "ready:/tmp/redis.tar.gz" in events
    assert "observe:shutdown-poweroff-requested" not in events


def test_run_prepare_until_poweroff_ready_stops_before_sync_on_backup_failure(
    monkeypatch: Any,
) -> None:
    events: list[str] = []
    context = PrepareUpdateShutdownContext(request_id="req-1", version="1.2.3")

    monkeypatch.setattr(
        update_shutdown,
        "collect_guest_observability",
        lambda phase: events.append(f"observe:{phase.value}"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "quiesce_shutdown_sidecars",
        lambda: events.append("quiesce"),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_redis",
        lambda context: (_ for _ in ()).throw(
            GuestDependencyError("backup failed", code="redis-backup-failed")
        ),
    )
    monkeypatch.setattr(
        update_shutdown,
        "backup_postgres",
        lambda context, *, create_backup: events.append("postgres-backup"),
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

    with pytest.raises(GuestDependencyError):
        update_shutdown.run_prepare_until_poweroff_ready(
            context,
            create_postgres_backup=_postgres_backup_outcome,
        )

    assert events == [
        "observe:shutdown-pre-stop",
        "quiesce",
    ]


def test_prepare_update_shutdown_reports_ordered_stop_failure_details(
) -> None:
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

    assert update_shutdown.shutdown_failure_message(stop_error) == (
        "Guest update shutdown failed at guest-services-stop: "
        "service app did not stop; remaining services: app, redis"
    )
    assert update_shutdown.failure_details(stop_error)["stopAction"] == (
        "ordered-compose-stop"
    )
    assert update_shutdown.failure_details(stop_error)["failedService"] == "app"
    assert update_shutdown.failure_details(stop_error)["remainingServices"] == [
        "app",
        "redis",
    ]


def test_quiesce_shutdown_sidecars_stops_runtime_observation_and_container_logs(
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
        f"systemctl:stop:{RuntimeService.RUNTIME_OBSERVATION.value}",
        f"state:{RuntimeService.RUNTIME_OBSERVATION.value}:inactive",
        f"systemctl:stop:{RuntimeService.CONTAINER_LOGS.value}",
        f"state:{RuntimeService.CONTAINER_LOGS.value}:inactive",
    ]


def test_quiesce_shutdown_sidecars_fails_when_observation_sidecar_remains_active(
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
            {RuntimeService.RUNTIME_OBSERVATION.value: "active"},
        ),
    )

    with pytest.raises(
        GuestDependencyError,
        match="guest systemd unit did not become inactive",
    ):
        update_shutdown.quiesce_shutdown_sidecars()

    assert events == [
        f"systemctl:stop:{RuntimeService.RUNTIME_OBSERVATION.value}",
        f"state:{RuntimeService.RUNTIME_OBSERVATION.value}:active",
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


def _record_redis_backup(
    context: PrepareUpdateShutdownContext,
    events: list[str],
) -> None:
    context.redis_backup_path = "/tmp/redis.tar.gz"
    events.append("redis-backup")


def _record_postgres_backup(
    context: PrepareUpdateShutdownContext,
    events: list[str],
) -> None:
    context.postgres_backup_path = "/tmp/postgres.tar.gz"
    events.append("postgres-backup")


def _postgres_backup_outcome() -> PostgresBackupOutcome:
    return PostgresBackupOutcome(
        archive=Path("/tmp/postgres.tar.gz"),
        alembic_revision="revision-1",
    )


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
