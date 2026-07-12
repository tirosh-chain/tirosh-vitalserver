from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from tirosh_guest_tools.contracts import RuntimeCommand
from tirosh_guest_tools.infrastructure.settings import (
    DEFAULT_SETTINGS_PATH,
    SETTINGS,
    install_default_settings,
)

GUEST_TOOLS_HOME = SETTINGS.paths.guest_tools_home
GUEST_TOOLS_VENV = GUEST_TOOLS_HOME / "venv"
PYTHON_WHEEL_DIR = SETTINGS.paths.python_wheel_dir

COMMANDS = [
    RuntimeCommand.GUEST_OBSERVED,
    RuntimeCommand.GUEST_OBSERVE,
    RuntimeCommand.GUEST_CONTAINER_LOGS,
    RuntimeCommand.GUEST_DIAGNOSTICS,
    RuntimeCommand.RUNTIME_ENV,
    RuntimeCommand.WRITE_RUNTIME_OBSERVATION,
    RuntimeCommand.RUNTIME_OBSERVATION,
    RuntimeCommand.VITALSERVER_HEALTH,
    RuntimeCommand.VITALSERVER_COMPOSE,
    RuntimeCommand.VITALSERVER_SYNC_HOST_TIME,
    RuntimeCommand.VITALSERVER_BOOTSTRAP,
    RuntimeCommand.VITALSERVER_ROOTFS_SMOKE,
    RuntimeCommand.VITALSERVER_RUNTIME_BOOT_SMOKE,
    RuntimeCommand.VITALSERVER_RUNTIME_DATA_PREPARE,
    RuntimeCommand.VITALSERVER_REDIS_RESTORE,
    RuntimeCommand.VITALSERVER_GUEST_CONTROL_API,
    RuntimeCommand.VITALSERVER_REDIS_BACKUP,
    RuntimeCommand.VITALSERVER_REPAIR_DATASTORE,
    RuntimeCommand.VITALSERVER_ACTIVATE_UPDATE,
    RuntimeCommand.VITALSERVER_PREPARE_UPDATE_SHUTDOWN,
    RuntimeCommand.GUEST_TOOLS_INSTALL_CONFIG,
]

COMPATIBILITY_LINKS = {
    RuntimeCommand.VITALSERVER_CONTAINER_LOGS: RuntimeCommand.GUEST_CONTAINER_LOGS,
    RuntimeCommand.VITALSERVER_DIAGNOSTICS: RuntimeCommand.GUEST_DIAGNOSTICS,
}


def install_guest_tools_runtime() -> None:
    installer = guest_tools_runtime_installer(PYTHON_WHEEL_DIR)
    subprocess.run(
        [
            sys.executable,
            str(installer),
            "--wheel-dir",
            str(PYTHON_WHEEL_DIR),
            "--guest-tools-home",
            str(GUEST_TOOLS_HOME),
        ],
        check=True,
    )
    for command in COMMANDS:
        link_command(command.value, command.value)
    for compatibility_name, target_name in COMPATIBILITY_LINKS.items():
        link_command(compatibility_name.value, target_name.value)


def migrate_guest_control_store() -> None:
    """Run the configured control store's explicit migration command."""

    subprocess.run(
        [
            str(GUEST_TOOLS_VENV / "bin" / "tirosh-guest-tools-migrate-control-store"),
        ],
        check=True,
    )


def guest_tools_runtime_installer(python_wheel_dir: Path) -> Path:
    """The installer and wheelhouse are one versioned delivery unit."""

    return python_wheel_dir.parent / "install-guest-tools-runtime.py"


def install_guest_tools_config() -> None:
    install_default_settings(DEFAULT_SETTINGS_PATH)


def link_command(name: str, target_name: str) -> None:
    destination = SETTINGS.paths.command_bin_dir / name
    target = GUEST_TOOLS_VENV / "bin" / target_name
    destination.unlink(missing_ok=True)
    destination.symlink_to(target)
