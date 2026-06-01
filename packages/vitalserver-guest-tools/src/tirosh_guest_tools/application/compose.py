from __future__ import annotations

import os
import subprocess
import time

from tirosh_guest_tools.common import (
    DEPLOY_DIR,
    MOUNT_POINT,
    compose_command,
    mount_runtime_share,
    mount_vital_files_share,
    output,
    run,
    utc_now,
)
from tirosh_guest_tools.runtime.config import load_config
from tirosh_guest_tools.settings import SETTINGS

ComposeAction = str


def run_compose_action(action: ComposeAction) -> None:
    mount_runtime_share()
    mount_vital_files_share()
    runtime_config = load_runtime_env()

    if action == "up":
        start_ordered()
    elif action == "testkit-up":
        start_testkit(runtime_config)
    elif action == "testkit-up-logged":
        start_testkit_logged(runtime_config)
    elif action == "stop":
        compose(["stop", "--timeout", str(SETTINGS.compose.stop_timeout_seconds)])
        run(["sync"])
    else:
        raise ValueError(f"unsupported compose action: {action}")


def load_runtime_env() -> dict[str, object]:
    config = load_config(DEPLOY_DIR / "runtime-config.json")
    os.environ["VITALSERVER_REDIS_HOST"] = str(config["redisHost"])
    os.environ["VITALSERVER_REDIS_PORT"] = str(config["redisPort"])
    os.environ["VITALSERVER_TRUST_PROXY"] = "1" if config["trustProxy"] else "0"
    os.environ["VITALSERVER_PUBLIC_HOST"] = str(config["publicHost"])
    os.environ["VITALSERVER_PUBLIC_PORT"] = str(config["publicPort"])
    os.environ["VITALSERVER_ADMIN_PASSWORD"] = str(config["adminPassword"])
    os.environ["VITALSERVER_VITAL_FILES_DIR"] = str(config["vitalFilesDirectory"])
    return config


def compose(
    arguments: list[str],
    *,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return run(compose_command(arguments), check=check)


def load_optional_docker_images() -> None:
    image_dir = DEPLOY_DIR / "optional-docker-images"
    if not image_dir.is_dir():
        print(f"optional Docker image bundle directory is missing: {image_dir}")
        return
    loaded = False
    for image_bundle in sorted(image_dir.iterdir()):
        if image_bundle.suffix not in {".tar", ".gz", ".tgz"}:
            continue
        print(f"Loading optional Docker image bundle: {image_bundle}")
        run(["docker", "load", "-i", str(image_bundle)])
        loaded = True
    if not loaded:
        print(f"No optional Docker image bundles found under {image_dir}")


def wait_for_redis() -> None:
    deadline = time.time() + 120
    while time.time() < deadline:
        completed = compose(["exec", "-T", "redis", "redis-cli", "ping"], check=False)
        if completed.returncode == 0 and "PONG" in output(
            compose_command(["exec", "-T", "redis", "redis-cli", "ping"]),
            check=False,
        ):
            return
        time.sleep(2)
    print("error: redis did not become ready")
    compose(["ps"], check=False)
    compose(["logs", "redis", "--tail=100"], check=False)
    raise SystemExit(1)


def wait_for_app() -> None:
    script = (
        "require('http').get('http://127.0.0.1/check', "
        "r => process.exit(r.statusCode >= 200 && r.statusCode < 300 ? 0 : 1))"
        ".on('error', () => process.exit(1))"
    )
    deadline = time.time() + 180
    while time.time() < deadline:
        completed = compose(["exec", "-T", "app", "node", "-e", script], check=False)
        if completed.returncode == 0:
            return
        time.sleep(2)
    print("error: app did not become healthy")
    compose(["ps"], check=False)
    compose(["logs", "app", "--tail=100"], check=False)
    raise SystemExit(1)


def start_ordered() -> None:
    compose(["up", "-d", "redis"])
    wait_for_redis()
    compose(
        ["up", "-d", "app", "audit-proxy", "vitaldb-observer", "redis-ui", "swagger-ui"]
    )
    wait_for_app()
    compose(["up", "-d", "edge"])


def start_testkit(runtime_config: dict[str, object]) -> None:
    if runtime_config["testkitEnabled"] is True:
        load_optional_docker_images()
        compose(["up", "-d", "testkit"])


def start_testkit_logged(runtime_config: dict[str, object]) -> None:
    log_file = MOUNT_POINT / "run" / "testkit-provision.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)
    with log_file.open("w", encoding="utf-8") as handle:
        if runtime_config["testkitEnabled"] is not True:
            handle.write(f"Optional TestKit service is disabled at {utc_now()}\n")
            return
        handle.write(
            f"Starting optional TestKit service via Docker Compose at {utc_now()}\n"
        )
        start_testkit(runtime_config)
        handle.write(
            f"Optional TestKit service provisioning completed at {utc_now()}\n"
        )
