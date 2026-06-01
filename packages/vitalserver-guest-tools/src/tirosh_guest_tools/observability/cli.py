from __future__ import annotations

import argparse

from tirosh_guest_tools.application.observability import (
    write_guest_observability_snapshot,
)
from tirosh_guest_tools.domain.operations import ObservationPhase


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Write a guest observability snapshot."
    )
    parser.add_argument("phase", nargs="?", default=ObservationPhase.MANUAL.value)
    args = parser.parse_args()

    write_guest_observability_snapshot(args.phase)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
