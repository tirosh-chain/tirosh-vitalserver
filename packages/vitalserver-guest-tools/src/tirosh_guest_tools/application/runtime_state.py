from __future__ import annotations

import subprocess
import time

from tirosh_guest_tools.common import RUNTIME_DIR, mount_runtime_share, systemctl
from tirosh_guest_tools.runtime.state_writer import write_runtime_state
from tirosh_guest_tools.settings import SETTINGS

RUNTIME_STATE_FILE = RUNTIME_DIR / "runtime-state.json"
REDIS_BACKUP_REQUEST_FILE = RUNTIME_DIR / "redis-backup.request"
REDIS_BACKUP_SERVICE = "tirosh-vitalserver-redis-backup.service"


def run_runtime_state_action(action: str) -> None:
    mount_runtime_share()
    if action == "once":
        write_current_state()
        return
    if action != "watch":
        raise ValueError(f"unsupported runtime state action: {action}")
    while True:
        trigger_redis_backup_if_requested()
        write_current_state()
        time.sleep(max(SETTINGS.intervals.runtime_state_seconds, 1))


def write_current_state() -> None:
    write_runtime_state(
        RUNTIME_STATE_FILE,
        guest_http=http_status("http://127.0.0.1/ready"),
        redis_ui_http=http_status("http://127.0.0.1/redis-ui/"),
        swagger_ui_http=http_status("http://127.0.0.1/swagger/"),
    )


def http_status(url: str) -> str:
    completed = subprocess.run(
        [
            "curl",
            "-sS",
            "-I",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "--max-time",
            "5",
            url,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    return completed.stdout if completed.returncode == 0 else "failed"


def trigger_redis_backup_if_requested() -> None:
    if not REDIS_BACKUP_REQUEST_FILE.is_file():
        return
    result = systemctl("is-active", "--quiet", REDIS_BACKUP_SERVICE, check=False)
    if result.returncode == 0:
        return
    systemctl("start", "--no-block", REDIS_BACKUP_SERVICE, check=False)
