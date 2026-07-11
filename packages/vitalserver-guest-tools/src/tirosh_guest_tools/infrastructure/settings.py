from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from enum import StrEnum
from importlib.resources import files
from pathlib import Path
from typing import Any

from tirosh_guest_tools.domain.errors import GuestContractError
from tirosh_guest_tools.infrastructure.settings_utils import (
    toml_bool_value,
    toml_enum_value,
    toml_float_value,
    toml_int_value,
    toml_path_value,
    toml_str_value,
    toml_table,
)

SETTINGS_PATH_ENVIRONMENT = "VITALSERVER_RUNTIME_CONTROLLER_SETTINGS_PATH"
_configured_settings_path = os.environ.get(SETTINGS_PATH_ENVIRONMENT)
if _configured_settings_path == "":
    raise GuestContractError(
        f"{SETTINGS_PATH_ENVIRONMENT} must be a non-empty path when configured",
        code="guest-tools-settings-path-invalid",
    )
DEFAULT_SETTINGS_PATH = Path(
    _configured_settings_path
    if _configured_settings_path is not None
    else "/etc/tirosh/guest-tools.toml"
)
DEFAULT_SETTINGS_RESOURCE = "resources/guest-tools.toml"


@dataclass(frozen=True)
class ShareSettings:
    runtime_tag: str
    runtime_mount: Path
    runtime_mount_mode: ShareMountMode
    vital_files_tag: str
    vital_files_mount: Path
    vital_files_mount_mode: ShareMountMode


class ShareMountMode(StrEnum):
    VIRTIOFS = "virtiofs"
    NATIVE = "native"


@dataclass(frozen=True)
class PathSettings:
    deploy_dir: Path
    runtime_dir: Path
    compose_file: Path
    runtime_config_file: Path
    runtime_settings_file: Path
    redis_relay_config_file: Path
    redis_relay_password_file: Path
    compose_runtime_limits_file: Path
    guest_tools_home: Path
    python_wheel_dir: Path
    command_bin_dir: Path


@dataclass(frozen=True)
class ComposeSettings:
    project_name: str
    environment_file: Path
    stop_timeout_seconds: int


@dataclass(frozen=True)
class IntervalSettings:
    command_poll_seconds: int
    runtime_observation_seconds: int
    observability_seconds: float


@dataclass(frozen=True)
class ContainerLogSettings:
    interval_seconds: float
    tail_lines: str
    max_bytes: int
    retained_files: int
    rotate_check_lines: int


@dataclass(frozen=True)
class ObservabilitySettings:
    vitaldb_observer_url: str


class LoggingFormat(StrEnum):
    JSON = "json"


class LoggingLevel(StrEnum):
    DEBUG = "debug"
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


@dataclass(frozen=True)
class LoggingSettings:
    format: LoggingFormat
    level: LoggingLevel
    stream_enabled: bool
    file_enabled: bool


@dataclass(frozen=True)
class GuestToolsSettings:
    shares: ShareSettings
    paths: PathSettings
    compose: ComposeSettings
    intervals: IntervalSettings
    container_logs: ContainerLogSettings
    observability: ObservabilitySettings
    logging: LoggingSettings
    guest_hostname: str


