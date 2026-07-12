from pathlib import Path

import pytest

from tirosh_guest_tools.infrastructure import system_install
from tirosh_guest_tools.infrastructure.system_install import (
    guest_tools_runtime_installer,
)


def test_guest_tools_runtime_installer_is_co_located_with_wheelhouse() -> None:
    assert guest_tools_runtime_installer(
        Path("/mnt/tirosh/deploy/python-wheels")
    ) == Path("/mnt/tirosh/deploy/install-guest-tools-runtime.py")
    assert guest_tools_runtime_installer(
        Path("/opt/vitalserver/current/runtime-controller/python-wheels")
    ) == Path(
        "/opt/vitalserver/current/runtime-controller/install-guest-tools-runtime.py"
    )


def test_migrate_guest_control_store_uses_installed_runtime_command(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    commands: list[tuple[list[str], bool]] = []
    monkeypatch.setattr(system_install, "GUEST_TOOLS_VENV", Path("/guest-tools/venv"))
    monkeypatch.setattr(
        system_install.subprocess,
        "run",
        lambda command, *, check: commands.append((command, check)),
    )

    system_install.migrate_guest_control_store(Path("/mnt/runtime/control"))

    assert commands == [
        (
            [
                "/guest-tools/venv/bin/tirosh-guest-tools-migrate-control-store",
                "--control-state-dir",
                "/mnt/runtime/control",
            ],
            True,
        )
    ]
