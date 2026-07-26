#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import uuid


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prove Linux standard uninstall, reinstall, and Runtime data preservation."
    )
    parser.add_argument("--bundle-directory", type=Path, required=True)
    parser.add_argument("--api-token-path", type=Path, required=True)
    parser.add_argument("--install-document", type=Path, required=True)
    parser.add_argument("--operation-document", type=Path, required=True)
    parser.add_argument("--data-sentinel", type=Path, required=True)
    parser.add_argument("--output-manifest", type=Path, required=True)
    parser.add_argument("--postgres-volume", default="vitalserver_postgres-data")
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
        stages.append(
            {"name": name, "status": "passed", "message": action(), "observedAt": now()}
        )

    try:
        if os.geteuid() != 0:
            raise RuntimeError("Linux uninstall/reinstall acceptance requires root")
        bundle = args.bundle_directory.resolve()
        installer = bundle / "install.sh"
        if not installer.is_file():
            raise RuntimeError(f"offline bundle installer is missing path={installer}")
        token = args.api_token_path.read_text(encoding="utf-8").strip()
        if not token:
            raise RuntimeError(f"Platform API token owner is empty path={args.api_token_path}")
        before_install = load_install(args.install_document)
        capabilities = request_json(args, token, "GET", "/platform/capabilities")
        if capabilities.get("canUninstallRuntime") is not True:
            raise RuntimeError("Platform Agent does not explicitly support uninstall")
        if args.data_sentinel.exists() or not args.data_sentinel.parent.is_dir():
            raise RuntimeError(f"data sentinel path is not available path={args.data_sentinel}")
        mutable_owner_digest = tree_digest(Path("/etc/vitalserver"), mutable_owner_paths())
        volume_before = inspect_volume(args.postgres_volume)
        stages.append(
            {
                "name": "preflight",
                "status": "passed",
                "message": "Install owner, standard uninstall capability, mutable owners, and Postgres volume are explicit.",
                "observedAt": now(),
            }
        )

        sentinel = os.urandom(64)

        def create_sentinel() -> str:
            with args.data_sentinel.open("xb") as stream:
                stream.write(sentinel)
                stream.flush()
                os.fsync(stream.fileno())
            return f"Runtime data sentinel created sha256={hashlib.sha256(sentinel).hexdigest()}."

        stage("data-sentinel-created", create_sentinel)
        uninstall_operation: dict[str, Any] = {}

        def accept_uninstall() -> str:
            nonlocal uninstall_operation
            uninstall_operation = request_json(
                args, token, "POST", "/platform/uninstall", {"mode": "standard"}
            )
            require_operation(uninstall_operation, "accepted")
            return f"Standard uninstall accepted operationId={uninstall_operation['operationId']}."

        stage("uninstall-accepted", accept_uninstall)

        def complete_uninstall() -> str:
            completed = wait_local_operation(
                args.operation_document,
                str(uninstall_operation["operationId"]),
                args.timeout_seconds,
            )
            require_operation(completed, "completed")
            if Path("/opt/vitalserver").exists() or args.install_document.exists():
                raise RuntimeError("standard uninstall left replaceable install owners")
            return f"Standard uninstall completed operationId={completed['operationId']}."

        stage("uninstall-completed", complete_uninstall)
        stage(
            "uninstall-data-preserved",
            lambda: prove_preserved(
                args.data_sentinel,
                sentinel,
                mutable_owner_digest,
                volume_before,
                args.postgres_volume,
                "uninstall",
            ),
        )

        def reinstall() -> str:
            result = subprocess.run([str(installer)], cwd=bundle, text=True)
            if result.returncode != 0:
                raise RuntimeError(f"offline reinstall failed exitCode={result.returncode}")
            wait_platform(args, token)
            after_install = load_install(args.install_document)
            for field in ("platformVersion", "runtimeBundleVersion"):
                if after_install.get(field) != before_install.get(field):
                    raise RuntimeError(
                        f"reinstall owner version changed field={field} before={before_install.get(field)} after={after_install.get(field)}"
                    )
            return f"Offline reinstall completed acceptanceRunId={after_install.get('installedAcceptanceRunId')}."

        stage("offline-reinstall", reinstall)
        stage(
            "reinstall-data-preserved",
            lambda: prove_preserved(
                args.data_sentinel,
                sentinel,
                mutable_owner_digest,
                volume_before,
                args.postgres_volume,
                "reinstall",
            ),
        )
        args.data_sentinel.unlink()
    except Exception as error:
        reason = str(error)
        stages.append(
            {"name": current_stage, "status": "failed", "message": reason, "observedAt": now()}
        )
        write_manifest(
            args.output_manifest,
            manifest(run_id, started_at, stages, "failed", current_stage, reason),
        )
        raise SystemExit(
            "VitalServer Linux uninstall/reinstall acceptance failed "
            f"runId={run_id} stage={current_stage} reason={reason} manifest={args.output_manifest}"
        )

    write_manifest(args.output_manifest, manifest(run_id, started_at, stages, "passed", None, None))
    print(
        "VitalServer Linux uninstall/reinstall acceptance passed "
        f"runId={run_id} manifest={args.output_manifest}"
    )
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


