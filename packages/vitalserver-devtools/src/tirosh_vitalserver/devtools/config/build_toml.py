from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any

DEFAULT_CONFIG_PATH = "config/vm-build.toml"
TomlTable = dict[str, Any]


def default_config_path() -> Path:
    return Path(DEFAULT_CONFIG_PATH)


def load_build_toml(path: Path) -> TomlTable:
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


def optional_bool(
    config: TomlTable,
    key: str,
    default: bool,
    *,
    path: str | None = None,
) -> bool:
    value = config.get(key, default)
    if not isinstance(value, bool):
        raise SystemExit(
            f"error: invalid boolean config value: {config_key(path, key)}"
        )
    return value


def section(config: TomlTable, name: str, *, path: str | None = None) -> TomlTable:
    value = config.get(name)
    if not isinstance(value, dict):
        raise SystemExit(f"error: missing [{config_key(path, name)}] in build config")
    return value


def nested_section(
    config: TomlTable,
    path: str,
    *,
    parent_path: str | None = None,
) -> TomlTable:
    value = config
    current_path = parent_path or ""
    for name in path.split("."):
        value = section(value, name, path=current_path or None)
        current_path = config_key(current_path or None, name)
    return value


def required_string(config: TomlTable, key: str, *, path: str | None = None) -> str:
    value = config.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing string config value: {config_key(path, key)}")
    return value


def optional_string(
    config: TomlTable,
    key: str,
    default: str,
    *,
    path: str | None = None,
) -> str:
    value = config.get(key, default)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: invalid string config value: {config_key(path, key)}")
    return value


def required_string_list(
    config: TomlTable,
    key: str,
    *,
    path: str | None = None,
) -> list[str]:
    value = config.get(key)
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(item, str) and item for item in value)
    ):
        raise SystemExit(
            f"error: missing string list config value: {config_key(path, key)}"
        )
    return value


def config_key(path: str | None, key: str) -> str:
    return f"{path}.{key}" if path else key
