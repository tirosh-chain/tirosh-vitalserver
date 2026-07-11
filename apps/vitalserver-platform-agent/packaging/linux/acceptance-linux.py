#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import uuid


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prove an installed Linux Native Runtime v2.")
    parser.add_argument("--api-token-path", type=Path, required=True)
    parser.add_argument("--runtime-provider-document", type=Path, required=True)
    parser.add_argument("--output-manifest", type=Path, required=True)
    parser.add_argument("--base-url", default="http://127.0.0.1:18321")
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--http-timeout-seconds", type=int, default=60)
    parser.add_argument("--boot-id-path", type=Path, default=Path("/proc/sys/kernel/random/boot_id"))
    parser.add_argument(
        "--support-directory",
        type=Path,
        default=Path("/var/lib/vitalserver/support"),
    )
    parser.add_argument(
        "--support-export-mode",
        choices=("execute", "capability-only"),
        default="execute",
    )
    return parser.parse_args()


def load_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise RuntimeError(f"{label} is missing path={path}") from error
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{label} read failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} must be a JSON object path={path}")
    return value


def require_fields(document: dict[str, Any], fields: tuple[str, ...], label: str) -> None:
    missing = [field for field in fields if field not in document]
    if missing:
        raise RuntimeError(f"{label} misses explicit fields: {','.join(missing)}")


def fetch_json(
    base_url: str,
    path: str,
    token: str,
    timeout_seconds: int,
    *,
    method: str = "GET",
) -> dict[str, Any]:
    request = Request(
        base_url.rstrip("/") + path,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        method=method,
    )
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            value = json.load(response)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"HTTP contract read failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"HTTP contract is not an object path={path}")
    return value


def fetch_pwa(base_url: str, timeout_seconds: int) -> None:
    try:
        with urlopen(base_url.rstrip("/") + "/", timeout=timeout_seconds) as response:
            content = response.read()
            status = response.status
    except (HTTPError, URLError, TimeoutError, OSError) as error:
        raise RuntimeError(f"Product PWA read failed: {error}") from error
    if status != 200 or not content:
        raise RuntimeError(f"Product PWA is unavailable status={status} bytes={len(content)}")


