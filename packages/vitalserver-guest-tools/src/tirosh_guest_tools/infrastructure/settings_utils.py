from __future__ import annotations

from enum import StrEnum
from pathlib import Path
from typing import Any

from tirosh_guest_tools.domain.errors import GuestContractError


def toml_table(document: dict[str, Any], key: str) -> dict[str, Any]:
    value = document.get(key, {})
    if not isinstance(value, dict):
        raise GuestContractError(
            f"guest tools setting '{key}' must be a TOML table",
            code="guest-tools-setting-type-invalid",
        )
    return value


def toml_str_value(document: dict[str, Any], key: str, default: str) -> str:
    value = document.get(key, default)
    if not isinstance(value, str) or value == "":
        raise GuestContractError(
            f"guest tools setting '{key}' must be a non-empty string",
            code="guest-tools-setting-type-invalid",
        )
    return value


def toml_path_value(document: dict[str, Any], key: str, default: str) -> Path:
    return Path(toml_str_value(document, key, default))


def toml_bool_value(document: dict[str, Any], key: str, default: bool) -> bool:
    value = document.get(key, default)
    if not isinstance(value, bool):
        raise GuestContractError(
            f"guest tools setting '{key}' must be a boolean",
            code="guest-tools-setting-type-invalid",
        )
    return value


def toml_enum_value[SettingEnum: StrEnum](
    document: dict[str, Any],
    key: str,
    default: str,
    enum_type: type[SettingEnum],
    *,
    choices: str,
) -> SettingEnum:
    value = toml_str_value(document, key, default)
    try:
        return enum_type(value)
    except ValueError as error:
        raise GuestContractError(
            f"guest tools setting '{key}' must be one of: {choices}",
            code="guest-tools-setting-value-invalid",
        ) from error


def toml_int_value(
    document: dict[str, Any],
    key: str,
    default: int,
    *,
    minimum: int,
) -> int:
    value = document.get(key, default)
    if not isinstance(value, int) or isinstance(value, bool):
        raise GuestContractError(
            f"guest tools setting '{key}' must be an integer",
            code="guest-tools-setting-type-invalid",
        )
    if value < minimum:
        raise GuestContractError(
            f"guest tools setting '{key}' must be >= {minimum}",
            code="guest-tools-setting-range-invalid",
        )
    return value


def toml_float_value(
    document: dict[str, Any],
    key: str,
    default: float,
    *,
    minimum: float,
) -> float:
    value = document.get(key, default)
    if not isinstance(value, int | float) or isinstance(value, bool):
        raise GuestContractError(
            f"guest tools setting '{key}' must be a number",
            code="guest-tools-setting-type-invalid",
        )
    value = float(value)
    if value < minimum:
        raise GuestContractError(
            f"guest tools setting '{key}' must be >= {minimum}",
            code="guest-tools-setting-range-invalid",
        )
    return value
