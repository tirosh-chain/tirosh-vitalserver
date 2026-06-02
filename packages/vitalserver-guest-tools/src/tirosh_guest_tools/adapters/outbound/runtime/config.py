from __future__ import annotations

import shlex
from pathlib import Path

from tirosh_guest_tools.domain.runtime_config import (
    RuntimeConfig,
    runtime_config_from_json,
)
from tirosh_guest_tools.infrastructure.common import read_json


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
    return runtime_config_from_json(document)


def export_line(name: str, value: object) -> str:
    if isinstance(value, bool):
        value = "1" if value else "0"
    return f"export {name}={shlex.quote(str(value))}"
