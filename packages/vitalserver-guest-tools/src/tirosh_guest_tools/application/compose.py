from __future__ import annotations

import json
import logging
import os
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tirosh_guest_tools.adapters.outbound.runtime.config import load_config
from tirosh_guest_tools.contracts import (
    ComposeService,
    RuntimeFileName,
)
from tirosh_guest_tools.domain.errors import (
    GuestContractError,
    GuestDependencyError,
    GuestUseCaseInputError,
)
from tirosh_guest_tools.domain.operations import ComposeAction
from tirosh_guest_tools.domain.runtime_config import RuntimeConfig
from tirosh_guest_tools.infrastructure.common import (
    DEPLOY_DIR,
    compose_command,
    mount_runtime_share,
    mount_vital_files_share,
    output,
    read_json,
    run,
)

logger = logging.getLogger(__name__)
COMPOSE_STOP_COMMAND_TIMEOUT_BUFFER_SECONDS = 10
ORDERED_STOP_POLICIES = (
    (ComposeService.TESTKIT, 30),
    (ComposeService.EDGE, 30),
    (ComposeService.SWAGGER_UI, 30),
    (ComposeService.REDIS_UI, 30),
    (ComposeService.RECORDER_INGRESS, 30),
    (ComposeService.VITALDB_OBSERVER, 30),
    (ComposeService.REDIS_RELAY, 30),
    (ComposeService.APP, 90),
    (ComposeService.REDIS, 60),
)
RUNNING_STATES = {"running", "restarting", "removing", "paused"}
RECORDER_INGRESS_SEND_DATA_MODES = {
    "passthrough",
    "mirror_spool",
    "spool_only",
    "spool_and_replay",
}
DEFAULT_RECORDER_INGRESS_SEND_DATA_MODE = "spool_and_replay"
DEFAULT_RECORDER_INGRESS_REPLAY_BATCH_SIZE = 10
DEFAULT_RECORDER_INGRESS_REPLAY_MAX_MIB_PER_SECOND = 20
DEFAULT_CONTAINER_MEMORY_LIMITS_ENABLED = False
DEFAULT_APP_CONTAINER_MEMORY_LIMIT_MIB = 2048
DEFAULT_RECORDER_INGRESS_CONTAINER_MEMORY_LIMIT_MIB = 410
DEFAULT_REDIS_CONTAINER_MEMORY_LIMIT_MIB = 3277
MIB_BYTES = 1024 * 1024


@dataclass(frozen=True)
class ComposeServiceState:
    service: str
    container: str
    state: str
    exit_code: int | None = None
    health: str = ""

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "service": self.service,
            "container": self.container,
            "state": self.state,
            "health": self.health,
        }
        if self.exit_code is not None:
            document["exitCode"] = self.exit_code
        return document


class ComposeStopTimeoutError(GuestDependencyError):
    def __init__(
        self,
        *,
        service: ComposeService,
        stop_timeout_seconds: int,
        command_timeout_seconds: int,
        service_states: list[ComposeServiceState],
        available_services: set[str],
    ) -> None:
        remaining = remaining_service_names(service_states)
        message = (
            "docker compose stop timed out while stopping "
            f"{service.value} after {command_timeout_seconds:g}s"
        )
        if remaining:
            message += f"; remaining services: {', '.join(remaining)}"
        super().__init__(message, code="compose-stop-timeout")
        self.details: dict[str, Any] = {
            "stopAction": "ordered-compose-stop",
            "failedService": service.value,
            "stopTimeoutSeconds": stop_timeout_seconds,
            "commandTimeoutSeconds": command_timeout_seconds,
            "remainingServices": remaining,
            "availableServices": sorted(available_services),
            "serviceStates": [state.as_json() for state in service_states],
        }


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
        stop_services_in_order()
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
    settings_path = DEPLOY_DIR / RuntimeFileName.RUNTIME_SETTINGS.value
    settings_document = read_json(settings_path)
    load_recorder_ingress_send_data_env(settings_document, settings_path)
    write_compose_runtime_limits(settings_document, settings_path)
    return config


