from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import threading

import pytest


ROOT = Path(__file__).resolve().parents[4]
ACCEPTANCE = (
    ROOT
    / "apps/vitalserver-platform-agent/packaging/linux/acceptance-linux.py"
)
REBOOT_ACCEPTANCE = (
    ROOT
    / "apps/vitalserver-platform-agent/packaging/linux/acceptance-reboot-linux.py"
)


class RuntimeContractHandler(BaseHTTPRequestHandler):
    provider_path: Path | None = None
    support_directory: Path | None = None
    support_operation: dict[str, object] | None = None
    active_platform_operation: dict[str, object] | None = None
    support_requests = 0

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/":
            self._write(200, b"<html>Runtime PWA</html>", "text/html")
            return
        if self.headers.get("Authorization") != "Bearer acceptance-token":
            self.send_response(401)
            self.end_headers()
            return
        documents = {
            "/platform": {
                "runtimeInstallationState": "executable",
                "services": [
                    {"role": role, "state": "running", "readError": None}
                    for role in (
                        "runtime-provider",
                        "public-proxy",
                        "log-sync",
                        "sleep-prevention",
                        "watchdog",
                    )
                ],
                "readIssues": [],
            },
            "/platform/capabilities": {"canExportLogs": True},
            "/platform/workflows/current": {
                "state": "loaded",
                "operation": self.support_operation or self.active_platform_operation,
                "readError": None,
            },
            "/runtime/capabilities": {
                "schemaVersion": 1,
                "capabilities": [
                    "services:list",
                    "settings:get",
                    "settings:apply",
                    "admin-password:apply",
                    "redis-relay:settings:get",
                    "redis-relay:settings:apply",
                ],
            },
            "/runtime/services": {"services": ["app", "postgres"]},
            "/runtime/stack": {
                "state": "loaded",
                "observedAt": "2026-07-11T00:00:00Z",
                "services": [{"service": "app", "state": "running"}],
                "probeErrors": [],
            },
            "/runtime/settings": {
                "state": "loaded",
                "settings": {"publicHost": ""},
                "readError": None,
            },
            "/runtime/redis-relay/settings": {
                "state": "loaded",
                "settings": {
                    "target": {"passwordConfigured": False},
                },
                "readError": None,
            },
            "/runtime/events?limit=10": {
                "events": [],
                "nextCursor": None,
                "matchingCount": None,
            },
        }
        document = documents.get(self.path)
        if document is None:
            self._write(404, b"{}", "application/json")
            return
        self._write(200, json.dumps(document).encode(), "application/json")

    def do_POST(self) -> None:  # noqa: N802
        if self.headers.get("Authorization") != "Bearer acceptance-token":
            self._write(401, b"{}", "application/json")
            return
        if self.path == "/platform/support-exports":
            type(self).support_requests += 1
            if self.support_directory is None:
                self._write(500, b"{}", "application/json")
                return
            operation_id = "workflow-0123456789abcdef0123456789abcdef"
            self.support_directory.mkdir(parents=True, exist_ok=True)
            artifact = self.support_directory / f"vitalserver-support-{operation_id}.tar.gz"
            artifact.write_bytes(b"support evidence")
            timestamp = "2026-07-11T00:00:00Z"
            accepted = {
                "schemaVersion": 1,
                "operationId": operation_id,
                "kind": "support-export",
                "state": "accepted",
                "startedAt": timestamp,
                "updatedAt": timestamp,
                "release": None,
                "artifact": None,
                "failure": None,
            }
            type(self).support_operation = {
                **accepted,
                "state": "completed",
                "artifact": {
                    "path": str(artifact),
                    "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                    "sizeBytes": artifact.stat().st_size,
                },
            }
            self._write(202, json.dumps(accepted).encode(), "application/json")
            return
        action = self.path.rsplit("/", maxsplit=1)[-1]
        if self.path not in {
            "/platform/runtime-provider/stop",
            "/platform/runtime-provider/start",
        }:
            self._write(404, b"{}", "application/json")
            return
        state = "stopped" if action == "stop" else "running"
        if self.provider_path is None:
            self._write(500, b"{}", "application/json")
            return
        self.provider_path.write_text(
            json.dumps({"schemaVersion": 1, "state": state, "updatedAt": "2026-07-11T00:00:01Z"}),
            encoding="utf-8",
        )
        self._write(
            200,
            json.dumps({
                "operationId": f"provider-{action}",
                "action": action,
                "state": "completed",
                "provider": {"state": "loaded", "document": None, "readError": None},
                "failure": None,
            }).encode(),
            "application/json",
        )

    def log_message(self, format: str, *args: object) -> None:
        return

    def _write(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


@pytest.mark.parametrize(
    ("support_export_mode", "active_update", "expected_support_requests"),
    (("execute", False, 1), ("capability-only", False, 0), ("execute", True, 0)),
)
def test_linux_installed_acceptance_writes_complete_owner_proof(
    tmp_path: Path,
    support_export_mode: str,
    active_update: bool,
    expected_support_requests: int,
) -> None:
    token = tmp_path / "token"
    token.write_text("acceptance-token\n", encoding="utf-8")
    provider = tmp_path / "runtime-provider.json"
    provider.write_text(
        json.dumps(
                {
                    "schemaVersion": 1,
                    "state": "running",
                    "updatedAt": "2026-07-11T00:00:00Z",
            }
        ),
        encoding="utf-8",
    )
    output = tmp_path / "linux-native-acceptance.json"
    boot_id = tmp_path / "boot-id"
    boot_id.write_text("11111111-1111-4111-8111-111111111111\n", encoding="utf-8")
    RuntimeContractHandler.provider_path = provider
    RuntimeContractHandler.support_directory = tmp_path / "support"
    RuntimeContractHandler.support_operation = None
    RuntimeContractHandler.support_requests = 0
    RuntimeContractHandler.active_platform_operation = (
        {
            "schemaVersion": 1,
            "operationId": "workflow-fedcba9876543210fedcba9876543210",
            "kind": "update-apply",
            "state": "running",
            "startedAt": "2026-07-11T00:00:00Z",
            "updatedAt": "2026-07-11T00:00:00Z",
            "release": None,
            "artifact": None,
            "failure": None,
        }
        if active_update
        else None
    )
    server = ThreadingHTTPServer(("127.0.0.1", 0), RuntimeContractHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run(
            [
                sys.executable,
                str(ACCEPTANCE),
                "--api-token-path",
                str(token),
                "--runtime-provider-document",
                str(provider),
                "--output-manifest",
                str(output),
                "--base-url",
                f"http://127.0.0.1:{server.server_port}",
                "--timeout-seconds",
                "2",
                "--boot-id-path",
                str(boot_id),
                "--support-directory",
                str(RuntimeContractHandler.support_directory),
                "--support-export-mode",
                support_export_mode,
            ],
            check=True,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    manifest = json.loads(output.read_text(encoding="utf-8"))
    assert manifest["platform"] == "linux-native-amd64"
    assert manifest["status"] == "passed"
    assert manifest["failureStage"] is None
    assert manifest["hostBootId"] == "11111111-1111-4111-8111-111111111111"
    assert RuntimeContractHandler.support_requests == expected_support_requests
    assert {stage["name"] for stage in manifest["stages"]} == {
        "preflight",
        "runtime-provider-running",
        "platform-contract",
        "runtime-capabilities",
        "runtime-services",
        "runtime-stack",
        "runtime-settings",
        "redis-relay-settings",
        "runtime-events",
        "product-pwa",
        "platform-support-export",
        "runtime-provider-stop",
        "runtime-provider-start",
        "runtime-after-provider-restart",
    }


def test_linux_reboot_acceptance_requires_changed_boot_id_and_runtime_proof(tmp_path: Path) -> None:
    token = tmp_path / "token"
    token.write_text("acceptance-token\n", encoding="utf-8")
    provider = tmp_path / "runtime-provider.json"
    provider.write_text(json.dumps({
        "schemaVersion": 1,
        "state": "running",
        "updatedAt": "2026-07-11T00:00:00Z",
    }), encoding="utf-8")
    install = tmp_path / "install.json"
    install.write_text(json.dumps({
        "schemaVersion": 1,
        "state": "installed",
        "platformVersion": "2.0.0",
        "runtimeBundleVersion": "2.3.4",
        "installedBootId": "11111111-1111-4111-8111-111111111111",
    }), encoding="utf-8")
    boot_id = tmp_path / "boot-id"
    boot_id.write_text("22222222-2222-4222-8222-222222222222\n", encoding="utf-8")
    runtime_proof = tmp_path / "runtime-after-reboot.json"
    reboot_proof = tmp_path / "reboot-acceptance.json"
    RuntimeContractHandler.provider_path = provider
    RuntimeContractHandler.support_directory = tmp_path / "support"
    RuntimeContractHandler.support_operation = None
    RuntimeContractHandler.active_platform_operation = None
    server = ThreadingHTTPServer(("127.0.0.1", 0), RuntimeContractHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run([
            sys.executable,
            str(REBOOT_ACCEPTANCE),
            "--api-token-path", str(token),
            "--runtime-provider-document", str(provider),
            "--install-document", str(install),
            "--runtime-acceptance-manifest", str(runtime_proof),
            "--output-manifest", str(reboot_proof),
            "--base-url", f"http://127.0.0.1:{server.server_port}",
            "--timeout-seconds", "2",
            "--boot-id-path", str(boot_id),
            "--support-directory", str(RuntimeContractHandler.support_directory),
        ], check=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    proof = json.loads(reboot_proof.read_text(encoding="utf-8"))
    assert proof["status"] == "passed"
    assert proof["installedBootId"] == "11111111-1111-4111-8111-111111111111"
    assert proof["currentBootId"] == "22222222-2222-4222-8222-222222222222"
    assert proof["runtimeAcceptanceRunId"] == json.loads(runtime_proof.read_text(encoding="utf-8"))["runId"]
