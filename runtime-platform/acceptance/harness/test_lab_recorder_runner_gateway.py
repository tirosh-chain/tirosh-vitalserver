"""Black-box proof for the Guest-local Lab Runner and Recorder Gateway boundary.

This test starts the production Node entrypoints, rather than replacing either
side with an HTTP fixture.  The observation collector is deliberately a small
C19 boundary fixture: it only acknowledges the Runner-owned observation that
the real Guest Runtime catalog would persist.  It never provides ingress,
capture, or finalization state; those facts remain owned by the real Recorder
Gateway process started by this test.
"""

from __future__ import annotations

import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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


ROOT = Path(__file__).resolve().parents[2]
NODE = os.environ.get("RUNTIME_PLATFORM_NODE", "node")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


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
        try:
            return error.code, json.loads(error.read())
        finally:
            error.close()


def request_bytes(url: str) -> tuple[int, str, bytes]:
    request = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status, response.headers.get_content_type(), response.read()
    except urllib.error.HTTPError as error:
        try:
            return error.code, error.headers.get_content_type(), error.read()
        finally:
            error.close()


class RunningNodeProcess:
    """One test-owned Node process with explicit readiness and teardown."""

    def __init__(self, command: list[str], ready_url: str, expected_states: set[str]) -> None:
        self.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.wait_for_ready(ready_url, expected_states)
        except BaseException:
            self.close()
            raise

    def wait_for_ready(self, url: str, expected_states: set[str]) -> None:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                stderr = self.process.stderr.read() if self.process.stderr is not None else ""
                raise AssertionError("Node process exited before readiness ({0}): {1}".format(self.process.returncode, stderr))
            try:
                status, document = request_json(url)
                if status == 200 and document.get("state") in expected_states:
                    return
            except (OSError, ValueError):
                pass
            time.sleep(0.05)
        raise AssertionError("Node process did not expose the expected ready endpoint: {0}".format(url))

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


class GuestRuntimeObservationCatalogFixture:
    """C19 catalog acknowledgement endpoint used only for this process proof."""

    def __init__(self, bearer_token: str) -> None:
        self.commands: list[dict] = []
        self.bearer_token = bearer_token
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
                if self.path != "/internal/v1/recorder-catalog/observations":
                    self.send_error(404)
                    return
                if self.headers.get("Authorization") != "Bearer " + owner.bearer_token:
                    self.send_error(401)
                    return
                try:
                    body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    command = json.loads(body)
                except (OSError, ValueError):
                    self.send_error(400)
                    return
                if not isinstance(command, dict):
                    self.send_error(400)
                    return
                owner.commands.append(command)
                encoded = json.dumps(
                    {
                        "schemaVersion": "v1",
                        "requestId": command["requestId"],
                        "outcome": "accepted",
                        "observationReference": {
                            "resourceType": "catalog-observation",
                            "resourceId": command["observationId"],
                        },
                        "receivedAt": "2026-07-24T00:00:00Z",
                        "persistedAt": "2026-07-24T00:00:00Z",
                    },
                    separators=(",", ":"),
                ).encode("utf-8")
                self.send_response(202)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def log_message(self, _format: str, *_arguments: object) -> None:
                return

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.endpoint = "http://127.0.0.1:{0}".format(self.server.server_port)

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


