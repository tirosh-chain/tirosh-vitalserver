from __future__ import annotations

import subprocess
from argparse import Namespace


def run_require_branch(args: Namespace) -> int:
    current_branch = subprocess.check_output(
        ["git", "branch", "--show-current"],
        text=True,
    ).strip()
    if current_branch != args.branch:
        raise SystemExit(
            "release artifacts must be built from branch "
            f"'{args.branch}' (current: {current_branch})"
        )
    return 0
