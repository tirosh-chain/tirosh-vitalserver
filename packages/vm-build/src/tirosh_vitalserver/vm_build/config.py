from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any

DEFAULT_CONFIG_PATH = "apps/vitalserver-vm-launcher/Support/Build/vm-build.toml"


def default_config_path() -> Path:
    return Path(DEFAULT_CONFIG_PATH)


def load_config(path: Path) -> dict[str, dict[str, Any]]:
    if not path.is_file():
        raise SystemExit(f"error: missing build config: {path}")
    try:
        with path.open("rb") as file:
            config = tomllib.load(file)
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit(f"error: invalid TOML config {path}: {exc}") from exc
    if not isinstance(config, dict):
        raise SystemExit(f"error: invalid build config: {path}")
    return config


def optional_bool(config: dict[str, Any], key: str, default: bool) -> bool:
    value = config.get(key, default)
    if not isinstance(value, bool):
        raise SystemExit(f"error: invalid boolean config value: {key}")
    return value


def parse_bool(value: str) -> bool:
    if value == "true":
        return True
    if value == "false":
        return False
    raise SystemExit(f"error: expected true or false, got: {value}")


def section(config: dict[str, dict[str, Any]], name: str) -> dict[str, Any]:
    value = config.get(name)
    if value is None:
        raise SystemExit(f"error: missing [{name}] in build config")
    return value


def required_string(config: dict[str, Any], key: str) -> str:
    value = config.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing string config value: {key}")
    return value


def optional_string(config: dict[str, Any], key: str, default: str) -> str:
    value = config.get(key, default)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: invalid string config value: {key}")
    return value


def required_string_list(config: dict[str, Any], key: str) -> list[str]:
    value = config.get(key)
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(item, str) and item for item in value)
    ):
        raise SystemExit(f"error: missing string list config value: {key}")
    return value
