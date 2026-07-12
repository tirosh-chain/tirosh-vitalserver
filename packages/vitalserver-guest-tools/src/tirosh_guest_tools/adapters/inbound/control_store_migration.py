"""Explicit lifecycle command for the Guest Control SQLite schema."""

from __future__ import annotations

from pathlib import Path

from tirosh_guest_tools.adapters.outbound.sqlite_control import SQLiteControlRepository


def migrate_control_store(control_state_dir: Path) -> dict[str, object]:
    """Apply and verify the control ledger schema at an explicit lifecycle gate."""

    database_path = control_state_dir / "control.sqlite"
    repository = SQLiteControlRepository(database_path)
    repository.migrate_schema()
    repository.check_ready()
    return {
        "schemaVersion": 1,
        "status": "passed",
        "databasePath": str(database_path),
    }
