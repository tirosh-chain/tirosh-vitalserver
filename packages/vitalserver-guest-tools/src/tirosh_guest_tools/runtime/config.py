from __future__ import annotations

import argparse
import shlex
from pathlib import Path
from typing import Any

from tirosh_guest_tools.common import read_json

DEFAULT_CONFIG: dict[str, Any] = {
    "adminPassword": "admin",
    "publicHost": "",
    "publicPort": "",
    "redisHost": "redis",
    "redisPort": 6379,
    "trustProxy": True,
    "testkitEnabled": True,
    "vitalFilesDirectory": "/mnt/tirosh-vital-files",
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
        ("VITALSERVER_REDIS_HOST", "redisHost"),
        ("VITALSERVER_REDIS_PORT", "redisPort"),
        ("VITALSERVER_TRUST_PROXY", "trustProxy"),
        ("VITALSERVER_PUBLIC_HOST", "publicHost"),
        ("VITALSERVER_PUBLIC_PORT", "publicPort"),
        ("VITALSERVER_ADMIN_PASSWORD", "adminPassword"),
        ("VITALSERVER_VITAL_FILES_DIR", "vitalFilesDirectory"),
        ("TIROSH_TESTKIT_ENABLED", "testkitEnabled"),
    ]:
        print(export_line(name, config[key]))
    return 0


def load_config(config_path: Path) -> dict[str, Any]:
    return {**DEFAULT_CONFIG, **read_json(config_path)}


def export_line(name: str, value: object) -> str:
    if isinstance(value, bool):
        value = "1" if value else "0"
    return f"export {name}={shlex.quote(str(value))}"


if __name__ == "__main__":
    raise SystemExit(main())
