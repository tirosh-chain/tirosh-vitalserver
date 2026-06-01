from __future__ import annotations

from pathlib import Path

from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.application.runtime_state import write_current_state
from tirosh_guest_tools.common import (
    DEPLOY_DIR,
    RUNTIME_DIR,
    Tee,
    compose_command,
    mount_runtime_share,
    request_id_from,
    request_version_from,
    run,
    systemctl,
    utc_now,
    write_json,
)
from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    OperationStatus,
)
from tirosh_guest_tools.runtime.config import load_config
from tirosh_guest_tools.system_install import install_guest_tools_runtime

REQUEST_FILE = RUNTIME_DIR / "activate-update.request"
RESULT_FILE = RUNTIME_DIR / "activate-update-result.json"
LOG_FILE = RUNTIME_DIR / "activate-update.log"


def run_activate_update() -> None:
    mount_runtime_share()
    with Tee(LOG_FILE) as log:
        log.write("guest update activation started")
        if not REQUEST_FILE.is_file():
            log.write("request file is missing; exiting")
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
            raise
        log.write(
            f"guest update activation requestId={request_id} "
            f"version={version or 'unknown'}"
        )
        write_result(
            request_id,
            OperationStatus.RUNNING,
            "Guest update activation started.",
        )
        try:
            activate_runtime()
        except Exception:
            collect_guest_observability("activation-failure")
            REQUEST_FILE.unlink(missing_ok=True)
            write_result(
                request_id,
                OperationStatus.FAILED,
                "Guest update activation failed. See activate-update.log.",
            )
            log.write("guest update activation failed")
            raise
        collect_guest_observability("activation-post")
        REQUEST_FILE.unlink(missing_ok=True)
        write_result(
            request_id,
            OperationStatus.COMPLETED,
            "Guest Docker images loaded and VitalServer services recreated.",
        )
        log.write("guest update activation completed")


def write_result(request_id: str, status: OperationStatus, message: str) -> None:
    write_json(
        RESULT_FILE,
        GuestOperationResult(
            operation="activate-update",
            request_id=request_id,
            schema_version=2,
            status=status,
            message=message,
            updated_at=utc_now(),
        ).as_json(),
    )


def activate_runtime() -> None:
    install_guest_tools_runtime()
    collect_guest_observability("activation-pre")
    load_bundled_docker_images()
    run(compose_command(["down", "--remove-orphans"]))
    run_compose_action("up")
    systemctl("restart", "tirosh-vitalserver-container-logs.service", check=False)
    systemctl("restart", "tirosh-runtime-state.service", check=False)
    write_current_state()
    run(["sync"], check=False)
    start_optional_testkit()


def load_bundled_docker_images() -> None:
    image_dir = DEPLOY_DIR / "docker-images"
    if not image_dir.is_dir():
        print(f"docker image bundle directory is missing: {image_dir}")
        return
    loaded = False
    for image_bundle in docker_image_bundles(image_dir):
        print(f"Loading Docker image bundle: {image_bundle}")
        run(["docker", "load", "-i", str(image_bundle)])
        loaded = True
    if loaded:
        print("Bundled Docker images are loaded.")
    else:
        print(f"No Docker image bundles found under {image_dir}")


def docker_image_bundles(image_dir: Path) -> list[Path]:
    return sorted(
        path
        for path in image_dir.iterdir()
        if path.name.endswith((".tar", ".tar.gz", ".tgz"))
    )


def start_optional_testkit() -> None:
    if load_config(DEPLOY_DIR / "runtime-config.json")["testkitEnabled"] is not True:
        return
    print("Scheduling optional TestKit provisioning via systemd.")
    systemctl("reset-failed", "tirosh-vitalserver-testkit.service", check=False)
    result = systemctl(
        "restart",
        "--no-block",
        "tirosh-vitalserver-testkit.service",
        check=False,
    )
    if result.returncode != 0:
        print("warning: failed to schedule optional TestKit provisioning")


def collect_guest_observability(phase: str) -> None:
    try:
        write_guest_observability_snapshot(phase)
    except Exception as error:
        print(f"warning: guest observability snapshot failed: {phase}: {error}")
