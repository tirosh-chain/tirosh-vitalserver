#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


INSTALL_DOCUMENT = Path("/var/lib/vitalserver/install.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a durable VitalServer Linux release rollback.")
    parser.add_argument("--operation-id", required=True)
    parser.add_argument("--operation-document", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._+-]+", args.operation_id):
        raise SystemExit("operation id is invalid")
    started_at = now()
    write_operation(args.operation_document, args.operation_id, "running", started_at, None, None)
    script = Path(__file__).with_name("rollback-linux.sh")
    try:
        result = subprocess.run([str(script)])
        if result.returncode != 0:
            raise RuntimeError(f"Linux rollback failed exitCode={result.returncode}")
        install = load_object(INSTALL_DOCUMENT, "install owner")
        release = {
            "platformVersion": require_string(install, "platformVersion", "install owner"),
            "runtimeBundleVersion": require_string(install, "runtimeBundleVersion", "install owner"),
        }
        write_operation(args.operation_document, args.operation_id, "completed", started_at, release, None)
        return 0
    except Exception as error:
        write_operation(
            args.operation_document,
            args.operation_id,
            "failed",
            started_at,
            None,
            {"kind": "rollbackFailed", "message": str(error)},
        )
        return 1


def load_object(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{label} read failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} must be an object path={path}")
    return value


def require_string(document: dict[str, object], field: str, label: str) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"{label} field is invalid: {field}")
    return value


def write_operation(
    path: Path,
    operation_id: str,
    state: str,
    started_at: str,
    release: dict[str, str] | None,
    failure: dict[str, str] | None,
) -> None:
    document = {
        "schemaVersion": 1,
        "operationId": operation_id,
        "kind": "rollback",
        "state": state,
        "startedAt": started_at,
        "updatedAt": now(),
        "release": release,
        "artifact": None,
        "failure": failure,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(document, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


if __name__ == "__main__":
    raise SystemExit(main())
