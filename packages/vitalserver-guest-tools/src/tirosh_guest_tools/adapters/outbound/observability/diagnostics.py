from __future__ import annotations

from tirosh_guest_tools.adapters.outbound.observability.commands import run_command
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
from tirosh_guest_tools.infrastructure.common import (
    DEPLOY_DIR,
    MOUNT_POINT,
    PROJECT_NAME,
)


def print_report() -> None:
    print("== system ==")
    print_command(["hostnamectl"])
    print_command(["uptime"])
    print_command(["df", "-h", "/", str(MOUNT_POINT)])
    print()
    print("== services ==")
    print_command(
        [
            "systemctl",
            "--no-pager",
            "--full",
            "status",
            "docker",
            RuntimeService.COMPOSE.value,
            RuntimeService.RUNTIME_STATE.value,
            RuntimeService.CONTAINER_LOGS.value,
        ]
    )
    print()
    print("== compose ps ==")
    print_command(compose_command(["ps"]))
    print()
    print("== compose logs ==")
    print_command(compose_command(["logs", "--tail=200"]))


def print_command(argv: list[str]) -> None:
    result = run_command(argv, timeout_seconds=15)
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip())


def compose_command(arguments: list[str]) -> list[str]:
    return [
        "docker",
        "compose",
        "--project-name",
        PROJECT_NAME,
        "-f",
        str(DEPLOY_DIR / RuntimeFileName.COMPOSE.value),
        *arguments,
    ]
