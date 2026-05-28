"""Load bed registry configuration."""

from __future__ import annotations

import tomllib
from pathlib import Path

DEFAULT_BED_REGISTRY_STATE_PATH = Path(
    "/var/lib/vitalserver-testkit/bed-registry.json"
)


def load_bed_registry_state_path(config_path: Path) -> Path:
    """Return the persistent bed registry path from TOML."""

    with config_path.open("rb") as file:
        payload = tomllib.load(file)

    bed_registry = payload.get("bed_registry", {})
    if not isinstance(bed_registry, dict):
        raise ValueError("[bed_registry] must be a TOML table")

    state_path = bed_registry.get("state_path")
    if state_path is None:
        return DEFAULT_BED_REGISTRY_STATE_PATH
    if not isinstance(state_path, str) or not state_path.strip():
        raise ValueError("[bed_registry].state_path must be a non-empty string")

    return Path(state_path)
