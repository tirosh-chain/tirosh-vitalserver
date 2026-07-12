from __future__ import annotations

from pathlib import Path

from tirosh_guest_tools.adapters.inbound.control_store_migration import (
    migrate_control_store,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control import SQLiteControlRepository


def test_explicit_control_store_migration_creates_and_verifies_ledger(
    tmp_path: Path,
) -> None:
    control_state_dir = tmp_path / "control"

    proof = migrate_control_store(control_state_dir)

    assert proof == {
        "schemaVersion": 1,
        "status": "passed",
        "databasePath": str(control_state_dir / "control.sqlite"),
    }
    SQLiteControlRepository(control_state_dir / "control.sqlite").check_ready()
