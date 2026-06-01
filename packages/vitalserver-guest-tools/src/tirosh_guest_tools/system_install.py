from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

GUEST_TOOLS_HOME = Path(
    os.environ.get("TIROSH_GUEST_TOOLS_HOME", "/opt/tirosh/guest-tools")
)
GUEST_TOOLS_VENV = GUEST_TOOLS_HOME / "venv"
PYTHON_WHEEL_DIR = Path(
    os.environ.get("TIROSH_PYTHON_WHEEL_DIR", "/mnt/tirosh/deploy/python-wheels")
)

COMMANDS = [
    "tirosh-guest-observed",
    "tirosh-guest-observe",
    "tirosh-guest-container-logs",
    "tirosh-guest-diagnostics",
    "tirosh-runtime-env",
    "tirosh-write-runtime-state",
    "tirosh-runtime-state",
    "tirosh-vitalserver-health",
    "tirosh-vitalserver-compose",
    "tirosh-vitalserver-command-poller",
    "tirosh-vitalserver-redis-backup",
    "tirosh-vitalserver-repair-datastore",
    "tirosh-vitalserver-activate-update",
    "tirosh-vitalserver-prepare-update-shutdown",
]

COMPATIBILITY_LINKS = {
    "tirosh-vitalserver-container-logs": "tirosh-guest-container-logs",
    "tirosh-vitalserver-diagnostics": "tirosh-guest-diagnostics",
}


def main() -> int:
    install_guest_tools_runtime()
    return 0


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
        link_command(command, command)
    for compatibility_name, target_name in COMPATIBILITY_LINKS.items():
        link_command(compatibility_name, target_name)


def latest_guest_tools_wheel() -> Path:
    wheels = sorted(PYTHON_WHEEL_DIR.glob("tirosh_vitalserver_guest_tools-*.whl"))
    if not wheels:
        raise FileNotFoundError(f"missing guest tools wheel under {PYTHON_WHEEL_DIR}")
    return wheels[-1]


def running_inside_guest_tools_venv() -> bool:
    executable = Path(sys.executable).resolve()
    try:
        executable.relative_to(GUEST_TOOLS_VENV.resolve())
        return True
    except ValueError:
        return False


def link_command(name: str, target_name: str) -> None:
    destination = Path("/usr/local/bin") / name
    target = GUEST_TOOLS_VENV / "bin" / target_name
    destination.unlink(missing_ok=True)
    destination.symlink_to(target)


if __name__ == "__main__":
    raise SystemExit(main())
