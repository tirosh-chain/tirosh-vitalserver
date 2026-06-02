from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from tirosh_guest_tools.contracts import RuntimeCommand
from tirosh_guest_tools.domain.errors import GuestDependencyError
from tirosh_guest_tools.infrastructure.settings import SETTINGS

GUEST_TOOLS_HOME = SETTINGS.paths.guest_tools_home
GUEST_TOOLS_VENV = GUEST_TOOLS_HOME / "venv"
PYTHON_WHEEL_DIR = SETTINGS.paths.python_wheel_dir

COMMANDS = [
    RuntimeCommand.GUEST_OBSERVED,
    RuntimeCommand.GUEST_OBSERVE,
    RuntimeCommand.GUEST_CONTAINER_LOGS,
    RuntimeCommand.GUEST_DIAGNOSTICS,
    RuntimeCommand.RUNTIME_ENV,
    RuntimeCommand.WRITE_RUNTIME_STATE,
    RuntimeCommand.RUNTIME_STATE,
    RuntimeCommand.VITALSERVER_HEALTH,
    RuntimeCommand.VITALSERVER_COMPOSE,
    RuntimeCommand.VITALSERVER_COMMAND_POLLER,
    RuntimeCommand.VITALSERVER_REDIS_BACKUP,
    RuntimeCommand.VITALSERVER_REPAIR_DATASTORE,
    RuntimeCommand.VITALSERVER_ACTIVATE_UPDATE,
    RuntimeCommand.VITALSERVER_PREPARE_UPDATE_SHUTDOWN,
]

COMPATIBILITY_LINKS = {
    RuntimeCommand.VITALSERVER_CONTAINER_LOGS: RuntimeCommand.GUEST_CONTAINER_LOGS,
    RuntimeCommand.VITALSERVER_DIAGNOSTICS: RuntimeCommand.GUEST_DIAGNOSTICS,
}


def install_guest_tools_runtime() -> None:
    wheel = latest_guest_tools_wheel()
    GUEST_TOOLS_HOME.mkdir(parents=True, exist_ok=True)
    if running_inside_guest_tools_venv():
        install_python = GUEST_TOOLS_VENV / "bin" / "python"
    else:
        subprocess.run(
            [sys.executable, "-m", "venv", "--clear", str(GUEST_TOOLS_VENV)],
            check=True,
        )
        install_python = GUEST_TOOLS_VENV / "bin" / "python"
    subprocess.run(
        [
            str(install_python),
            "-m",
            "pip",
            "install",
            "--no-index",
            "--no-deps",
            str(wheel),
        ],
        check=True,
    )
    for command in COMMANDS:
        link_command(command.value, command.value)
    for compatibility_name, target_name in COMPATIBILITY_LINKS.items():
        link_command(compatibility_name.value, target_name.value)


def latest_guest_tools_wheel() -> Path:
    wheels = sorted(PYTHON_WHEEL_DIR.glob("tirosh_vitalserver_guest_tools-*.whl"))
    if not wheels:
        raise GuestDependencyError(
            f"missing guest tools wheel under {PYTHON_WHEEL_DIR}",
            code="guest-tools-wheel-missing",
        )
    return wheels[-1]


def running_inside_guest_tools_venv() -> bool:
    executable = Path(sys.executable).resolve()
    try:
        executable.relative_to(GUEST_TOOLS_VENV.resolve())
        return True
    except ValueError:
        return False


def link_command(name: str, target_name: str) -> None:
    destination = SETTINGS.paths.command_bin_dir / name
    target = GUEST_TOOLS_VENV / "bin" / target_name
    destination.unlink(missing_ok=True)
    destination.symlink_to(target)
