from __future__ import annotations

import shutil
import subprocess
from collections.abc import Sequence
from pathlib import Path


def require_tool(name: str, install_hint: str | None = None) -> None:
    if shutil.which(name):
        return
    message = f"missing required tool: {name}"
    if install_hint:
        message = f"{message}. {install_hint}"
    raise SystemExit(f"error: {message}")


def run(
    command: Sequence[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> None:
    subprocess.run(command, check=True, cwd=cwd, env=env)


def capture_json(command: Sequence[str]) -> object:
    import json

    output = subprocess.check_output(command, text=True)
    return json.loads(output)
