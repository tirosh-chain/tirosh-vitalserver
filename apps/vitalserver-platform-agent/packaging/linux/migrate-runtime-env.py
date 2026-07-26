#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import tempfile
from contextlib import suppress
from pathlib import Path

EXPECTED_VALUES = {
    "VITALSERVER_RUNTIME_RUN_DIR": "/var/lib/vitalserver/run",
    "REDIS_RELAY_STATUS_OWNER_SOCKET": (
        "/run/tirosh/status-owner/redis-relay-status-owner.sock"
    ),
    "REDIS_RELAY_STATUS_OWNER_URL": "",
}


class RuntimeEnvironmentMigrationError(RuntimeError):
    pass


def migrate_runtime_environment(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
        mode = path.stat().st_mode & 0o777
    except FileNotFoundError as error:
        raise RuntimeEnvironmentMigrationError(
            f"Runtime environment owner is missing path={path}"
        ) from error
    except UnicodeDecodeError as error:
        raise RuntimeEnvironmentMigrationError(
            f"Runtime environment owner decode failed path={path}: {error}"
        ) from error
    except OSError as error:
        raise RuntimeEnvironmentMigrationError(
            f"Runtime environment owner read failed path={path}: {error}"
        ) from error

    lines = text.splitlines()
    positions: dict[str, int] = {}
    values: dict[str, str] = {}
    for index, line in enumerate(lines):
        name, separator, value = line.partition("=")
        if not separator or name not in EXPECTED_VALUES:
            continue
        if name in positions:
            raise RuntimeEnvironmentMigrationError(
                f"Runtime environment owner defines {name} more than once path={path}"
            )
        positions[name] = index
        values[name] = value

    legacy_url = values.get("REDIS_RELAY_STATUS_OWNER_URL")
    if legacy_url not in (None, ""):
        raise RuntimeEnvironmentMigrationError(
            "Runtime environment has an explicit legacy Redis Relay status owner "
            "URL; refusing to replace it with the Linux private socket transport "
            f"path={path}"
        )

    changed = False
    for name, expected in EXPECTED_VALUES.items():
        current = values.get(name)
        if current is None:
            lines.append(f"{name}={expected}")
            changed = True
            continue
        if current != expected:
            raise RuntimeEnvironmentMigrationError(
                "Runtime environment transport value differs from the required "
                f"owner contract name={name} actual={current!r} expected={expected!r} "
                f"path={path}"
            )

    if not changed:
        return False
    _atomic_write(path, "\n".join(lines) + "\n", mode=mode)
    return True


def _atomic_write(path: Path, content: str, *, mode: int) -> None:
    temporary: str | None = None
    try:
        descriptor, temporary = tempfile.mkstemp(
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        _sync_directory(path.parent)
    except OSError as error:
        if temporary is not None:
            with suppress(FileNotFoundError):
                os.unlink(temporary)
        raise RuntimeEnvironmentMigrationError(
            f"Runtime environment owner write failed path={path}: {error}"
        ) from error


def _sync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Migrate the Linux Runtime environment to the private Redis Relay "
            "status transport."
        )
    )
    parser.add_argument("--path", type=Path, required=True)
    args = parser.parse_args()
    try:
        changed = migrate_runtime_environment(args.path)
    except RuntimeEnvironmentMigrationError as error:
        parser.exit(1, f"error: {error}\n")
    print("migrated" if changed else "current")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