def load_settings(path: Path = DEFAULT_SETTINGS_PATH) -> GuestToolsSettings:
    document = default_settings_document()
    if path.is_file():
        document = merge_toml_documents(document, read_settings_file(path))

    shares = toml_table(document, "shares")
    runtime_mount = toml_path_value(shares, "runtimeMount")
    vital_files_mount = toml_path_value(shares, "vitalFilesMount")

    paths = toml_table(document, "paths")
    deploy_dir = toml_path_value(paths, "deployDir")
    runtime_dir = toml_path_value(paths, "runtimeDir")
    guest_tools_home = toml_path_value(paths, "guestToolsHome")

    return GuestToolsSettings(
        shares=ShareSettings(
            runtime_tag=toml_str_value(shares, "runtimeTag"),
            runtime_mount=runtime_mount,
            runtime_mount_mode=toml_enum_value(
                shares,
                "runtimeMountMode",
                ShareMountMode,
                choices="virtiofs, native",
            ),
            vital_files_tag=toml_str_value(shares, "vitalFilesTag"),
            vital_files_mount=vital_files_mount,
            vital_files_mount_mode=toml_enum_value(
                shares,
                "vitalFilesMountMode",
                ShareMountMode,
                choices="virtiofs, native",
            ),
        ),
        paths=PathSettings(
            deploy_dir=deploy_dir,
            runtime_dir=runtime_dir,
            compose_file=toml_path_value(paths, "composeFile"),
            runtime_config_file=toml_path_value(paths, "runtimeConfigFile"),
            runtime_settings_file=toml_path_value(paths, "runtimeSettingsFile"),
            redis_relay_config_file=toml_path_value(paths, "redisRelayConfigFile"),
            redis_relay_password_file=toml_path_value(paths, "redisRelayPasswordFile"),
            compose_runtime_limits_file=toml_path_value(
                paths,
                "composeRuntimeLimitsFile",
            ),
            guest_tools_home=guest_tools_home,
            python_wheel_dir=toml_path_value(paths, "pythonWheelDir"),
            command_bin_dir=toml_path_value(paths, "commandBinDir"),
        ),
        compose=ComposeSettings(
            project_name=toml_str_value(
                toml_table(document, "compose"),
                "projectName",
            ),
            environment_file=toml_path_value(
                toml_table(document, "compose"),
                "environmentFile",
            ),
            stop_timeout_seconds=toml_int_value(
                toml_table(document, "compose"),
                "stopTimeoutSeconds",
                minimum=1,
            ),
        ),
        intervals=IntervalSettings(
            command_poll_seconds=toml_int_value(
                toml_table(document, "intervals"),
                "commandPollSeconds",
                minimum=1,
            ),
            runtime_observation_seconds=toml_int_value(
                toml_table(document, "intervals"),
                "runtimeObservationSeconds",
                minimum=1,
            ),
            observability_seconds=toml_float_value(
                toml_table(document, "intervals"),
                "observabilitySeconds",
                minimum=1.0,
            ),
        ),
        container_logs=ContainerLogSettings(
            interval_seconds=toml_float_value(
                toml_table(document, "containerLogs"),
                "intervalSeconds",
                minimum=1.0,
            ),
            tail_lines=toml_str_value(
                toml_table(document, "containerLogs"),
                "tailLines",
            ),
            max_bytes=toml_int_value(
                toml_table(document, "containerLogs"),
                "maxBytes",
                minimum=1,
            ),
            retained_files=toml_int_value(
                toml_table(document, "containerLogs"),
                "retainedFiles",
                minimum=1,
            ),
            rotate_check_lines=toml_int_value(
                toml_table(document, "containerLogs"),
                "rotateCheckLines",
                minimum=1,
            ),
        ),
        observability=ObservabilitySettings(
            vitaldb_observer_url=toml_str_value(
                toml_table(document, "observability"),
                "vitaldbObserverUrl",
            )
        ),
        logging=LoggingSettings(
            format=toml_enum_value(
                toml_table(document, "logging"),
                "format",
                LoggingFormat,
                choices="json",
            ),
            level=toml_enum_value(
                toml_table(document, "logging"),
                "level",
                LoggingLevel,
                choices="debug, info, warning, error, critical",
            ),
            stream_enabled=toml_bool_value(
                toml_table(document, "logging"),
                "streamEnabled",
            ),
            file_enabled=toml_bool_value(
                toml_table(document, "logging"),
                "fileEnabled",
            ),
        ),
        guest_hostname=toml_str_value(document, "guestHostname"),
    )


def read_settings_file(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        parsed = tomllib.load(handle)
    if not isinstance(parsed, dict):
        raise GuestContractError(
            f"guest tools settings must be a TOML table: {path}",
            code="guest-tools-settings-invalid",
        )
    return parsed


def default_settings_text() -> str:
    return files("tirosh_guest_tools").joinpath(DEFAULT_SETTINGS_RESOURCE).read_text(
        encoding="utf-8"
    )


def default_settings_document() -> dict[str, Any]:
    parsed = tomllib.loads(default_settings_text())
    if not isinstance(parsed, dict):
        raise GuestContractError(
            "guest tools packaged default settings must be a TOML table",
            code="guest-tools-settings-invalid",
        )
    return parsed


def merge_toml_documents(
    base: dict[str, Any],
    override: dict[str, Any],
) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        base_value = merged.get(key)
        if isinstance(base_value, dict) and isinstance(value, dict):
            merged[key] = merge_toml_documents(base_value, value)
        else:
            merged[key] = value
    return merged


def install_default_settings(
    path: Path = DEFAULT_SETTINGS_PATH,
    *,
    overwrite: bool = False,
) -> None:
    if path.exists() and not overwrite:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(default_settings_text(), encoding="utf-8")
    os.replace(temporary, path)


SETTINGS = load_settings()
