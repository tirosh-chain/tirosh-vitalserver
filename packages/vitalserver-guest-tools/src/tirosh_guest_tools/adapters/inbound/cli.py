from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_guest_tools.adapters.inbound.operations.command_poller import (
    run_command_poller,
)
from tirosh_guest_tools.adapters.outbound.observability.container_logs import (
    run_container_log_action,
)
from tirosh_guest_tools.adapters.outbound.observability.daemon import (
    run_observability_daemon,
)
from tirosh_guest_tools.adapters.outbound.observability.diagnostics import print_report
from tirosh_guest_tools.adapters.outbound.runtime.config import (
    print_runtime_config_exports,
)
from tirosh_guest_tools.adapters.outbound.runtime.health import check_runtime_health
from tirosh_guest_tools.adapters.outbound.runtime.state_writer import (
    write_runtime_state,
)
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
from tirosh_guest_tools.application.runtime_state import run_runtime_state_action
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
    run_prepare_update_shutdown,
)
from tirosh_guest_tools.domain.operations import (
    ComposeAction,
    ContainerLogAction,
    RuntimeStateAction,
)
from tirosh_guest_tools.infrastructure.logging import configure_logging
from tirosh_guest_tools.infrastructure.settings import SETTINGS
from tirosh_guest_tools.infrastructure.system_install import install_guest_tools_runtime


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


def write_runtime_state_command() -> int:
    parser = argparse.ArgumentParser(description="Write guest runtime state JSON.")
    parser.add_argument("runtime_state", type=Path)
    parser.add_argument("guest_http", nargs="?")
    parser.add_argument("redis_ui_http", nargs="?")
    parser.add_argument("swagger_ui_http", nargs="?")
    args = parser.parse_args()

    write_runtime_state(
        args.runtime_state,
        guest_http=args.guest_http,
        redis_ui_http=args.redis_ui_http,
        swagger_ui_http=args.swagger_ui_http,
    )
    return 0


def runtime_state() -> int:
    parser = argparse.ArgumentParser(description="Write or watch guest runtime state.")
    parser.add_argument(
        "action",
        nargs="?",
        choices=[action.value for action in RuntimeStateAction],
        default=RuntimeStateAction.WATCH.value,
    )
    args = parser.parse_args()
    run_runtime_state_action(args.action)
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


def vitalserver_command_poller() -> int:
    parser = argparse.ArgumentParser(description="Dispatch guest command requests.")
    parser.parse_args()
    run_command_poller()
    return 0


def vitalserver_redis_backup() -> int:
    parser = argparse.ArgumentParser(description="Back up the Redis Docker volume.")
    parser.parse_args()
    configure_logging(SETTINGS.logging, log_file=REDIS_BACKUP_LOG_FILE)
    run_redis_backup()
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
    parser.parse_args()
    configure_logging(SETTINGS.logging, log_file=PREPARE_UPDATE_SHUTDOWN_LOG_FILE)
    run_prepare_update_shutdown()
    return 0


def guest_tools_install_runtime() -> int:
    parser = argparse.ArgumentParser(description="Install the guest tools runtime.")
    parser.parse_args()
    install_guest_tools_runtime()
    return 0
