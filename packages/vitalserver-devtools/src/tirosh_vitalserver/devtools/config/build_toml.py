from __future__ import annotations

import tomllib
from argparse import Namespace
from pathlib import Path
from typing import Any

DEFAULT_CONFIG_PATH = "config/vm-build.toml"


def default_config_path() -> Path:
    return Path(DEFAULT_CONFIG_PATH)


def load_build_toml(path: Path) -> dict[str, dict[str, Any]]:
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


def run_config_value(args: Namespace) -> int:
    value: object = load_build_toml(args.config)
    for key in args.key.split("."):
        if not isinstance(value, dict) or key not in value:
            raise SystemExit(f"error: missing config value: {args.key}")
        value = value[key]
    if isinstance(value, bool):
        print("true" if value else "false")
    elif isinstance(value, int | float | str):
        print(value)
    else:
        raise SystemExit(f"error: config value is not scalar: {args.key}")
    return 0


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


def section(config: dict[str, Any], name: str) -> dict[str, Any]:
    value = config.get(name)
    if not isinstance(value, dict):
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
