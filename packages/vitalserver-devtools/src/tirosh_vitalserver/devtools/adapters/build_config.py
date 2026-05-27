from __future__ import annotations

from pathlib import Path
from typing import Any

from tirosh_vitalserver.devtools.config.build_toml import load_build_toml


def load_config(path: Path) -> dict[str, Any]:
    return load_build_toml(path)
