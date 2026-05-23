from __future__ import annotations

from pathlib import Path


def repo_root() -> Path:
    current = Path(__file__).resolve()
    for parent in current.parents:
        if (parent / ".git").exists() and (parent / "apps").is_dir():
            return parent
    raise RuntimeError(f"could not locate repository root from {current}")
