from __future__ import annotations

import argparse
import shlex
from pathlib import Path
from typing import Any

from tirosh_guest_tools.common import read_json
from tirosh_guest_tools.domain.operations import RuntimeConfigKey

DEFAULT_CONFIG: dict[str, Any] = {
    RuntimeConfigKey.ADMIN_PASSWORD.value: "admin",
    RuntimeConfigKey.PUBLIC_HOST.value: "",
    RuntimeConfigKey.PUBLIC_PORT.value: "",
    RuntimeConfigKey.REDIS_BACKUP_RETENTION_COUNT.value: 30,
    RuntimeConfigKey.REDIS_HOST.value: "redis",
    RuntimeConfigKey.REDIS_PORT.value: 6379,
    RuntimeConfigKey.TRUST_PROXY.value: True,
    RuntimeConfigKey.TESTKIT_ENABLED.value: True,
    RuntimeConfigKey.VITAL_FILES_DIRECTORY.value: "/mnt/tirosh-vital-files",
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Print shell exports for the guest runtime config."
    )
    parser.add_argument("runtime_config", type=Path)
    args = parser.parse_args()

    if not args.runtime_config.is_file():
        parser.exit(1, f"error: missing {args.runtime_config}\n")

    config = load_config(args.runtime_config)
    for name, key in [
        ("VITALSERVER_REDIS_HOST", RuntimeConfigKey.REDIS_HOST),
        ("VITALSERVER_REDIS_PORT", RuntimeConfigKey.REDIS_PORT),
        ("VITALSERVER_TRUST_PROXY", RuntimeConfigKey.TRUST_PROXY),
        ("VITALSERVER_PUBLIC_HOST", RuntimeConfigKey.PUBLIC_HOST),
        ("VITALSERVER_PUBLIC_PORT", RuntimeConfigKey.PUBLIC_PORT),
        ("VITALSERVER_ADMIN_PASSWORD", RuntimeConfigKey.ADMIN_PASSWORD),
        ("VITALSERVER_VITAL_FILES_DIR", RuntimeConfigKey.VITAL_FILES_DIRECTORY),
    ]:
        print(export_line(name, config[key.value]))
    return 0


def load_config(config_path: Path) -> dict[str, Any]:
    return {**DEFAULT_CONFIG, **read_json(config_path)}


def export_line(name: str, value: object) -> str:
    if isinstance(value, bool):
        value = "1" if value else "0"
    return f"export {name}={shlex.quote(str(value))}"


if __name__ == "__main__":
    raise SystemExit(main())
