from __future__ import annotations

import argparse

from tirosh_guest_tools.application.compose import run_compose_action


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Manage the guest Docker Compose stack."
    )
    parser.add_argument(
        "action",
        nargs="?",
        choices=["up", "testkit-up", "testkit-up-logged", "stop"],
        default="up",
    )
    args = parser.parse_args()
    run_compose_action(args.action)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
