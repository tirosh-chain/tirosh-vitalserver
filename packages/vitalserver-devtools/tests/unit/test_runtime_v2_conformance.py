from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import subprocess
from threading import Thread
import time

from tirosh_vitalserver.devtools.runtime_v2_conformance import (
    ConformanceTransportError,
    PLATFORM_CAPABILITIES,
    PLATFORM_SERVICE_ROLES,
    RuntimeV2ConformanceSuite,
    http_json_getter,
    validate_platform_state,
)


def _documents() -> dict[str, dict[str, object]]:
    return {
        "/platform": {
            "runtimeInstallationState": "executable",
            "services": [
                {"role": role, "state": "running", "readError": None}
                for role in sorted(PLATFORM_SERVICE_ROLES)
            ],
            "platformHealth": "healthy",
            "installedVersion": "2.0.0",
            "runtimeProviderState": "running",
            "runtimeProviderErrors": [],
            "runtimeEndpoint": "192.168.64.2",
            "healthIssues": [],
        },
        "/platform/capabilities": {
            capability: True for capability in PLATFORM_CAPABILITIES
        },
        "/platform/operations": {
            "activeOperation": None,
            "install": {"state": "unavailable", "document": None, "readError": None},
            "lease": {
                "state": "unavailable",
                "document": None,
                "readError": None,
                "staleReason": None,
            },
        },
        "/platform/runtime-endpoint": {
            "state": "loaded",
            "read": {
                "state": "loaded",
                "address": "192.168.64.2",
                "source": "platform-agent",
                "reason": None,
            },
            "readError": None,
        },
        "/platform/runtime-provider": {
            "state": "loaded",
            "document": {"state": "running"},
            "readError": None,
        },
        "/runtime/capabilities": {
            "schemaVersion": 1,
            "capabilities": ["services:list", "stack:status"],
        },
        "/runtime/services": {"services": ["app", "redis"]},
        "/runtime/stack": {
            "state": "ready",
            "observedAt": "2026-07-11T00:00:00Z",
            "services": [
                {
                    "service": "app",
                    "state": "running",
                    "health": "healthy",
                    "observedAt": "2026-07-11T00:00:00Z",
                }
            ],
            "probeErrors": [],
        },
    }


def test_cross_platform_core_contract_passes_without_os_specific_fields() -> None:
    documents = _documents()
    report = RuntimeV2ConformanceSuite(lambda path: documents[path]).run()

    assert report.passed
    assert report.issues == ()
    assert report.checked_resources == tuple(documents)


def test_platform_contract_rejects_vm_specific_and_product_fields() -> None:
    document = _documents()["/platform"]
    document["vmIP"] = "192.168.64.2"
    document["redisUIHTTP"] = "200"

    issues = validate_platform_state(document)

    assert any("vmIP" in issue for issue in issues)
    assert any("redisUIHTTP" in issue for issue in issues)


def test_platform_service_state_rejects_launchd_vocabulary_and_missing_failure_evidence() -> None:
    platform = _documents()["/platform"]
    services = platform["services"]
    assert isinstance(services, list)
    assert isinstance(services[0], dict)
    assert isinstance(services[1], dict)
    services[0]["state"] = "loaded"
    services[1]["state"] = "read-failed"
    services[1]["readError"] = None
    services[2]["state"] = "unavailable"
    services[2]["readError"] = None

    issues = validate_platform_state(platform)

    assert any("unknown value: loaded" in issue for issue in issues)
    assert sum("must explain unavailable or failed state" in issue for issue in issues) == 2


def test_platform_contract_requires_every_role_without_inference() -> None:
    document = _documents()["/platform"]
    document["services"] = [
        service
        for service in document["services"]  # type: ignore[union-attr]
        if service["role"] != "runtime-provider"
    ]

    issues = validate_platform_state(document)

    assert "missing Platform service roles: runtime-provider" in issues


def test_transport_failures_stay_distinct_from_contract_failures() -> None:
    def failed_transport(path: str) -> dict[str, object]:
        raise ConformanceTransportError(f"network failure for {path}")

    report = RuntimeV2ConformanceSuite(failed_transport).run(
        platform=True, runtime=False
    )

    assert not report.passed
    assert len(report.issues) == 5
    assert all("network failure" in issue.message for issue in report.issues)


