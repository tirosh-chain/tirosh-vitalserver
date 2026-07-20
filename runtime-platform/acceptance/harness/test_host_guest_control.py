"""Black-box Host/Guest control proof using only public HTTP contracts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
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
        try:
            return error.code, error.read()
        finally:
            error.close()


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
        self.platformctl_binary = self.work / "platformctl"
        self._build(
            "services/guest-runtime",
            "./cmd/guest-runtime-control-http-acceptance-fixture",
            self.guest_runtime_control_http_acceptance_fixture_binary,
        )
        self._build("services/host-agent", "./cmd/acceptance-host-agent", self.host_binary)
        self._build("interfaces/platformctl", "./cmd/platformctl", self.platformctl_binary)
        self.guest_process = subprocess.Popen(
            [
                str(self.guest_runtime_control_http_acceptance_fixture_binary),
                *self.guest_fixture_arguments(),
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

    def guest_fixture_arguments(self) -> list[str]:
        return compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
            listen_address=f"127.0.0.1:{self.guest_port}", state_database_path=str(self.work / "guest.sqlite"), service_version="acceptance", instance_id="guest-acceptance",
            archive_export_outcome_mode="succeed", recorder_gateway_cold_path_source_endpoint="http://127.0.0.1:8090", lab_recorder_runner_endpoint="http://127.0.0.1:8091", external_upstream_outcome_mode="unsupported", outbound_relay_outcome_mode="unsupported",
            guest_node_id="guest-acceptance", time_authority_id="guest-time-acceptance", time_probe_outcome_mode="unsupported",
            telemetry_collector_probe_outcome_mode="unsupported", telemetry_export_outcome_mode="unavailable",
        )

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

    def platformctl(self, *arguments: str, standard_input: str | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.platformctl_binary), "--control-endpoint", self.host_url, *arguments],
            input=standard_input,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_platformctl_uses_the_public_host_facade_without_state_discovery(self) -> None:
        endpoint_read = self.platformctl("guest-runtime-control-endpoint")
        self.assertEqual(0, endpoint_read.returncode, endpoint_read.stderr)
        endpoint_response = json.loads(endpoint_read.stdout)
        self.assertEqual(200, endpoint_response["httpStatus"], endpoint_response)
        endpoint = endpoint_response["document"]
        self.assertEqual("available", endpoint["state"], endpoint)
        configured_endpoint = endpoint["value"]

        start = self.platformctl(
            "guest",
            "start",
            "--request-id",
            "platformctl-host-start-1",
            "--guest-runtime-control-endpoint-id",
            configured_endpoint["id"],
            "--expected-resource-revision",
            str(configured_endpoint["resourceRevision"]),
        )
        self.assertEqual(0, start.returncode, start.stderr)
        start_response = json.loads(start.stdout)
        self.assertEqual(202, start_response["httpStatus"], start_response)
        self.assertEqual("succeeded", start_response["document"]["state"], start_response)

        readiness = self.platformctl("runtime", "readiness")
        self.assertEqual(0, readiness.returncode, readiness.stderr)
        readiness_response = json.loads(readiness.stdout)
        self.assertEqual(200, readiness_response["httpStatus"], readiness_response)
        self.assertEqual("available", readiness_response["document"]["state"], readiness_response)

        archive_provider = self.platformctl("runtime", "archive-export-provider")
        self.assertEqual(0, archive_provider.returncode, archive_provider.stderr)
        archive_provider_response = json.loads(archive_provider.stdout)
        self.assertEqual(200, archive_provider_response["httpStatus"], archive_provider_response)
        archive_provider_document = archive_provider_response["document"]
        self.assertEqual("available", archive_provider_document["state"], archive_provider_document)
        self.assertEqual(
            {"kind": "archive-export-outcome-profile", "id": "bundled-archive", "capabilityRevision": 1},
            archive_provider_document["value"]["provider"],
        )
        self.assertNotIn("artifactManifestReference", archive_provider_document["value"])
        self.assertNotIn("upload", archive_provider_document["value"])
        self.assertNotIn("indexing", archive_provider_document["value"])

        host_time = self.platformctl(
            "time", "apply",
            "--scope", "host",
            "--request-id", "platformctl-host-time-apply-1",
            "--authority-id", "acceptance-host-time",
            "--expected-resource-revision", "0",
            "--node-kind", "host",
            "--node-id", "host-agent",
            "--profile", "enterprise-ntp",
            "--source-profile", "enterprise-ntp",
            "--source-id", "hospital-ntp-primary",
        )
        self.assertEqual(0, host_time.returncode, host_time.stderr)
        host_time_response = json.loads(host_time.stdout)
        self.assertEqual(202, host_time_response["httpStatus"], host_time_response)
        self.assertEqual("succeeded", host_time_response["document"]["state"], host_time_response)
        guest_time = self.platformctl(
            "time", "apply",
            "--scope", "guest",
            "--request-id", "platformctl-guest-time-apply-1",
            "--authority-id", "acceptance-guest-time",
            "--expected-resource-revision", "0",
            "--node-kind", "guest",
            "--node-id", "guest-acceptance",
            "--profile", "enterprise-ntp",
            "--source-profile", "enterprise-ntp",
            "--source-id", "hospital-ntp-primary",
        )
        self.assertEqual(0, guest_time.returncode, guest_time.stderr)
        guest_time_response = json.loads(guest_time.stdout)
        self.assertEqual(202, guest_time_response["httpStatus"], guest_time_response)
        self.assertEqual("succeeded", guest_time_response["document"]["state"], guest_time_response)

        host_telemetry = self.platformctl(
            "telemetry", "apply",
            "--scope", "host",
            "--request-id", "platformctl-host-telemetry-apply-1",
            "--pipeline-id", "acceptance-host-telemetry",
            "--expected-resource-revision", "0",
            "--node-kind", "host",
            "--node-id", "host-agent",
            "--collector-resource-type", "otel-collector",
            "--collector-resource-id", "acceptance-collector",
            "--allowed-attribute-keys", "operation.kind,outcome.code",
            "--max-attributes", "8",
            "--max-value-length", "128",
            "--max-distinct-values-per-key", "32",
        )
        self.assertEqual(0, host_telemetry.returncode, host_telemetry.stderr)
        host_telemetry_response = json.loads(host_telemetry.stdout)
        self.assertEqual(202, host_telemetry_response["httpStatus"], host_telemetry_response)
        self.assertEqual("succeeded", host_telemetry_response["document"]["state"], host_telemetry_response)
        guest_telemetry = self.platformctl(
            "telemetry", "apply",
            "--scope", "guest",
            "--request-id", "platformctl-guest-telemetry-apply-1",
            "--pipeline-id", "acceptance-guest-telemetry",
            "--expected-resource-revision", "0",
            "--node-kind", "guest",
            "--node-id", "guest-acceptance",
            "--collector-resource-type", "otel-collector",
            "--collector-resource-id", "acceptance-collector",
            "--allowed-attribute-keys", "operation.kind,outcome.code",
            "--max-attributes", "8",
            "--max-value-length", "128",
            "--max-distinct-values-per-key", "32",
        )
        self.assertEqual(0, guest_telemetry.returncode, guest_telemetry.stderr)
        guest_telemetry_response = json.loads(guest_telemetry.stdout)
        self.assertEqual(202, guest_telemetry_response["httpStatus"], guest_telemetry_response)
        self.assertEqual("succeeded", guest_telemetry_response["document"]["state"], guest_telemetry_response)

        created = self.platformctl(
            "lab", "create",
            "--request-id", "platformctl-lab-create-1",
            "--session-id", "platformctl-lab-session-1",
            "--name", "baseline-monitoring",
            "--scenario", "baseline-monitoring",
            "--recorder-count", "1",
        )
        self.assertEqual(0, created.returncode, created.stderr)
        created_response = json.loads(created.stdout)
        self.assertEqual(202, created_response["httpStatus"], created_response)
        self.assertEqual("succeeded", created_response["document"]["state"], created_response)
        lab_beds = self.platformctl("runtime", "lab-beds")
        self.assertEqual(0, lab_beds.returncode, lab_beds.stderr)
        lab_beds_response = json.loads(lab_beds.stdout)
        self.assertEqual("available", lab_beds_response["document"]["state"], lab_beds_response)
        bed = lab_beds_response["document"]["value"][0]
        hidden = self.platformctl(
            "lab", "resource",
            "--request-id", "platformctl-lab-bed-hide-1",
            "--resource-type", "lab-bed",
            "--resource-id", bed["id"],
            "--expected-resource-revision", str(bed["resourceRevision"]),
            "--action", "hide",
        )
        self.assertEqual(0, hidden.returncode, hidden.stderr)
        hidden_response = json.loads(hidden.stdout)
        self.assertEqual(202, hidden_response["httpStatus"], hidden_response)
        self.assertEqual("succeeded", hidden_response["document"]["state"], hidden_response)

        external = self.platformctl(
            "external-upstream", "apply",
            "--request-id", "platformctl-external-apply-1",
            "--integration-id", "platformctl-external-primary",
            "--expected-resource-revision", "0",
            "--provider-kind", "external-capability-profile",
            "--provider-id", "external-upstream",
            "--provider-capability-revision", "1",
            "--endpoint-resource-type", "external-vitalserver-endpoint",
            "--endpoint-resource-id", "primary",
        )
        self.assertEqual(0, external.returncode, external.stderr)
        external_response = json.loads(external.stdout)
        self.assertEqual(202, external_response["httpStatus"], external_response)
        self.assertEqual("succeeded", external_response["document"]["state"], external_response)
        topology = self.platformctl(
            "topology", "apply",
            "--request-id", "platformctl-topology-apply-1",
            "--topology-id", "platformctl-primary-topology",
            "--expected-resource-revision", "0",
            "--profile-kind", "external-upstream",
            "--endpoint-resource-type", "external-upstream-integration",
            "--endpoint-resource-id", "platformctl-external-primary",
        )
        self.assertEqual(0, topology.returncode, topology.stderr)
        topology_response = json.loads(topology.stdout)
        self.assertEqual(202, topology_response["httpStatus"], topology_response)
        self.assertEqual("succeeded", topology_response["document"]["state"], topology_response)

        stale_start = self.platformctl(
            "guest",
            "start",
            "--request-id",
            "platformctl-host-start-stale-1",
            "--guest-runtime-control-endpoint-id",
            configured_endpoint["id"],
            "--expected-resource-revision",
            str(configured_endpoint["resourceRevision"]),
        )
        self.assertNotEqual(0, stale_start.returncode)
        stale_response = json.loads(stale_start.stdout)
        self.assertEqual(400, stale_response["httpStatus"], stale_response)
        self.assertEqual("rejected", stale_response["document"]["state"], stale_response)

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


class HostGuestArchiveCredentialMaterialAcceptance(HostGuestControlAcceptance):
    """Proves C51 stays Guest-owned while platformctl uses only the Host facade."""

    # This stack deliberately selects a different Archive provider. Keep the
    # general Host/Guest control proof on its outcome-profile stack; this class
    # contributes only the C51 credential-material proof below.
    test_platformctl_uses_the_public_host_facade_without_state_discovery = None
    test_lifecycle_facade_and_guest_topology_ownership = None

    credential_kind = "vitalserver-library-credential"
    credential_id = "hospital-vitalserver-library"

    def guest_fixture_arguments(self) -> list[str]:
        configuration_path = self.work / "external-vitalserver-delivery-configuration.json"
        shutil.copyfile(
            ROOT / "contracts/examples/v1/valid/external-vitalserver-delivery-configuration.json",
            configuration_path,
        )
        self.credential_material_path = self.work / "guest-private" / "archive-credential.json"
        return compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
            listen_address=f"127.0.0.1:{self.guest_port}", state_database_path=str(self.work / "guest.sqlite"), service_version="acceptance", instance_id="guest-credential-acceptance",
            archive_export_outcome_mode=None, archive_provider_kind="vitalserver-indexed-library", archive_provider_id=self.credential_id,
            archive_provider_vitalserver_configuration_kind="external-vitalserver-delivery-configuration", archive_provider_vitalserver_configuration_path=str(configuration_path), archive_provider_credential_material_path=str(self.credential_material_path),
            recorder_gateway_cold_path_source_endpoint="http://127.0.0.1:8090", lab_recorder_runner_endpoint="http://127.0.0.1:8091", external_upstream_outcome_mode="unsupported", outbound_relay_outcome_mode="unsupported",
            guest_node_id="guest-credential-acceptance", time_authority_id="guest-time-acceptance", time_probe_outcome_mode="unsupported",
            telemetry_collector_probe_outcome_mode="unsupported", telemetry_export_outcome_mode="unavailable",
        )

    def test_platformctl_provisions_archive_credential_through_host_without_secret_exposure(self) -> None:
        before = self.platformctl("archive", "credential-material")
        self.assertEqual(0, before.returncode, before.stderr)
        before_response = json.loads(before.stdout)
        self.assertEqual(200, before_response["httpStatus"], before_response)
        self.assertEqual("missing", before_response["document"]["state"], before_response)
        self.assertEqual(
            {"kind": self.credential_kind, "id": self.credential_id},
            before_response["document"]["credentialReference"],
        )

        password = "acceptance-only-archive-password"
        provision = self.platformctl(
            "archive", "credential-material", "provision",
            "--credential-kind", self.credential_kind,
            "--credential-id", self.credential_id,
            "--user-id", "acceptance-operator",
            "--password-stdin", "true",
            standard_input=f"{password}\n",
        )
        self.assertEqual(0, provision.returncode, provision.stderr)
        provision_response = json.loads(provision.stdout)
        self.assertEqual(200, provision_response["httpStatus"], provision_response)
        self.assertEqual("provisioned", provision_response["document"]["state"], provision_response)
        self.assertNotIn(password, provision.stdout + provision.stderr)
        self.assertNotIn("acceptance-operator", provision.stdout + provision.stderr)

        after = self.platformctl("archive", "credential-material")
        self.assertEqual(0, after.returncode, after.stderr)
        after_response = json.loads(after.stdout)
        self.assertEqual(200, after_response["httpStatus"], after_response)
        self.assertEqual("available", after_response["document"]["state"], after_response)
        self.assertEqual(
            {"kind": self.credential_kind, "id": self.credential_id},
            after_response["document"]["credentialReference"],
        )

        self.assertTrue(self.credential_material_path.is_file())
        self.assertEqual(0o600, self.credential_material_path.stat().st_mode & 0o777)
        material = self.credential_material_path.read_text(encoding="utf-8")
        self.assertIn(password, material)
        self.assertIn("acceptance-operator", material)
        self.assertNotIn(password, (self.work / "guest.sqlite").read_bytes().decode("latin-1"))


if __name__ == "__main__":
    unittest.main()
