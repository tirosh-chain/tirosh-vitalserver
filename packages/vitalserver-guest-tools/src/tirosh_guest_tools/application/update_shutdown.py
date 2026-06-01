from __future__ import annotations

import subprocess
from dataclasses import dataclass

from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.application.redis_backup import BACKUP_DIR, run_redis_backup
from tirosh_guest_tools.common import (
    RUNTIME_DIR,
    Tee,
    mount_runtime_share,
    request_id_from,
    request_version_from,
    systemctl,
    utc_now,
    write_json,
)
from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    OperationStatus,
)

REQUEST_FILE = RUNTIME_DIR / "prepare-update-shutdown.request"
RESULT_FILE = RUNTIME_DIR / "prepare-update-shutdown-result.json"
LOG_FILE = RUNTIME_DIR / "prepare-update-shutdown.log"


@dataclass
class PrepareUpdateShutdownContext:
    request_id: str
    version: str
    redis_backup_path: str = ""


def run_prepare_update_shutdown() -> None:
    mount_runtime_share()
    with Tee(LOG_FILE) as log:
        context: PrepareUpdateShutdownContext | None = None
        try:
            context = prepare_context(log)
            if context is None:
                return
            run_prepare(context, log)
        except Exception as error:
            log.log(f"status=failed error={error}")
            collect_guest_observability("shutdown-failure")
            if context is not None:
                write_result(
                    context,
                    OperationStatus.FAILED,
                    f"Guest update shutdown failed at: {error}",
                    step="failed",
                    reason_codes=("guest-update-shutdown-failed",),
                )
            REQUEST_FILE.unlink(missing_ok=True)
            raise


def prepare_context(log: Tee) -> PrepareUpdateShutdownContext | None:
    log.log("guest update shutdown preparation started")
    if not REQUEST_FILE.is_file():
        log.write("request file is missing; exiting")
        return None
    request_id = request_id_from(REQUEST_FILE)
    version = request_version_from(REQUEST_FILE)
    log.log(f"requestId={request_id} version={version or 'unknown'}")
    context = PrepareUpdateShutdownContext(request_id=request_id, version=version)
    write_result(
        context,
        OperationStatus.RUNNING,
        "Guest update shutdown preparation started.",
        step="starting",
    )
    return context


def run_prepare(context: PrepareUpdateShutdownContext, log: Tee) -> None:
    collect_guest_observability("shutdown-pre-stop")
    backup_redis(context, log)
    write_result(
        context,
        OperationStatus.RUNNING,
        "Redis backup completed. Stopping guest services.",
        step="redis-backup",
    )
    stop_runtime_services(log)
    log.log("step=sync status=started")
    subprocess.run(["sync"], check=True)
    log.log("step=sync status=completed")
    collect_guest_observability("shutdown-post-sync")
    write_result(
        context,
        OperationStatus.READY,
        "Guest services are stopped and filesystems are synced.",
        step="ready",
    )
    REQUEST_FILE.unlink(missing_ok=True)
    log.log("guest update shutdown preparation ready")


def collect_guest_observability(phase: str) -> None:
    try:
        write_guest_observability_snapshot(phase)
    except Exception as error:
        print(f"warning: guest observability snapshot failed: {phase}: {error}")


def backup_redis(
    context: PrepareUpdateShutdownContext,
    log: Tee,
) -> None:
    log.log("step=redis-backup status=started")
    outcome = run_redis_backup()
    redis_backup_path = str(outcome.archive)
    if not redis_backup_path:
        backups = sorted(BACKUP_DIR.glob("redis-*.tar.gz"))
        redis_backup_path = str(backups[-1]) if backups else ""
    if not redis_backup_path:
        raise RuntimeError("redis backup archive was not created")
    context.redis_backup_path = redis_backup_path
    log.log(f"step=redis-backup status=completed archive={redis_backup_path}")


def stop_runtime_services(log: Tee) -> None:
    log.log("step=guest-services-stop status=started")
    systemctl("stop", "tirosh-vitalserver-container-logs.service", check=False)
    systemctl("stop", "tirosh-runtime-state.service", check=False)
    run_compose_action("stop")
    log.log("step=guest-services-stop status=completed")


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
            operation="prepare-update-shutdown",
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
