#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


OPT_ROOT = Path("/opt/vitalserver")
ETC_ROOT = Path("/etc/vitalserver")
VAR_ROOT = Path("/var/lib/vitalserver")
LOG_ROOT = Path("/var/log/vitalserver")
UNIT_ROOT = Path("/etc/systemd/system")
EXTERNAL_PROOF_ROOT = Path("/var/lib/vitalserver-uninstall-proof")
INSTALL_DOCUMENT = VAR_ROOT / "install.json"
PROVIDER_CONFIG = ETC_ROOT / "native-runtime-provider.json"
PLATFORM_CONFIG = ETC_ROOT / "platform-agent.json"
CURRENT_LINK = OPT_ROOT / "current"
LOCK_PATH = Path("/var/lock/vitalserver-linux-install.lock")
VERSION_PATTERN = re.compile(r"[A-Za-z0-9._+-]+")
UNITS = {
    "vitalserver-platform-agent.service": "/opt/vitalserver/current/bin/vitalserver-platform-agent",
    "vitalserver-runtime-controller.service": "/opt/vitalserver/current/bin/vitalserver-runtime-controller.pyz",
    "vitalserver-runtime-provider.service": "/opt/vitalserver/current/bin/vitalserver-runtime-provider",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a durable VitalServer Linux uninstall.")
    parser.add_argument("--mode", choices=("standard", "clean"), required=True)
    parser.add_argument("--operation-id", required=True)
    parser.add_argument("--operation-document", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if os.geteuid() != 0:
        raise SystemExit("VitalServer Linux uninstall requires root.")
    if not VERSION_PATTERN.fullmatch(args.operation_id):
        raise SystemExit("operation id is invalid")
    started_at = now()
    try:
        LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOCK_PATH.open("a+") as lock:
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RuntimeError("another VitalServer Linux install, update, or uninstall is active") from error
            write_operation(args.operation_document, args.operation_id, "running", started_at, None)
            ownership = validate_ownership(args.operation_document)
            uninstall(args.mode, ownership)
            proof = {
                "schemaVersion": 1,
                "operationId": args.operation_id,
                "mode": args.mode,
                "state": "completed",
                "removedAt": now(),
                "platformVersion": ownership["platformVersion"],
                "runtimeBundleVersion": ownership["runtimeBundleVersion"],
                "runtimeDataPreserved": args.mode == "standard",
            }
            if args.mode == "clean":
                proof_root = EXTERNAL_PROOF_ROOT
                write_operation(args.operation_document, args.operation_id, "completed", started_at, None)
                remove_tree(ETC_ROOT)
                remove_tree(VAR_ROOT)
                remove_tree(LOG_ROOT)
                write_json(proof_root / f"linux-uninstall-{args.operation_id}.json", proof, 0o600)
            else:
                proof_root = VAR_ROOT / "proof"
                write_json(proof_root / f"linux-uninstall-{args.operation_id}.json", proof, 0o600)
                write_operation(args.operation_document, args.operation_id, "completed", started_at, None)
        print(
            "VitalServer Linux uninstall completed "
            f"mode={args.mode} proof={proof_root / f'linux-uninstall-{args.operation_id}.json'}"
        )
        return 0
    except Exception as error:
        failure = {"kind": "uninstallFailed", "message": str(error)}
        try:
            write_operation(args.operation_document, args.operation_id, "failed", started_at, failure)
        except Exception:
            write_json(
                EXTERNAL_PROOF_ROOT / f"linux-uninstall-{args.operation_id}.json",
                {
                    "schemaVersion": 1,
                    "operationId": args.operation_id,
                    "mode": args.mode,
                    "state": "failed",
                    "failedAt": now(),
                    "failure": failure,
                },
                0o600,
            )
        print(f"VitalServer Linux uninstall failed reason={error}", file=os.sys.stderr)
        return 1


def validate_ownership(operation_document: Path) -> dict[str, str]:
    install = load_object(INSTALL_DOCUMENT, "install owner")
    if install.get("schemaVersion") != 1 or install.get("state") != "installed":
        raise RuntimeError("install owner identity is invalid")
    platform_version = require_version(install, "platformVersion", "install owner")
    runtime_bundle_version = require_version(install, "runtimeBundleVersion", "install owner")
    if not CURRENT_LINK.is_symlink():
        raise RuntimeError(f"current release owner symlink is missing path={CURRENT_LINK}")
    target = os.readlink(CURRENT_LINK)
    expected_target = f"releases/{platform_version}"
    if target != expected_target:
        raise RuntimeError(f"current release owner differs expected={expected_target} actual={target}")
    release_root = OPT_ROOT / expected_target
    release = load_object(release_root / "release.json", "release owner")
    if (
        release.get("schemaVersion") != 1
        or release.get("platformVersion") != platform_version
        or release.get("runtimeBundleVersion") != runtime_bundle_version
    ):
        raise RuntimeError("release owner identity differs from install owner")

    provider = load_object(PROVIDER_CONFIG, "Native Provider config")
    if provider.get("schemaVersion") != 1:
        raise RuntimeError("Native Provider config schemaVersion must be 1")
    expected_provider = {
        "composeFile": str(CURRENT_LINK / "runtime-bundle/compose.yaml"),
        "composeEnvironmentFile": str(ETC_ROOT / "runtime.env"),
        "composeProjectName": "vitalserver",
        "projectDirectory": str(CURRENT_LINK / "runtime-bundle"),
    }
    for field, expected in expected_provider.items():
        if provider.get(field) != expected:
            raise RuntimeError(f"Native Provider config owner differs field={field}")
    compose_executable = provider.get("composeExecutable")
    if (
        not isinstance(compose_executable, str)
        or not Path(compose_executable).is_absolute()
        or not Path(compose_executable).is_file()
        or not os.access(compose_executable, os.X_OK)
    ):
        raise RuntimeError("Native Provider compose executable owner is invalid")

    platform = load_object(PLATFORM_CONFIG, "Platform Agent config")
    delivery = platform.get("delivery")
    if (
        platform.get("schemaVersion") != 1
        or not isinstance(delivery, dict)
        or delivery.get("uninstallTool") != str(CURRENT_LINK / "tools/uninstall-linux.py")
        or delivery.get("supportExportTool") != str(CURRENT_LINK / "tools/support-export-linux.py")
        or delivery.get("schedulerKind") != "systemd-transient"
    ):
        raise RuntimeError("Platform Agent uninstall owner is invalid")

    for unit, executable in UNITS.items():
        path = UNIT_ROOT / unit
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            raise RuntimeError(f"systemd unit owner read failed path={path}: {error}") from error
        exec_start = next((line for line in text.splitlines() if line.startswith("ExecStart=")), None)
        if exec_start is None or executable not in exec_start:
            raise RuntimeError(f"systemd unit owner differs path={path}")

    expected_operation = VAR_ROOT / "run/platform-workflow.json"
    if operation_document != expected_operation:
        raise RuntimeError(
            f"uninstall operation owner path differs expected={expected_operation} actual={operation_document}"
        )
    return {
        "platformVersion": platform_version,
        "runtimeBundleVersion": runtime_bundle_version,
        "composeExecutable": compose_executable,
        **expected_provider,
    }


def uninstall(mode: str, ownership: dict[str, str]) -> None:
    run(["systemctl", "stop", "vitalserver-runtime-controller.service", "vitalserver-runtime-provider.service"])
    compose = [
        ownership["composeExecutable"],
        "compose",
        "--project-name",
        ownership["composeProjectName"],
        "--env-file",
        ownership["composeEnvironmentFile"],
        "--file",
        ownership["composeFile"],
        "--project-directory",
        ownership["projectDirectory"],
        "down",
    ]
    if mode == "clean":
        compose.append("--volumes")
    run(compose)
    run(["systemctl", "stop", "vitalserver-platform-agent.service"])
    run(["systemctl", "disable", *UNITS])
    for unit in UNITS:
        (UNIT_ROOT / unit).unlink()
    run(["systemctl", "daemon-reload"])
    remove_tree(OPT_ROOT)
    INSTALL_DOCUMENT.unlink()
    run_root = VAR_ROOT / "run"
    if run_root.exists():
        for child in run_root.iterdir():
            if child != VAR_ROOT / "run/platform-workflow.json":
                remove_tree(child) if child.is_dir() and not child.is_symlink() else child.unlink()


def run(command: list[str]) -> None:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        reason = result.stderr.strip() or result.stdout.strip() or "no command output"
        raise RuntimeError(f"command failed exitCode={result.returncode} command={command[0]} reason={reason}")


def load_object(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{label} read failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} must be an object path={path}")
    return value


def require_version(document: dict[str, object], field: str, label: str) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not VERSION_PATTERN.fullmatch(value):
        raise RuntimeError(f"{label} field is invalid: {field}")
    return value


def remove_tree(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.exists():
        shutil.rmtree(path)


def write_operation(
    path: Path,
    operation_id: str,
    state: str,
    started_at: str,
    failure: dict[str, str] | None,
) -> None:
    write_json(
        path,
        {
            "schemaVersion": 1,
            "operationId": operation_id,
            "kind": "uninstall",
            "state": state,
            "startedAt": started_at,
            "updatedAt": now(),
            "release": None,
            "artifact": None,
            "failure": failure,
        },
        0o600,
    )


def write_json(path: Path, document: dict[str, object], mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(document, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def now() -> str:
    return datetime.now(UTC).isoformat()


if __name__ == "__main__":
    raise SystemExit(main())
