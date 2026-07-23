from __future__ import annotations

import logging
import subprocess
import time
from collections.abc import Callable
from typing import Any

from tirosh_guest_tools.adapters.outbound.observability.collectors import (
    OBSERVABILITY_DIR,
)
from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.contexts import (
    PostgresBackupOutcome,
    PrepareUpdateShutdownContext,
)
from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.application.redis_backup import run_redis_backup
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import (
    ComposeAction,
    ObservationPhase,
)
from tirosh_guest_tools.infrastructure.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    run,
    systemctl,
)

LOG_FILE = RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_LOG.value
SIDECAR_STOP_TIMEOUT_SECONDS = 30.0
SIDECAR_STOP_POLL_SECONDS = 0.5
FINAL_SYNC_TIMEOUT_SECONDS = 60.0
POWEROFF_REQUEST_TIMEOUT_SECONDS = 15.0
logger = logging.getLogger(__name__)


class GuestPoweroffRequestError(GuestDependencyError):
    pass


def run_prepare_update_shutdown_for_request(
    *,
    request_id: str,
    version: str,
    create_postgres_backup: Callable[[], PostgresBackupOutcome],
) -> None:
    mount_runtime_share()
    context = PrepareUpdateShutdownContext(request_id=request_id, version=version)
    try:
        run_prepare(
            context,
            create_postgres_backup=create_postgres_backup,
        )
    except Exception:
        logger.exception("guest update shutdown preparation failed")
        collect_guest_observability(ObservationPhase.SHUTDOWN_FAILURE)
        raise


def run_prepare(
    context: PrepareUpdateShutdownContext,
    *,
    create_postgres_backup: Callable[[], PostgresBackupOutcome],
    on_poweroff_ready: Callable[[PrepareUpdateShutdownContext], None] | None = None,
) -> None:
    run_prepare_until_poweroff_ready(
        context,
        create_postgres_backup=create_postgres_backup,
        on_poweroff_ready=on_poweroff_ready,
    )
    request_guest_poweroff()
    collect_guest_observability(ObservationPhase.SHUTDOWN_POWEROFF_REQUESTED)


def run_prepare_until_poweroff_ready(
    context: PrepareUpdateShutdownContext,
    *,
    create_postgres_backup: Callable[[], PostgresBackupOutcome],
    on_poweroff_ready: Callable[[PrepareUpdateShutdownContext], None] | None = None,
) -> None:
    collect_guest_observability(ObservationPhase.SHUTDOWN_PRE_STOP)
    quiesce_shutdown_sidecars()
    backup_redis(context)
    backup_postgres(
        context,
        create_backup=create_postgres_backup,
    )
    stop_runtime_services()
    collect_guest_observability(ObservationPhase.SHUTDOWN_POST_SYNC)
    logger.info("final sync started before guest poweroff")
    run(["sync"], timeout_seconds=FINAL_SYNC_TIMEOUT_SECONDS)
    if on_poweroff_ready is not None:
        on_poweroff_ready(context)
    logger.info("guest poweroff ready result recorded")


def collect_guest_observability(phase: ObservationPhase) -> str | None:
    try:
        write_guest_observability_snapshot(phase)
        return str(OBSERVABILITY_DIR / f"{phase.value}.latest.json")
    except Exception as error:
        logger.warning(
            "guest observability snapshot failed",
            extra={"fields": {"phase": phase.value, "error": str(error)}},
        )
        return None


def failure_details(error: Exception) -> dict[str, Any]:
    details = getattr(error, "details", None)
    if isinstance(details, dict):
        return dict(details)
    return {}


def shutdown_failure_message(error: Exception) -> str:
    details = failure_details(error)
    failed_service = details.get("failedService")
    remaining = details.get("remainingServices")
    if isinstance(failed_service, str) and isinstance(remaining, list):
        remaining_text = ", ".join(str(service) for service in remaining)
        if remaining_text:
            return (
                "Guest update shutdown failed at guest-services-stop: "
                f"service {failed_service} did not stop; "
                f"remaining services: {remaining_text}"
            )
    return f"Guest update shutdown failed at: {error}"


