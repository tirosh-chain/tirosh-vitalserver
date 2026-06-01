from __future__ import annotations

import argparse

from tirosh_guest_tools.common import (
    MOUNT_POINT,
    RUNTIME_DIR,
    Tee,
    mount_runtime_share,
    request_id_from,
    request_version_from,
    systemctl,
    utc_now,
    write_json,
)
from tirosh_guest_tools.compose import main as compose_main
from tirosh_guest_tools.observability.cli import main as observe_main
from tirosh_guest_tools.redis.backup import main as redis_backup_main

REQUEST_FILE = RUNTIME_DIR / "prepare-update-shutdown.request"
RESULT_FILE = RUNTIME_DIR / "prepare-update-shutdown-result.json"
LOG_FILE = RUNTIME_DIR / "prepare-update-shutdown.log"
BACKUP_DIR = MOUNT_POINT / "backups" / "redis"
REQUEST_ID = ""
REDIS_BACKUP_PATH = ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare guest for update shutdown.")
    parser.parse_args()
    mount_runtime_share()
    with Tee(LOG_FILE) as log:
        try:
            return run_prepare(log)
        except Exception as error:
            log.log(f"status=failed error={error}")
            collect_guest_observability("shutdown-failure")
            if REQUEST_ID:
                write_result(
                    "failed",
                    f"Guest update shutdown failed at: {error}",
                    "failed",
                    "guest-update-shutdown-failed",
                )
            REQUEST_FILE.unlink(missing_ok=True)
            raise


def run_prepare(log: Tee) -> int:
    global REQUEST_ID
    log.log("guest update shutdown preparation started")
    if not REQUEST_FILE.is_file():
        log.write("request file is missing; exiting")
        return 0
    REQUEST_ID = request_id_from(REQUEST_FILE)
    version = request_version_from(REQUEST_FILE)
    log.log(f"requestId={REQUEST_ID} version={version or 'unknown'}")
    write_result("running", "Guest update shutdown preparation started.", "starting")
    collect_guest_observability("shutdown-pre-stop")
    backup_redis(log)
    write_result(
        "running",
        "Redis backup completed. Stopping guest services.",
        "redis-backup",
    )
    stop_runtime_services(log)
    log.log("step=sync status=started")
    __import__("subprocess").run(["sync"], check=True)
    log.log("step=sync status=completed")
    collect_guest_observability("shutdown-post-sync")
    write_result(
        "ready",
        "Guest services are stopped and filesystems are synced.",
        "ready",
    )
    REQUEST_FILE.unlink(missing_ok=True)
    log.log("guest update shutdown preparation ready")
    return 0


def collect_guest_observability(phase: str) -> None:
    import sys

    original_argv = sys.argv
    try:
        sys.argv = ["tirosh-guest-observe", phase]
        observe_main()
    except Exception as error:
        print(f"warning: guest observability snapshot failed: {phase}: {error}")
    finally:
        sys.argv = original_argv


def backup_redis(log: Tee) -> None:
    global REDIS_BACKUP_PATH
    log.log("step=redis-backup status=started")
    redis_backup_main()
    backups = sorted(BACKUP_DIR.glob("redis-*.tar.gz"))
    REDIS_BACKUP_PATH = str(backups[-1]) if backups else ""
    if not REDIS_BACKUP_PATH:
        raise RuntimeError("redis backup archive was not created")
    log.log(f"step=redis-backup status=completed archive={REDIS_BACKUP_PATH}")


def stop_runtime_services(log: Tee) -> None:
    log.log("step=guest-services-stop status=started")
    systemctl("stop", "tirosh-vitalserver-container-logs.service", check=False)
    systemctl("stop", "tirosh-runtime-state.service", check=False)
    run_compose_tool("stop")
    log.log("step=guest-services-stop status=completed")


def run_compose_tool(action: str) -> None:
    import sys

    original_argv = sys.argv
    try:
        sys.argv = ["tirosh-vitalserver-compose", action]
        compose_main()
    finally:
        sys.argv = original_argv


def write_result(
    status: str,
    message: str,
    step: str = "",
    reason: str = "",
) -> None:
    document = {
        "operation": "prepare-update-shutdown",
        "requestId": REQUEST_ID,
        "schemaVersion": 1,
        "message": message,
        "status": status,
        "updatedAt": utc_now(),
    }
    if step:
        document["step"] = step
    if reason:
        document["reasonCodes"] = [reason]
    if REDIS_BACKUP_PATH:
        document["redisBackupPath"] = REDIS_BACKUP_PATH
    write_json(RESULT_FILE, document)


if __name__ == "__main__":
    raise SystemExit(main())