def write_manifest(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


def main() -> int:
    args = parse_args()
    run_id = str(uuid.uuid4())
    started_at = utc_now()
    stages: list[dict[str, str]] = []
    current_stage = "preflight"
    host_boot_id: str | None = None

    def stage(name: str, action: Callable[[], str]) -> None:
        nonlocal current_stage
        current_stage = name
        message = action()
        stages.append({"name": name, "status": "passed", "message": message, "observedAt": utc_now()})

    try:
        try:
            token = args.api_token_path.read_text(encoding="utf-8").strip()
        except (FileNotFoundError, OSError, UnicodeDecodeError) as error:
            raise RuntimeError(f"Platform API token owner read failed path={args.api_token_path}: {error}") from error
        if not token:
            raise RuntimeError(f"Platform API token owner is empty path={args.api_token_path}")
        try:
            host_boot_id = str(uuid.UUID(args.boot_id_path.read_text(encoding="utf-8").strip()))
        except (FileNotFoundError, OSError, UnicodeDecodeError, ValueError) as error:
            raise RuntimeError(f"Host boot ID owner read failed path={args.boot_id_path}: {error}") from error
        stages.append({"name": "preflight", "status": "passed", "message": "Acceptance owner inputs are available.", "observedAt": utc_now()})

        def wait_provider_state(expected_state: str) -> str:
            deadline = time.monotonic() + args.timeout_seconds
            last_reason = "not read"
            while time.monotonic() < deadline:
                try:
                    provider = load_object(args.runtime_provider_document, "Runtime Provider document")
                    require_fields(provider, ("schemaVersion", "state", "updatedAt"), "Runtime Provider document")
                    if provider["schemaVersion"] != 1:
                        raise RuntimeError(f"Runtime Provider schemaVersion is unsupported: {provider['schemaVersion']}")
                    if provider["state"] == "failed":
                        raise RuntimeError(
                            "Runtime Provider reported failed "
                            f"terminalReason={provider.get('terminalReason')} message={provider.get('message')}"
                        )
                    if provider["state"] == expected_state:
                        return f"Runtime Provider reported {expected_state} with explicit lifecycle state."
                    last_reason = f"state={provider['state']}"
                except RuntimeError as error:
                    last_reason = str(error)
                time.sleep(1)
            raise RuntimeError(
                f"Runtime Provider did not reach {expected_state} before deadline lastRead={last_reason}"
            )

        stage("runtime-provider-running", lambda: wait_provider_state("running"))

        def platform_contract() -> str:
            document = fetch_json(args.base_url, "/platform", token, args.http_timeout_seconds)
            require_fields(document, ("runtimeInstallationState", "services", "readIssues"), "Platform contract")
            services = document["services"]
            if not isinstance(services, list):
                raise RuntimeError("Platform services must be an array")
            roles = {service.get("role") for service in services if isinstance(service, dict)}
            expected = {"runtime-provider", "public-proxy", "log-sync", "sleep-prevention", "watchdog"}
            if roles != expected:
                raise RuntimeError(f"Platform service roles differ expected={sorted(expected)} actual={sorted(str(role) for role in roles)}")
            return "Platform owner contract is complete."

        stage("platform-contract", platform_contract)

        def runtime_capabilities() -> str:
            document = fetch_json(args.base_url, "/runtime/capabilities", token, args.http_timeout_seconds)
            require_fields(document, ("schemaVersion", "capabilities"), "Runtime capabilities")
            capabilities = document["capabilities"]
            if document["schemaVersion"] != 1 or not isinstance(capabilities, list):
                raise RuntimeError("Runtime capabilities contract is invalid")
            required = {
                "services:list",
                "settings:get",
                "settings:apply",
                "admin-password:apply",
                "redis-relay:settings:get",
                "redis-relay:settings:apply",
            }
            missing = required - set(capabilities)
            if missing:
                raise RuntimeError(f"Runtime capabilities are missing: {sorted(missing)}")
            return "Runtime Controller capabilities are available."

        stage("runtime-capabilities", runtime_capabilities)

        def runtime_services() -> str:
            document = fetch_json(args.base_url, "/runtime/services", token, args.http_timeout_seconds)
            services = document.get("services")
            if not isinstance(services, list) or not services:
                raise RuntimeError("Runtime Controller service list is empty or missing")
            return "Runtime Controller service list is non-empty."

        stage("runtime-services", runtime_services)

        def runtime_stack() -> str:
            document = fetch_json(args.base_url, "/runtime/stack", token, args.http_timeout_seconds)
            require_fields(document, ("state", "observedAt", "services", "probeErrors"), "Runtime stack")
            services = document["services"]
            if not isinstance(services, list):
                raise RuntimeError("Runtime stack services must be an array")
            failed = [service.get("service") for service in services if isinstance(service, dict) and service.get("state") in {"exited", "restarting", "failed"}]
            if failed:
                raise RuntimeError(f"Runtime stack contains failed services: {failed}")
            return "Runtime stack has no failed required service."

        stage("runtime-stack", runtime_stack)

        def runtime_settings() -> str:
            document = fetch_json(args.base_url, "/runtime/settings", token, args.http_timeout_seconds)
            require_fields(document, ("state", "settings", "readError"), "Runtime settings")
            if document["state"] != "loaded" or not isinstance(document["settings"], dict) or document["readError"] is not None:
                raise RuntimeError(f"Runtime settings owner is not loaded state={document['state']} readError={document['readError']}")
            return "Runtime Controller settings owner is loaded."

        stage("runtime-settings", runtime_settings)

        def redis_relay_settings() -> str:
            document = fetch_json(
                args.base_url,
                "/runtime/redis-relay/settings",
                token,
                args.http_timeout_seconds,
            )
            require_fields(document, ("state", "settings", "readError"), "Redis Relay settings")
            settings = document["settings"]
            if document["state"] != "loaded" or not isinstance(settings, dict) or document["readError"] is not None:
                raise RuntimeError(f"Redis Relay settings owner is not loaded state={document['state']} readError={document['readError']}")
            target = settings.get("target")
            if not isinstance(target, dict) or "passwordConfigured" not in target or "password" in target:
                raise RuntimeError("Redis Relay settings secret state is not explicit or exposes password material")
            return "Runtime Controller Redis Relay settings owner is loaded without secret material."

        stage("redis-relay-settings", redis_relay_settings)

        def redis_relay_status_owner() -> str:
            deadline = time.monotonic() + args.timeout_seconds
            last_reason = "not read"
            while time.monotonic() < deadline:
                try:
                    document = fetch_json(
                        args.base_url,
                        "/runtime/redis-relay/status",
                        token,
                        args.http_timeout_seconds,
                    )
                    require_fields(
                        document,
                        ("readState", "document", "readError"),
                        "Redis Relay status owner",
                    )
                    status_document = document["document"]
                    if (
                        document["readState"] == "loaded"
                        and isinstance(status_document, dict)
                        and document["readError"] is None
                    ):
                        require_fields(
                            status_document,
                            ("schemaVersion", "observedAt", "enabled", "state"),
                            "Redis Relay status owner document",
                        )
                        return (
                            "Redis Relay published its status through the Runtime "
                            "Controller owner transport."
                        )
                    last_reason = (
                        f"readState={document['readState']} "
                        f"readError={document['readError']}"
                    )
                except RuntimeError as error:
                    last_reason = str(error)
                time.sleep(1)
            raise RuntimeError(
                "Redis Relay status owner did not report a loaded document "
                f"before deadline lastRead={last_reason}"
            )

        stage("redis-relay-status-owner", redis_relay_status_owner)

        def runtime_events() -> str:
            document = fetch_json(args.base_url, "/runtime/events?limit=10", token, args.http_timeout_seconds)
            require_fields(document, ("events", "nextCursor", "matchingCount"), "Runtime event history")
            if not isinstance(document["events"], list):
                raise RuntimeError("Runtime event history events must be an array")
            return "Runtime Controller event history contract is available."

        stage("runtime-events", runtime_events)
        stage("product-pwa", lambda: (fetch_pwa(args.base_url, args.http_timeout_seconds), "Common product PWA is served by Platform Agent.")[1])

        def support_export() -> str:
            capabilities = fetch_json(args.base_url, "/platform/capabilities", token, args.http_timeout_seconds)
            if capabilities.get("canExportLogs") is not True:
                raise RuntimeError("Platform support export capability is not available")
            if args.support_export_mode == "capability-only":
                return "Platform support export capability is explicitly available; artifact execution is deferred while the enclosing Platform workflow owns the durable operation resource."
            current = fetch_json(
                args.base_url,
                "/platform/workflows/current",
                token,
                args.http_timeout_seconds,
            )
            active = current.get("operation")
            if (
                current.get("state") == "loaded"
                and isinstance(active, dict)
                and active.get("state") in {"accepted", "running"}
            ):
                if active.get("kind") == "update-apply" and active.get("state") == "running":
                    return (
                        "Platform support export capability is explicitly available; "
                        f"artifact execution is deferred by enclosing update operationId={active.get('operationId')}."
                    )
                raise RuntimeError(
                    "Platform support export is blocked by active workflow "
                    f"operationId={active.get('operationId')} kind={active.get('kind')} state={active.get('state')}"
                )
            accepted = fetch_json(
                args.base_url,
                "/platform/support-exports",
                token,
                args.http_timeout_seconds,
                method="POST",
            )
            require_fields(
                accepted,
                ("schemaVersion", "operationId", "kind", "state", "startedAt", "updatedAt", "release", "artifact", "failure"),
                "Support export accepted workflow",
            )
            operation_id = accepted.get("operationId")
            if accepted.get("kind") != "support-export" or accepted.get("state") != "accepted" or not isinstance(operation_id, str):
                raise RuntimeError(f"Support export was not accepted response={accepted}")
            deadline = time.monotonic() + args.timeout_seconds
            operation: dict[str, Any] | None = None
            while time.monotonic() < deadline:
                resource = fetch_json(args.base_url, "/platform/workflows/current", token, args.http_timeout_seconds)
                if resource.get("state") != "loaded" or not isinstance(resource.get("operation"), dict):
                    raise RuntimeError(f"Support export workflow owner is not loaded resource={resource}")
                operation = resource["operation"]
                if operation.get("operationId") != operation_id:
                    raise RuntimeError(
                        f"Support export workflow identity changed expected={operation_id} actual={operation.get('operationId')}"
                    )
                if operation.get("state") == "completed":
                    break
                if operation.get("state") == "failed":
                    raise RuntimeError(f"Support export workflow failed evidence={operation.get('failure')}")
                time.sleep(1)
            if operation is None or operation.get("state") != "completed":
                raise RuntimeError(f"Support export did not complete operationId={operation_id}")
            artifact = operation.get("artifact")
            if not isinstance(artifact, dict):
                raise RuntimeError("Completed support export has no artifact evidence")
            path_value = artifact.get("path")
            if not isinstance(path_value, str):
                raise RuntimeError("Support export artifact path is missing")
            path = Path(path_value)
            support_root = args.support_directory.resolve()
            if path.is_symlink() or not path.is_file() or path.parent.resolve() != support_root:
                raise RuntimeError(f"Support export artifact is outside managed root or invalid path={path}")
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            actual_digest = digest.hexdigest()
            actual_size = path.stat().st_size
            if artifact.get("sha256") != actual_digest or artifact.get("sizeBytes") != actual_size:
                raise RuntimeError("Support export artifact digest or byte size differs from workflow evidence")
            return f"Managed support artifact is complete operationId={operation_id} sha256={actual_digest}."

        stage("platform-support-export", support_export)

        def provider_command(action: str, expected_state: str) -> str:
            response = fetch_json(
                args.base_url,
                f"/platform/runtime-provider/{action}",
                token,
                args.timeout_seconds,
                method="POST",
            )
            require_fields(response, ("operationId", "action", "state", "provider", "failure"), f"Runtime Provider {action} command")
            if response["action"] != action or response["state"] != "completed" or response["failure"] is not None:
                raise RuntimeError(f"Runtime Provider {action} command failed response={response}")
            wait_provider_state(expected_state)
            return f"Runtime Provider {action} command completed and owner reached {expected_state}."

        stage("runtime-provider-stop", lambda: provider_command("stop", "stopped"))
        stage("runtime-provider-start", lambda: provider_command("start", "running"))
        stage("runtime-after-provider-restart", runtime_capabilities)
    except Exception as error:
        reason = str(error)
        stages.append({"name": current_stage, "status": "failed", "message": reason, "observedAt": utc_now()})
        write_manifest(args.output_manifest, {
            "schemaVersion": 1, "runId": run_id, "platform": "linux-native-amd64", "status": "failed",
            "startedAt": started_at, "completedAt": utc_now(), "stages": stages,
            "failureStage": current_stage, "failureReason": reason,
            "runtimeProviderDocumentPath": str(args.runtime_provider_document),
            "hostBootId": host_boot_id,
        })
        raise SystemExit(
            f"VitalServer Linux acceptance failed runId={run_id} stage={current_stage} "
            f"reason={reason} manifest={args.output_manifest}"
        )

    write_manifest(args.output_manifest, {
        "schemaVersion": 1, "runId": run_id, "platform": "linux-native-amd64", "status": "passed",
        "startedAt": started_at, "completedAt": utc_now(), "stages": stages,
        "failureStage": None, "failureReason": None,
        "runtimeProviderDocumentPath": str(args.runtime_provider_document),
        "hostBootId": host_boot_id,
    })
    print(f"VitalServer Linux acceptance passed runId={run_id} manifest={args.output_manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
