"""Black-box external, time, and observability proof through public HTTP contracts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from acceptance.harness.guest_runtime_control_http_acceptance_fixture_arguments import (
    compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments,
)
from tooling.contracts import ContractRepository


ROOT = Path(__file__).resolve().parents[2]
GO = os.environ.get("RUNTIME_PLATFORM_GO", "go")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def local_unicast_ipv4_address() -> str:
    """Return the Host interface address used for an external-dependency proof.

    The C46 adapter intentionally rejects loopback. UDP connect selects a local
    route without sending an NTP/HTTP request, which lets the acceptance server
    bind a real non-loopback Host interface without depending on an Internet
    service or pretending 127.0.0.1 is an external VitalServer.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.connect(("192.0.2.1", 9))
        address = probe.getsockname()[0]
    if address.startswith("127.") or address == "0.0.0.0":
        raise AssertionError("Host did not expose a non-loopback IPv4 address for the external VitalServer acceptance proof")
    return address


class RunningExternalVitalServer:
    """One C46-declared external HTTP observation endpoint for acceptance."""

    def __init__(self, observation_path: str, accepted_status: int) -> None:
        self.observation_path = observation_path
        self.accepted_status = accepted_status
        self.requests: list[tuple[str, str]] = []
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
                owner.requests.append((self.command, self.path))
                if self.path != owner.observation_path:
                    self.send_response(404)
                else:
                    self.send_response(owner.accepted_status)
                self.end_headers()

            def log_message(self, _format: str, *_arguments: object) -> None:
                return

        self.address = local_unicast_ipv4_address()
        self.server = ThreadingHTTPServer((self.address, 0), Handler)
        self.port = int(self.server.server_address[1])
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

    def write_c46(self, directory: Path, configuration_id: str, integration_id: str) -> Path:
        path = directory / "external-vitalserver-delivery.json"
        document = {
            "schemaVersion": "v1",
            "configurationId": configuration_id,
            "externalUpstreamIntegrationReference": {"resourceType": "external-upstream-integration", "resourceId": integration_id},
            "vitalServerDeliveryProvider": {"kind": "external-vitalserver", "id": integration_id, "capabilityRevision": 1},
            "vitalServerPacketDeliveryEndpoint": {"scheme": "http", "host": self.address, "port": self.port},
            "vitalServerDeliveryAcknowledgementTimeoutMilliseconds": 1000,
            "vitalServerObservationEndpoint": {"scheme": "http", "host": self.address, "port": self.port, "path": self.observation_path, "acceptedStatusCodes": [self.accepted_status]},
            "vitalServerArchiveProvider": {"kind": "vitalserver-indexed-library", "id": integration_id + "-library", "capabilityRevision": 1},
            "vitalServerIndexedLibraryEndpoint": {"scheme": "http", "host": self.address, "port": self.port},
            "vitalServerArchiveCredentialReference": {"kind": "vitalserver-library-credential", "id": integration_id + "-library"},
            "vitalServerArchiveRequestTimeoutMilliseconds": 1000,
        }
        path.write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")
        return path


def request_json(url: str, method: str = "GET", payload: dict | None = None) -> tuple[int, dict]:
    body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(url, data=body, method=method)
    request.add_header("Accept", "application/json")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


class RunningProcess:
    def __init__(self, command: list[str], ready_url: str) -> None:
        self.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.wait_for_ready(ready_url)

    def wait_for_ready(self, url: str) -> None:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                stderr = self.process.stderr.read() if self.process.stderr is not None else ""
                raise AssertionError("process exited early ({0}): {1}".format(self.process.returncode, stderr))
            try:
                status, body = request_json(url)
                if status == 200 and body.get("state") in {"available", "failed", "missing"}:
                    return
            except (OSError, ValueError):
                pass
            time.sleep(0.05)
        raise AssertionError("process did not become ready: {0}".format(url))

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        if self.process.stdout is not None:
            self.process.stdout.close()
        if self.process.stderr is not None:
            self.process.stderr.close()


