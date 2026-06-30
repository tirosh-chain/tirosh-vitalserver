from __future__ import annotations

import logging

from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.runtime_state import write_current_state
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.operations import (
    ComposeAction,
    GuestOperationResult,
    OperationName,
    OperationStatus,
)
from tirosh_guest_tools.infrastructure.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    read_json,
    request_id_from,
    systemctl,
    utc_now,
    write_json,
)

REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.RECONCILE_COMPOSE_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.RECONCILE_COMPOSE_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.RECONCILE_COMPOSE_LOG.value
logger = logging.getLogger(__name__)


def run_reconcile_compose() -> None:
    mount_runtime_share()
    logger.info("guest compose reconcile started")
    if not REQUEST_FILE.is_file():
        logger.info("request file is missing; exiting")
        write_result("", OperationStatus.SKIPPED, "request file is missing")
        return
    try:
        request_id = request_id_from(REQUEST_FILE)
        action = compose_action_from_request(REQUEST_FILE)
    except Exception:
        write_result("", OperationStatus.FAILED, "Compose reconcile request metadata is invalid.")
        REQUEST_FILE.unlink(missing_ok=True)
        logger.exception("compose reconcile request metadata is invalid")
        raise
    write_result(request_id, OperationStatus.RUNNING, "Guest compose reconcile started.")
    REQUEST_FILE.unlink(missing_ok=True)
    try:
        run_compose_action(action)
        systemctl("restart", RuntimeService.CONTAINER_LOGS.value, check=False)
        systemctl("restart", RuntimeService.RUNTIME_STATE.value, check=False)
        write_current_state()
    except Exception:
        write_result(
            request_id,
            OperationStatus.FAILED,
            "Guest compose reconcile failed. See reconcile-compose.log.",
        )
        logger.exception(
            "guest compose reconcile failed",
            extra={"fields": {"requestId": request_id}},
        )
        raise
    write_result(
        request_id,
        OperationStatus.COMPLETED,
        "Guest compose services reconciled.",
    )
    logger.info(
        "guest compose reconcile completed",
        extra={"fields": {"requestId": request_id}},
    )


def compose_action_from_request(path: object) -> ComposeAction:
    document = read_json(path)
    action = document.get("composeAction", ComposeAction.UP.value)
    return ComposeAction(action)


def write_result(request_id: str, status: OperationStatus, message: str) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation=OperationName.RECONCILE_COMPOSE,
            request_id=request_id,
            schema_version=1,
            status=status,
            message=message,
            updated_at=utc_now(),
        ).as_json(),
    )
