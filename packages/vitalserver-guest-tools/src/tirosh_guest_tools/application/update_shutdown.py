from __future__ import annotations

import logging
import subprocess
from dataclasses import dataclass

from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.application.redis_backup import run_redis_backup
from tirosh_guest_tools.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    request_id_from,
    request_version_from,
    systemctl,
    utc_now,
    write_json,
)
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    ObservationPhase,
    OperationName,
    OperationStatus,
    ReasonCode,
)
from tirosh_guest_tools.inbound import ComposeAction

REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_LOG.value
logger = logging.getLogger(__name__)


@dataclass
class PrepareUpdateShutdownContext:
    request_id: str
    version: str
    redis_backup_path: str = ""


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
        collect_guest_observability(ObservationPhase.SHUTDOWN_FAILURE)
        if context is not None:
            write_result(
                context,
                OperationStatus.FAILED,
                f"Guest update shutdown failed at: {error}",
                step=OperationStatus.FAILED.value,
                reason_codes=(ReasonCode.GUEST_UPDATE_SHUTDOWN_FAILED.value,),
            )
        REQUEST_FILE.unlink(missing_ok=True)
        raise


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
    return context


def run_prepare(context: PrepareUpdateShutdownContext) -> None:
    collect_guest_observability(ObservationPhase.SHUTDOWN_PRE_STOP)
    backup_redis(context)
    write_result(
        context,
        OperationStatus.RUNNING,
        "Redis backup completed. Stopping guest services.",
        step=OperationName.REDIS_BACKUP.value,
    )
    stop_runtime_services()
    logger.info("sync started", extra={"fields": {"step": "sync"}})
    subprocess.run(["sync"], check=True)
    logger.info("sync completed", extra={"fields": {"step": "sync"}})
    collect_guest_observability(ObservationPhase.SHUTDOWN_POST_SYNC)
    write_result(
        context,
        OperationStatus.READY,
        "Guest services are stopped and filesystems are synced.",
        step=OperationStatus.READY.value,
    )
    REQUEST_FILE.unlink(missing_ok=True)
    logger.info("guest update shutdown preparation ready")


def collect_guest_observability(phase: ObservationPhase) -> None:
    try:
        write_guest_observability_snapshot(phase)
    except Exception as error:
        logger.warning(
            "guest observability snapshot failed",
            extra={"fields": {"phase": phase.value, "error": str(error)}},
        )


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
    systemctl("stop", RuntimeService.CONTAINER_LOGS.value, check=False)
    systemctl("stop", RuntimeService.RUNTIME_STATE.value, check=False)
    run_compose_action(ComposeAction.STOP)
    logger.info(
        "guest services stop completed",
        extra={"fields": {"step": "guest-services-stop"}},
    )


def write_result(
    context: PrepareUpdateShutdownContext,
    status: OperationStatus,
    message: str,
    *,
    step: str = "",
    reason_codes: tuple[str, ...] = (),
) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation=OperationName.PREPARE_UPDATE_SHUTDOWN,
            request_id=context.request_id,
            schema_version=1,
            message=message,
            status=status,
            updated_at=utc_now(),
            step=step,
            reason_codes=reason_codes,
            redis_backup_path=context.redis_backup_path,
        ).as_json(),
    )