def load_recorder_ingress_send_data_env(
    document: dict[str, Any],
    settings_path: os.PathLike[str] | str,
) -> None:
    os.environ["RECORDER_INGRESS_SEND_DATA_MODE"] = recorder_ingress_send_data_mode(
        document,
        settings_path,
    )
    os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE"] = str(
        positive_int_setting(
            document,
            settings_path,
            "recorderIngressSendDataReplayBatchSize",
            DEFAULT_RECORDER_INGRESS_REPLAY_BATCH_SIZE,
            "runtime-settings-recorder-ingress-send-data-replay-batch-size-invalid",
        )
    )
    replay_max_mib_per_second = positive_int_setting(
        document,
        settings_path,
        "recorderIngressSendDataReplayMaxMiBPerSecond",
        DEFAULT_RECORDER_INGRESS_REPLAY_MAX_MIB_PER_SECOND,
        "runtime-settings-recorder-ingress-send-data-replay-max-mib-invalid",
    )
    os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND"] = str(
        replay_max_mib_per_second * MIB_BYTES
    )


def write_compose_runtime_limits(
    document: dict[str, Any],
    settings_path: os.PathLike[str] | str,
) -> None:
    output_path = DEPLOY_DIR / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value
    enabled = bool_setting(
        document,
        settings_path,
        "containerMemoryLimitsEnabled",
        DEFAULT_CONTAINER_MEMORY_LIMITS_ENABLED,
        "runtime-settings-container-memory-limits-enabled-invalid",
    )
    if not enabled:
        try:
            output_path.unlink()
        except FileNotFoundError:
            pass
        return

    limits = {
        ComposeService.APP.value: positive_int_setting(
            document,
            settings_path,
            "vitalServerContainerMemoryLimitMiB",
            DEFAULT_APP_CONTAINER_MEMORY_LIMIT_MIB,
            "runtime-settings-vitalserver-container-memory-limit-mib-invalid",
        ),
        ComposeService.RECORDER_INGRESS.value: positive_int_setting(
            document,
            settings_path,
            "recorderIngressContainerMemoryLimitMiB",
            DEFAULT_RECORDER_INGRESS_CONTAINER_MEMORY_LIMIT_MIB,
            "runtime-settings-recorder-ingress-container-memory-limit-mib-invalid",
        ),
        ComposeService.REDIS.value: positive_int_setting(
            document,
            settings_path,
            "redisContainerMemoryLimitMiB",
            DEFAULT_REDIS_CONTAINER_MEMORY_LIMIT_MIB,
            "runtime-settings-redis-container-memory-limit-mib-invalid",
        ),
    }
    lines = ["services:"]
    for service, limit_mib in limits.items():
        lines.extend([
            f"  {service}:",
            f"    mem_limit: {limit_mib * MIB_BYTES}",
        ])
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def recorder_ingress_send_data_mode(
    document: dict[str, Any],
    settings_path: os.PathLike[str] | str,
) -> str:
    mode = document.get(
        "recorderIngressSendDataMode",
        DEFAULT_RECORDER_INGRESS_SEND_DATA_MODE,
    )
    if not isinstance(mode, str) or mode not in RECORDER_INGRESS_SEND_DATA_MODES:
        raise GuestContractError(
            "runtime settings field is invalid: "
            f"{settings_path} recorderIngressSendDataMode",
            code="runtime-settings-recorder-ingress-send-data-mode-invalid",
        )
    return mode


def positive_int_setting(
    document: dict[str, Any],
    settings_path: os.PathLike[str] | str,
    field: str,
    default: int,
    code: str,
) -> int:
    value = document.get(field, default)
    if not isinstance(value, int) or value <= 0:
        raise GuestContractError(
            f"runtime settings field is invalid: {settings_path} {field}",
            code=code,
        )
    return value


def bool_setting(
    document: dict[str, Any],
    settings_path: os.PathLike[str] | str,
    field: str,
    default: bool,
    code: str,
) -> bool:
    value = document.get(field, default)
    if not isinstance(value, bool):
        raise GuestContractError(
            f"runtime settings field is invalid: {settings_path} {field}",
            code=code,
        )
    return value


