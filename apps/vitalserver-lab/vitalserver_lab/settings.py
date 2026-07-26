from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class LabSettings:
    host: str
    port: int
    service_name: str
    session_store: str
    allow_memory_store: bool
    database_url: str | None
    vital_files_mount: Path
    recorder_archive_finalize_url: str | None = None


class LabSettingsConfigurationError(Exception):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


def bool_from_env(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


def int_from_env(name: str, *, default: int) -> int:
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    try:
        value = int(raw_value)
    except ValueError as error:
        raise LabSettingsConfigurationError(
            f"{name} must be an integer.",
            kind="labSettingsInvalidInteger",
        ) from error
    if value <= 0:
        raise LabSettingsConfigurationError(
            f"{name} must be greater than zero.",
            kind="labSettingsInvalidInteger",
        )
    return value


def load_settings() -> LabSettings:
    return LabSettings(
        host=os.environ.get("VITALSERVER_LAB_HOST", "0.0.0.0"),
        port=int_from_env("VITALSERVER_LAB_PORT", default=8080),
        service_name=os.environ.get("VITALSERVER_LAB_SERVICE_NAME", "vitalserver-lab"),
        session_store=os.environ.get("VITALSERVER_LAB_SESSION_STORE", "postgres"),
        allow_memory_store=bool_from_env("VITALSERVER_LAB_ALLOW_MEMORY_STORE"),
        database_url=os.environ.get("VITALSERVER_LAB_DATABASE_URL"),
        vital_files_mount=Path(
            os.environ.get(
                "VITALSERVER_LAB_VITAL_FILES_MOUNT",
                "/mnt/tirosh-vital-files",
            )
        ),
        recorder_archive_finalize_url=os.environ.get(
            "VITALSERVER_LAB_RECORDER_ARCHIVE_FINALIZE_URL",
            "http://recorder-ingress:8080/recorder-ingress/raw-archive/finalize",
        ),
    )
