from __future__ import annotations

import logging
import os
import subprocess
import time

from tirosh_guest_tools.common import (
    DEPLOY_DIR,
    compose_command,
    mount_runtime_share,
    mount_vital_files_share,
    output,
    run,
)
from tirosh_guest_tools.contracts import (
    ComposeService,
    RuntimeFileName,
)
from tirosh_guest_tools.domain.errors import GuestUseCaseInputError
from tirosh_guest_tools.inbound import ComposeAction
from tirosh_guest_tools.runtime.config import RuntimeConfig, load_config
from tirosh_guest_tools.settings import SETTINGS

logger = logging.getLogger(__name__)


def run_compose_action(action: ComposeAction | str) -> None:
    action = ComposeAction(action)
    mount_runtime_share()
    mount_vital_files_share()
    runtime_config = load_runtime_env()

    if action == ComposeAction.UP:
        start_ordered()
    elif action == ComposeAction.TESTKIT_UP:
        start_testkit(runtime_config)
    elif action == ComposeAction.TESTKIT_UP_LOGGED:
        start_testkit_logged(runtime_config)
    elif action == ComposeAction.STOP:
        compose(["stop", "--timeout", str(SETTINGS.compose.stop_timeout_seconds)])
        run(["sync"])
    else:
        raise GuestUseCaseInputError(
            f"unsupported compose action: {action}",
            code="compose-action-unsupported",
        )


def load_runtime_env() -> RuntimeConfig:
    config = load_config(DEPLOY_DIR / RuntimeFileName.RUNTIME_CONFIG.value)
    os.environ["VITALSERVER_REDIS_HOST"] = config.redis_host
    os.environ["VITALSERVER_REDIS_PORT"] = str(config.redis_port)
    os.environ["VITALSERVER_TRUST_PROXY"] = "1" if config.trust_proxy else "0"
    os.environ["VITALSERVER_PUBLIC_HOST"] = config.public_host
    os.environ["VITALSERVER_PUBLIC_PORT"] = str(config.public_port)
    os.environ["VITALSERVER_ADMIN_PASSWORD"] = config.admin_password
    os.environ["VITALSERVER_VITAL_FILES_DIR"] = config.vital_files_directory
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
        logger.info(
            "optional Docker image bundle directory is missing",
            extra={"fields": {"imageDirectory": str(image_dir)}},
        )
        return
    loaded = False
    for image_bundle in sorted(image_dir.iterdir()):
        if image_bundle.suffix not in {".tar", ".gz", ".tgz"}:
            continue
        logger.info(
            "loading optional Docker image bundle",
            extra={"fields": {"imageBundle": str(image_bundle)}},
        )
        run(["docker", "load", "-i", str(image_bundle)])
        loaded = True
    if not loaded:
        logger.info(
            "no optional Docker image bundles found",
            extra={"fields": {"imageDirectory": str(image_dir)}},
        )


def wait_for_redis() -> None:
    deadline = time.time() + 120
    while time.time() < deadline:
        completed = compose(
            ["exec", "-T", ComposeService.REDIS.value, "redis-cli", "ping"],
            check=False,
        )
        if completed.returncode == 0 and "PONG" in output(
            compose_command(
                ["exec", "-T", ComposeService.REDIS.value, "redis-cli", "ping"]
            ),
            check=False,
        ):
            return
        time.sleep(2)
    logger.error("redis did not become ready")
    compose(["ps"], check=False)
    compose(["logs", ComposeService.REDIS.value, "--tail=100"], check=False)
    raise SystemExit(1)


def wait_for_app() -> None:
    script = (
        "require('http').get('http://127.0.0.1/check', "
        "r => process.exit(r.statusCode >= 200 && r.statusCode < 300 ? 0 : 1))"
        ".on('error', () => process.exit(1))"
    )
    deadline = time.time() + 180
    while time.time() < deadline:
        completed = compose(
            ["exec", "-T", ComposeService.APP.value, "node", "-e", script],
            check=False,
        )
        if completed.returncode == 0:
            return
        time.sleep(2)
    logger.error("app did not become healthy")
    compose(["ps"], check=False)
    compose(["logs", ComposeService.APP.value, "--tail=100"], check=False)
    raise SystemExit(1)


def start_ordered() -> None:
    compose(["up", "-d", ComposeService.REDIS.value])
    wait_for_redis()
    compose(
        [
            "up",
            "-d",
            ComposeService.APP.value,
            ComposeService.AUDIT_PROXY.value,
            ComposeService.VITALDB_OBSERVER.value,
            ComposeService.REDIS_UI.value,
            ComposeService.SWAGGER_UI.value,
        ]
    )
    wait_for_app()
    compose(["up", "-d", ComposeService.EDGE.value])


def start_testkit(runtime_config: RuntimeConfig) -> None:
    if runtime_config.testkit_enabled:
        load_optional_docker_images()
        compose(["up", "-d", ComposeService.TESTKIT.value])


def start_testkit_logged(runtime_config: RuntimeConfig) -> None:
    if not runtime_config.testkit_enabled:
        logger.info("optional TestKit service is disabled")
        return
    logger.info("starting optional TestKit service via Docker Compose")
    start_testkit(runtime_config)
    logger.info("optional TestKit service provisioning completed")
