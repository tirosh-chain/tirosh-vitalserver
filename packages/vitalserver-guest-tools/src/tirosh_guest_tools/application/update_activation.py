from __future__ import annotations

import logging
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.runtime.config import load_config
from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.application.runtime_state import write_current_state
from tirosh_guest_tools.contracts import (
    RuntimeFileName,
    RuntimeService,
)
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.domain.operations import (
    ComposeAction,
    GuestOperationResult,
    ObservationPhase,
    OperationName,
    OperationStatus,
)
from tirosh_guest_tools.infrastructure.common import (
    DEPLOY_DIR,
    RUNTIME_DIR,
    compose_command,
    mount_runtime_share,
    request_id_from,
    request_version_from,
    run,
    systemctl,
    utc_now,
    write_json,
)
from tirosh_guest_tools.infrastructure.system_install import install_guest_tools_runtime

REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.ACTIVATE_UPDATE_REQUEST.value
RESULT_FILE = RUNTIME_DIR / RuntimeFileName.ACTIVATE_UPDATE_RESULT.value
LOG_FILE = RUNTIME_DIR / RuntimeFileName.ACTIVATE_UPDATE_LOG.value
logger = logging.getLogger(__name__)


def run_activate_update() -> None:
    mount_runtime_share()
    logger.info("guest update activation started")
    if not REQUEST_FILE.is_file():
        logger.info("request file is missing; exiting")
        write_result("", OperationStatus.SKIPPED, "request file is missing")
        return
    try:
        request_id = request_id_from(REQUEST_FILE)
        version = request_version_from(REQUEST_FILE)
    except Exception:
        write_result(
            "",
            OperationStatus.FAILED,
            "Activation request metadata is invalid.",
        )
        logger.exception("activation request metadata is invalid")
        raise
    logger.info(
        "guest update activation request loaded",
        extra={"fields": {"requestId": request_id, "version": version or None}},
    )
    write_result(
        request_id,
        OperationStatus.RUNNING,
        "Guest update activation started.",
    )
    try:
        activate_runtime()
    except Exception:
        collect_guest_observability(ObservationPhase.ACTIVATION_FAILURE)
        REQUEST_FILE.unlink(missing_ok=True)
        write_result(
            request_id,
            OperationStatus.FAILED,
            "Guest update activation failed. See activate-update.log.",
        )
        logger.exception(
            "guest update activation failed",
            extra={"fields": {"requestId": request_id}},
        )
        raise
    collect_guest_observability(ObservationPhase.ACTIVATION_POST)
    REQUEST_FILE.unlink(missing_ok=True)
    write_result(
        request_id,
        OperationStatus.COMPLETED,
        "Guest Docker images loaded and VitalServer services recreated.",
    )
    logger.info(
        "guest update activation completed",
        extra={"fields": {"requestId": request_id}},
    )


def write_result(request_id: str, status: OperationStatus, message: str) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation=OperationName.ACTIVATE_UPDATE,
            request_id=request_id,
            schema_version=2,
            status=status,
            message=message,
            updated_at=utc_now(),
        ).as_json(),
    )


def activate_runtime() -> None:
    install_guest_tools_runtime()
    collect_guest_observability(ObservationPhase.ACTIVATION_PRE)
    load_bundled_docker_images()
    run(compose_command(["down", "--remove-orphans"]))
    run_compose_action(ComposeAction.UP)
    systemctl("restart", RuntimeService.CONTAINER_LOGS.value, check=False)
    systemctl("restart", RuntimeService.RUNTIME_STATE.value, check=False)
    write_current_state()
    run(["sync"], check=False)
    start_optional_testkit()


def load_bundled_docker_images() -> None:
    image_dir = DEPLOY_DIR / "docker-images"
    if not image_dir.is_dir():
        raise GuestDependencyError(
            f"docker image bundle directory is missing: {image_dir}",
            code="docker-image-bundle-directory-missing",
        )
    loaded = False
    for image_bundle in docker_image_bundles(image_dir):
        logger.info(
            "loading Docker image bundle",
            extra={"fields": {"imageBundle": str(image_bundle)}},
        )
        run(["docker", "load", "-i", str(image_bundle)])
        loaded = True
    if loaded:
        logger.info("bundled Docker images are loaded")
    else:
        raise GuestDependencyError(
            f"No Docker image bundles found under {image_dir}",
            code="docker-image-bundle-empty",
        )


def docker_image_bundles(image_dir: Path) -> list[Path]:
    return sorted(
        path
        for path in image_dir.iterdir()
        if path.name.endswith((".tar", ".tar.gz", ".tgz"))
    )


def start_optional_testkit() -> None:
    runtime_config = load_config(DEPLOY_DIR / RuntimeFileName.RUNTIME_CONFIG.value)
    if not runtime_config.testkit_enabled:
        return
    logger.info("scheduling optional TestKit provisioning via systemd")
    systemctl("reset-failed", RuntimeService.TESTKIT.value, check=False)
    result = systemctl(
        "restart",
        "--no-block",
        RuntimeService.TESTKIT.value,
        check=False,
    )
    if result.returncode != 0:
        logger.warning("failed to schedule optional TestKit provisioning")


def collect_guest_observability(phase: ObservationPhase) -> None:
    try:
        write_guest_observability_snapshot(phase)
    except Exception as error:
        logger.warning(
            "guest observability snapshot failed",
            extra={"fields": {"phase": phase.value, "error": str(error)}},
        )
