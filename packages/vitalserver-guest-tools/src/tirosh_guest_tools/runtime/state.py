from __future__ import annotations

import argparse

from tirosh_guest_tools.application.runtime_state import run_runtime_state_action
from tirosh_guest_tools.inbound import RuntimeStateAction


def main() -> int:
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


if __name__ == "__main__":
    raise SystemExit(main())
