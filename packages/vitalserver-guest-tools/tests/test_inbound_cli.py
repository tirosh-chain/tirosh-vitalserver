from __future__ import annotations

import sys
import tomllib
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.inbound import cli
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError


def test_guest_tools_console_scripts_are_owned_by_inbound_cli() -> None:
    pyproject = Path(__file__).parents[1] / "pyproject.toml"
    with pyproject.open("rb") as handle:
        document = tomllib.load(handle)

    scripts = document["project"]["scripts"]

    assert scripts
    for target in scripts.values():
        assert target.startswith("tirosh_guest_tools.adapters.inbound.cli:")


def test_control_store_migration_cli_passes_the_explicit_data_root(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    requested_paths: list[Path] = []
    control_state_dir = Path("/mnt/runtime/control")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "tirosh-guest-tools-migrate-control-store",
            "--control-state-dir",
            str(control_state_dir),
        ],
    )

    def migrate(path: Path) -> dict[str, object]:
        requested_paths.append(path)
        return {
            "databasePath": str(path / "control.sqlite"),
            "schemaVersion": 1,
            "status": "passed",
        }

    monkeypatch.setattr(
        cli,
        "migrate_control_store",
        migrate,
    )

    assert cli.guest_tools_migrate_control_store() == 0

    assert requested_paths == [control_state_dir]
    assert capsys.readouterr().out == (
        '{"databasePath": "/mnt/runtime/control/control.sqlite", '
        '"schemaVersion": 1, "status": "passed"}\n'
    )


def test_control_store_migration_cli_reports_dependency_failure(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "tirosh-guest-tools-migrate-control-store",
            "--control-state-dir",
            "/mnt/runtime/control",
        ],
    )

    def fail(_: Path) -> dict[str, object]:
        raise GuestControlDependencyError(
            "the control database cannot be opened",
            kind="controlStoreUnavailable",
        )

    monkeypatch.setattr(cli, "migrate_control_store", fail)

    with pytest.raises(SystemExit) as exit_error:
        cli.guest_tools_migrate_control_store()

    assert exit_error.value.code == 1
    assert capsys.readouterr().err == (
        "error: controlStoreUnavailable: the control database cannot be opened\n"
    )
