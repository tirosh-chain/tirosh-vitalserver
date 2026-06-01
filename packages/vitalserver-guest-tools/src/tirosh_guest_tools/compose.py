from __future__ import annotations

import argparse

from tirosh_guest_tools.application.compose import run_compose_action
from tirosh_guest_tools.inbound import ComposeAction


def main() -> int:
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
    run_compose_action(args.action)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
