from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.inbound.control_store_migration import (
    migrate_control_store,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control import SQLiteControlRepository
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.infrastructure.settings import ControlStoreSettings


def test_explicit_control_store_migration_creates_and_verifies_ledger(
    tmp_path: Path,
) -> None:
    control_root = tmp_path / "runtime-data"
    control_root.mkdir()
    control_state_dir = control_root / "control"

    proof = migrate_control_store(
        control_state_dir,
        control_store=ControlStoreSettings(
            root=control_root,
            requires_mount=False,
        ),
    )

    assert proof == {
        "schemaVersion": 1,
        "status": "passed",
        "databasePath": str(control_state_dir / "control.sqlite"),
    }
    SQLiteControlRepository(control_state_dir / "control.sqlite").check_ready()


def test_control_store_migration_does_not_create_missing_platform_root(
    tmp_path: Path,
) -> None:
    control_root = tmp_path / "runtime-data"
    control_state_dir = control_root / "control"

    with pytest.raises(GuestControlDependencyError) as error:
        migrate_control_store(
            control_state_dir,
            control_store=ControlStoreSettings(
                root=control_root,
                requires_mount=False,
            ),
        )

    assert error.value.kind == "controlStoreRootUnavailable"
    assert not control_root.exists()
    assert not (control_state_dir / "control.sqlite").exists()


def test_control_store_migration_requires_declared_mount_before_writing(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    control_root = tmp_path / "runtime-data"
    control_root.mkdir()
    control_state_dir = control_root / "control"
    monkeypatch.setattr(
        "tirosh_guest_tools.adapters.inbound.control_store_migration."
        "control_state_root_is_mounted",
        lambda _: False,
    )

    with pytest.raises(GuestControlDependencyError) as error:
        migrate_control_store(
            control_state_dir,
            control_store=ControlStoreSettings(
                root=control_root,
                requires_mount=True,
            ),
        )

    assert error.value.kind == "controlStoreRootNotMounted"
    assert not control_state_dir.exists()
    assert not (control_state_dir / "control.sqlite").exists()


def test_control_store_migration_rejects_symlink_root(
    tmp_path: Path,
) -> None:
    actual_root = tmp_path / "actual-runtime-data"
    actual_root.mkdir()
    control_root = tmp_path / "runtime-data"
    control_root.symlink_to(actual_root, target_is_directory=True)
    control_state_dir = control_root / "control"

    with pytest.raises(GuestControlDependencyError) as error:
        migrate_control_store(
            control_state_dir,
            control_store=ControlStoreSettings(
                root=control_root,
                requires_mount=False,
            ),
        )

    assert error.value.kind == "controlStoreRootUnavailable"
    assert not (actual_root / "control.sqlite").exists()
