from __future__ import annotations

import sys
import tomllib
from pathlib import Path
from types import SimpleNamespace

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


def test_control_store_migration_cli_uses_the_configured_data_root(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    requested_locations: list[tuple[Path, object]] = []
    control_state_dir = Path("/guest-owned/control")
    control_store = SimpleNamespace(
        root=Path("/guest-owned"),
        requires_mount=False,
    )
    monkeypatch.setattr(
        sys,
        "argv",
        ["tirosh-guest-tools-migrate-control-store"],
    )
    monkeypatch.setattr(
        cli,
        "SETTINGS",
        SimpleNamespace(
            paths=SimpleNamespace(control_state_dir=control_state_dir),
            control_store=control_store,
        ),
    )

    def migrate(path: Path, *, control_store: object) -> dict[str, object]:
        requested_locations.append((path, control_store))
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

    assert requested_locations == [(control_state_dir, control_store)]
    assert capsys.readouterr().out == (
        '{"databasePath": "/guest-owned/control/control.sqlite", '
        '"schemaVersion": 1, "status": "passed"}\n'
    )


def test_control_store_migration_cli_reports_dependency_failure(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(
        sys,
        "argv",
        ["tirosh-guest-tools-migrate-control-store"],
    )

    def fail(_: Path, *, control_store: object) -> dict[str, object]:
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


def test_control_store_migration_cli_rejects_alternate_data_root(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "tirosh-guest-tools-migrate-control-store",
            "--control-state-dir",
            "/another/control",
        ],
    )

    with pytest.raises(SystemExit) as exit_error:
        cli.guest_tools_migrate_control_store()

    assert exit_error.value.code == 2
    assert "unrecognized arguments: --control-state-dir /another/control" in (
        capsys.readouterr().err
    )
