from __future__ import annotations

import argparse

from tirosh_guest_tools.observability.collectors import (
    collect_snapshot,
    collect_text_report,
)
from tirosh_guest_tools.observability.writer import write_oneshot_snapshot


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Write a guest observability snapshot."
    )
    parser.add_argument("phase", nargs="?", default="manual")
    args = parser.parse_args()

    snapshot = collect_snapshot(phase=args.phase, detail="oneshot")
    write_oneshot_snapshot(args.phase, snapshot, collect_text_report(snapshot))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
