#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any
import uuid


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prove a VitalServer Linux reboot and post-reboot Runtime acceptance.")
    parser.add_argument("--api-token-path", type=Path, required=True)
    parser.add_argument("--runtime-provider-document", type=Path, required=True)
    parser.add_argument("--install-document", type=Path, required=True)
    parser.add_argument("--runtime-acceptance-manifest", type=Path, required=True)
    parser.add_argument("--output-manifest", type=Path, required=True)
    parser.add_argument("--base-url", default="http://127.0.0.1:18321")
    parser.add_argument("--timeout-seconds", type=int, default=360)
    parser.add_argument("--http-timeout-seconds", type=int, default=60)
    parser.add_argument("--boot-id-path", type=Path, default=Path("/proc/sys/kernel/random/boot_id"))
    parser.add_argument(
        "--support-directory",
        type=Path,
        default=Path("/var/lib/vitalserver/support"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_id = str(uuid.uuid4())
    started_at = now()
    stages: list[dict[str, str]] = []
    current_stage = "preflight"
    installed_boot_id: str | None = None
    current_boot_id: str | None = None
    runtime_acceptance_run_id: str | None = None
    try:
        install = load_object(args.install_document, "install owner")
        if install.get("schemaVersion") != 1 or install.get("state") != "installed":
            raise RuntimeError(f"install owner contract is invalid path={args.install_document}")
        try:
            installed_boot_id = str(uuid.UUID(str(install.get("installedBootId"))))
            current_boot_id = str(uuid.UUID(args.boot_id_path.read_text(encoding="utf-8").strip()))
        except (FileNotFoundError, OSError, UnicodeDecodeError, ValueError) as error:
            raise RuntimeError(f"boot ID owner read failed: {error}") from error
        stages.append({"name": "preflight", "status": "passed", "message": "Install and boot ID owners are available.", "observedAt": now()})

        current_stage = "boot-id-changed"
        if current_boot_id == installed_boot_id:
            raise RuntimeError(f"host has not rebooted since install owner was published bootId={current_boot_id}")
        stages.append({"name": current_stage, "status": "passed", "message": f"Host boot ID changed installed={installed_boot_id} current={current_boot_id}.", "observedAt": now()})

        current_stage = "installed-runtime-acceptance"
        command = [
            sys.executable,
            str(Path(__file__).with_name("acceptance-linux.py")),
            "--api-token-path", str(args.api_token_path),
            "--runtime-provider-document", str(args.runtime_provider_document),
            "--output-manifest", str(args.runtime_acceptance_manifest),
            "--base-url", args.base_url,
            "--timeout-seconds", str(args.timeout_seconds),
            "--http-timeout-seconds", str(args.http_timeout_seconds),
            "--boot-id-path", str(args.boot_id_path),
            "--support-directory", str(args.support_directory),
        ]
        result = subprocess.run(command)
        if result.returncode != 0:
            raise RuntimeError(f"post-reboot installed Runtime acceptance failed exitCode={result.returncode}")
        acceptance = load_object(args.runtime_acceptance_manifest, "post-reboot Runtime acceptance")
        if acceptance.get("status") != "passed" or acceptance.get("hostBootId") != current_boot_id or not isinstance(acceptance.get("runId"), str):
            raise RuntimeError("post-reboot Runtime acceptance does not prove the current boot")
        runtime_acceptance_run_id = str(acceptance["runId"])
        stages.append({"name": current_stage, "status": "passed", "message": f"Runtime acceptance passed after reboot runId={runtime_acceptance_run_id}.", "observedAt": now()})
    except Exception as error:
        reason = str(error)
        stages.append({"name": current_stage, "status": "failed", "message": reason, "observedAt": now()})
        write_manifest(args.output_manifest, proof(
            run_id, started_at, stages, "failed", current_stage, reason,
            installed_boot_id, current_boot_id, runtime_acceptance_run_id,
        ))
        raise SystemExit(
            f"VitalServer Linux reboot acceptance failed runId={run_id} stage={current_stage} reason={reason} manifest={args.output_manifest}"
        )

    write_manifest(args.output_manifest, proof(
        run_id, started_at, stages, "passed", None, None,
        installed_boot_id, current_boot_id, runtime_acceptance_run_id,
    ))
    print(f"VitalServer Linux reboot acceptance passed runId={run_id} manifest={args.output_manifest}")
    return 0


def load_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{label} read failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} must be an object path={path}")
    return value


def proof(
    run_id: str,
    started_at: str,
    stages: list[dict[str, str]],
    status: str,
    failure_stage: str | None,
    failure_reason: str | None,
    installed_boot_id: str | None,
    current_boot_id: str | None,
    runtime_acceptance_run_id: str | None,
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "runId": run_id,
        "platform": "linux-native-amd64",
        "kind": "reboot",
        "status": status,
        "startedAt": started_at,
        "completedAt": now(),
        "stages": stages,
        "failureStage": failure_stage,
        "failureReason": failure_reason,
        "installedBootId": installed_boot_id,
        "currentBootId": current_boot_id,
        "runtimeAcceptanceRunId": runtime_acceptance_run_id,
    }


def write_manifest(path: Path, document: dict[str, Any]) -> None:
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
