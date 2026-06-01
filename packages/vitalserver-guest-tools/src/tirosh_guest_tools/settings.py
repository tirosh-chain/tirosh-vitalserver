from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

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


@dataclass(frozen=True)
class GuestToolsSettings:
    shares: ShareSettings
    paths: PathSettings
    compose: ComposeSettings
    intervals: IntervalSettings
    container_logs: ContainerLogSettings
    observability: ObservabilitySettings
    guest_hostname: str


def load_settings(path: Path = DEFAULT_SETTINGS_PATH) -> GuestToolsSettings:
    document: dict[str, Any] = {}
    if path.is_file():
        with path.open("rb") as handle:
            parsed = tomllib.load(handle)
        if not isinstance(parsed, dict):
            raise ValueError(f"guest tools settings must be a TOML table: {path}")
        document = parsed

    shares = table(document, "shares")
    runtime_mount = path_value(shares, "runtimeMount", "/mnt/tirosh")
    vital_files_mount = path_value(
        shares,
        "vitalFilesMount",
        "/mnt/tirosh-vital-files",
    )

    paths = table(document, "paths")
    deploy_dir = path_value(paths, "deployDir", str(runtime_mount / "deploy"))
    runtime_dir = path_value(paths, "runtimeDir", str(runtime_mount / "run"))
    guest_tools_home = path_value(paths, "guestToolsHome", "/opt/tirosh/guest-tools")

    return GuestToolsSettings(
        shares=ShareSettings(
            runtime_tag=str_value(shares, "runtimeTag", "tirosh"),
            runtime_mount=runtime_mount,
            vital_files_tag=str_value(shares, "vitalFilesTag", "tirosh-vital-files"),
            vital_files_mount=vital_files_mount,
        ),
        paths=PathSettings(
            deploy_dir=deploy_dir,
            runtime_dir=runtime_dir,
            guest_tools_home=guest_tools_home,
            python_wheel_dir=path_value(
                paths,
                "pythonWheelDir",
                str(deploy_dir / "python-wheels"),
            ),
            command_bin_dir=path_value(paths, "commandBinDir", "/usr/local/bin"),
        ),
        compose=ComposeSettings(
            project_name=str_value(
                table(document, "compose"),
                "projectName",
                "vitalserver",
            ),
            stop_timeout_seconds=int_value(
                table(document, "compose"),
                "stopTimeoutSeconds",
                120,
                minimum=1,
            ),
        ),
        intervals=IntervalSettings(
            command_poll_seconds=int_value(
                table(document, "intervals"),
                "commandPollSeconds",
                3,
                minimum=1,
            ),
            runtime_state_seconds=int_value(
                table(document, "intervals"),
                "runtimeStateSeconds",
                5,
                minimum=1,
            ),
            observability_seconds=float_value(
                table(document, "intervals"),
                "observabilitySeconds",
                10.0,
                minimum=1.0,
            ),
        ),
        container_logs=ContainerLogSettings(
            interval_seconds=float_value(
                table(document, "containerLogs"),
                "intervalSeconds",
                5.0,
                minimum=1.0,
            ),
            tail_lines=str_value(table(document, "containerLogs"), "tailLines", "1000"),
            max_bytes=int_value(
                table(document, "containerLogs"),
                "maxBytes",
                10_485_760,
                minimum=1,
            ),
            retained_files=int_value(
                table(document, "containerLogs"),
                "retainedFiles",
                5,
                minimum=1,
            ),
            rotate_check_lines=int_value(
                table(document, "containerLogs"),
                "rotateCheckLines",
                200,
                minimum=1,
            ),
        ),
        observability=ObservabilitySettings(
            vitaldb_observer_url=str_value(
                table(document, "observability"),
                "vitaldbObserverUrl",
                "http://127.0.0.1:18084/api/v1/observations",
            )
        ),
        guest_hostname=str_value(document, "guestHostname", "tirosh-vitalserver"),
    )


def table(document: dict[str, Any], key: str) -> dict[str, Any]:
    value = document.get(key, {})
    if not isinstance(value, dict):
        raise ValueError(f"guest tools setting '{key}' must be a TOML table")
    return value


def str_value(document: dict[str, Any], key: str, default: str) -> str:
    value = document.get(key, default)
    if not isinstance(value, str) or value == "":
        raise ValueError(f"guest tools setting '{key}' must be a non-empty string")
    return value


def path_value(document: dict[str, Any], key: str, default: str) -> Path:
    return Path(str_value(document, key, default))


def int_value(
    document: dict[str, Any],
    key: str,
    default: int,
    *,
    minimum: int,
) -> int:
    value = document.get(key, default)
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"guest tools setting '{key}' must be an integer")
    if value < minimum:
        raise ValueError(f"guest tools setting '{key}' must be >= {minimum}")
    return value


def float_value(
    document: dict[str, Any],
    key: str,
    default: float,
    *,
    minimum: float,
) -> float:
    value = document.get(key, default)
    if not isinstance(value, int | float) or isinstance(value, bool):
        raise ValueError(f"guest tools setting '{key}' must be a number")
    value = float(value)
    if value < minimum:
        raise ValueError(f"guest tools setting '{key}' must be >= {minimum}")
    return value


SETTINGS = load_settings()