def test_runtime_contract_reports_duplicate_owner_values() -> None:
    documents = _documents()
    documents["/runtime/capabilities"]["capabilities"] = [
        "services:list",
        "services:list",
    ]
    documents["/runtime/services"]["services"] = ["app", "app"]

    report = RuntimeV2ConformanceSuite(lambda path: documents[path]).run(
        platform=False, runtime=True
    )

    assert not report.passed
    assert {issue.resource for issue in report.issues} == {
        "/runtime/capabilities",
        "/runtime/services",
    }


def test_portable_platform_agent_passes_live_platform_and_runtime_conformance(
    tmp_path: Path,
) -> None:
    go = shutil.which("go")
    assert go is not None, "Go is required to prove Windows/Linux Platform Agent"
    root = Path(__file__).resolve().parents[4]
    agent_root = root / "apps/vitalserver-platform-agent"
    binary = tmp_path / "vitalserver-platform-agent"
    subprocess.run(
        [go, "build", "-mod=vendor", "-trimpath", "-o", str(binary), "./cmd/vitalserver-platform-agent"],
        cwd=agent_root,
        check=True,
    )

    runtime_server = ThreadingHTTPServer(("127.0.0.1", 0), _RuntimeControllerHandler)
    runtime_thread = Thread(target=runtime_server.serve_forever, daemon=True)
    runtime_thread.start()
    runtime_port = runtime_server.server_address[1]

    state = tmp_path / "state"
    state.mkdir()
    runtime_executable = state / "runtime-provider"
    runtime_executable.write_text("runtime", encoding="utf-8")
    runtime_executable.chmod(0o755)
    (state / "runtime-endpoint.json").write_text(
        json.dumps(
            {"address": "127.0.0.1", "source": "platform-agent", "state": "loaded"}
        ),
        encoding="utf-8",
    )
    (state / "runtime-provider.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "state": "running",
                "operation": None,
                "operationID": None,
                "bootID": None,
                "startedAt": "2026-07-11T00:00:00Z",
                "updatedAt": "2026-07-11T00:00:00Z",
                "deadlineAt": None,
                "terminalReason": None,
                "message": None,
            }
        ),
        encoding="utf-8",
    )
    listen_port = _unused_port()
    config = tmp_path / "platform-agent.json"
    config.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "listenAddress": f"127.0.0.1:{listen_port}",
                "apiToken": "test-token",
                "runtimeExecutable": str(runtime_executable),
                "runtimeEndpointDocument": str(state / "runtime-endpoint.json"),
                "runtimeProviderDocument": str(state / "runtime-provider.json"),
                "operationLeaseDocument": str(state / "operation-lease.json"),
                "runtimeControllerPort": runtime_port,
                "pwaDirectory": "",
                "platformServices": {
                    role: None for role in PLATFORM_SERVICE_ROLES
                },
            }
        ),
        encoding="utf-8",
    )

    process = subprocess.Popen(
        [str(binary), "--config", str(config)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        getter = http_json_getter(
            base_url=f"http://127.0.0.1:{listen_port}",
            timeout_seconds=2,
            bearer_token="test-token",
        )
        for _ in range(100):
            try:
                getter("/platform/capabilities")
                break
            except ConformanceTransportError:
                if process.poll() is not None:
                    stdout, stderr = process.communicate()
                    raise AssertionError(
                        f"Platform Agent exited early stdout={stdout} stderr={stderr}"
                    )
                time.sleep(0.02)
        else:
            raise AssertionError("Platform Agent did not become reachable")

        report = RuntimeV2ConformanceSuite(getter).run()
        assert report.passed, report.issues
    finally:
        process.terminate()
        process.wait(timeout=5)
        runtime_server.shutdown()
        runtime_server.server_close()
        runtime_thread.join(timeout=5)


class _RuntimeControllerHandler(BaseHTTPRequestHandler):
    documents = {
        "/runtime/capabilities": {
            "schemaVersion": 1,
            "capabilities": ["services:list", "stack:status"],
        },
        "/runtime/services": {"services": ["app", "redis"]},
        "/runtime/stack": {
            "state": "ready",
            "observedAt": "2026-07-11T00:00:00Z",
            "services": [
                {
                    "service": "app",
                    "state": "running",
                    "health": "healthy",
                    "observedAt": "2026-07-11T00:00:00Z",
                }
            ],
            "probeErrors": [],
        },
    }

    def do_GET(self) -> None:
        document = self.documents.get(self.path)
        if document is None:
            self.send_error(404)
            return
        data = json.dumps(document).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: object) -> None:
        return


def _unused_port() -> int:
    server = ThreadingHTTPServer(("127.0.0.1", 0), BaseHTTPRequestHandler)
    try:
        return int(server.server_address[1])
    finally:
        server.server_close()
