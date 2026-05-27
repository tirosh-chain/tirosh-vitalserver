from __future__ import annotations

import subprocess

from tirosh_vitalserver.devtools.core.toolchain import require_branch_match


def run_require_branch(branch: str) -> int:
    current_branch = subprocess.check_output(
        ["git", "branch", "--show-current"],
        text=True,
    ).strip()
    require_branch_match(branch, current_branch)
    return 0
