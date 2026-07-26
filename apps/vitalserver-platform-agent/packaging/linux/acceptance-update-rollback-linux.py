#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import hashlib
import json
import os
from pathlib import Path
import time
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import uuid


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prove Linux update, rollback, and mutable data preservation.")
    parser.add_argument("--api-token-path", type=Path, required=True)
    parser.add_argument("--install-document", type=Path, required=True)
    parser.add_argument("--update-bundle", type=Path, required=True)
    parser.add_argument("--expected-update-platform-version", required=True)
    parser.add_argument("--expected-update-runtime-bundle-version", required=True)
    parser.add_argument("--data-sentinel", type=Path, required=True)
    parser.add_argument("--output-manifest", type=Path, required=True)
    parser.add_argument("--base-url", default="http://127.0.0.1:18321")
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--http-timeout-seconds", type=int, default=60)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_id = str(uuid.uuid4())
    started_at = now()
    stages: list[dict[str, str]] = []
    current_stage = "preflight"

    def stage(name: str, action: Callable[[], str]) -> None:
        nonlocal current_stage
        current_stage = name
        message = action()
        stages.append({"name": name, "status": "passed", "message": message, "observedAt": now()})

    try:
        token = args.api_token_path.read_text(encoding="utf-8").strip()
        if not token:
            raise RuntimeError(f"Platform API token owner is empty path={args.api_token_path}")
        if not args.update_bundle.is_file():
            raise RuntimeError(f"update bundle is missing path={args.update_bundle}")
        before = load_install(args.install_document)
        capabilities = request_json(args, token, "GET", "/platform/capabilities")
        if capabilities.get("canApplyBundle") is not True or capabilities.get("canRollbackRelease") is not True:
            raise RuntimeError("Platform Agent does not explicitly support trusted update apply and release rollback")
        if args.data_sentinel.exists():
            raise RuntimeError(f"data sentinel already exists path={args.data_sentinel}")
        if not args.data_sentinel.parent.is_dir():
            raise RuntimeError(f"data sentinel parent is missing path={args.data_sentinel.parent}")
        stages.append({"name": "preflight", "status": "passed", "message": "Update, rollback, owner, and mutable data inputs are explicit.", "observedAt": now()})

        sentinel = os.urandom(64)

        def create_sentinel() -> str:
            with args.data_sentinel.open("xb") as stream:
                stream.write(sentinel)
                stream.flush()
                os.fsync(stream.fileno())
            return f"Mutable data sentinel created sha256={hashlib.sha256(sentinel).hexdigest()}."

        stage("data-sentinel-created", create_sentinel)

        update_operation: dict[str, Any] = {}

        def accept_update() -> str:
            nonlocal update_operation
            update_operation = request_json(
                args,
                token,
                "POST",
                "/platform/update-bundles/apply",
                {"bundle": {"kind": "localPath", "value": str(args.update_bundle.resolve())}},
            )
            require_operation(update_operation, "update-apply", "accepted")
            return f"Update apply accepted operationId={update_operation['operationId']}."

        stage("update-accepted", accept_update)

        def complete_update() -> str:
            completed = wait_operation(args, token, str(update_operation["operationId"]), "update-apply")
            release = completed.get("release")
            if not isinstance(release, dict) or release.get("platformVersion") != args.expected_update_platform_version or release.get("runtimeBundleVersion") != args.expected_update_runtime_bundle_version:
                raise RuntimeError(f"completed update release differs expected={args.expected_update_platform_version}/{args.expected_update_runtime_bundle_version} actual={release}")
            install = load_install(args.install_document)
            require_install_versions(install, args.expected_update_platform_version, args.expected_update_runtime_bundle_version)
            return f"Update completed and install owner advanced operationId={completed['operationId']}."

        stage("update-completed", complete_update)
        stage("update-data-preserved", lambda: prove_sentinel(args.data_sentinel, sentinel, "update"))

        rollback_operation: dict[str, Any] = {}

        def accept_rollback() -> str:
            nonlocal rollback_operation
            rollback_operation = request_json(args, token, "POST", "/platform/releases/rollback")
            require_operation(rollback_operation, "rollback", "accepted")
            return f"Release rollback accepted operationId={rollback_operation['operationId']}."

        stage("rollback-accepted", accept_rollback)

        def complete_rollback() -> str:
            completed = wait_operation(args, token, str(rollback_operation["operationId"]), "rollback")
            install = load_install(args.install_document)
            require_install_versions(install, str(before["platformVersion"]), str(before["runtimeBundleVersion"]))
            return f"Rollback completed and install owner returned to the original release operationId={completed['operationId']}."

        stage("rollback-completed", complete_rollback)
        stage("rollback-data-preserved", lambda: prove_sentinel(args.data_sentinel, sentinel, "rollback"))
        args.data_sentinel.unlink()
    except Exception as error:
        reason = str(error)
        stages.append({"name": current_stage, "status": "failed", "message": reason, "observedAt": now()})
        write_manifest(args.output_manifest, manifest(run_id, started_at, stages, "failed", current_stage, reason))
        raise SystemExit(
            f"VitalServer Linux update/rollback acceptance failed runId={run_id} stage={current_stage} reason={reason} manifest={args.output_manifest}"
        )

    write_manifest(args.output_manifest, manifest(run_id, started_at, stages, "passed", None, None))
    print(f"VitalServer Linux update/rollback acceptance passed runId={run_id} manifest={args.output_manifest}")
    return 0


