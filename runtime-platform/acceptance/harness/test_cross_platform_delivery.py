"""Black-box proof for selected Windows/Linux provider bridge semantics.

The bridge executable is deliberately a portable deterministic fixture. It
proves Host's C21 composition, request-id/revision idempotency, and no-fallback
behavior. It does not claim that Hyper-V or libvirt executed on this macOS
workspace; those facts remain C24 clean-host proof stages.
"""

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

from tooling.contracts import ContractRepository


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


def wait_for_endpoint(url: str, process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr else ""
            raise AssertionError(f"Host Agent exited early ({process.returncode}): {stderr}")
        try:
            status, body = request_json(url)
            if status == 200 and json.loads(body)["state"] == "available":
                return
        except (OSError, json.JSONDecodeError, KeyError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"Host Agent did not become reachable: {url}")


def wait_for_file(path: Path, process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr else ""
            raise AssertionError(f"Host Agent exited before publishing {path.name} ({process.returncode}): {stderr}")
        if path.is_file():
            return
        time.sleep(0.05)
    raise AssertionError(f"Host Agent did not publish {path}")


class CrossPlatformDeliveryAcceptance(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.work = Path(self.temporary_directory.name)
        self.host_binary = self.work / "host-agent"
        self.platformctl_binary = self.work / "platformctl"
        build = subprocess.run(
            [GO, "build", "-o", str(self.host_binary), "./cmd/host-agent"],
            cwd=ROOT / "services" / "host-agent",
            capture_output=True,
            text=True,
            check=False,
        )
        if build.returncode != 0:
            raise AssertionError(f"build Host Agent failed:\n{build.stdout}\n{build.stderr}")
        build = subprocess.run(
            [GO, "build", "-o", str(self.platformctl_binary), "./cmd/platformctl"],
            cwd=ROOT / "interfaces" / "platformctl",
            capture_output=True,
            text=True,
            check=False,
        )
        if build.returncode != 0:
            raise AssertionError(f"build platformctl failed:\n{build.stdout}\n{build.stderr}")
        self.bridge_log = self.work / "bridge-invocations.jsonl"
        self.bridge = self.work / "provider-bridge-fixture.py"
        self.bridge.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "invocation = json.load(sys.stdin)\n"
            "with open(os.environ['RUNTIME_PLATFORM_BRIDGE_LOG'], 'a', encoding='utf-8') as handle:\n"
            "    handle.write(json.dumps(invocation, separators=(',', ':')) + '\\n')\n"
            "lifecycle = invocation['lifecycle']\n"
            "outcome = os.environ.get('RUNTIME_PLATFORM_BRIDGE_OUTCOME', 'running')\n"
            "if lifecycle['action'] == 'stop' and outcome == 'running':\n"
            "    outcome = 'stopped'\n"
            "result = {'schemaVersion':'v1','requestId':lifecycle['requestId'],'providerId':lifecycle['providerId'],'observedState':outcome,'observedAt':'2026-07-17T00:00:00Z'}\n"
            "if outcome in ('unavailable', 'failed'):\n"
            "    result['issue'] = {'code':'fixture-provider-' + outcome,'dependency':invocation['providerKind']}\n"
            "print(json.dumps(result, separators=(',', ':')))\n",
            encoding="utf-8",
        )
        self.bridge.chmod(0o755)
        self.host_process: subprocess.Popen[str] | None = None

    def tearDown(self) -> None:
        if self.host_process is not None:
            if self.host_process.poll() is None:
                self.host_process.terminate()
                try:
                    self.host_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.host_process.kill()
                    self.host_process.wait(timeout=5)
            if self.host_process.stdout is not None:
                self.host_process.stdout.close()
            if self.host_process.stderr is not None:
                self.host_process.stderr.close()
        self.temporary_directory.cleanup()

    def start_host(self, provider_kind: str, outcome: str = "running") -> str:
        port = free_port()
        deployment_configuration = self.write_host_deployment_configuration(provider_kind, port)
        environment = dict(os.environ)
        environment["RUNTIME_PLATFORM_BRIDGE_LOG"] = str(self.bridge_log)
        environment["RUNTIME_PLATFORM_BRIDGE_OUTCOME"] = outcome
        self.host_process = subprocess.Popen(
            [
                str(self.host_binary),
                "--deployment-configuration", str(deployment_configuration),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        base_url = f"http://127.0.0.1:{port}"
        wait_for_file(self.work / "host-agent.local.json", self.host_process)
        wait_for_endpoint(base_url + "/v1/platform/guest-runtime-control-endpoint", self.host_process)
        return base_url

    def write_host_deployment_configuration(self, provider_kind: str, port: int) -> Path:
        configuration = {
            "schemaVersion": "v1",
            "control": {
                "localAdministration": {
                    "transport": "unix-domain-socket",
                    "endpointAddress": str(self.work / "host-agent.sock"),
                    "descriptorPath": str(self.work / "host-agent.local.json"),
                    "authorizedUserId": os.geteuid(),
                },
                "loopbackHTTP": {"mode": "development-loopback", "listenAddress": f"127.0.0.1:{port}"},
                "stateDatabasePath": str(self.work / "host.sqlite"),
                "guestTimeoutMilliseconds": 5000,
            },
            "installation": {
                "installationId": "host-installation",
                "productVersion": "acceptance",
                "runtimeVersion": "acceptance",
                "dataDirectory": str(self.work / "data"),
            },
            "guestRuntimeControlEndpoint": {"id": "guest-control", "scheme": "http", "host": "127.0.0.1", "port": 18443},
            "provider": {
                "kind": provider_kind,
                "id": "guest-vm",
                "nativeProviderBridgeExecutablePath": str(self.bridge),
                "nativeVirtualMachineName": "guest-vm",
                "hostServiceName": "vitalserver-host-agent",
                "nativeGuestMachineOwnership": "externally-provisioned",
            },
            "time": {"hostNodeId": "acceptance-host", "timeAuthorityId": "acceptance-time", "kind": "time-authority-outcome-profile", "providerMode": "unsupported"},
            "telemetry": {"kind": "telemetry-export-outcome-profile", "pipelineMode": "unsupported", "exportMode": "unavailable"},
            "updateBootstrap": {"mode": "unavailable"},
        }
        path = self.work / "host-agent-deployment.json"
        path.write_text(json.dumps(configuration), encoding="utf-8")
        return path

    @staticmethod
    def lifecycle(base_url: str, request_id: str, revision: int, action: str = "start") -> tuple[int, dict]:
        status, body = request_json(
            base_url + f"/v1/platform/guest:{action}",
            method="POST",
            payload={
                "schemaVersion": "v1",
                "requestId": request_id,
                "guestRuntimeControlEndpointId": "guest-control",
                "expectedResourceRevision": revision,
                "action": action,
            },
        )
        return status, json.loads(body)

    def bridge_invocations(self) -> list[dict]:
        if not self.bridge_log.exists():
            return []
        return [json.loads(line) for line in self.bridge_log.read_text(encoding="utf-8").splitlines() if line]

    def test_windows_selected_provider_preserves_request_revision_idempotency(self) -> None:
        base_url = self.start_host("windows-hyperv-scm")
        status, body = request_json(base_url + "/v1/platform/guest-runtime-control-endpoint")
        self.assertEqual(200, status, body)
        endpoint = json.loads(body)["value"]
        self.assertEqual("windows-hyperv-scm", endpoint["provider"]["kind"])

        status, operation = self.lifecycle(base_url, "windows-start-1", endpoint["resourceRevision"])
        self.assertEqual(202, status, operation)
        self.assertEqual("succeeded", operation["state"])
        status, replay = self.lifecycle(base_url, "windows-start-1", endpoint["resourceRevision"])
        self.assertEqual(202, status, replay)
        self.assertEqual(operation["id"], replay["id"])

        invocations = self.bridge_invocations()
        self.assertEqual(1, len(invocations), invocations)
        self.assertEqual("windows-hyperv-scm", invocations[0]["providerKind"])
        self.assertEqual("windows-start-1", invocations[0]["requestId"])
        self.assertEqual(endpoint["resourceRevision"], invocations[0]["expectedGuestRuntimeControlEndpointRevision"])
        self.assertEqual(invocations[0]["requestId"], invocations[0]["lifecycle"]["requestId"])

        status, rejection = self.lifecycle(base_url, "windows-start-1", endpoint["resourceRevision"] + 1, action="stop")
        self.assertEqual(400, status, rejection)
        self.assertEqual("request-id-reused-with-different-command", rejection["issue"]["code"])
        status, rejection = self.lifecycle(base_url, "windows-stale-1", endpoint["resourceRevision"])
        self.assertEqual(400, status, rejection)
        self.assertEqual("resource-revision-conflict", rejection["issue"]["code"])
        self.assertEqual(1, len(self.bridge_invocations()))

    def test_linux_unavailable_outcome_is_not_retried_as_another_provider(self) -> None:
        base_url = self.start_host("linux-kvm-libvirt-systemd", outcome="unavailable")
        status, body = request_json(base_url + "/v1/platform/guest-runtime-control-endpoint")
        self.assertEqual(200, status, body)
        endpoint = json.loads(body)["value"]
        status, operation = self.lifecycle(base_url, "linux-start-1", endpoint["resourceRevision"])
        self.assertEqual(202, status, operation)
        self.assertEqual("failed", operation["state"])
        self.assertEqual("fixture-provider-unavailable", operation["failure"]["code"])
        invocations = self.bridge_invocations()
        self.assertEqual(1, len(invocations), invocations)
        self.assertEqual("linux-kvm-libvirt-systemd", invocations[0]["providerKind"])

        status, body = request_json(base_url + "/v1/platform/guest-runtime-control-endpoint")
        self.assertEqual(200, status, body)
        updated = json.loads(body)["value"]
        self.assertEqual("unavailable", updated["provider"]["state"])
        self.assertEqual("unavailable", updated["transport"]["state"])

    def test_unknown_provider_kind_fails_before_host_configuration(self) -> None:
        deployment_configuration = self.write_host_deployment_configuration("unconfigured-native-provider", free_port())
        completed = subprocess.run(
            [
                str(self.host_binary),
                "--deployment-configuration", str(deployment_configuration),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("deployment configuration is invalid", completed.stderr)
        self.assertFalse((self.work / "host.sqlite").exists())

    def test_host_local_administration_descriptor_drives_platformctl_without_a_tcp_endpoint(self) -> None:
        self.start_host("linux-kvm-libvirt-systemd")
        descriptor_path = self.work / "host-agent.local.json"
        descriptor = json.loads(descriptor_path.read_text(encoding="utf-8"))
        self.assertEqual(
            {
                "schemaVersion": "v1",
                "transport": "unix-domain-socket",
                "address": str(self.work / "host-agent.sock"),
            },
            descriptor,
        )
        invocation = subprocess.run(
            [str(self.platformctl_binary), "--local-control-descriptor", str(descriptor_path), "installation"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, invocation.returncode, invocation.stderr)
        response = json.loads(invocation.stdout)
        self.assertEqual(200, response["httpStatus"])
        self.assertEqual("available", response["document"]["state"])

        assert self.host_process is not None
        self.host_process.terminate()
        self.host_process.wait(timeout=5)
        if self.host_process.stdout is not None:
            self.host_process.stdout.close()
        if self.host_process.stderr is not None:
            self.host_process.stderr.close()
        self.host_process = None
        self.assertFalse(descriptor_path.exists(), "Host Agent left a stale C52 descriptor after shutdown")

    def test_windows_and_linux_bridge_evidence_is_c22_valid_when_wrong_os_is_explicit(self) -> None:
        repository = ContractRepository(ROOT)
        repository.load()
        provider_root = ROOT / "providers" / "os-provider-bridge"
        for provider_kind, command in (
            ("windows-hyperv-scm", "./cmd/windows-hyperv-scm-bridge"),
            ("linux-kvm-libvirt-systemd", "./cmd/linux-kvm-libvirt-systemd-bridge"),
        ):
            binary = self.work / provider_kind
            build = subprocess.run(
                [GO, "build", "-o", str(binary), command],
                cwd=provider_root,
                capture_output=True,
                text=True,
                check=False,
            )
            if build.returncode != 0:
                raise AssertionError(f"build {provider_kind} bridge failed:\n{build.stdout}\n{build.stderr}")
            output = subprocess.run(
                [str(binary), "--mode", "evidence", "--provider-id", "guest-vm", "--vm-name", "guest-a", "--service-name", "vitalserver-host-agent"],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(0, output.returncode, output.stderr)
            evidence = json.loads(output.stdout)
            self.assertEqual([], repository.validate_instance("provider-installation-evidence.schema.json", evidence))
            self.assertEqual(provider_kind, evidence["providerKind"])
            self.assertEqual("macos", evidence["hostPlatform"])
            self.assertEqual("unavailable", evidence["installation"]["state"])
            self.assertEqual(provider_kind + "-host-platform-mismatch", evidence["installation"]["issue"]["code"])


if __name__ == "__main__":
    unittest.main()
