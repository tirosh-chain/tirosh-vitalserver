from __future__ import annotations

import argparse

from tirosh_guest_tools.application.update_activation import (
    LOG_FILE,
    run_activate_update,
)
from tirosh_guest_tools.logging import configure_logging
from tirosh_guest_tools.settings import SETTINGS


def main() -> int:
    parser = argparse.ArgumentParser(description="Activate a guest runtime update.")
    parser.parse_args()
    configure_logging(
        SETTINGS.logging,
        log_file=LOG_FILE,
    )
    run_activate_update()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