def request_json(
    args: argparse.Namespace,
    token: str,
    method: str,
    path: str,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = Request(args.base_url.rstrip("/") + path, data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=args.http_timeout_seconds) as response:
            value = json.load(response)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Platform request failed method={method} path={path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"Platform response is not an object method={method} path={path}")
    return value


def wait_operation(args: argparse.Namespace, token: str, operation_id: str, kind: str) -> dict[str, Any]:
    deadline = time.monotonic() + args.timeout_seconds
    last_reason = "not read"
    while time.monotonic() < deadline:
        try:
            resource = request_json(args, token, "GET", "/platform/workflows/current")
            operation = resource.get("operation")
            if resource.get("state") != "loaded" or not isinstance(operation, dict):
                last_reason = f"resourceState={resource.get('state')} readError={resource.get('readError')}"
            elif operation.get("operationId") != operation_id:
                raise RuntimeError(f"Platform workflow identity changed expected={operation_id} actual={operation.get('operationId')}")
            elif operation.get("kind") != kind:
                raise RuntimeError(f"Platform workflow kind changed expected={kind} actual={operation.get('kind')}")
            elif operation.get("state") == "completed":
                require_operation(operation, kind, "completed")
                return operation
            elif operation.get("state") == "failed":
                raise RuntimeError(f"Platform workflow failed operationId={operation_id} failure={operation.get('failure')}")
            else:
                last_reason = f"state={operation.get('state')}"
        except RuntimeError as error:
            last_reason = str(error)
            if "identity changed" in last_reason or "kind changed" in last_reason or "workflow failed" in last_reason:
                raise
        time.sleep(1)
    raise RuntimeError(f"Platform workflow did not complete operationId={operation_id} lastRead={last_reason}")


def require_operation(operation: dict[str, Any], kind: str, state: str) -> None:
    required = {"schemaVersion", "operationId", "kind", "state", "startedAt", "updatedAt", "release", "artifact", "failure"}
    missing = sorted(required - set(operation))
    if missing or operation.get("schemaVersion") != 1 or operation.get("kind") != kind or operation.get("state") != state:
        raise RuntimeError(f"Platform workflow contract is invalid missing={missing} operation={operation}")
    if state != "failed" and operation.get("failure") is not None:
        raise RuntimeError(f"non-failed Platform workflow carries failure operation={operation}")


def load_install(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"install owner read failed path={path}: {error}") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or value.get("state") != "installed":
        raise RuntimeError(f"install owner contract is invalid path={path}")
    for field in ("platformVersion", "runtimeBundleVersion"):
        if not isinstance(value.get(field), str) or not value[field]:
            raise RuntimeError(f"install owner field is invalid path={path} field={field}")
    return value


def require_install_versions(document: dict[str, Any], platform_version: str, runtime_version: str) -> None:
    if document.get("platformVersion") != platform_version or document.get("runtimeBundleVersion") != runtime_version:
        raise RuntimeError(f"install owner version differs expected={platform_version}/{runtime_version} actual={document.get('platformVersion')}/{document.get('runtimeBundleVersion')}")


def prove_sentinel(path: Path, expected: bytes, stage: str) -> str:
    try:
        actual = path.read_bytes()
    except OSError as error:
        raise RuntimeError(f"mutable data sentinel read failed after {stage} path={path}: {error}") from error
    if actual != expected:
        raise RuntimeError(f"mutable data sentinel changed after {stage} path={path}")
    return f"Mutable data sentinel is unchanged after {stage}."


def manifest(
    run_id: str,
    started_at: str,
    stages: list[dict[str, str]],
    status: str,
    failure_stage: str | None,
    failure_reason: str | None,
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "runId": run_id,
        "platform": "linux-native-amd64",
        "kind": "update-rollback-data-preservation",
        "status": status,
        "startedAt": started_at,
        "completedAt": now(),
        "stages": stages,
        "failureStage": failure_stage,
        "failureReason": failure_reason,
    }


def write_manifest(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


def now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


if __name__ == "__main__":
    raise SystemExit(main())
