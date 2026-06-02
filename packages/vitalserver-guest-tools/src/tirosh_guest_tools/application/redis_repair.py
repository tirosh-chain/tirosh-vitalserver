from __future__ import annotations

import logging

from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.runtime_state import write_current_state
from tirosh_guest_tools.common import (
    PROJECT_NAME,
    RUNTIME_DIR,
    compose_command,
    mount_runtime_share,
    request_id_from,
    run,
    utc_now,
    write_json,
)
from tirosh_guest_tools.contracts import ComposeService, RuntimeFileName
from tirosh_guest_tools.domain.operations import (
    ComposeAction,
    GuestOperationResult,
    OperationName,
    OperationStatus,
)

REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.REPAIR_DATASTORE_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.REPAIR_DATASTORE_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.REPAIR_DATASTORE_LOG.value
REDIS_VOLUME = f"{PROJECT_NAME}_redis-data"
logger = logging.getLogger(__name__)


def run_repair_datastore() -> None:
    mount_runtime_share()
    logger.info("datastore repair started")
    if not REQUEST_FILE.is_file():
        logger.info("request file is missing; exiting")
        write_result("", OperationStatus.SKIPPED, "request file is missing")
        return
    request_id = request_id_from(REQUEST_FILE)
    write_result(
        request_id,
        OperationStatus.RUNNING,
        "Datastore repair is running.",
    )
    try:
        restart_runtime_compose()
    except Exception:
        REQUEST_FILE.unlink(missing_ok=True)
        write_result(
            request_id,
            OperationStatus.FAILED,
            "Datastore repair failed. See repair-datastore.log.",
        )
        logger.exception(
            "datastore repair failed",
            extra={"fields": {"requestId": request_id}},
        )
        raise
    REQUEST_FILE.unlink(missing_ok=True)
    write_result(
        request_id,
        OperationStatus.COMPLETED,
        "Redis append-only file checked and VitalServer services restarted.",
    )
    logger.info(
        "datastore repair completed",
        extra={"fields": {"requestId": request_id}},
    )


def write_result(request_id: str, status: OperationStatus, message: str) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation=OperationName.REPAIR_DATASTORE,
            request_id=request_id,
            schema_version=2,
            message=message,
            status=status,
            updated_at=utc_now(),
        ).as_json(),
    )


def restart_runtime_compose() -> None:
    run(
        compose_command(
            [
                "stop",
                ComposeService.APP.value,
                ComposeService.AUDIT_PROXY.value,
                ComposeService.REDIS_UI.value,
                ComposeService.EDGE.value,
                ComposeService.REDIS.value,
            ]
        ),
        check=False,
    )
    repair_appendonly_file()
    run_compose_action(ComposeAction.UP)
    write_current_state()


def repair_appendonly_file() -> None:
    if run(["docker", "volume", "inspect", REDIS_VOLUME], check=False).returncode != 0:
        logger.info(
            "redis volume does not exist",
            extra={"fields": {"volume": REDIS_VOLUME}},
        )
        return
    run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{REDIS_VOLUME}:/data",
            "redis:3.2.12-alpine",
            "sh",
            "-c",
            (
                "set -eu; "
                "if [ ! -f /data/appendonly.aof ]; then "
                "echo 'appendonly.aof does not exist; nothing to repair'; exit 0; fi; "
                "if redis-check-aof /data/appendonly.aof; then "
                "echo 'appendonly.aof is valid'; exit 0; fi; "
                "backup=\"/data/appendonly.aof.bak.$(date +%Y%m%d%H%M%S)\"; "
                "cp /data/appendonly.aof \"$backup\"; "
                "printf 'created backup: %s\\n' \"$backup\"; "
                "printf 'y\\n' | redis-check-aof --fix /data/appendonly.aof"
            ),
        ]
    )
