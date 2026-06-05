"""Load TestKit logging from declarative TOML."""

from __future__ import annotations

import copy
import logging.config
import tomllib
from pathlib import Path
from typing import Any, TextIO


def configure_testkit_logging(
    *,
    config_path: Path,
    stream: TextIO | None = None,
) -> None:
    """Apply the [logging] dictConfig from a TestKit TOML file."""

    config = load_logging_config(config_path)
    if stream is not None:
        config["handlers"]["stdout"]["stream"] = stream

    logging.config.dictConfig(config)


def load_logging_config(config_path: Path) -> dict[str, Any]:
    """Return the [logging] dictConfig from a TestKit TOML file."""

    with config_path.open("rb") as file:
        payload = tomllib.load(file)

    logging_config = payload.get("logging")
    if not isinstance(logging_config, dict):
        raise ValueError("[logging] must be a TOML table")

    return copy.deepcopy(logging_config)
