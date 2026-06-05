from __future__ import annotations

import time

from tirosh_guest_tools.adapters.outbound.runtime.state_writer import (
    write_runtime_state,
)
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.domain.errors import GuestUseCaseInputError
from tirosh_guest_tools.domain.operations import RuntimeStateAction
from tirosh_guest_tools.infrastructure.common import (
    RUNTIME_DIR,
    mount_runtime_share,
    systemctl,
)
from tirosh_guest_tools.infrastructure.settings import SETTINGS

RUNTIME_STATE_FILE = RUNTIME_DIR / RuntimeFileName.RUNTIME_STATE.value
REDIS_BACKUP_REQUEST_FILE = RUNTIME_DIR / RuntimeFileName.REDIS_BACKUP_REQUEST.value


def run_runtime_state_action(action: RuntimeStateAction | str) -> None:
    action = RuntimeStateAction(action)
    mount_runtime_share()
    if action == RuntimeStateAction.ONCE:
        write_current_state()
        return
    if action != RuntimeStateAction.WATCH:
        raise GuestUseCaseInputError(
            f"unsupported runtime state action: {action}",
            code="runtime-state-action-unsupported",
        )
    while True:
        trigger_redis_backup_if_requested()
        write_current_state()
        time.sleep(max(SETTINGS.intervals.runtime_state_seconds, 1))


def write_current_state() -> None:
    write_runtime_state(RUNTIME_STATE_FILE)


def trigger_redis_backup_if_requested() -> None:
    if not REDIS_BACKUP_REQUEST_FILE.is_file():
        return
    result = systemctl(
        "is-active",
        "--quiet",
        RuntimeService.REDIS_BACKUP.value,
        check=False,
    )
    if result.returncode == 0:
        return
    systemctl("start", "--no-block", RuntimeService.REDIS_BACKUP.value, check=False)
