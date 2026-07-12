from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from tirosh_guest_tools.adapters.inbound.control_store_migration import (
    migrate_control_store,
)
from tirosh_guest_tools.adapters.inbound.guest_control_api import (
    DEFAULT_HOST as GUEST_CONTROL_API_DEFAULT_HOST,
)
from tirosh_guest_tools.adapters.inbound.guest_control_api import (
    DEFAULT_PORT as GUEST_CONTROL_API_DEFAULT_PORT,
)
from tirosh_guest_tools.adapters.inbound.guest_control_api import (
    serve_guest_control_api,
)
from tirosh_guest_tools.adapters.inbound.observability_daemon import (
    run_observability_daemon,
)
from tirosh_guest_tools.adapters.outbound.observability.container_logs import (
    run_container_log_action,
)
from tirosh_guest_tools.adapters.outbound.observability.diagnostics import print_report
from tirosh_guest_tools.adapters.outbound.runtime.config import (
    print_runtime_config_exports,
)
from tirosh_guest_tools.adapters.outbound.runtime.health import check_runtime_health
from tirosh_guest_tools.adapters.outbound.runtime.observation_writer import (
    write_runtime_observation,
)
from tirosh_guest_tools.application.bootstrap import run_guest_bootstrap
from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.application.redis_backup import (
    LOG_FILE as REDIS_BACKUP_LOG_FILE,
)
from tirosh_guest_tools.application.redis_backup import (
    run_redis_backup,
)
from tirosh_guest_tools.application.redis_repair import (
    LOG_FILE as REDIS_REPAIR_LOG_FILE,
)
from tirosh_guest_tools.application.redis_repair import (
    run_repair_datastore,
)
from tirosh_guest_tools.application.redis_restore import (
    LOG_FILE as REDIS_RESTORE_LOG_FILE,
)
from tirosh_guest_tools.application.redis_restore import (
    restore_redis_archive,
)
from tirosh_guest_tools.application.rootfs_smoke import run_rootfs_smoke
from tirosh_guest_tools.application.runtime_boot_smoke import run_runtime_boot_smoke
from tirosh_guest_tools.application.runtime_data_prepare import prepare_runtime_data
from tirosh_guest_tools.application.runtime_observation import (
    run_runtime_observation_action,
)
from tirosh_guest_tools.application.update_activation import (
    LOG_FILE as ACTIVATE_UPDATE_LOG_FILE,
)
from tirosh_guest_tools.application.update_activation import (
    run_activate_update,
)
from tirosh_guest_tools.application.update_shutdown import (
    LOG_FILE as PREPARE_UPDATE_SHUTDOWN_LOG_FILE,
)
from tirosh_guest_tools.application.update_shutdown import (
    run_prepare_update_shutdown_for_request,
)
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.operations import (
    ComposeAction,
    ContainerLogAction,
    RuntimeObservationAction,
)
from tirosh_guest_tools.infrastructure.bootstrap_operations import (
    default_bootstrap_context,
    default_bootstrap_operations,
    sync_host_time,
)
from tirosh_guest_tools.infrastructure.logging import configure_logging
from tirosh_guest_tools.infrastructure.settings import SETTINGS
from tirosh_guest_tools.infrastructure.system_install import (
    install_guest_tools_config,
    install_guest_tools_runtime,
)


def guest_observed() -> int:
    parser = argparse.ArgumentParser(description="Run guest observability daemon.")
    parser.add_argument(
        "--interval",
        type=float,
        default=SETTINGS.intervals.observability_seconds,
    )
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    run_observability_daemon(interval_seconds=args.interval, once=args.once)
    return 0


def guest_observe() -> int:
    parser = argparse.ArgumentParser(
        description="Write a guest observability snapshot."
    )
    parser.add_argument("phase", nargs="?", default="manual")
    args = parser.parse_args()

    write_guest_observability_snapshot(args.phase)
    return 0


def guest_container_logs() -> int:
    parser = argparse.ArgumentParser(
        description="Write Docker Compose logs to the shared runtime directory."
    )
    parser.add_argument(
        "action",
        nargs="?",
        choices=[action.value for action in ContainerLogAction],
        default=ContainerLogAction.WATCH.value,
    )
    args = parser.parse_args()

    run_container_log_action(args.action)
    return 0


def guest_diagnostics() -> int:
    parser = argparse.ArgumentParser(description="Print guest diagnostic details.")
    parser.parse_args()
    print_report()
    return 0


def runtime_env() -> int:
    parser = argparse.ArgumentParser(
        description="Print shell exports for the guest runtime config."
    )
    parser.add_argument("runtime_config", type=Path)
    args = parser.parse_args()

    if not args.runtime_config.is_file():
        parser.exit(1, f"error: missing {args.runtime_config}\n")

    print_runtime_config_exports(args.runtime_config)
    return 0


def write_runtime_observation_command() -> int:
    parser = argparse.ArgumentParser(
        description="Write guest runtime observation artifact JSON."
    )
    parser.add_argument("runtime_observation", type=Path)
    parser.add_argument("guest_http", nargs="?")
    parser.add_argument("redis_ui_http", nargs="?")
    parser.add_argument("swagger_ui_http", nargs="?")
    args = parser.parse_args()

    write_runtime_observation(
        args.runtime_observation,
        guest_http=args.guest_http,
        redis_ui_http=args.redis_ui_http,
        swagger_ui_http=args.swagger_ui_http,
    )
    return 0