def backup_redis(
    context: PrepareUpdateShutdownContext,
) -> None:
    logger.info("redis backup started", extra={"fields": {"step": "redis-backup"}})
    outcome = run_redis_backup()
    redis_backup_path = str(outcome.archive)
    if not redis_backup_path:
        raise GuestDependencyError(
            "redis backup archive was not created",
            code="redis-backup-archive-missing",
        )
    context.redis_backup_path = redis_backup_path
    logger.info(
        "redis backup completed",
        extra={
            "fields": {"step": "redis-backup", "archive": redis_backup_path}
        },
    )


def backup_postgres(
    context: PrepareUpdateShutdownContext,
    *,
    create_backup: Callable[[], PostgresBackupOutcome],
) -> None:
    logger.info(
        "postgres backup started",
        extra={"fields": {"step": "postgres-backup"}},
    )
    outcome = create_backup()
    postgres_backup_path = str(outcome.archive)
    if not postgres_backup_path:
        raise GuestDependencyError(
            "PostgreSQL backup archive was not created",
            code="postgres-backup-archive-missing",
        )
    context.postgres_backup_path = postgres_backup_path
    logger.info(
        "postgres backup completed",
        extra={
            "fields": {
                "step": "postgres-backup",
                "archive": postgres_backup_path,
                "databaseId": outcome.database_id,
                "alembicRevisions": list(outcome.alembic_revisions),
            }
        },
    )


def stop_runtime_services() -> None:
    logger.info(
        "guest services stop started",
        extra={"fields": {"step": "guest-services-stop"}},
    )
    run_compose_action(ComposeAction.STOP)
    logger.info(
        "guest services stop completed",
        extra={"fields": {"step": "guest-services-stop"}},
    )


def quiesce_shutdown_sidecars() -> None:
    logger.info(
        "guest shutdown sidecar quiesce started",
        extra={"fields": {"step": "guest-sidecar-quiesce"}},
    )
    stop_sidecar_service(RuntimeService.RUNTIME_OBSERVATION)
    stop_sidecar_service(RuntimeService.CONTAINER_LOGS)
    logger.info(
        "guest shutdown sidecar quiesce completed",
        extra={"fields": {"step": "guest-sidecar-quiesce"}},
    )


def stop_sidecar_service(service: RuntimeService) -> None:
    result = systemctl("stop", service.value, check=False)
    if result.returncode != 0:
        raise GuestDependencyError(
            f"failed to stop guest sidecar service: {service.value}",
            code="guest-sidecar-service-stop-failed",
        )
    wait_for_unit_inactive(service, timeout_seconds=SIDECAR_STOP_TIMEOUT_SECONDS)


def wait_for_unit_inactive(
    service: RuntimeService,
    *,
    timeout_seconds: float,
) -> None:
    deadline = time.monotonic() + timeout_seconds
    while True:
        active_state = read_service_active_state(service)
        if active_state in {"inactive", "failed"}:
            return
        if time.monotonic() >= deadline:
            raise GuestDependencyError(
                "guest systemd unit did not become inactive: "
                f"{service.value} activeState={active_state}",
                code="guest-sidecar-service-stop-timeout",
            )
        time.sleep(SIDECAR_STOP_POLL_SECONDS)


def read_service_active_state(service: RuntimeService) -> str:
    result = subprocess.run(
        [
            "systemctl",
            "show",
            "--property=ActiveState",
            "--value",
            service.value,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        raise GuestDependencyError(
            "failed to read guest systemd unit state: "
            f"{service.value} error={stderr or result.returncode}",
            code="guest-sidecar-service-state-read-failed",
        )
    active_state = (result.stdout or "").strip()
    if not active_state:
        raise GuestDependencyError(
            f"guest systemd unit active state is empty: {service.value}",
            code="guest-sidecar-service-state-empty",
        )
    return active_state


def request_guest_poweroff() -> None:
    result = systemctl(
        "--no-block",
        "poweroff",
        check=False,
        timeout_seconds=POWEROFF_REQUEST_TIMEOUT_SECONDS,
    )
    if result.returncode == 0:
        return
    stderr = (result.stderr or "").strip()
    raise GuestPoweroffRequestError(
        f"systemctl poweroff failed: {stderr or result.returncode}",
        code="guest-poweroff-request-failed",
    )
