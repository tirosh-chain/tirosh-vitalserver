from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import HostProxyInput


def create_env_file_from_example(root: Path) -> bool:
    env_file = root / ".env"
    if env_file.is_file():
        return False
    shutil.copy2(root / ".env.example", env_file)
    return True


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def run_command_quiet(command: list[str]) -> bool:
    return (
        subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def submodule_exists(root: Path) -> bool:
    return (root / "vendor/vitalserver/.git").exists()


def sync_python_workspace(root: Path, uv: str) -> int:
    return subprocess.run([uv, "sync"], cwd=root, check=False).returncode


def run_compose_config(input: HostProxyInput, compose: str) -> bool:
    environment = {
        "VITALSERVER_BIND_HOST": input.bind_host,
        "VITALSERVER_HTTP_PORT": input.http_port,
        "VITALSERVER_TRUST_PROXY": input.trust_proxy,
    }
    return (
        subprocess.run(
            [*compose.split(), "config"],
            cwd=repo_root(),
            env={**os.environ, **environment},
            check=False,
        ).returncode
        == 0
    )


def installed_testkit_runtime(python: str) -> bool:
    return (
        subprocess.run(
            [
                python,
                "-c",
                "import pydantic_settings, tirosh_vitalserver.testkit",
            ],
            check=False,
        ).returncode
        == 0
    )
