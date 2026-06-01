from __future__ import annotations

import argparse

from tirosh_guest_tools.common import (
    PROJECT_NAME,
    RUNTIME_DIR,
    Tee,
    compose_command,
    mount_runtime_share,
    request_id_from,
    run,
    utc_now,
    write_json,
)
from tirosh_guest_tools.compose import main as compose_main
from tirosh_guest_tools.runtime.state import write_current_state

REQUEST_FILE = RUNTIME_DIR / "repair-datastore.request"
RESULT_FILE = RUNTIME_DIR / "repair-datastore-result.json"
LOG_FILE = RUNTIME_DIR / "repair-datastore.log"
REDIS_VOLUME = f"{PROJECT_NAME}_redis-data"
REQUEST_ID = ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair the Redis datastore.")
    parser.parse_args()
    mount_runtime_share()
    with Tee(LOG_FILE) as log:
        log.write("datastore repair started")
        if not REQUEST_FILE.is_file():
            log.write("request file is missing; exiting")
            write_result("", "skipped", "request file is missing")
            return 0
        request_id = request_id_from(REQUEST_FILE)
        write_result(request_id, "running", "Datastore repair is running.")
        try:
            restart_runtime_compose()
        except Exception:
            REQUEST_FILE.unlink(missing_ok=True)
            write_result(
                request_id,
                "failed",
                "Datastore repair failed. See repair-datastore.log.",
            )
            log.write("datastore repair failed")
            raise
        REQUEST_FILE.unlink(missing_ok=True)
        write_result(
            request_id,
            "completed",
            "Redis append-only file checked and VitalServer services restarted.",
        )
        log.write("datastore repair completed")
        return 0


def write_result(request_id: str, status: str, message: str) -> None:
    write_json(
        RESULT_FILE,
        {
            "operation": "repair-datastore",
            "requestId": request_id,
            "schemaVersion": 2,
            "message": message,
            "status": status,
            "updatedAt": utc_now(),
        },
    )


def restart_runtime_compose() -> None:
    run(
        compose_command(["stop", "app", "audit-proxy", "redis-ui", "edge", "redis"]),
        check=False,
    )
    repair_appendonly_file()
    run_compose_tool("up")
    write_current_state()


def repair_appendonly_file() -> None:
    if run(["docker", "volume", "inspect", REDIS_VOLUME], check=False).returncode != 0:
        print(f"redis volume does not exist: {REDIS_VOLUME}")
        return
    run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{REDIS_VOLUME}:/data",
            "redis:3.2.12-alpine",
            "sh",
            "-c",
            (
                "set -eu; "
                "if [ ! -f /data/appendonly.aof ]; then "
                "echo 'appendonly.aof does not exist; nothing to repair'; exit 0; fi; "
                "if redis-check-aof /data/appendonly.aof; then "
                "echo 'appendonly.aof is valid'; exit 0; fi; "
                "backup=\"/data/appendonly.aof.bak.$(date +%Y%m%d%H%M%S)\"; "
                "cp /data/appendonly.aof \"$backup\"; "
                "printf 'created backup: %s\\n' \"$backup\"; "
                "printf 'y\\n' | redis-check-aof --fix /data/appendonly.aof"
            ),
        ]
    )


def run_compose_tool(action: str) -> None:
    import sys

    original_argv = sys.argv
    try:
        sys.argv = ["tirosh-vitalserver-compose", action]
        result = compose_main()
        if result != 0:
            raise SystemExit(result)
    finally:
        sys.argv = original_argv


if __name__ == "__main__":
    raise SystemExit(main())
