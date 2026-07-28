from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import threading


ROOT = Path(__file__).resolve().parents[4]
ACCEPTANCE = ROOT / "apps/vitalserver-platform-agent/packaging/linux/acceptance-update-rollback-linux.py"


class DeliveryHandler(BaseHTTPRequestHandler):
    install_document: Path | None = None
    operation: dict[str, object] | None = None

    def do_GET(self) -> None:  # noqa: N802
        if self.headers.get("Authorization") != "Bearer acceptance-token":
            self._write(401, {})
            return
        if self.path == "/platform/capabilities":
            self._write(200, {"canApplyBundle": True, "canRollbackRelease": True})
            return
        if self.path == "/platform/workflows/current":
            self._write(200, {"state": "loaded", "operation": self.operation, "readError": None})
            return
        self._write(404, {})

    def do_POST(self) -> None:  # noqa: N802
        if self.headers.get("Authorization") != "Bearer acceptance-token":
            self._write(401, {})
            return
        if self.path == "/platform/update-bundles/apply":
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            assert Path(body["bundle"]["value"]).is_absolute()
            type(self).operation = _operation("update-1", "update-apply", "completed", "2.0.0", "2.3.4")
            self._write_install("2.0.0", "2.3.4", "releases/1.0.0")
            accepted = dict(self.operation)
            accepted["state"] = "accepted"
            accepted["release"] = None
            self._write(202, accepted)
            return
        if self.path == "/platform/releases/rollback":
            type(self).operation = _operation("rollback-1", "rollback", "completed", "1.0.0", "1.2.0")
            self._write_install("1.0.0", "1.2.0", "releases/2.0.0")
            accepted = dict(self.operation)
            accepted["state"] = "accepted"
            accepted["release"] = None
            self._write(202, accepted)
            return
        self._write(404, {})

    def _write_install(self, platform_version: str, runtime_version: str, previous: str) -> None:
        assert self.install_document is not None
        self.install_document.write_text(json.dumps({
            "schemaVersion": 1,
            "state": "installed",
            "platformVersion": platform_version,
            "runtimeBundleVersion": runtime_version,
            "previousRelease": previous,
        }), encoding="utf-8")

    def _write(self, status: int, document: dict[str, object]) -> None:
        body = json.dumps(document).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def test_linux_update_rollback_acceptance_proves_version_and_data_round_trip(tmp_path: Path) -> None:
    token = tmp_path / "token"
    token.write_text("acceptance-token\n", encoding="utf-8")
    install = tmp_path / "install.json"
    install.write_text(json.dumps({
        "schemaVersion": 1,
        "state": "installed",
        "platformVersion": "1.0.0",
        "runtimeBundleVersion": "1.2.0",
        "previousRelease": None,
    }), encoding="utf-8")
    bundle = tmp_path / "update.tar.gz"
    bundle.write_bytes(b"bundle")
    data = tmp_path / "data"
    data.mkdir()
    sentinel = data / ".acceptance-sentinel"
    output = tmp_path / "update-rollback-acceptance.json"
    DeliveryHandler.install_document = install
    DeliveryHandler.operation = None
    server = ThreadingHTTPServer(("127.0.0.1", 0), DeliveryHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run([
            sys.executable,
            str(ACCEPTANCE),
            "--api-token-path", str(token),
            "--install-document", str(install),
            "--update-bundle", str(bundle),
            "--expected-update-platform-version", "2.0.0",
            "--expected-update-runtime-bundle-version", "2.3.4",
            "--data-sentinel", str(sentinel),
            "--output-manifest", str(output),
            "--base-url", f"http://127.0.0.1:{server.server_port}",
            "--timeout-seconds", "2",
        ], check=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    proof = json.loads(output.read_text(encoding="utf-8"))
    assert proof["status"] == "passed"
    assert proof["kind"] == "update-rollback-data-preservation"
    assert {stage["name"] for stage in proof["stages"]} == {
        "preflight",
        "data-sentinel-created",
        "update-accepted",
        "update-completed",
        "update-data-preserved",
        "rollback-accepted",
        "rollback-completed",
        "rollback-data-preserved",
    }
    assert not sentinel.exists()


def _operation(
    operation_id: str,
    kind: str,
    state: str,
    platform_version: str,
    runtime_version: str,
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "operationId": operation_id,
        "kind": kind,
        "state": state,
        "startedAt": "2026-07-11T00:00:00Z",
        "updatedAt": "2026-07-11T00:00:01Z",
        "release": {
            "platformVersion": platform_version,
            "runtimeBundleVersion": runtime_version,
        },
        "artifact": None,
        "failure": None,
    }
