from __future__ import annotations

import json
import os
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, TextIO

from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.errors import (
    GuestContractError,
    GuestOperationRequestError,
)
from tirosh_guest_tools.settings import SETTINGS

MOUNT_TAG = SETTINGS.shares.runtime_tag
MOUNT_POINT = SETTINGS.shares.runtime_mount
VITAL_FILES_MOUNT_TAG = SETTINGS.shares.vital_files_tag
VITAL_FILES_MOUNT_POINT = SETTINGS.shares.vital_files_mount
DEPLOY_DIR = SETTINGS.paths.deploy_dir
RUNTIME_DIR = SETTINGS.paths.runtime_dir
PROJECT_NAME = SETTINGS.compose.project_name


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def mount_share(tag: str = MOUNT_TAG, mount_point: Path = MOUNT_POINT) -> None:
    mount_point.mkdir(parents=True, exist_ok=True)
    if not is_mountpoint(mount_point):
        subprocess.run(["mount", "-t", "virtiofs", tag, str(mount_point)], check=True)


def mount_runtime_share() -> None:
    mount_share(MOUNT_TAG, MOUNT_POINT)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)


def mount_vital_files_share() -> None:
    mount_share(VITAL_FILES_MOUNT_TAG, VITAL_FILES_MOUNT_POINT)


def is_mountpoint(path: Path) -> bool:
    return subprocess.run(["mountpoint", "-q", str(path)], check=False).returncode == 0


def compose_command(arguments: list[str]) -> list[str]:
    return [
        "docker",
        "compose",
        "--project-name",
        PROJECT_NAME,
        "-f",
        str(DEPLOY_DIR / RuntimeFileName.COMPOSE.value),
        *arguments,
    ]


def run(
    arguments: list[str],
    *,
    check: bool = True,
    stdout: int | TextIO | None = None,
    stderr: int | TextIO | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        check=check,
        text=True,
        stdout=stdout,
        stderr=stderr,
    )


def output(arguments: list[str], *, check: bool = True) -> str:
    completed = subprocess.run(
        arguments,
        check=check,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise GuestContractError(
            f"expected JSON object: {path}",
            code="guest-json-object-invalid",
        )
    return value


def write_json(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def request_id_from(path: Path) -> str:
    request_id = read_json(path).get("requestId")
    if not isinstance(request_id, str) or not request_id:
        raise GuestOperationRequestError(
            f"requestId is missing: {path}",
            code="guest-operation-request-id-missing",
        )
    return request_id


def request_version_from(path: Path) -> str:
    document = read_json(path)
    if "version" not in document:
        return ""
    version = document["version"]
    if not isinstance(version, str):
        raise GuestOperationRequestError(
            f"version must be a string when present: {path}",
            code="guest-operation-request-version-invalid",
        )
    return version


def systemctl(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["systemctl", *arguments], check=check)


def service_is_running(service: str) -> bool:
    completed = subprocess.run(
        ["systemctl", "show", "--property=ActiveState", "--value", service],
        check=False,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip() in {"active", "activating"}
