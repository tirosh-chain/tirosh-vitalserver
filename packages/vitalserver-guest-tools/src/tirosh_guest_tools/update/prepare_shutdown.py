from __future__ import annotations

import argparse

from tirosh_guest_tools.application.update_shutdown import (
    LOG_FILE,
    run_prepare_update_shutdown,
)
from tirosh_guest_tools.logging import configure_logging
from tirosh_guest_tools.settings import SETTINGS


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare guest for update shutdown.")
    parser.parse_args()
    configure_logging(
        SETTINGS.logging,
        log_file=LOG_FILE,
    )
    run_prepare_update_shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
