from __future__ import annotations

import tomllib
from dataclasses import dataclass
from enum import StrEnum
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

DEFAULT_SETTINGS_PATH = Path("/etc/tirosh/guest-tools.toml")


@dataclass(frozen=True)
class ShareSettings:
    runtime_tag: str
    runtime_mount: Path
    vital_files_tag: str
    vital_files_mount: Path


@dataclass(frozen=True)
class PathSettings:
    deploy_dir: Path
    runtime_dir: Path
    guest_tools_home: Path
    python_wheel_dir: Path
    command_bin_dir: Path


@dataclass(frozen=True)
class ComposeSettings:
    project_name: str
    stop_timeout_seconds: int


@dataclass(frozen=True)
class IntervalSettings:
    command_poll_seconds: int
    runtime_state_seconds: int
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
    document: dict[str, Any] = {}
    if path.is_file():
        with path.open("rb") as handle:
            parsed = tomllib.load(handle)
        if not isinstance(parsed, dict):
            raise GuestContractError(
                f"guest tools settings must be a TOML table: {path}",
                code="guest-tools-settings-invalid",
            )
        document = parsed

    shares = toml_table(document, "shares")
    runtime_mount = toml_path_value(shares, "runtimeMount", "/mnt/tirosh")
    vital_files_mount = toml_path_value(
        shares,
        "vitalFilesMount",
        "/mnt/tirosh-vital-files",
    )

    paths = toml_table(document, "paths")
    deploy_dir = toml_path_value(paths, "deployDir", str(runtime_mount / "deploy"))
    runtime_dir = toml_path_value(paths, "runtimeDir", str(runtime_mount / "run"))
    guest_tools_home = toml_path_value(
        paths,
        "guestToolsHome",
        "/opt/tirosh/guest-tools",
    )

    return GuestToolsSettings(
        shares=ShareSettings(
            runtime_tag=toml_str_value(shares, "runtimeTag", "tirosh"),
            runtime_mount=runtime_mount,
            vital_files_tag=toml_str_value(
                shares,
                "vitalFilesTag",
                "tirosh-vital-files",
            ),
            vital_files_mount=vital_files_mount,
        ),
        paths=PathSettings(
            deploy_dir=deploy_dir,
            runtime_dir=runtime_dir,
            guest_tools_home=guest_tools_home,
            python_wheel_dir=toml_path_value(
                paths,
                "pythonWheelDir",
                str(deploy_dir / "python-wheels"),
            ),
            command_bin_dir=toml_path_value(paths, "commandBinDir", "/usr/local/bin"),
        ),
        compose=ComposeSettings(
            project_name=toml_str_value(
                toml_table(document, "compose"),
                "projectName",
                "vitalserver",
            ),
            stop_timeout_seconds=toml_int_value(
                toml_table(document, "compose"),
                "stopTimeoutSeconds",
                120,
                minimum=1,
            ),
        ),
        intervals=IntervalSettings(
            command_poll_seconds=toml_int_value(
                toml_table(document, "intervals"),
                "commandPollSeconds",
                3,
                minimum=1,
            ),
            runtime_state_seconds=toml_int_value(
                toml_table(document, "intervals"),
                "runtimeStateSeconds",
                5,
                minimum=1,
            ),
            observability_seconds=toml_float_value(
                toml_table(document, "intervals"),
                "observabilitySeconds",
                10.0,
                minimum=1.0,
            ),
        ),
        container_logs=ContainerLogSettings(
            interval_seconds=toml_float_value(
                toml_table(document, "containerLogs"),
                "intervalSeconds",
                5.0,
                minimum=1.0,
            ),
            tail_lines=toml_str_value(
                toml_table(document, "containerLogs"),
                "tailLines",
                "1000",
            ),
            max_bytes=toml_int_value(
                toml_table(document, "containerLogs"),
                "maxBytes",
                10_485_760,
                minimum=1,
            ),
            retained_files=toml_int_value(
                toml_table(document, "containerLogs"),
                "retainedFiles",
                5,
                minimum=1,
            ),
            rotate_check_lines=toml_int_value(
                toml_table(document, "containerLogs"),
                "rotateCheckLines",
                200,
                minimum=1,
            ),
        ),
        observability=ObservabilitySettings(
            vitaldb_observer_url=toml_str_value(
                toml_table(document, "observability"),
                "vitaldbObserverUrl",
                "http://127.0.0.1:18084/api/v1/observations",
            )
        ),
        logging=LoggingSettings(
            format=toml_enum_value(
                toml_table(document, "logging"),
                "format",
                "json",
                LoggingFormat,
                choices="json",
            ),
            level=toml_enum_value(
                toml_table(document, "logging"),
                "level",
                "info",
                LoggingLevel,
                choices="debug, info, warning, error, critical",
            ),
            stream_enabled=toml_bool_value(
                toml_table(document, "logging"),
                "streamEnabled",
                True,
            ),
            file_enabled=toml_bool_value(
                toml_table(document, "logging"),
                "fileEnabled",
                True,
            ),
        ),
        guest_hostname=toml_str_value(document, "guestHostname", "tirosh-vitalserver"),
    )


SETTINGS = load_settings()
