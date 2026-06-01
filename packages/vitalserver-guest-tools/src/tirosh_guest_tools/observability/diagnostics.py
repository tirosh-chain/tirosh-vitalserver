from __future__ import annotations

import argparse

from tirosh_guest_tools.common import DEPLOY_DIR, MOUNT_POINT, PROJECT_NAME
from tirosh_guest_tools.observability.commands import run_command


def main() -> int:
    parser = argparse.ArgumentParser(description="Print guest diagnostic details.")
    parser.parse_args()
    print_report()
    return 0


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
            "tirosh-vitalserver-compose.service",
            "tirosh-runtime-state.service",
            "tirosh-vitalserver-container-logs.service",
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
        str(DEPLOY_DIR / "compose.yaml"),
        *arguments,
    ]


if __name__ == "__main__":
    raise SystemExit(main())
