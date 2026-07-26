"""Explicit lifecycle command for the Guest Control SQLite schema."""

from __future__ import annotations

import os
import stat
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.sqlite_control import SQLiteControlRepository
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.infrastructure.settings import (
    ControlStoreSettings,
    validate_control_store_location,
)


def migrate_control_store(
    control_state_dir: Path,
    *,
    control_store: ControlStoreSettings,
) -> dict[str, object]:
    """Apply and verify the control ledger schema at an explicit lifecycle gate."""

    prepare_control_state_directory(control_state_dir, control_store)
    database_path = control_state_dir / "control.sqlite"
    repository = SQLiteControlRepository(database_path)
    repository.migrate_schema()
    repository.check_ready()
    return {
        "schemaVersion": 1,
        "status": "passed",
        "databasePath": str(database_path),
    }


def prepare_control_state_directory(
    control_state_dir: Path,
    control_store: ControlStoreSettings,
) -> None:
    """Verify the platform root before creating Guest-owned state below it."""

    validate_control_store_location(control_store, control_state_dir)
    require_real_control_store_root(control_store)
    if control_store.requires_mount and not control_state_root_is_mounted(
        control_store.root
    ):
        raise GuestControlDependencyError(
            "control SQLite root must be mounted before migration: "
            f"{control_store.root}",
            kind="controlStoreRootNotMounted",
        )

    relative_state_dir = control_state_dir.relative_to(control_store.root)
    current = control_store.root
    for component in relative_state_dir.parts:
        current = current / component
        ensure_real_control_state_directory(current)


def require_real_control_store_root(control_store: ControlStoreSettings) -> None:
    """The platform must provision this root; Guest lifecycle never creates it."""

    try:
        mode = control_store.root.lstat().st_mode
    except FileNotFoundError as error:
        raise GuestControlDependencyError(
            "control SQLite root is missing; platform provisioning is required: "
            f"{control_store.root}",
            kind="controlStoreRootUnavailable",
        ) from error
    except OSError as error:
        raise GuestControlDependencyError(
            "control SQLite root cannot be inspected: "
            f"{control_store.root}: {error}",
            kind="controlStoreRootUnavailable",
        ) from error
    if not stat.S_ISDIR(mode):
        raise GuestControlDependencyError(
            "control SQLite root must be an existing real directory: "
            f"{control_store.root}",
            kind="controlStoreRootUnavailable",
        )


def control_state_root_is_mounted(root: Path) -> bool:
    """Read the operating-system mount state at the lifecycle boundary."""

    return os.path.ismount(root)


def ensure_real_control_state_directory(path: Path) -> None:
    try:
        path.mkdir(mode=0o750)
    except FileExistsError:
        pass
    except OSError as error:
        raise GuestControlDependencyError(
            "control SQLite state directory is unavailable: "
            f"{path}: {error}",
            kind="controlStoreUnavailable",
        ) from error
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise GuestControlDependencyError(
            "control SQLite state directory cannot be inspected: "
            f"{path}: {error}",
            kind="controlStoreUnavailable",
        ) from error
    if not stat.S_ISDIR(mode):
        raise GuestControlDependencyError(
            "control SQLite state directory must be a real directory: "
            f"{path}",
            kind="controlStoreUnavailable",
        )
