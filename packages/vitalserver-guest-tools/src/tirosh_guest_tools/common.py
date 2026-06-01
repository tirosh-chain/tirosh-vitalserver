from __future__ import annotations

import json
import os
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, TextIO

MOUNT_TAG = os.environ.get("TIROSH_SHARE_TAG", "tirosh")
MOUNT_POINT = Path(os.environ.get("TIROSH_SHARE_MOUNT", "/mnt/tirosh"))
VITAL_FILES_MOUNT_TAG = os.environ.get(
    "TIROSH_VITAL_FILES_SHARE_TAG", "tirosh-vital-files"
)
VITAL_FILES_MOUNT_POINT = Path(
    os.environ.get("TIROSH_VITAL_FILES_SHARE_MOUNT", "/mnt/tirosh-vital-files")
)
DEPLOY_DIR = Path(os.environ.get("TIROSH_DEPLOY_DIR", str(MOUNT_POINT / "deploy")))
RUNTIME_DIR = Path(os.environ.get("TIROSH_RUNTIME_DIR", str(MOUNT_POINT / "run")))
PROJECT_NAME = os.environ.get(
    "TIROSH_COMPOSE_PROJECT_NAME",
    os.environ.get("TIROSH_COMPOSE_PROJECT", "vitalserver"),
)


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
        str(DEPLOY_DIR / "compose.yaml"),
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
        raise ValueError(f"expected JSON object: {path}")
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
        raise ValueError(f"requestId is missing: {path}")
    return request_id


def request_version_from(path: Path) -> str:
    version = read_json(path).get("version", "")
    return version if isinstance(version, str) else ""


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


class Tee:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle: TextIO | None = None

    def __enter__(self) -> Tee:
        self.handle = self.path.open("w", encoding="utf-8")
        return self

    def __exit__(self, *_: object) -> None:
        if self.handle:
            self.handle.close()

    def write(self, text: str) -> None:
        print(text, flush=True)
        if self.handle:
            self.handle.write(text)
            self.handle.write("\n")
            self.handle.flush()

    def log(self, text: str) -> None:
        self.write(f"{utc_now()} {text}")