def compose(
    arguments: list[str],
    *,
    check: bool = True,
    timeout_seconds: float | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    return run(
        compose_command(arguments),
        check=check,
        stdout=subprocess.PIPE if capture_output else None,
        stderr=subprocess.PIPE if capture_output else None,
        timeout_seconds=timeout_seconds,
    )


def stop_services_in_order() -> None:
    available_services = compose_services()
    for service, stop_timeout_seconds in ORDERED_STOP_POLICIES:
        if service.value not in available_services:
            logger.info(
                "compose service is not present; skipping ordered stop",
                extra={"fields": {"service": service.value}},
            )
            continue
        command_timeout_seconds = (
            stop_timeout_seconds + COMPOSE_STOP_COMMAND_TIMEOUT_BUFFER_SECONDS
        )
        logger.info(
            "compose service stop started",
            extra={
                "fields": {
                    "service": service.value,
                    "stopTimeoutSeconds": stop_timeout_seconds,
                    "commandTimeoutSeconds": command_timeout_seconds,
                }
            },
        )
        try:
            compose(
                ["stop", "--timeout", str(stop_timeout_seconds), service.value],
                timeout_seconds=command_timeout_seconds,
            )
        except subprocess.TimeoutExpired as error:
            states = inspect_compose_service_states(check=False)
            raise ComposeStopTimeoutError(
                service=service,
                stop_timeout_seconds=stop_timeout_seconds,
                command_timeout_seconds=command_timeout_seconds,
                service_states=states,
                available_services=available_services,
            ) from error
        logger.info(
            "compose service stop completed",
            extra={"fields": {"service": service.value}},
        )


def compose_services() -> set[str]:
    completed = compose(["config", "--services"], capture_output=True)
    stdout = required_compose_stdout(
        completed,
        command_description="docker compose config --services",
        missing_code="guest-compose-services-output-missing",
        empty_code="guest-compose-services-output-empty",
    )
    return {
        line.strip()
        for line in stdout.splitlines()
        if line.strip()
    }


def inspect_compose_service_states(*, check: bool = True) -> list[ComposeServiceState]:
    completed = compose(
        ["ps", "--all", "--format", "json"],
        check=check,
        capture_output=True,
    )
    if completed.returncode != 0:
        return []
    if completed.stdout is None:
        raise GuestDependencyError(
            "docker compose ps --all --format json did not provide stdout",
            code="guest-compose-ps-output-missing",
        )
    return parse_compose_ps_json(completed.stdout)


def required_compose_stdout(
    completed: subprocess.CompletedProcess[str],
    *,
    command_description: str,
    missing_code: str,
    empty_code: str,
) -> str:
    stdout = completed.stdout
    if stdout is None:
        raise GuestDependencyError(
            f"{command_description} did not provide stdout",
            code=missing_code,
        )
    if not stdout.strip():
        raise GuestDependencyError(
            f"{command_description} produced empty stdout",
            code=empty_code,
        )
    return stdout


def parse_compose_ps_json(stdout: str) -> list[ComposeServiceState]:
    text = stdout.strip()
    if not text:
        return []
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
    else:
        rows = value if isinstance(value, list) else [value]
    return [
        compose_service_state_from_json(row)
        for row in rows
        if isinstance(row, dict)
    ]


def compose_service_state_from_json(row: dict[str, Any]) -> ComposeServiceState:
    return ComposeServiceState(
        service=string_value(row, "Service", "service"),
        container=string_value(row, "Name", "name", "Container", "container"),
        state=string_value(row, "State", "state", "Status", "status"),
        exit_code=int_value(row, "ExitCode", "exitCode"),
        health=string_value(row, "Health", "health"),
    )


def string_value(row: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = row.get(key)
        if value is not None:
            return str(value)
    return ""


def int_value(row: dict[str, Any], *keys: str) -> int | None:
    for key in keys:
        value = row.get(key)
        if isinstance(value, int):
            return value
        if isinstance(value, str) and value.strip():
            try:
                return int(value)
            except ValueError:
                return None
    return None


def remaining_service_names(states: list[ComposeServiceState]) -> list[str]:
    return sorted(
        {
            state.service
            for state in states
            if state.service and state.state.lower() in RUNNING_STATES
        }
    )


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
            ComposeService.RECORDER_INGRESS.value,
            ComposeService.VITALDB_OBSERVER.value,
            ComposeService.REDIS_RELAY.value,
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
