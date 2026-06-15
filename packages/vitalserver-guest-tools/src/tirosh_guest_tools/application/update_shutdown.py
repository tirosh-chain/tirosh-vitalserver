from __future__ import annotations

import logging
import subprocess
import time
from typing import Any

from tirosh_guest_tools.adapters.outbound.observability.collectors import (
    OBSERVABILITY_DIR,
)
from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.contexts import PrepareUpdateShutdownContext
from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.application.redis_backup import run_redis_backup
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import (
    ComposeAction,
    GuestOperationResult,
    ObservationPhase,
    OperationName,
    OperationStatus,
    ReasonCode,
    ShutdownPhase,
)
from tirosh_guest_tools.infrastructure.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    request_id_from,
    request_version_from,
    run,
    systemctl,
    utc_now,
    write_json,
)

REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_LOG.value
SIDECAR_STOP_TIMEOUT_SECONDS = 30.0
SIDECAR_STOP_POLL_SECONDS = 0.5
REDIS_BACKUP_ACTIVE_WAIT_TIMEOUT_SECONDS = 300.0
FINAL_SYNC_TIMEOUT_SECONDS = 60.0
POWEROFF_REQUEST_TIMEOUT_SECONDS = 15.0
logger = logging.getLogger(__name__)


class GuestPoweroffRequestError(GuestDependencyError):
    pass


def run_prepare_update_shutdown() -> None:
    mount_runtime_share()
    context: PrepareUpdateShutdownContext | None = None
    try:
        context = prepare_context()
        if context is None:
            return
        run_prepare(context)
    except Exception as error:
        logger.exception("guest update shutdown preparation failed")
        snapshot_path = collect_guest_observability(ObservationPhase.SHUTDOWN_FAILURE)
        if context is not None:
            details = failure_details(error)
            if snapshot_path is not None:
                details["failureSnapshotPath"] = snapshot_path
            write_result(
                context,
                OperationStatus.FAILED,
                shutdown_failure_message(error),
                step=OperationStatus.FAILED.value,
                reason_codes=(ReasonCode.GUEST_UPDATE_SHUTDOWN_FAILED.value,),
                shutdown_phase=(
                    ShutdownPhase.POWEROFF_FAILED
                    if isinstance(error, GuestPoweroffRequestError)
                    else None
                ),
                details=details,
            )
        REQUEST_FILE.unlink(missing_ok=True)
        raise


def write_dispatch_failure_result(
    *,
    message: str,
    reason_code: ReasonCode,
) -> None:
    request_id = request_id_from(REQUEST_FILE)
    context = PrepareUpdateShutdownContext(
        request_id=request_id,
        version=request_version_from(REQUEST_FILE),
    )
    write_result(
        context,
        OperationStatus.FAILED,
        message,
        step="dispatch",
        reason_codes=(reason_code.value,),
    )


def prepare_context() -> PrepareUpdateShutdownContext | None:
    logger.info("guest update shutdown preparation started")
    if not REQUEST_FILE.is_file():
        logger.info("request file is missing; exiting")
        return None
    request_id = request_id_from(REQUEST_FILE)
    version = request_version_from(REQUEST_FILE)
    logger.info(
        "guest update shutdown request loaded",
        extra={"fields": {"requestId": request_id, "version": version or None}},
    )
    context = PrepareUpdateShutdownContext(request_id=request_id, version=version)
    write_result(
        context,
        OperationStatus.RUNNING,
        "Guest update shutdown preparation started.",
        step="starting",
    )
    REQUEST_FILE.unlink(missing_ok=True)
    return context


def run_prepare(context: PrepareUpdateShutdownContext) -> None:
    collect_guest_observability(ObservationPhase.SHUTDOWN_PRE_STOP)
    quiesce_shutdown_sidecars()
    backup_redis(context)
    write_result(
        context,
        OperationStatus.RUNNING,
        "Redis backup completed. Stopping guest services.",
        step=OperationName.REDIS_BACKUP.value,
    )
    write_result(
        context,
        OperationStatus.RUNNING,
        "Stopping guest services.",
        step="guest-services-stop",
    )
    stop_runtime_services()
    collect_guest_observability(ObservationPhase.SHUTDOWN_POST_SYNC)
    write_result(
        context,
        OperationStatus.RUNNING,
        "Guest services are stopped. Preparing final filesystem sync.",
        step=ShutdownPhase.PREPARED.value,
        shutdown_phase=ShutdownPhase.PREPARED,
    )
    logger.info("final sync started before guest poweroff")
    run(["sync"], timeout_seconds=FINAL_SYNC_TIMEOUT_SECONDS)
    write_result(
        context,
        OperationStatus.READY,
        "Guest services are stopped and filesystems synced. Guest poweroff request is being issued.",
        step=ShutdownPhase.POWEROFF_READY.value,
        shutdown_phase=ShutdownPhase.POWEROFF_READY,
    )
    logger.info("guest poweroff ready result recorded")
    request_guest_poweroff()
    collect_guest_observability(ObservationPhase.SHUTDOWN_POWEROFF_REQUESTED)
    REQUEST_FILE.unlink(missing_ok=True)


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
    stop_sidecar_service(RuntimeService.COMMAND_POLLER)
    stop_sidecar_service(RuntimeService.RUNTIME_STATE)
    stop_sidecar_service(RuntimeService.CONTAINER_LOGS)
    wait_for_unit_inactive(
        RuntimeService.REDIS_BACKUP,
        timeout_seconds=REDIS_BACKUP_ACTIVE_WAIT_TIMEOUT_SECONDS,
    )
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


def write_result(
    context: PrepareUpdateShutdownContext,
    status: OperationStatus,
    message: str,
    *,
    step: str = "",
    reason_codes: tuple[str, ...] = (),
    shutdown_phase: ShutdownPhase | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation=OperationName.PREPARE_UPDATE_SHUTDOWN,
            request_id=context.request_id,
            schema_version=2,
            message=message,
            status=status,
            updated_at=utc_now(),
            step=step,
            reason_codes=reason_codes,
            redis_backup_path=context.redis_backup_path,
            shutdown_phase=shutdown_phase,
            details=details,
        ).as_json(),
    )
