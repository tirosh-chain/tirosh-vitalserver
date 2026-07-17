"""Black-box Host/Guest control proof using only public HTTP contracts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request

from acceptance.harness.guest_runtime_control_http_acceptance_fixture_arguments import (
    compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments,
)


ROOT = Path(__file__).resolve().parents[2]
GO = os.environ.get("RUNTIME_PLATFORM_GO", "go")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def request_json(url: str, method: str = "GET", payload: dict | None = None) -> tuple[int, bytes]:
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def wait_for_ready(url: str, process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr else ""
            raise AssertionError(f"process exited early ({process.returncode}): {stderr}")
        try:
            status, body = request_json(url)
            if status == 200 and json.loads(body)["state"] in {"available", "failed"}:
                return
        except (OSError, json.JSONDecodeError, KeyError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"service did not become reachable: {url}")


class HostGuestControlAcceptance(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.work = Path(self.temporary_directory.name)
        self.guest_port = free_port()
        self.host_port = free_port()
        self.guest_runtime_control_http_acceptance_fixture_binary = self.work / "guest-runtime-control-http-acceptance-fixture"
        self.host_binary = self.work / "acceptance-host-agent"
        self._build(
            "services/guest-runtime",
            "./cmd/guest-runtime-control-http-acceptance-fixture",
            self.guest_runtime_control_http_acceptance_fixture_binary,
        )
        self._build("services/host-agent", "./cmd/acceptance-host-agent", self.host_binary)
        self.guest_process = subprocess.Popen(
            [
                str(self.guest_runtime_control_http_acceptance_fixture_binary),
                *compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
                    listen_address=f"127.0.0.1:{self.guest_port}", state_database_path=str(self.work / "guest.sqlite"), service_version="acceptance", instance_id="guest-acceptance",
                    archive_export_outcome_mode="succeed", external_upstream_outcome_mode="unsupported", outbound_relay_outcome_mode="unsupported",
                    guest_node_id="guest-acceptance", time_authority_id="guest-time-acceptance", time_probe_outcome_mode="unsupported",
                    telemetry_collector_probe_outcome_mode="unsupported", telemetry_export_outcome_mode="unavailable",
                ),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.guest_url = f"http://127.0.0.1:{self.guest_port}"
        wait_for_ready(self.guest_url + "/v1/runtime/readiness", self.guest_process)
        self.host_process = subprocess.Popen(
            [
                str(self.host_binary),
                "--listen", f"127.0.0.1:{self.host_port}",
                "--state-db", str(self.work / "host.sqlite"),
                "--installation-id", "host-installation",
                "--product-version", "acceptance",
                "--runtime-version", "acceptance",
                "--data-directory", str(self.work / "data"),
                "--guest-runtime-control-endpoint-id", "guest-control",
                "--guest-runtime-control-http-scheme", "http",
                "--guest-runtime-control-http-host", "127.0.0.1",
                "--guest-runtime-control-http-port", str(self.guest_port),
                "--provider-kind", "linux-kvm-libvirt-systemd",
                "--provider-id", "guest-vm",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.host_url = f"http://127.0.0.1:{self.host_port}"
        wait_for_ready(self.host_url + "/v1/platform/guest-runtime-control-endpoint", self.host_process)

    def tearDown(self) -> None:
        for process in (getattr(self, "host_process", None), getattr(self, "guest_process", None)):
            if process is None:
                continue
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            if process.stdout is not None:
                process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()
        self.temporary_directory.cleanup()

    def _build(self, relative_directory: str, package: str, output: Path) -> None:
        completed = subprocess.run(
            [GO, "build", "-o", str(output), package],
            cwd=ROOT / relative_directory,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(f"build {package} failed:\n{completed.stdout}\n{completed.stderr}")

    def get_host_endpoint(self) -> dict:
        status, body = request_json(self.host_url + "/v1/platform/guest-runtime-control-endpoint")
        self.assertEqual(200, status, body)
        result = json.loads(body)
        self.assertEqual("available", result["state"], result)
        return result["value"]

    def lifecycle(self, action: str, request_id: str, revision: int) -> dict:
        status, body = request_json(
            self.host_url + f"/v1/platform/guest:{action}",
            method="POST",
            payload={
                "schemaVersion": "v1",
                "requestId": request_id,
                "guestRuntimeControlEndpointId": "guest-control",
                "expectedResourceRevision": revision,
                "action": action,
            },
        )
        self.assertEqual(202, status, body)
        operation = json.loads(body)
        self.assertEqual("succeeded", operation["state"], operation)
        return operation

    def test_lifecycle_facade_and_guest_topology_ownership(self) -> None:
        endpoint = self.get_host_endpoint()
        self.assertEqual("not-observed", endpoint["provider"]["state"])
        self.assertEqual("not-checked", endpoint["transport"]["state"])

        self.lifecycle("start", "host-start-1", endpoint["resourceRevision"])
        endpoint = self.get_host_endpoint()
        self.assertEqual("running", endpoint["provider"]["state"])
        self.assertEqual("not-checked", endpoint["transport"]["state"])

        guest_status, guest_body = request_json(self.guest_url + "/v1/runtime/readiness")
        host_status, host_body = request_json(self.host_url + "/v1/runtime/readiness")
        self.assertEqual(200, guest_status, guest_body)
        self.assertEqual(200, host_status, host_body)
        self.assertEqual("available", json.loads(host_body)["state"])
        endpoint = self.get_host_endpoint()
        self.assertEqual("reachable", endpoint["transport"]["state"])

        external_integration_command = {
            "schemaVersion": "v1",
            "requestId": "external-integration-apply-1",
            "integrationId": "external-primary",
            "expectedResourceRevision": 0,
            "spec": {
                "provider": {
                    "kind": "external-capability-profile",
                    "id": "external-upstream",
                    "capabilityRevision": 1,
                },
                "endpointReference": {"resourceType": "external-vitalserver-endpoint", "resourceId": "primary"},
            },
        }
        status, body = request_json(self.host_url + "/v1/runtime/external-upstreams", method="POST", payload=external_integration_command)
        self.assertEqual(202, status, body)
        self.assertEqual("succeeded", json.loads(body)["state"])

        topology_command = {
            "schemaVersion": "v1",
            "requestId": "topology-apply-1",
            "topologyId": "primary-topology",
            "expectedResourceRevision": 0,
            "spec": {
                "profileKind": "external-upstream",
                "providerKind": "vitalserver",
                "endpointReference": {"resourceType": "external-upstream-integration", "resourceId": "external-primary"},
            },
        }
        status, body = request_json(self.host_url + "/v1/runtime/topology:apply", method="POST", payload=topology_command)
        self.assertEqual(202, status, body)
        self.assertEqual("succeeded", json.loads(body)["state"])
        status, body = request_json(self.host_url + "/v1/runtime/topology")
        self.assertEqual(200, status, body)
        topology = json.loads(body)["value"]
        self.assertEqual("unsupported", topology["status"]["readState"])
        self.assertEqual("not-checked", topology["status"]["connection"]["state"])

        endpoint = self.get_host_endpoint()
        self.lifecycle("stop", "host-stop-1", endpoint["resourceRevision"])
        status, body = request_json(self.host_url + "/v1/runtime/readiness")
        self.assertEqual(200, status, body)
        unavailable = json.loads(body)
        self.assertEqual("unavailable", unavailable["state"])
        self.assertEqual("guest-provider-stopped", unavailable["issue"]["code"])
        direct_status, direct_body = request_json(self.guest_url + "/v1/runtime/readiness")
        self.assertEqual(200, direct_status, direct_body)
        self.assertEqual("available", json.loads(direct_body)["state"])

        stopped_endpoint = self.get_host_endpoint()
        rejected_command = dict(topology_command)
        rejected_command["requestId"] = "topology-while-stopped"
        rejected_command["expectedResourceRevision"] = 1
        status, body = request_json(self.host_url + "/v1/runtime/topology:apply", method="POST", payload=rejected_command)
        self.assertEqual(503, status, body)
        self.assertEqual("rejected", json.loads(body)["state"])

        self.lifecycle("reboot", "host-reboot-1", stopped_endpoint["resourceRevision"])
        status, body = request_json(self.host_url + "/v1/runtime/readiness")
        self.assertEqual(200, status, body)
        self.assertEqual("available", json.loads(body)["state"])

        malformed = dict(topology_command)
        malformed["requestId"] = "topology-invalid-1"
        malformed["unexpected"] = True
        status, body = request_json(self.host_url + "/v1/runtime/topology:apply", method="POST", payload=malformed)
        self.assertEqual(400, status, body)
        rejection = json.loads(body)
        self.assertEqual("rejected", rejection["state"])
        self.assertEqual("invalid-command-envelope", rejection["issue"]["code"])


if __name__ == "__main__":
    unittest.main()
