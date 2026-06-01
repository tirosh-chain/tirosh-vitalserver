from __future__ import annotations

import argparse
import os
from pathlib import Path

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
from tirosh_guest_tools.compose import main as compose_main
from tirosh_guest_tools.observability.cli import main as observe_main
from tirosh_guest_tools.runtime.state import write_current_state
from tirosh_guest_tools.system_install import install_guest_tools_runtime

REQUEST_FILE = RUNTIME_DIR / "activate-update.request"
RESULT_FILE = RUNTIME_DIR / "activate-update-result.json"
LOG_FILE = RUNTIME_DIR / "activate-update.log"
REQUEST_ID = ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Activate a guest runtime update.")
    parser.parse_args()
    mount_runtime_share()
    with Tee(LOG_FILE) as log:
        log.write("guest update activation started")
        if not REQUEST_FILE.is_file():
            log.write("request file is missing; exiting")
            write_result("", "skipped", "request file is missing")
            return 0
        try:
            request_id = request_id_from(REQUEST_FILE)
            version = request_version_from(REQUEST_FILE)
        except Exception:
            write_result("", "failed", "Activation request metadata is invalid.")
            raise
        global REQUEST_ID
        REQUEST_ID = request_id
        log.write(
            f"guest update activation requestId={request_id} "
            f"version={version or 'unknown'}"
        )
        write_result(request_id, "running", "Guest update activation started.")
        try:
            activate_runtime()
        except Exception:
            collect_guest_observability("activation-failure")
            REQUEST_FILE.unlink(missing_ok=True)
            write_result(
                request_id,
                "failed",
                "Guest update activation failed. See activate-update.log.",
            )
            log.write("guest update activation failed")
            raise
        collect_guest_observability("activation-post")
        REQUEST_FILE.unlink(missing_ok=True)
        write_result(
            request_id,
            "completed",
            "Guest Docker images loaded and VitalServer services recreated.",
        )
        log.write("guest update activation completed")
        return 0


def write_result(request_id: str, status: str, message: str) -> None:
    write_json(
        RESULT_FILE,
        {
            "operation": "activate-update",
            "requestId": request_id,
            "schemaVersion": 2,
            "message": message,
            "status": status,
            "updatedAt": utc_now(),
        },
    )


def activate_runtime() -> None:
    install_guest_tools_runtime()
    collect_guest_observability("activation-pre")
    load_bundled_docker_images()
    run(compose_command(["down", "--remove-orphans"]))
    run_compose_tool("up")
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
    if os.environ.get("TIROSH_TESTKIT_ENABLED", "0") != "1":
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
    import sys

    original_argv = sys.argv
    try:
        sys.argv = ["tirosh-guest-observe", phase]
        observe_main()
    except Exception as error:
        print(f"warning: guest observability snapshot failed: {phase}: {error}")
    finally:
        sys.argv = original_argv


def run_compose_tool(action: str) -> None:
    import sys

    original_argv = sys.argv
    try:
        sys.argv = ["tirosh-vitalserver-compose", action]
        compose_main()
    finally:
        sys.argv = original_argv


if __name__ == "__main__":
    raise SystemExit(main())