class LabRecorderRunnerGatewayAcceptance(unittest.TestCase):
    """Prove one complete Runner-owned live effect against a real Gateway."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.work = Path(self.temporary_directory.name)
        self.processes: list[RunningNodeProcess] = []
        self.catalog_bearer_token = "acceptance-recorder-gateway-token"
        self.catalog_token_material = self.work / "recorder-catalog.token"
        self.catalog_token_material.write_text(self.catalog_bearer_token, encoding="utf-8")
        self.archive_bearer_token = "acceptance-archive-source-token"
        self.archive_token_material = self.work / "archive-source.token"
        self.archive_token_material.write_text(self.archive_bearer_token, encoding="utf-8")
        self.catalog = GuestRuntimeObservationCatalogFixture(self.catalog_bearer_token)

    def tearDown(self) -> None:
        for process in reversed(self.processes):
            process.close()
        self.catalog.close()
        self.temporary_directory.cleanup()

    def start_vitalserver(self) -> str:
        port = free_port()
        endpoint = "http://127.0.0.1:{0}".format(port)
        process = RunningNodeProcess(
            [
                NODE,
                str(
                    ROOT
                    / "services"
                    / "recorder-gateway"
                    / "dist"
                    / "test"
                    / "fixtures"
                    / "accepted-vital-server-socketio.js"
                ),
                "--listen",
                "127.0.0.1:{0}".format(port),
            ],
            endpoint + "/healthz",
            {"ready"},
        )
        self.processes.append(process)
        return endpoint

    def start_gateway(
        self,
        *,
        replay_interval_ms: int = 600000,
        replay_max_attempts: int = 3,
        vitalserver_delivery_url: str = "http://127.0.0.1:1",
    ) -> str:
        port = free_port()
        endpoint = "http://127.0.0.1:{0}".format(port)
        process = RunningNodeProcess(
            [
                NODE,
                str(ROOT / "services" / "recorder-gateway" / "dist" / "cmd" / "recorder-gateway.js"),
                "--listen", "127.0.0.1:{0}".format(port),
                "--state-dir", str(self.work / "gateway-state"),
                "--vitalserver-delivery-url", vitalserver_delivery_url,
                "--provider-kind", "vitalserver",
                "--provider-id", "acceptance-vitalserver",
                "--capability-revision", "1",
                "--vitalserver-delivery-acknowledgement-timeout-ms", "1000",
                "--delivery-replay-max-items", "100",
                "--delivery-replay-max-bytes", "1048576",
                "--cold-path-capture-max-retained-packets", "100",
                "--cold-path-capture-max-retained-payload-bytes", "1048576",
                "--replay-interval-ms", str(replay_interval_ms),
                "--replay-max-attempts", str(replay_max_attempts),
                "--replay-retry-delay-ms", "100",
                "--replay-lease-duration-ms", "1000",
                "--guest-runtime-observation-catalog-endpoint", self.catalog.endpoint,
                "--guest-runtime-observation-catalog-bearer-token-material-path", str(self.catalog_token_material),
                "--recorder-vital-upload-max-bytes", "1048576",
                "--recorder-vital-upload-recovery-interval-ms", "600000",
                "--recorder-vital-upload-recovery-max-items", "10",
                "--guest-runtime-archive-source-admission-endpoint", self.catalog.endpoint + "/internal/v1/archive/recorder-uploads",
                "--guest-runtime-archive-source-admission-bearer-token-material-path", str(self.archive_token_material),
                "--guest-runtime-archive-source-admission-request-timeout-ms", "1000",
            ],
            endpoint + "/v1/recorder-cold-path/captures/unknown-capture",
            {"missing"},
        )
        self.processes.append(process)
        return endpoint

    def start_runner(self, gateway_endpoint: str) -> str:
        port = free_port()
        endpoint = "http://127.0.0.1:{0}".format(port)
        process = RunningNodeProcess(
            [
                NODE,
                str(ROOT / "services" / "lab-recorder-runner" / "dist" / "cmd" / "lab-recorder-runner.js"),
                "--listen", "127.0.0.1:{0}".format(port),
                "--recorder-gateway-endpoint", gateway_endpoint,
                "--scenario-catalog", str(ROOT / "product" / "guest-product" / "lab-scenario-catalog.v1.json"),
                "--lab-replay-state-directory", str(self.work / "lab-replay-runner-state"),
            ],
            endpoint + "/v1/lab-recorder-runs/runner-readiness-probe",
            {"missing"},
        )
        self.processes.append(process)
        return endpoint

    def test_real_runner_finalizes_a_real_gateway_capture_and_publishes_c19(self) -> None:
        gateway_endpoint = self.start_gateway()
        runner_endpoint = self.start_runner(gateway_endpoint)

        status, started = request_json(
            runner_endpoint + "/v1/lab-recorder-runs",
            method="POST",
            payload={
                "schemaVersion": "v1",
                "requestId": "lab-runner-gateway-start-1",
                "virtualRecorderId": "lab-recorder-acceptance-1",
                "recorderGatewayRecorderCode": "LAB-ACCEPTANCE-1",
                "scenarioId": "baseline-monitoring",
            },
        )
        self.assertEqual(201, status, started)
        self.assertEqual("running", started["state"])
        self.assertEqual("published", started["observationDelivery"]["state"])
        self.assertGreaterEqual(started["emittedPacketCount"], 1)
        self.assertEqual(1, len(self.catalog.commands))
        observation = self.catalog.commands[0]
        self.assertEqual("v1", observation["schemaVersion"])
        self.assertEqual("recorder-{0}".format(started["recorderGatewayRecorderCode"]), observation["envelope"]["recorderId"])
        self.assertEqual("ready", observation["envelope"]["runtime"]["state"])
        self.assertEqual("not-reported", observation["envelope"]["time"]["state"])

        status, finalized = request_json(
            runner_endpoint + "/v1/lab-recorder-runs/{0}:stop".format(started["id"]),
            method="POST",
            payload={
                "schemaVersion": "v1",
                "requestId": "lab-runner-gateway-stop-1",
                "expectedRunRevision": 1,
            },
        )
        self.assertEqual(201, status, finalized)
        self.assertEqual("finalized", finalized["state"])
        self.assertEqual(started["coldPathCaptureId"], finalized["coldPathCaptureId"])
        self.assertGreaterEqual(finalized["emittedPacketCount"], 1)
        self.assertEqual("recorder-gateway-cold-path-finalization-receipt", finalized["finalizationReceipt"]["kind"])

        status, capture = request_json(gateway_endpoint + "/v1/recorder-cold-path/captures/{0}".format(finalized["coldPathCaptureId"]))
        self.assertEqual(200, status, capture)
        self.assertEqual("available", capture["state"])
        self.assertEqual("finalized", capture["value"]["state"])
        receipt = capture["value"]["finalizationReceipt"]
        self.assertEqual(finalized["finalizationReceipt"]["id"], receipt["id"])
        self.assertEqual(finalized["emittedPacketCount"], receipt["finalizedPacketSequence"]["packetCount"])

        status, content_type, packet_sequence = request_bytes(
            gateway_endpoint + "/v1/recorder-cold-path/captures/{0}:packet-sequence".format(finalized["coldPathCaptureId"])
        )
        self.assertEqual(200, status)
        self.assertEqual("application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl", content_type)
        self.assertEqual(receipt["finalizedPacketSequence"]["sha256"], hashlib.sha256(packet_sequence).hexdigest())
        self.assertIn(b'"payloadBase64"', packet_sequence)

    def test_replay_batch_is_idempotent_and_upstream_failure_is_not_success(self) -> None:
        gateway_endpoint = self.start_gateway(replay_interval_ms=20, replay_max_attempts=1)
        runner_endpoint = self.start_runner(gateway_endpoint)
        status, preparation = request_json(
            runner_endpoint + "/internal/v1/lab-replays:prepare",
            method="POST",
            payload={
                "schemaVersion": "v1",
                "replayId": "replay-acceptance-1",
                "recorderGatewayRecorderCode": "LAB-REPLAY-1",
                "spoolDatabaseSha256": "a" * 64,
                "frameCount": 1,
            },
        )
        self.assertEqual(201, status, preparation)
        frame = {
            "offsetSeconds": 0,
            "outputTime": preparation["outputStartedAt"],
            "tracks": [
                {
                    "outputTrackId": 2001,
                    "sourceTrackId": 1,
                    "kind": 2,
                    "name": "PLETH_HR",
                    "deviceName": "Solar8000",
                    "unit": "/min",
                    "monitorType": 9,
                    "numericValue": 72,
                }
            ],
        }
        replay_id = preparation["replayId"]
        batch_id = "replay-batch-" + hashlib.sha256(
            "{0}:0:1".format(replay_id).encode("utf-8")
        ).hexdigest()
        batch_command = {
            "schemaVersion": "v1",
            "replayId": replay_id,
            "runnerSessionId": preparation["runnerSessionId"],
            "batchId": batch_id,
            "startOffsetSecond": 0,
            "frames": [frame],
            "finalBatch": True,
        }
        batch_url = runner_endpoint + "/internal/v1/lab-replays/{0}/batches".format(
            preparation["runnerSessionId"]
        )
        status, accepted = request_json(batch_url, method="POST", payload=batch_command)
        self.assertEqual(202, status, accepted)
        retry_status, retried = request_json(batch_url, method="POST", payload=batch_command)
        self.assertEqual(202, retry_status, retried)
        self.assertEqual(accepted, retried)

        encoded_frame = json.dumps(frame, separators=(",", ":")).encode("utf-8")
        frame_digest = hashlib.sha256(
            replay_id.encode("utf-8") + b":0:" + encoded_frame
        ).hexdigest()
        ingress_receipt_id = "lab-ingress-" + frame_digest
        status, ingress = request_json(
            gateway_endpoint + "/v1/recorder-ingress/receipts/" + ingress_receipt_id
        )
        self.assertEqual(200, status, ingress)
        self.assertEqual("available", ingress["state"])
        self.assertEqual(ingress_receipt_id, ingress["value"]["id"])

        delivery_url = (
            gateway_endpoint
            + "/v1/recorder-ingress/receipts/"
            + ingress_receipt_id
            + "/delivery"
        )
        deadline = time.monotonic() + 5
        delivery: dict = {}
        while time.monotonic() < deadline:
            status, delivery = request_json(delivery_url)
            if (
                status == 200
                and delivery.get("state") == "available"
                and delivery.get("value", {}).get("retry", {}).get("state") == "exhausted"
            ):
                break
            time.sleep(0.05)
        self.assertEqual("available", delivery.get("state"), delivery)
        self.assertEqual("unavailable", delivery["value"]["outcome"]["state"])
        self.assertEqual("exhausted", delivery["value"]["retry"]["state"])

        status, confirmation = request_json(
            runner_endpoint
            + "/internal/v1/lab-replays/{0}:confirm-upstream".format(
                preparation["runnerSessionId"]
            ),
            method="POST",
            payload={
                "schemaVersion": "v1",
                "replayId": replay_id,
                "runnerSessionId": preparation["runnerSessionId"],
                "expectedFrameCount": 1,
            },
        )
        self.assertEqual(400, status, confirmation)
        self.assertEqual("rejected", confirmation["state"])
        self.assertEqual("vitalserver-delivery-terminal-failure", confirmation["issue"]["code"])

    def test_replay_succeeds_only_after_real_gateway_receives_vitalserver_acknowledgement(self) -> None:
        vitalserver_endpoint = self.start_vitalserver()
        gateway_endpoint = self.start_gateway(
            replay_interval_ms=20,
            replay_max_attempts=3,
            vitalserver_delivery_url=vitalserver_endpoint,
        )
        runner_endpoint = self.start_runner(gateway_endpoint)
        status, preparation = request_json(
            runner_endpoint + "/internal/v1/lab-replays:prepare",
            method="POST",
            payload={
                "schemaVersion": "v1",
                "replayId": "replay-success-1",
                "recorderGatewayRecorderCode": "LAB-REPLAY-SUCCESS-1",
                "spoolDatabaseSha256": "b" * 64,
                "frameCount": 1,
            },
        )
        self.assertEqual(201, status, preparation)
        frame = {
            "offsetSeconds": 0,
            "outputTime": preparation["outputStartedAt"],
            "tracks": [
                {
                    "outputTrackId": 2001,
                    "sourceTrackId": 1,
                    "kind": 2,
                    "name": "PLETH_HR",
                    "deviceName": "Solar8000",
                    "unit": "/min",
                    "monitorType": 9,
                    "numericValue": 72,
                }
            ],
        }
        replay_id = preparation["replayId"]
        batch_id = "replay-batch-" + hashlib.sha256(
            "{0}:0:1".format(replay_id).encode("utf-8")
        ).hexdigest()
        status, accepted = request_json(
            runner_endpoint
            + "/internal/v1/lab-replays/{0}/batches".format(
                preparation["runnerSessionId"]
            ),
            method="POST",
            payload={
                "schemaVersion": "v1",
                "replayId": replay_id,
                "runnerSessionId": preparation["runnerSessionId"],
                "batchId": batch_id,
                "startOffsetSecond": 0,
                "frames": [frame],
                "finalBatch": True,
            },
        )
        self.assertEqual(202, status, accepted)

        confirmation_url = (
            runner_endpoint
            + "/internal/v1/lab-replays/{0}:confirm-upstream".format(
                preparation["runnerSessionId"]
            )
        )
        deadline = time.monotonic() + 5
        confirmation_status = 0
        confirmation: dict = {}
        while time.monotonic() < deadline:
            confirmation_status, confirmation = request_json(
                confirmation_url,
                method="POST",
                payload={
                    "schemaVersion": "v1",
                    "replayId": replay_id,
                    "runnerSessionId": preparation["runnerSessionId"],
                    "expectedFrameCount": 1,
                },
            )
            if confirmation_status == 200:
                break
            self.assertEqual(409, confirmation_status, confirmation)
            self.assertEqual("pending", confirmation["state"])
            time.sleep(0.05)
        self.assertEqual(200, confirmation_status, confirmation)
        self.assertEqual("v1", confirmation["schemaVersion"])
        self.assertEqual(1, confirmation["deliveredFrameCount"])

        status, vitalserver = request_json(vitalserver_endpoint + "/healthz")
        self.assertEqual(200, status, vitalserver)
        self.assertEqual(1, vitalserver["acceptedPacketCount"])


if __name__ == "__main__":
    unittest.main()
