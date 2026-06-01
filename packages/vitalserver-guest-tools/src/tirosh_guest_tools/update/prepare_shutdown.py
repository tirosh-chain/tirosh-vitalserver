from __future__ import annotations

import argparse

from tirosh_guest_tools.application.update_shutdown import run_prepare_update_shutdown


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare guest for update shutdown.")
    parser.parse_args()
    run_prepare_update_shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
