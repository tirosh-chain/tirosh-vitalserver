from __future__ import annotations

import argparse
import os
import subprocess
import time

from tirosh_guest_tools.common import RUNTIME_DIR, mount_runtime_share, systemctl
from tirosh_guest_tools.runtime.state_writer import main as write_runtime_state_main

RUNTIME_STATE_FILE = RUNTIME_DIR / "runtime-state.json"
REDIS_BACKUP_REQUEST_FILE = RUNTIME_DIR / "redis-backup.request"
REDIS_BACKUP_SERVICE = "tirosh-vitalserver-redis-backup.service"
INTERVAL_SECONDS = int(os.environ.get("TIROSH_RUNTIME_STATE_INTERVAL", "5"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Write or watch guest runtime state.")
    parser.add_argument("action", nargs="?", choices=["watch", "once"], default="watch")
    args = parser.parse_args()

    mount_runtime_share()
    if args.action == "once":
        write_current_state()
        return 0
    while True:
        trigger_redis_backup_if_requested()
        write_current_state()
        time.sleep(max(INTERVAL_SECONDS, 1))


def write_current_state() -> None:
    argv = [
        str(RUNTIME_STATE_FILE),
        http_status("http://127.0.0.1/ready"),
        http_status("http://127.0.0.1/redis-ui/"),
        http_status("http://127.0.0.1/swagger/"),
    ]
    import sys

    original_argv = sys.argv
    try:
        sys.argv = ["tirosh-write-runtime-state", *argv]
        result = write_runtime_state_main()
        if result != 0:
            raise SystemExit(result)
    finally:
        sys.argv = original_argv


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


if __name__ == "__main__":
    raise SystemExit(main())
