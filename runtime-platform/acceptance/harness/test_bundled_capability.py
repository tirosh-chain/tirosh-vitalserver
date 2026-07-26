"""Black-box bundled-upstream capability ownership proof."""

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
    require_recorder_catalog_test_database_url,
)
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


class BundledUpstreamCapabilityAcceptance(unittest.TestCase):
    def setUp(self) -> None:
        self.contracts = ContractRepository(ROOT)
        self.contracts.load()
        self.temporary_directory = tempfile.TemporaryDirectory()
        work = Path(self.temporary_directory.name)
        self.port = free_port()
        binary = work / "guest-runtime-control-http-acceptance-fixture"
        built = subprocess.run(
            [GO, "build", "-o", str(binary), "./cmd/guest-runtime-control-http-acceptance-fixture"],
            cwd=ROOT / "services" / "guest-runtime",
            capture_output=True,
            text=True,
            check=False,
        )
        if built.returncode != 0:
            raise AssertionError("build Guest Runtime failed:\n{0}\n{1}".format(built.stdout, built.stderr))
        self.process = subprocess.Popen(
            [
                str(binary),
                *compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
                    listen_address="127.0.0.1:{0}".format(self.port), state_database_path=str(work / "guest.sqlite"), bootstrap_evidence_root_directory=str(work / "bootstrap-evidence"), service_version="bundled-capability-acceptance", instance_id="guest-capability-acceptance",
                    recorder_catalog_database_url=require_recorder_catalog_test_database_url(), recorder_catalog_admission_bearer_token="bundled-capability-catalog-token", recorder_observation_max_report_age_seconds=300,
                    archive_source_admission_bearer_token="bundled-capability-archive-token", archive_artifact_object_root_directory=str(work / "archive-artifacts"), archive_source_maximum_bytes=67108864, lab_replay_source_object_root_directory=str(work / "lab-replay-sources"), lab_replay_source_maximum_bytes=67108864, lab_replay_spool_root_directory=str(work / "lab-replay-spools"), lab_replay_string_track_policy="skip", lab_replay_gap_policy="fail-frame", lab_replay_frame_batch_size=1, recorder_attribution_policy_kind="recorder-assignment-owner",
                    archive_export_outcome_mode="succeed", recorder_gateway_cold_path_source_endpoint="http://127.0.0.1:8090", lab_recorder_runner_endpoint="http://127.0.0.1:8091", external_upstream_outcome_mode="unsupported", outbound_relay_outcome_mode="unsupported",
                    guest_node_id="guest-capability-acceptance", time_authority_id="guest-time-capability-acceptance", time_probe_outcome_mode="unsupported",
                    telemetry_collector_probe_outcome_mode="unsupported", telemetry_export_outcome_mode="unavailable",
                ),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.url = "http://127.0.0.1:{0}".format(self.port)
        self.wait_for_readiness()

    def tearDown(self) -> None:
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
        self.temporary_directory.cleanup()

    def wait_for_readiness(self) -> None:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                stderr = self.process.stderr.read() if self.process.stderr is not None else ""
                raise AssertionError("Guest Runtime exited early ({0}): {1}".format(self.process.returncode, stderr))
            try:
                status, body = request_json(self.url + "/v1/runtime/readiness")
                if status == 200 and json.loads(body)["state"] == "available":
                    return
            except (OSError, json.JSONDecodeError, KeyError):
                pass
            time.sleep(0.05)
        raise AssertionError("Guest Runtime did not become ready")

    def test_bundled_topology_persists_capability_without_connection_claim(self) -> None:
        command = {
            "schemaVersion": "v1",
            "requestId": "bundled-topology-apply-1",
            "topologyId": "primary-topology",
            "expectedResourceRevision": 0,
            "spec": {
                "profileKind": "bundled-upstream",
                "providerKind": "vitalserver",
                "endpointReference": {"resourceType": "upstream-endpoint", "resourceId": "bundled-vitalserver"},
            },
        }
        status, body = request_json(self.url + "/v1/runtime/topology:apply", method="POST", payload=command)
        self.assertEqual(202, status, body)
        self.assertEqual("succeeded", json.loads(body)["state"])

        status, body = request_json(self.url + "/v1/runtime/capabilities")
        self.assertEqual(200, status, body)
        capability_read = json.loads(body)
        self.assertEqual("available", capability_read["state"], capability_read)
        self.assertEqual([], self.contracts.validate_instance("capability-document.schema.json", capability_read["value"]))
        self.assertEqual("bundled-vitalserver", capability_read["value"]["provider"]["id"])
        self.assertEqual("upstream.recorder.deliver", capability_read["value"]["commands"][0]["name"])

        status, body = request_json(self.url + "/v1/runtime/topology")
        self.assertEqual(200, status, body)
        topology_read = json.loads(body)
        self.assertEqual("available", topology_read["state"], topology_read)
        self.assertEqual([], self.contracts.validate_instance("runtime-topology.schema.json", topology_read["value"]))
        topology = topology_read["value"]
        self.assertEqual("available", topology["status"]["readState"])
        self.assertEqual("not-checked", topology["status"]["connection"]["state"])
        self.assertEqual(capability_read["value"]["id"], topology["status"]["capabilityDocumentReference"]["resourceId"])


if __name__ == "__main__":
    unittest.main()