def wait_local_operation(path: Path, operation_id: str, timeout_seconds: int) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    last_reason = "not read"
    while time.monotonic() < deadline:
        try:
            operation = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(operation, dict):
                last_reason = "operation document is not an object"
            elif operation.get("operationId") != operation_id:
                raise RuntimeError(
                    f"uninstall workflow identity changed expected={operation_id} actual={operation.get('operationId')}"
                )
            elif operation.get("state") == "completed":
                return operation
            elif operation.get("state") == "failed":
                raise RuntimeError(f"uninstall workflow failed failure={operation.get('failure')}")
            else:
                last_reason = f"state={operation.get('state')}"
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            last_reason = str(error)
        time.sleep(1)
    raise RuntimeError(f"uninstall workflow did not complete lastRead={last_reason}")


def wait_platform(args: argparse.Namespace, token: str) -> None:
    deadline = time.monotonic() + args.timeout_seconds
    last_reason = "not read"
    while time.monotonic() < deadline:
        try:
            request_json(args, token, "GET", "/platform")
            request_json(args, token, "GET", "/runtime/capabilities")
            return
        except RuntimeError as error:
            last_reason = str(error)
        time.sleep(1)
    raise RuntimeError(f"reinstalled Platform and Runtime APIs did not become available lastRead={last_reason}")


def require_operation(operation: dict[str, Any], state: str) -> None:
    required = {
        "schemaVersion", "operationId", "kind", "state", "startedAt", "updatedAt", "release", "artifact", "failure"
    }
    missing = sorted(required - set(operation))
    if (
        missing
        or operation.get("schemaVersion") != 1
        or operation.get("kind") != "uninstall"
        or operation.get("state") != state
        or operation.get("failure") is not None
    ):
        raise RuntimeError(f"uninstall workflow contract is invalid missing={missing} operation={operation}")


def load_install(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"install owner read failed path={path}: {error}") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or value.get("state") != "installed":
        raise RuntimeError(f"install owner contract is invalid path={path}")
    for field in ("platformVersion", "runtimeBundleVersion", "installedAcceptanceRunId"):
        if not isinstance(value.get(field), str) or not value[field]:
            raise RuntimeError(f"install owner field is invalid path={path} field={field}")
    return value


def mutable_owner_paths() -> tuple[Path, ...]:
    return (
        Path("runtime-config.json"),
        Path("runtime-settings.json"),
        Path("runtime.env"),
        Path("secrets"),
        Path("redis-relay"),
    )


def tree_digest(root: Path, selected: tuple[Path, ...]) -> str:
    digest = hashlib.sha256()
    files: list[Path] = []
    for relative in selected:
        path = root / relative
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(candidate for candidate in path.rglob("*") if candidate.is_file())
        else:
            raise RuntimeError(f"mutable owner is missing path={path}")
    for path in sorted(files):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        data = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def inspect_volume(name: str) -> dict[str, str]:
    result = subprocess.run(
        ["docker", "volume", "inspect", name], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if result.returncode != 0:
        raise RuntimeError(f"Postgres volume inspect failed name={name} reason={result.stderr.strip()}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Postgres volume inspect JSON is invalid name={name}: {error}") from error
    if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], dict):
        raise RuntimeError(f"Postgres volume inspect result is invalid name={name}")
    document = value[0]
    identity = {field: document.get(field) for field in ("Name", "Driver", "Mountpoint", "CreatedAt")}
    if not all(isinstance(item, str) and item for item in identity.values()):
        raise RuntimeError(f"Postgres volume identity is incomplete name={name} identity={identity}")
    return identity  # type: ignore[return-value]


def prove_preserved(
    sentinel_path: Path,
    sentinel: bytes,
    owner_digest: str,
    volume: dict[str, str],
    volume_name: str,
    stage: str,
) -> str:
    if sentinel_path.read_bytes() != sentinel:
        raise RuntimeError(f"Runtime data sentinel changed after {stage} path={sentinel_path}")
    actual_digest = tree_digest(Path("/etc/vitalserver"), mutable_owner_paths())
    if actual_digest != owner_digest:
        raise RuntimeError(
            f"mutable owner digest changed after {stage} expected={owner_digest} actual={actual_digest}"
        )
    actual_volume = inspect_volume(volume_name)
    if actual_volume != volume:
        raise RuntimeError(
            f"Postgres volume identity changed after {stage} expected={volume} actual={actual_volume}"
        )
    return (
        f"Runtime sentinel, mutable owner digest, and Postgres volume identity are unchanged after {stage}."
    )


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
        "kind": "uninstall-reinstall-data-preservation",
        "runId": run_id,
        "platform": "linux-native-amd64",
        "startedAt": started_at,
        "completedAt": now(),
        "status": status,
        "failureStage": failure_stage,
        "failureReason": failure_reason,
        "stages": stages,
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
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def now() -> str:
    return datetime.now(UTC).isoformat()


if __name__ == "__main__":
    raise SystemExit(main())