def runtime_observation() -> int:
    parser = argparse.ArgumentParser(
        description="Write or watch guest runtime observation outputs."
    )
    parser.add_argument(
        "action",
        nargs="?",
        choices=[action.value for action in RuntimeObservationAction],
        default=RuntimeObservationAction.WATCH.value,
    )
    args = parser.parse_args()
    run_runtime_observation_action(args.action)
    return 0


def vitalserver_health() -> int:
    parser = argparse.ArgumentParser(description="Check guest runtime health.")
    parser.parse_args()
    check_runtime_health()
    return 0


def vitalserver_compose() -> int:
    parser = argparse.ArgumentParser(
        description="Manage the guest Docker Compose stack."
    )
    parser.add_argument(
        "action",
        nargs="?",
        choices=[action.value for action in ComposeAction],
        default=ComposeAction.UP.value,
    )
    args = parser.parse_args()
    configure_logging(SETTINGS.logging)
    run_compose_action(args.action)
    return 0


def vitalserver_sync_host_time() -> int:
    parser = argparse.ArgumentParser(
        description="Synchronize guest clock from the explicit host time contract."
    )
    parser.parse_args()
    sync_host_time()
    return 0


def vitalserver_bootstrap() -> int:
    parser = argparse.ArgumentParser(description="Run guest bootstrap workflow.")
    parser.parse_args()
    configure_logging(SETTINGS.logging)
    run_guest_bootstrap(
        context=default_bootstrap_context(),
        operations=default_bootstrap_operations(),
    )
    return 0


def vitalserver_rootfs_smoke() -> int:
    parser = argparse.ArgumentParser(
        description="Validate golden rootfs Docker and Compose runtime behavior."
    )
    parser.parse_args()
    configure_logging(SETTINGS.logging)
    run_rootfs_smoke()
    return 0


def vitalserver_runtime_boot_smoke() -> int:
    parser = argparse.ArgumentParser(
        description="Validate runtime boot contracts after guest bootstrap."
    )
    parser.parse_args()
    configure_logging(SETTINGS.logging)
    run_runtime_boot_smoke()
    return 0


def vitalserver_runtime_data_prepare() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare the guest runtime data disk contract."
    )
    parser.parse_args()
    prepare_runtime_data()
    return 0


def vitalserver_guest_control_api() -> int:
    parser = argparse.ArgumentParser(description="Run the Guest Control API.")
    parser.add_argument("--host", default=GUEST_CONTROL_API_DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=GUEST_CONTROL_API_DEFAULT_PORT)
    parser.add_argument(
        "--redis-relay-status-owner-socket",
        type=Path,
        default=(
            Path(configured)
            if (configured := os.environ.get("REDIS_RELAY_STATUS_OWNER_SOCKET"))
            else None
        ),
    )
    args = parser.parse_args()
    configure_logging(SETTINGS.logging)
    serve_guest_control_api(
        host=args.host,
        port=args.port,
        redis_relay_status_owner_socket=args.redis_relay_status_owner_socket,
    )
    return 0


def vitalserver_redis_backup() -> int:
    parser = argparse.ArgumentParser(description="Back up the Redis Docker volume.")
    parser.parse_args()
    configure_logging(SETTINGS.logging, log_file=REDIS_BACKUP_LOG_FILE)
    run_redis_backup()
    return 0


def vitalserver_redis_restore() -> int:
    parser = argparse.ArgumentParser(description="Restore the Redis Docker volume.")
    parser.add_argument("--archive", required=True)
    args = parser.parse_args()
    configure_logging(SETTINGS.logging, log_file=REDIS_RESTORE_LOG_FILE)
    restore_redis_archive(Path(args.archive))
    return 0


def vitalserver_repair_datastore() -> int:
    parser = argparse.ArgumentParser(description="Repair the Redis datastore.")
    parser.parse_args()
    configure_logging(SETTINGS.logging, log_file=REDIS_REPAIR_LOG_FILE)
    run_repair_datastore()
    return 0


def vitalserver_activate_update() -> int:
    parser = argparse.ArgumentParser(description="Activate a guest runtime update.")
    parser.parse_args()
    configure_logging(SETTINGS.logging, log_file=ACTIVATE_UPDATE_LOG_FILE)
    run_activate_update()
    return 0


def vitalserver_prepare_update_shutdown() -> int:
    parser = argparse.ArgumentParser(description="Prepare guest for update shutdown.")
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    configure_logging(SETTINGS.logging, log_file=PREPARE_UPDATE_SHUTDOWN_LOG_FILE)
    run_prepare_update_shutdown_for_request(
        request_id=args.request_id,
        version=args.version,
    )
    return 0


def guest_tools_install_runtime() -> int:
    parser = argparse.ArgumentParser(description="Install the guest tools runtime.")
    parser.parse_args()
    install_guest_tools_runtime()
    return 0


def guest_tools_install_config() -> int:
    parser = argparse.ArgumentParser(description="Install default guest tools config.")
    parser.parse_args()
    install_guest_tools_config()
    return 0


def guest_tools_migrate_control_store() -> int:
    """Apply and verify the configured Guest Control SQLite schema explicitly."""

    parser = argparse.ArgumentParser(
        description="Apply and verify the Guest Control SQLite schema."
    )
    parser.parse_args()
    try:
        # The Guest Control API resolves this exact setting too.  This lifecycle
        # command deliberately has no alternate data-root option: creating or
        # migrating another ledger would leave the API's configured ledger
        # unprepared.
        proof = migrate_control_store(
            SETTINGS.paths.control_state_dir,
            control_store=SETTINGS.control_store,
        )
    except GuestControlDependencyError as error:
        parser.exit(1, f"error: {error.kind}: {error.message}\n")
    print(json.dumps(proof, sort_keys=True))
    return 0
