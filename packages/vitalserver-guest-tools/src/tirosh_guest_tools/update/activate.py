from __future__ import annotations

import argparse

from tirosh_guest_tools.application.update_activation import run_activate_update


def main() -> int:
    parser = argparse.ArgumentParser(description="Activate a guest runtime update.")
    parser.parse_args()
    run_activate_update()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