class RunningGuest(RunningProcess):
    def __init__(self, binary: Path, parent: Path, suffix: str, *, external: str = "available", relay: str = "available", clock: str = "synchronized", pipeline: str = "ready", export: str = "exported", external_provider_kind: str = "external-capability-profile", external_provider_id: str = "external-upstream", external_c46_path: Path | None = None, external_timeout_milliseconds: int | None = None) -> None:
        work = Path(tempfile.mkdtemp(dir=parent, prefix="external-time-guest-"))
        self.port = free_port()
        self.url = "http://127.0.0.1:{0}".format(self.port)
        super().__init__(
            [
                str(binary),
                *compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
                    listen_address="127.0.0.1:{0}".format(self.port), state_database_path=str(work / "guest.sqlite"), service_version="external-time-acceptance", instance_id="guest-" + suffix,
                    archive_export_outcome_mode="succeed", recorder_gateway_cold_path_source_endpoint="http://127.0.0.1:8090", lab_recorder_runner_endpoint="http://127.0.0.1:8091", external_upstream_outcome_mode=external, outbound_relay_outcome_mode=relay,
                    guest_node_id="guest-" + suffix, time_authority_id="guest-time-" + suffix, time_probe_outcome_mode=clock,
                    telemetry_collector_probe_outcome_mode=pipeline, telemetry_export_outcome_mode=export,
                    external_upstream_observation_provider_kind=external_provider_kind,
                    external_upstream_observation_provider_id=external_provider_id,
                    external_upstream_observation_external_vitalserver_delivery_configuration_path=None if external_c46_path is None else str(external_c46_path),
                    external_upstream_observation_request_timeout_milliseconds=external_timeout_milliseconds,
                ),
            ],
            self.url + "/v1/runtime/readiness",
        )


class RunningHost(RunningProcess):
    def __init__(self, binary: Path, parent: Path, guest: RunningGuest, *, clock: str = "synchronized", pipeline: str = "ready", export: str = "exported") -> None:
        work = Path(tempfile.mkdtemp(dir=parent, prefix="external-time-host-"))
        self.port = free_port()
        self.url = "http://127.0.0.1:{0}".format(self.port)
        super().__init__(
            [
                str(binary), "--listen", "127.0.0.1:{0}".format(self.port),
                "--state-db", str(work / "host.sqlite"),
                "--installation-id", "host-installation", "--product-version", "external-time-acceptance",
                "--runtime-version", "external-time-acceptance", "--data-directory", str(work / "data"),
                "--guest-runtime-control-endpoint-id", "guest-control", "--guest-runtime-control-http-scheme", "http",
                "--guest-runtime-control-http-host", "127.0.0.1", "--guest-runtime-control-http-port", str(guest.port),
                "--provider-kind", "linux-kvm-libvirt-systemd", "--provider-id", "guest-vm",
                "--host-node-id", "host-external-time", "--time-authority-id", "host-time-authority",
                "--time-provider-mode", clock, "--telemetry-pipeline-mode", pipeline,
                "--telemetry-export-mode", export,
            ],
            self.url + "/v1/platform/guest-runtime-control-endpoint",
        )


class ExternalTimeObservabilityAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = ContractRepository(ROOT)
        cls.contracts.load()
        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.temporary_directory.name)
        cls.guest_binary = cls.work / "guest-runtime-control-http-acceptance-fixture"
        cls.host_binary = cls.work / "acceptance-host-agent"
        cls.build("services/guest-runtime", "./cmd/guest-runtime-control-http-acceptance-fixture", cls.guest_binary)
        cls.build("services/host-agent", "./cmd/acceptance-host-agent", cls.host_binary)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def build(cls, relative_directory: str, package: str, output: Path) -> None:
        built = subprocess.run([GO, "build", "-o", str(output), package], cwd=ROOT / relative_directory, capture_output=True, text=True, check=False)
        if built.returncode != 0:
            raise AssertionError("build {0} failed:\n{1}\n{2}".format(package, built.stdout, built.stderr))

    def start_guest(self, suffix: str, **modes: str) -> RunningGuest:
        runtime = RunningGuest(self.guest_binary, self.work, suffix, **modes)
        self.addCleanup(runtime.close)
        return runtime

    def start_host(self, guest: RunningGuest, **modes: str) -> RunningHost:
        runtime = RunningHost(self.host_binary, self.work, guest, **modes)
        self.addCleanup(runtime.close)
        return runtime

    def assert_schema(self, schema: str, value: dict) -> None:
        self.assertEqual([], self.contracts.validate_instance(schema, value), value)

    def read(self, base: str, path: str, expected_state: str = "available") -> dict:
        status, result = request_json(base + path)
        self.assertEqual(200, status, result)
        self.assert_schema("read-result.schema.json", result)
        self.assertEqual(expected_state, result["state"], result)
        return result

    def post(self, base: str, path: str, command: dict, expected_status: int = 202) -> dict:
        status, result = request_json(base + path, "POST", command)
        self.assertEqual(expected_status, status, result)
        return result

    @staticmethod
    def external_command(request_id: str, integration_id: str = "external-primary", provider_kind: str = "external-capability-profile", provider_id: str = "external-upstream", endpoint_resource_type: str = "external-vitalserver-endpoint", endpoint_resource_id: str = "primary") -> dict:
        return {
            "schemaVersion": "v1", "requestId": request_id, "integrationId": integration_id,
            "expectedResourceRevision": 0,
            "spec": {
                "provider": {"kind": provider_kind, "id": provider_id, "capabilityRevision": 1},
                "endpointReference": {"resourceType": endpoint_resource_type, "resourceId": endpoint_resource_id},
            },
        }

    @staticmethod
    def relay_command(request_id: str, target_id: str = "relay-primary") -> dict:
        return {
            "schemaVersion": "v1", "requestId": request_id, "targetId": target_id,
            "expectedResourceRevision": 0,
            "spec": {
                "provider": {"kind": "outbound-relay-profile", "id": "outbound-relay", "capabilityRevision": 1},
                "endpointReference": {"resourceType": "relay-consumer-endpoint", "resourceId": "primary"},
            },
        }

    @staticmethod
    def time_command(request_id: str, authority_id: str, node_kind: str, node_id: str) -> dict:
        return {
            "schemaVersion": "v1", "requestId": request_id, "authorityId": authority_id,
            "expectedResourceRevision": 0, "node": {"kind": node_kind, "id": node_id},
            "spec": {"profile": "enterprise-ntp", "source": {"profile": "enterprise-ntp", "sourceId": "ntp-primary"}},
        }

    @staticmethod
    def telemetry_pipeline(request_id: str, pipeline_id: str, node_kind: str, node_id: str) -> dict:
        return {
            "schemaVersion": "v1", "requestId": request_id, "pipelineId": pipeline_id,
            "expectedResourceRevision": 0, "node": {"kind": node_kind, "id": node_id},
            "spec": {
                "protocol": "otlp-http", "collectorReference": {"resourceType": "otel-collector", "resourceId": "collector-primary"},
                "signalKinds": ["logs", "metrics", "traces"],
                "redaction": {"allowedAttributeKeys": ["operation.kind"], "maxAttributes": 1, "maxValueLength": 32, "maxDistinctValuesPerKey": 1},
            },
        }

    @staticmethod
    def telemetry_signal(request_id: str, pipeline_id: str, operation_kind: str) -> dict:
        return {
            "schemaVersion": "v1", "requestId": request_id, "pipelineId": pipeline_id, "expectedResourceRevision": 1,
            "signal": {
                "schemaVersion": "v1", "service": {"name": "guest-runtime", "version": "external-time-acceptance", "instanceId": "guest-external-time"},
                "signalKinds": ["logs", "metrics", "traces"], "signalName": "runtime.event", "emittedAt": "2026-07-17T09:00:00Z",
            },
            "attributes": {"operation.kind": operation_kind, "patient.id": "must-never-leave-process"},
        }

    def test_external_topology_relay_catalog_and_guest_telemetry(self) -> None:
        guest = self.start_guest("available")
        external_operation = self.post(guest.url, "/v1/runtime/external-upstreams", self.external_command("external-upstream-apply"))
        self.assert_schema("operation.schema.json", external_operation)
        self.assertEqual("succeeded", external_operation["state"], external_operation)
        integration = self.read(guest.url, "/v1/runtime/external-upstreams/external-primary")["value"]
        self.assert_schema("external-upstream-integration.schema.json", integration)
        self.assertEqual("available", integration["status"]["state"], integration)
        self.assertEqual("reachable", integration["status"]["connection"]["state"], integration)

        topology = self.post(guest.url, "/v1/runtime/topology:apply", {
            "schemaVersion": "v1", "requestId": "external-topology-apply", "topologyId": "primary-topology", "expectedResourceRevision": 0,
            "spec": {"profileKind": "external-upstream", "providerKind": "vitalserver", "endpointReference": {"resourceType": "external-upstream-integration", "resourceId": "external-primary"}},
        })
        self.assert_schema("operation.schema.json", topology)
        self.assertEqual("succeeded", topology["state"], topology)
        topology_resource = self.read(guest.url, "/v1/runtime/topology")["value"]
        self.assertEqual("available", topology_resource["status"]["readState"], topology_resource)
        capability = self.read(guest.url, "/v1/runtime/capabilities")["value"]
        self.assert_schema("capability-document.schema.json", capability)
        commands = {item["name"]: item for item in capability["commands"]}
        for name in ("upstream.lifecycle.start", "upstream.lifecycle.stop", "upstream.update", "upstream.backup"):
            self.assertEqual("unsupported", commands[name]["state"], commands)

        relay_operation = self.post(guest.url, "/v1/runtime/relay-targets", self.relay_command("relay-target-apply"))
        self.assertEqual("succeeded", relay_operation["state"], relay_operation)
        relay = self.read(guest.url, "/v1/runtime/relay-targets/relay-primary")["value"]
        self.assert_schema("outbound-relay-target.schema.json", relay)
        self.assertEqual("available", relay["status"]["state"], relay)

        time_operation = self.post(guest.url, "/v1/time/authorities", self.time_command("guest-time-apply", "guest-time-available", "guest", "guest-available"))
        self.assertEqual("succeeded", time_operation["state"], time_operation)
        quality = self.read(guest.url, "/v1/time/clock-quality")["value"]
        self.assert_schema("clock-quality.schema.json", quality)
        self.assertEqual("synchronized", quality["state"], quality)
        self.assertEqual("guest", quality["node"]["kind"], quality)
        for evidence in ("source", "stratum", "offsetMs", "uncertaintyMs", "lastSyncAt"):
            self.assertIn(evidence, quality, quality)

        envelope = {
            "schemaVersion": "v1", "protocolVersion": "v1", "recorderId": "recorder-observation-source", "bootId": "observation-boot", "sequence": 7,
            "occurredAt": "2026-07-17T08:59:00Z",
            "time": {"state": "synchronized", "sourceId": "recorder-ntp", "offsetMs": 0.25, "uncertaintyMs": 1.0, "lastSyncAt": "2026-07-17T08:59:00Z"},
            "runtime": {"state": "ready", "version": "1.2.3"},
        }
        catalog_operation = self.post(guest.url, "/v1/runtime/catalog/recorder-observations", {"schemaVersion": "v1", "requestId": "catalog-observation-ingest", "observationId": "observation-primary", "envelope": envelope})
        self.assertEqual("succeeded", catalog_operation["state"], catalog_operation)
        observation = self.read(guest.url, "/v1/runtime/catalog/recorder-observations/observation-primary")["value"]
        self.assert_schema("catalog-observation.schema.json", observation)
        self.assertEqual(envelope["occurredAt"], observation["envelope"]["occurredAt"], observation)
        self.assertNotEqual(envelope["occurredAt"], observation["receivedAt"], observation)
        replay = self.post(guest.url, "/v1/runtime/catalog/recorder-observations", {"schemaVersion": "v1", "requestId": "catalog-observation-replay", "observationId": "observation-other", "envelope": envelope})
        self.assertEqual(catalog_operation["id"], replay["id"], replay)

        pipeline_operation = self.post(guest.url, "/v1/runtime/telemetry/pipelines", self.telemetry_pipeline("guest-telemetry-pipeline", "guest-telemetry", "guest", "guest-available"))
        self.assert_schema("operation.schema.json", pipeline_operation)
        self.assertEqual("succeeded", pipeline_operation["state"], pipeline_operation)
        emitted = self.post(guest.url, "/v1/runtime/telemetry/signals", self.telemetry_signal("guest-telemetry-signal", "guest-telemetry", "lab-delete"))
        self.assert_schema("operation.schema.json", emitted)
        self.assertEqual("succeeded", emitted["state"], emitted)
        receipt_id = emitted["evidenceReferences"][0]["id"]
        receipt = self.read(guest.url, "/v1/runtime/telemetry/receipts/" + receipt_id)["value"]
        self.assert_schema("telemetry-emission-receipt.schema.json", receipt)
        self.assertEqual("exported", receipt["outcome"], receipt)
        self.assertIn("patient.id", receipt["redactedAttributeKeys"], receipt)
        self.assertNotIn("must-never-leave-process", json.dumps(receipt), receipt)
        cardinality = self.post(guest.url, "/v1/runtime/telemetry/signals", self.telemetry_signal("guest-telemetry-cardinality", "guest-telemetry", "another-operation"))
        cardinality_receipt = self.read(guest.url, "/v1/runtime/telemetry/receipts/" + cardinality["evidenceReferences"][0]["id"])["value"]
        self.assertEqual("dropped", cardinality_receipt["outcome"], cardinality_receipt)
        self.assertIn("operation.kind", cardinality_receipt["droppedAttributeKeys"], cardinality_receipt)
        after = self.read(guest.url, "/v1/runtime/topology")["value"]
        self.assertEqual(topology_resource["resourceRevision"], after["resourceRevision"], after)

    def test_external_vitalserver_http_observation_uses_only_the_c46_declared_endpoint(self) -> None:
        integration_id = "external-vitalserver-http"
        configuration_id = "external-vitalserver-http-delivery"
        external_vitalserver = RunningExternalVitalServer("/operator-approved-status", 204)
        self.addCleanup(external_vitalserver.close)
        configuration_path = external_vitalserver.write_c46(self.work, configuration_id, integration_id)
        guest = self.start_guest(
            "external-vitalserver-http",
            external="",
            external_provider_kind="external-vitalserver-http",
            external_provider_id=integration_id,
            external_c46_path=configuration_path,
            external_timeout_milliseconds=1000,
        )
        operation = self.post(
            guest.url,
            "/v1/runtime/external-upstreams",
            self.external_command(
                "external-vitalserver-http-observation",
                integration_id=integration_id,
                provider_kind="external-vitalserver-http",
                provider_id=integration_id,
                endpoint_resource_type="external-vitalserver-delivery-configuration",
                endpoint_resource_id=configuration_id,
            ),
        )
        self.assertEqual("succeeded", operation["state"], operation)
        integration = self.read(guest.url, "/v1/runtime/external-upstreams/" + integration_id)["value"]
        self.assertEqual("available", integration["status"]["state"], integration)
        self.assertEqual("reachable", integration["status"]["connection"]["state"], integration)
        self.assertEqual([("GET", "/operator-approved-status")], external_vitalserver.requests)

    def test_unavailable_and_unknown_profiles_remain_explicit_and_independent(self) -> None:
        known = self.start_guest("known", external="unavailable", relay="available", clock="failed", pipeline="unavailable", export="unavailable")
        external = self.post(known.url, "/v1/runtime/external-upstreams", self.external_command("external-upstream-unavailable"))
        self.assertEqual("succeeded", external["state"], external)
        integration = self.read(known.url, "/v1/runtime/external-upstreams/external-primary")["value"]
        self.assertEqual("unavailable", integration["status"]["state"], integration)
        relay = self.post(known.url, "/v1/runtime/relay-targets", self.relay_command("relay-target-available"))
        self.assertEqual("succeeded", relay["state"], relay)
        relay_resource = self.read(known.url, "/v1/runtime/relay-targets/relay-primary")["value"]
        self.assertEqual("available", relay_resource["status"]["state"], relay_resource)
        topology = self.post(known.url, "/v1/runtime/topology:apply", {
            "schemaVersion": "v1", "requestId": "unavailable-external-topology", "topologyId": "primary-topology", "expectedResourceRevision": 0,
            "spec": {"profileKind": "external-upstream", "providerKind": "vitalserver", "endpointReference": {"resourceType": "external-upstream-integration", "resourceId": "external-primary"}},
        })
        self.assertEqual("succeeded", topology["state"], topology)
        unavailable_capability = self.read(known.url, "/v1/runtime/capabilities", "unavailable")
        self.assertEqual("external-upstream-unavailable", unavailable_capability["issue"]["code"], unavailable_capability)
        time_operation = self.post(known.url, "/v1/time/authorities", self.time_command("guest-time-failed", "guest-time-known", "guest", "guest-known"))
        self.assertEqual("succeeded", time_operation["state"], time_operation)
        clock = self.read(known.url, "/v1/time/clock-quality")["value"]
        self.assertEqual("failed", clock["state"], clock)
        self.assertIn("issue", clock, clock)
        pipeline = self.post(known.url, "/v1/runtime/telemetry/pipelines", self.telemetry_pipeline("unavailable-telemetry-pipeline", "guest-telemetry", "guest", "guest-known"))
        self.assertEqual("succeeded", pipeline["state"], pipeline)
        emitted = self.post(known.url, "/v1/runtime/telemetry/signals", self.telemetry_signal("unavailable-telemetry-signal", "guest-telemetry", "lab-stop"))
        self.assertEqual("failed", emitted["state"], emitted)
        receipt = self.read(known.url, "/v1/runtime/telemetry/receipts/" + emitted["evidenceReferences"][0]["id"])["value"]
        self.assertEqual("unavailable", receipt["outcome"], receipt)

        unknown = self.start_guest("unknown", external="outcome-unknown", relay="outcome-unknown", clock="outcome-unknown", pipeline="ready", export="outcome-unknown")
        external_unknown = self.post(unknown.url, "/v1/runtime/external-upstreams", self.external_command("external-upstream-unknown"))
        self.assertEqual("running", external_unknown["state"], external_unknown)
        self.assertEqual("missing", self.read(unknown.url, "/v1/runtime/external-upstreams/external-primary", "missing")["state"])
        time_unknown = self.post(unknown.url, "/v1/time/authorities", self.time_command("guest-time-unknown", "guest-time-unknown", "guest", "guest-unknown"))
        self.assertEqual("running", time_unknown["state"], time_unknown)
        self.assertEqual("missing", self.read(unknown.url, "/v1/time/clock-quality", "missing")["state"])
        pipeline_unknown = self.post(unknown.url, "/v1/runtime/telemetry/pipelines", self.telemetry_pipeline("unknown-telemetry-pipeline", "guest-telemetry", "guest", "guest-unknown"))
        self.assertEqual("succeeded", pipeline_unknown["state"], pipeline_unknown)
        signal_unknown = self.post(unknown.url, "/v1/runtime/telemetry/signals", self.telemetry_signal("unknown-telemetry-signal", "guest-telemetry", "lab-start"))
        self.assertEqual("running", signal_unknown["state"], signal_unknown)
        self.assertFalse(signal_unknown.get("evidenceReferences"), signal_unknown)

    def test_host_and_guest_time_and_telemetry_are_node_local(self) -> None:
        guest = self.start_guest("host", clock="unsupported", pipeline="unsupported", export="unavailable")
        host = self.start_host(guest)
        host_time = self.post(host.url, "/v1/platform/time/authorities", self.time_command("host-time-apply", "host-time-authority", "host", "host-external-time"))
        self.assert_schema("operation.schema.json", host_time)
        self.assertEqual("succeeded", host_time["state"], host_time)
        host_quality = self.read(host.url, "/v1/platform/time/clock-quality")["value"]
        self.assertEqual("host", host_quality["node"]["kind"], host_quality)
        self.assertEqual("synchronized", host_quality["state"], host_quality)
        guest_quality = self.read(guest.url, "/v1/time/clock-quality", "missing")
        self.assertEqual("missing", guest_quality["state"], guest_quality)
        forwarded_guest_quality = self.read(host.url, "/v1/time/clock-quality", "missing")
        self.assertEqual("guest-time-authority-missing", forwarded_guest_quality["issue"]["code"], forwarded_guest_quality)
        self.assertNotEqual(host_quality["node"], forwarded_guest_quality.get("value", {}).get("node"), forwarded_guest_quality)

        host_pipeline = self.post(host.url, "/v1/platform/telemetry/pipelines", self.telemetry_pipeline("host-telemetry-pipeline", "host-telemetry", "host", "host-external-time"))
        self.assertEqual("succeeded", host_pipeline["state"], host_pipeline)
        signal = self.telemetry_signal("host-telemetry-signal", "host-telemetry", "host-start")
        signal["signal"]["service"] = {"name": "host-agent", "version": "external-time-acceptance", "instanceId": "host-external-time"}
        emitted = self.post(host.url, "/v1/platform/telemetry/signals", signal)
        self.assert_schema("operation.schema.json", emitted)
        self.assertEqual("succeeded", emitted["state"], emitted)
        receipt = self.read(host.url, "/v1/platform/telemetry/receipts/" + emitted["evidenceReferences"][0]["id"])["value"]
        self.assertEqual("exported", receipt["outcome"], receipt)
        self.assertIn("patient.id", receipt["redactedAttributeKeys"], receipt)


if __name__ == "__main__":
    unittest.main()
