from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root


def vm_home_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else repo_root() / path
