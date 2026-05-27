"""Load TestKit session registry configuration."""

from __future__ import annotations

import tomllib
from pathlib import Path


DEFAULT_SESSION_STATE_PATH = Path("/var/lib/vitalserver-testkit/sessions.json")


def load_session_state_path(config_path: Path) -> Path:
    """Return the persistent session registry path from TestKit TOML."""

    with config_path.open("rb") as file:
        payload = tomllib.load(file)

    sessions = payload.get("sessions", {})
    if not isinstance(sessions, dict):
        raise ValueError("[sessions] must be a TOML table")

    state_path = sessions.get("state_path")
    if state_path is None:
        return DEFAULT_SESSION_STATE_PATH
    if not isinstance(state_path, str) or not state_path.strip():
        raise ValueError("[sessions].state_path must be a non-empty string")

    return Path(state_path)
