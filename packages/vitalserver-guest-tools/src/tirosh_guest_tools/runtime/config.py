from __future__ import annotations

import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tirosh_guest_tools.common import read_json
from tirosh_guest_tools.contracts import RuntimeConfigKey
from tirosh_guest_tools.domain.errors import GuestContractError


@dataclass(frozen=True)
class RuntimeConfig:
    admin_password: str
    public_host: str
    public_port: int
    redis_backup_retention_count: int
    redis_host: str
    redis_port: int
    testkit_enabled: bool
    trust_proxy: bool
    vital_files_directory: str


def print_runtime_config_exports(runtime_config: Path) -> None:
    config = load_config(runtime_config)
    for name, value in [
        ("VITALSERVER_REDIS_HOST", config.redis_host),
        ("VITALSERVER_REDIS_PORT", config.redis_port),
        ("VITALSERVER_TRUST_PROXY", config.trust_proxy),
        ("VITALSERVER_PUBLIC_HOST", config.public_host),
        ("VITALSERVER_PUBLIC_PORT", config.public_port),
        ("VITALSERVER_ADMIN_PASSWORD", config.admin_password),
        ("VITALSERVER_VITAL_FILES_DIR", config.vital_files_directory),
    ]:
        print(export_line(name, value))


def load_config(config_path: Path) -> RuntimeConfig:
    document = read_json(config_path)
    return RuntimeConfig(
        admin_password=required_str(document, RuntimeConfigKey.ADMIN_PASSWORD),
        public_host=required_str(
            document,
            RuntimeConfigKey.PUBLIC_HOST,
            allow_empty=True,
        ),
        public_port=required_int(document, RuntimeConfigKey.PUBLIC_PORT, minimum=1),
        redis_backup_retention_count=required_int(
            document,
            RuntimeConfigKey.REDIS_BACKUP_RETENTION_COUNT,
            minimum=1,
            maximum=30,
        ),
        redis_host=required_str(document, RuntimeConfigKey.REDIS_HOST),
        redis_port=required_int(document, RuntimeConfigKey.REDIS_PORT, minimum=1),
        testkit_enabled=required_bool(document, RuntimeConfigKey.TESTKIT_ENABLED),
        trust_proxy=required_bool(document, RuntimeConfigKey.TRUST_PROXY),
        vital_files_directory=required_str(
            document,
            RuntimeConfigKey.VITAL_FILES_DIRECTORY,
        ),
    )


def required_str(
    document: dict[str, Any],
    key: RuntimeConfigKey,
    *,
    allow_empty: bool = False,
) -> str:
    value = required_value(document, key)
    if not isinstance(value, str):
        raise GuestContractError(
            f"runtime-config field '{key.value}' must be a string",
            code="runtime-config-field-type-invalid",
        )
    if not allow_empty and value == "":
        raise GuestContractError(
            f"runtime-config field '{key.value}' must be non-empty",
            code="runtime-config-field-empty",
        )
    return value


def required_int(
    document: dict[str, Any],
    key: RuntimeConfigKey,
    *,
    minimum: int,
    maximum: int | None = None,
) -> int:
    value = required_value(document, key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise GuestContractError(
            f"runtime-config field '{key.value}' must be an integer",
            code="runtime-config-field-type-invalid",
        )
    if value < minimum:
        raise GuestContractError(
            f"runtime-config field '{key.value}' must be >= {minimum}",
            code="runtime-config-field-range-invalid",
        )
    if maximum is not None and value > maximum:
        raise GuestContractError(
            f"runtime-config field '{key.value}' must be <= {maximum}",
            code="runtime-config-field-range-invalid",
        )
    return value


def required_bool(document: dict[str, Any], key: RuntimeConfigKey) -> bool:
    value = required_value(document, key)
    if not isinstance(value, bool):
        raise GuestContractError(
            f"runtime-config field '{key.value}' must be a boolean",
            code="runtime-config-field-type-invalid",
        )
    return value


def required_value(document: dict[str, Any], key: RuntimeConfigKey) -> Any:
    if key.value not in document:
        raise GuestContractError(
            f"runtime-config field '{key.value}' is missing",
            code="runtime-config-field-missing",
        )
    return document[key.value]


def export_line(name: str, value: object) -> str:
    if isinstance(value, bool):
        value = "1" if value else "0"
    return f"export {name}={shlex.quote(str(value))}"
