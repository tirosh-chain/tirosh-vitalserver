"""Black-box Lab, Archive, and deletion proof through Guest Runtime public HTTP contracts."""

from __future__ import annotations

import base64
import gzip
import hashlib
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import re
import urllib.error
import urllib.request
import urllib.parse
import zlib

from acceptance.harness.guest_runtime_control_http_acceptance_fixture_arguments import (
    compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments,
    require_recorder_catalog_test_database_url,
)
from tooling.contracts import ContractRepository


ROOT = Path(__file__).resolve().parents[2]
GO = os.environ.get("RUNTIME_PLATFORM_GO", "go")
PROVIDER = {
    "kind": "archive-export-outcome-profile",
    "id": "bundled-archive",
    "capabilityRevision": 1,
}


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def local_non_loopback_address() -> str:
    """Return a local interface address suitable for C46 external topology.

    The UDP connect establishes no application exchange; it only asks the OS
    which source address it would use. A missing non-loopback address makes
    the external-topology acceptance case unsupported, never loopback.
    """

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("198.51.100.1", 443))
            address = probe.getsockname()[0]
        except OSError as error:
            raise unittest.SkipTest("no non-loopback local address is available for C46 acceptance") from error
    if address.startswith("127.") or address == "0.0.0.0":
        raise unittest.SkipTest("no non-loopback local address is available for C46 acceptance")
    return address


def request_json(url: str, method: str = "GET", payload: dict | None = None) -> tuple[int, dict]:
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def read_http_request_body(request: http.server.BaseHTTPRequestHandler) -> bytes:
    """Read the fixture request body, including Go's streaming chunked upload."""

    if request.headers.get("Transfer-Encoding", "").lower() != "chunked":
        return request.rfile.read(int(request.headers.get("Content-Length", "0")))
    chunks: list[bytes] = []
    while True:
        size_line = request.rfile.readline().split(b";", 1)[0].strip()
        size = int(size_line, 16)
        if size == 0:
            request.rfile.readline()
            return b"".join(chunks)
        chunks.append(request.rfile.read(size))
        if request.rfile.read(2) != b"\r\n":
            raise ValueError("chunked request delimiter is invalid")


class FinalizedColdPathGatewayFixture:
    """A C45-contract fixture, not an Archive substitute.

    The Guest Runtime still performs the receipt read, Gateway digest check, and
    binary .vital formation. This fixture is deliberately limited to owning the
    explicit Gateway facts that a real recorder/Gateway pair would expose.
    """

    finalization_receipt_id = "finalization-lab-export"
    capture_id = "capture-lab-export"

    def __init__(self) -> None:
        self.recorder_id = ""
        frame = {
            "vrcode": "LAB-archive-fixture",
            "rooms": {
                "Lab archive bed": {
                    "roomname": "Lab archive bed",
                    "trks": [
                        {"name": "HR", "dname": "VitalServer Lab", "montype": "ECG_HR", "type": "num", "unit": "/min", "recs": [{"dt": 1710000000, "val": 75}]},
                        {"name": "ECG", "dname": "VitalServer Lab", "montype": "ECG_WAV", "type": "wav", "srate": 2, "unit": "mV", "mindisp": -1, "maxdisp": 1, "recs": [{"dt": 1710000000, "val": [0.1, 0.2]}]},
                    ],
                }
            },
        }
        packet = {
            "ingressReceiptId": "ingress-lab-export",
            "packetId": "packet-lab-export",
            "receivedAt": "2026-07-19T00:00:00Z",
            "payloadEncoding": "binary",
            "payloadBase64": base64.b64encode(zlib.compress(json.dumps(frame, separators=(",", ":")).encode("utf-8"))).decode("ascii"),
        }
        self.packet_sequence = (json.dumps(packet, separators=(",", ":")) + "\n").encode("utf-8")
        self.packet_sequence_digest = hashlib.sha256(self.packet_sequence).hexdigest()
        fixture = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802: stdlib HTTP handler API
                if self.path == "/v1/recorder-cold-path/finalization-receipts/" + fixture.finalization_receipt_id:
                    fixture._write_json(self, {
                        "schemaVersion": "v1",
                        "state": "available",
                        "observedAt": "2026-07-19T00:00:00Z",
                        "value": {
                            "schemaVersion": "v1",
                            "id": fixture.finalization_receipt_id,
                            "requestId": "finalize-lab-export",
                            "captureReference": {"resourceType": "recorder-cold-path-capture", "resourceId": fixture.capture_id},
                            "expectedCaptureRevision": 1,
                            "finalizedCaptureRevision": 2,
                            "recorderId": fixture.recorder_id,
                            "connection": {"sessionId": "lab-archive-session", "protocolVersion": "v2"},
                            "finalizedPacketSequence": {
                                "resourceType": "recorder-cold-path-packet-sequence", "resourceId": fixture.capture_id,
                                "format": "recorder-gateway-cold-path-packet-sequence-v1",
                                "mediaType": "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl",
                                "packetCount": 1, "payloadByteCount": len(fixture.packet_sequence), "sha256": fixture.packet_sequence_digest,
                            },
                            "finalizedAt": "2026-07-19T00:00:00Z",
                        },
                    })
                    return
                if self.path == "/v1/recorder-cold-path/captures/" + fixture.capture_id + ":packet-sequence":
                    self.send_response(200)
                    self.send_header("Content-Type", "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl")
                    self.send_header("Content-Length", str(len(fixture.packet_sequence)))
                    self.end_headers()
                    self.wfile.write(fixture.packet_sequence)
                    return
                self.send_error(404)

            def log_message(self, *_: object) -> None:
                return

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.endpoint = "http://127.0.0.1:{0}".format(self.server.server_port)

    @staticmethod
    def _write_json(response: http.server.BaseHTTPRequestHandler, value: dict) -> None:
        encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
        response.send_response(200)
        response.send_header("Content-Type", "application/json")
        response.send_header("Content-Length", str(len(encoded)))
        response.end_headers()
        response.wfile.write(encoded)

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


class LabRecorderRunnerFixture:
    """Runner control-contract fixture for Lab lifecycle orchestration.

    It does not stand in for the Recorder Gateway: that boundary remains the
    finalized C45 fixture above. Its only role is to supply the explicit start
    and finalization receipts that Guest Runtime persists before Archive reads
    the Gateway source.
    """

    def __init__(self, gateway: FinalizedColdPathGatewayFixture) -> None:
        self.gateway = gateway
        self.runs: dict[str, dict] = {}
        self.archive_on_terminal_stop = True
        fixture = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802: stdlib HTTP handler API
                length = int(self.headers.get("Content-Length", "0"))
                try:
                    command = json.loads(self.rfile.read(length))
                except (ValueError, OSError):
                    fixture._write_json(self, 400, fixture._rejected("invalid-lab-recorder-run-command", "request body must be valid JSON"))
                    return
                if self.path == "/v1/lab-recorder-runs":
                    fixture._start(self, command)
                    return
                if self.path.startswith("/v1/lab-recorder-runs/") and self.path.endswith(":stop"):
                    fixture._stop(self, self.path.removeprefix("/v1/lab-recorder-runs/").removesuffix(":stop"), command)
                    return
                fixture._write_json(self, 404, fixture._rejected("lab-recorder-runner-route-not-found", "Runner control route is not implemented"))

            def log_message(self, *_: object) -> None:
                return

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.endpoint = "http://127.0.0.1:{0}".format(self.server.server_port)

    def _start(self, response: http.server.BaseHTTPRequestHandler, command: dict) -> None:
        request_id = command.get("requestId")
        recorder_id = command.get("virtualRecorderId")
        recorder_code = command.get("recorderGatewayRecorderCode")
        scenario_id = command.get("scenarioId")
        if not all(isinstance(value, str) and value for value in (request_id, recorder_id, recorder_code, scenario_id)):
            self._write_json(response, 400, self._rejected("invalid-lab-recorder-run-identity", "Runner start identities must be present"))
            return
        run_id = "lab-run-" + recorder_id
        current = self.runs.get(run_id)
        if current is None:
            self.gateway.recorder_id = "recorder-" + recorder_code
            current = {
                "schemaVersion": "v1", "id": run_id, "requestId": request_id,
                "virtualRecorderId": recorder_id, "recorderGatewayRecorderCode": recorder_code,
                "recorderGatewayRecorderId": "recorder-" + recorder_code,
                "coldPathCaptureId": self.gateway.capture_id, "scenarioId": scenario_id,
                "archiveOnTerminalStop": self.archive_on_terminal_stop, "resourceRevision": 1, "state": "running",
                "emittedPacketCount": 1, "startedAt": "2026-07-20T00:00:00Z", "updatedAt": "2026-07-20T00:00:00Z",
            }
            self.runs[run_id] = current
        self._write_json(response, 201, current)

    def _stop(self, response: http.server.BaseHTTPRequestHandler, run_id: str, command: dict) -> None:
        current = self.runs.get(run_id)
        if current is None or command.get("expectedRunRevision") != 1:
            self._write_json(response, 400, self._rejected("lab-recorder-run-live-effect-missing", "Runner has no matching live run"))
            return
        finalized = {
            **current,
            "requestId": command.get("requestId"), "resourceRevision": 2, "state": "finalized", "emittedPacketCount": 2,
            "updatedAt": "2026-07-20T00:01:00Z",
            "finalizationReceipt": {
                "kind": "recorder-gateway-cold-path-finalization-receipt", "id": self.gateway.finalization_receipt_id,
                "captureId": self.gateway.capture_id, "recorderId": current["recorderGatewayRecorderId"], "finalizedAt": "2026-07-20T00:01:00Z",
            },
        }
        self.runs[run_id] = finalized
        self._write_json(response, 201, finalized)

    @staticmethod
    def _write_json(response: http.server.BaseHTTPRequestHandler, status: int, value: dict) -> None:
        encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
        response.send_response(status)
        response.send_header("Content-Type", "application/json")
        response.send_header("Content-Length", str(len(encoded)))
        response.end_headers()
        response.wfile.write(encoded)

    @staticmethod
    def _rejected(code: str, message: str) -> dict:
        return {"schemaVersion": "v1", "state": "rejected", "issue": {"code": code, "message": message, "retryable": False, "dependency": "lab-recorder-runner"}}

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


class VitalServerIndexedLibraryFixture:
    """Minimal external VitalServer library owner for an end-to-end contract proof.

    It exposes the documented upload/login/file-list exchanges and owns only
    its own accepted filenames. It is intentionally bound through a real
    non-loopback C46 endpoint; the Guest Runtime still reads C46/C51 and forms
    the artifact from the finalized Recorder Gateway cold path.
    """

    def __init__(self) -> None:
        self.host = local_non_loopback_address()
        self.uploaded_file_names: set[str] = set()
        self.request_paths: list[str] = []
        self.upload_error = ""
        fixture = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802: stdlib HTTP handler API
                fixture.request_paths.append(self.path)
                body = read_http_request_body(self)
                if self.path == "/upload":
                    match = re.search(rb'filename="?([^";\r\n]+)', body)
                    if match is None:
                        fixture.upload_error = "multipart upload did not contain a filename disposition"
                        self.send_error(400)
                        return
                    fixture.uploaded_file_names.add(match.group(1).decode("utf-8"))
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"success")
                    return
                if self.path == "/api/login":
                    form = urllib.parse.parse_qs(body.decode("utf-8"), keep_blank_values=True)
                    if form.get("id") != ["archive-admin"] or form.get("pw") != ["private-password"]:
                        self.send_error(401)
                        return
                    self._write_json({"res": True, "access_token": "external-library-token"})
                    return
                self.send_error(404)

            def do_GET(self) -> None:  # noqa: N802: stdlib HTTP handler API
                fixture.request_paths.append(self.path)
                if self.path == "/healthz":
                    self.send_response(200)
                    self.end_headers()
                    return
                if self.path != "/api/filelist?access_token=external-library-token&unixtimestamp=1":
                    self.send_error(404)
                    return
                encoded = gzip.compress(json.dumps([{"filename": value} for value in sorted(fixture.uploaded_file_names)], separators=(",", ":")).encode("utf-8"))
                self.send_response(200)
                self.send_header("Content-Type", "application/gzip")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def _write_json(self, value: dict) -> None:
                encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def log_message(self, *_: object) -> None:
                return

        self.server = http.server.ThreadingHTTPServer(("0.0.0.0", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.endpoint = "http://{0}:{1}".format(self.host, self.server.server_port)

    def write_explicit_configuration(self, directory: Path) -> tuple[Path, Path]:
        parsed = urllib.parse.urlsplit(self.endpoint)
        configuration_path = directory / "external-vitalserver-delivery.json"
        credential_path = directory / "external-vitalserver-library-credential.json"
        configuration_path.write_text(json.dumps({
            "schemaVersion": "v1", "configurationId": "acceptance-external-vitalserver-delivery",
            "externalUpstreamIntegrationReference": {"resourceType": "external-upstream-integration", "resourceId": "acceptance-external-vitalserver"},
            "vitalServerDeliveryProvider": {"kind": "external-vitalserver", "id": "acceptance-external-vitalserver", "capabilityRevision": 1},
            "vitalServerPacketDeliveryEndpoint": {"scheme": parsed.scheme, "host": parsed.hostname, "port": parsed.port},
            "vitalServerDeliveryAcknowledgementTimeoutMilliseconds": 1000,
            "vitalServerObservationEndpoint": {"scheme": parsed.scheme, "host": parsed.hostname, "port": parsed.port, "path": "/healthz", "acceptedStatusCodes": [200]},
            "vitalServerArchiveProvider": {"kind": "vitalserver-indexed-library", "id": "acceptance-external-vitalserver-library", "capabilityRevision": 1},
            "vitalServerIndexedLibraryEndpoint": {"scheme": parsed.scheme, "host": parsed.hostname, "port": parsed.port},
            "vitalServerArchiveCredentialReference": {"kind": "vitalserver-library-credential", "id": "acceptance-external-vitalserver-library"},
            "vitalServerArchiveRequestTimeoutMilliseconds": 1000,
        }, separators=(",", ":")), encoding="utf-8")
        credential_path.write_text(json.dumps({
            "schemaVersion": "v1", "credentialReference": {"kind": "vitalserver-library-credential", "id": "acceptance-external-vitalserver-library"},
            "userId": "archive-admin", "password": "private-password",
        }, separators=(",", ":")), encoding="utf-8")
        credential_path.chmod(0o600)
        return configuration_path, credential_path

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


class RunningGuest:
    def __init__(self, binary: Path, parent: Path, mode: str | None, use_external_indexed_library: bool = False) -> None:
        self.work = Path(tempfile.mkdtemp(dir=parent))
        self.port = free_port()
        self.url = "http://127.0.0.1:{0}".format(self.port)
        self.gateway = FinalizedColdPathGatewayFixture()
        self.runner = LabRecorderRunnerFixture(self.gateway)
        self.indexed_library = VitalServerIndexedLibraryFixture() if use_external_indexed_library else None
        archive_arguments: dict[str, str | None] = {
            "archive_provider_kind": "archive-export-outcome-profile",
            "archive_provider_id": "bundled-archive",
            "archive_provider_vitalserver_configuration_kind": None,
            "archive_provider_vitalserver_configuration_path": None,
            "archive_provider_credential_material_path": None,
        }
        if self.indexed_library is not None:
            configuration_path, credential_path = self.indexed_library.write_explicit_configuration(self.work)
            archive_arguments = {
                "archive_provider_kind": "vitalserver-indexed-library",
                "archive_provider_id": "acceptance-external-vitalserver-library",
                "archive_provider_vitalserver_configuration_kind": "external-vitalserver-delivery-configuration",
                "archive_provider_vitalserver_configuration_path": str(configuration_path),
                "archive_provider_credential_material_path": str(credential_path),
            }
        self.process = subprocess.Popen(
            [
                str(binary),
                *compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
                    listen_address="127.0.0.1:{0}".format(self.port), state_database_path=str(self.work / "guest.sqlite"), bootstrap_evidence_root_directory=str(self.work / "bootstrap-evidence"), service_version="lab-archive-acceptance", instance_id="guest-lab-archive-acceptance",
                    recorder_catalog_database_url=require_recorder_catalog_test_database_url(), recorder_catalog_admission_bearer_token="lab-archive-catalog-token", recorder_observation_max_report_age_seconds=300,
                    archive_source_admission_bearer_token="lab-archive-source-token", archive_artifact_object_root_directory=str(self.work / "archive-artifacts"), archive_source_maximum_bytes=67108864, lab_replay_source_object_root_directory=str(self.work / "lab-replay-sources"), lab_replay_source_maximum_bytes=67108864, lab_replay_spool_root_directory=str(self.work / "lab-replay-spools"), lab_replay_string_track_policy="skip", lab_replay_gap_policy="fail-frame", lab_replay_frame_batch_size=1, recorder_attribution_policy_kind="recorder-assignment-owner",
                    archive_export_outcome_mode=mode, recorder_gateway_cold_path_source_endpoint=self.gateway.endpoint, lab_recorder_runner_endpoint=self.runner.endpoint, external_upstream_outcome_mode="unsupported", outbound_relay_outcome_mode="unsupported",
                    guest_node_id="guest-lab-archive-acceptance", time_authority_id="guest-time-lab-archive-acceptance", time_probe_outcome_mode="unsupported",
                    telemetry_collector_probe_outcome_mode="unsupported", telemetry_export_outcome_mode="unavailable",
                    **archive_arguments,
                ),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.wait_for_ready()

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
        self.runner.close()
        self.gateway.close()
        if self.indexed_library is not None:
            self.indexed_library.close()

    def wait_for_ready(self) -> None:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                stderr = self.process.stderr.read() if self.process.stderr is not None else ""
                raise AssertionError("Guest Runtime exited early ({0}): {1}".format(self.process.returncode, stderr))
            try:
                status, body = request_json(self.url + "/v1/runtime/readiness")
                if status == 200 and body["state"] == "available":
                    return
            except (OSError, ValueError, KeyError):
                pass
            time.sleep(0.05)
        raise AssertionError("Guest Runtime did not become ready")


class LabArchiveDeletionAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = ContractRepository(ROOT)
        cls.contracts.load()
        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.temporary_directory.name)
        cls.binary = cls.work / "guest-runtime-control-http-acceptance-fixture"
        built = subprocess.run(
            [GO, "build", "-o", str(cls.binary), "./cmd/guest-runtime-control-http-acceptance-fixture"],
            cwd=ROOT / "services" / "guest-runtime",
            capture_output=True,
            text=True,
            check=False,
        )
        if built.returncode != 0:
            raise AssertionError("build Guest Runtime failed:\n{0}\n{1}".format(built.stdout, built.stderr))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def start(self, mode: str | None = "succeed", use_external_indexed_library: bool = False) -> RunningGuest:
        runtime = RunningGuest(self.binary, self.work, mode, use_external_indexed_library)
        self.addCleanup(runtime.close)
        return runtime

    def assert_schema(self, schema: str, value: dict) -> None:
        self.assertEqual([], self.contracts.validate_instance(schema, value), value)

    def read(self, runtime: RunningGuest, path: str, expected: str = "available") -> dict:
        status, result = request_json(runtime.url + path)
        self.assertEqual(200, status, result)
        self.assert_schema("read-result.schema.json", result)
        self.assertEqual(expected, result["state"], result)
        return result

    def post(self, runtime: RunningGuest, path: str, payload: dict, expected_status: int = 202) -> dict:
        status, result = request_json(runtime.url + path, "POST", payload)
        self.assertEqual(expected_status, status, result)
        return result

    def create_stopped_session(self, runtime: RunningGuest, count: int = 2, auto_archive: bool = True) -> tuple[dict, list[dict]]:
        runtime.runner.archive_on_terminal_stop = auto_archive
        create = {
            "schemaVersion": "v1",
            "requestId": "lab-session-create-{0}".format(count),
            "sessionId": "lab-session-archive-{0}".format(count),
            "expectedSessionRevision": 0,
            "name": "baseline-monitoring",
            "scenario": "baseline-monitoring",
            "recorderCount": count,
        }
        operation = self.post(runtime, "/v1/runtime/lab/sessions", create)
        self.assert_schema("operation.schema.json", operation)
        self.assertEqual("succeeded", operation["state"], operation)
        session = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(create["sessionId"]))["value"]
        self.assert_schema("lab-resources.schema.json", session)
        self.assertEqual("lab", session["origin"])
        self.assertTrue(session["name"].startswith("LAB-"), session)
        recorders = self.read(runtime, "/v1/runtime/lab/recorders")["value"]
        self.assertEqual(count, len(recorders), recorders)
        for recorder in recorders:
            self.assert_schema("lab-resources.schema.json", recorder)
            self.assertEqual("lab", recorder["origin"])
            self.assertTrue(recorder["name"].startswith("LAB-"), recorder)

        started = self.post(
            runtime,
            "/v1/runtime/lab/resources:command",
            {
                "schemaVersion": "v1",
                "requestId": "lab-session-start-{0}".format(count),
                "resourceType": "lab-session",
                "resourceId": session["id"],
                "expectedResourceRevision": session["resourceRevision"],
                "action": "start",
            },
        )
        self.assertEqual("succeeded", started["state"], started)
        running = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
        stopped = self.post(
            runtime,
            "/v1/runtime/lab/resources:command",
            {
                "schemaVersion": "v1",
                "requestId": "lab-session-stop-{0}".format(count),
                "resourceType": "lab-session",
                "resourceId": running["id"],
                "expectedResourceRevision": running["resourceRevision"],
                "action": "stop",
            },
        )
        self.assert_schema("operation.schema.json", stopped)
        self.assertEqual("succeeded", stopped["state"], stopped)
        session = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
        self.assertEqual("stopped", session["state"], session)
        recorders = self.read(runtime, "/v1/runtime/lab/recorders")["value"]
        self.assertTrue(all(item["executionState"] == "stopped" for item in recorders), recorders)
        return session, recorders

    def export(self, runtime: RunningGuest, recorder: dict, request_id: str) -> dict:
        runtime.gateway.recorder_id = recorder["recorderGatewayRecorderId"]
        operation = self.post(
            runtime,
            "/v1/runtime/archive/exports",
            {
                "schemaVersion": "v1",
                "requestId": request_id,
                "virtualRecorderId": recorder["id"],
                "expectedResourceRevision": recorder["resourceRevision"],
                "source": {"kind": "recorder-gateway-cold-path", "coldPathFinalizationReceiptId": runtime.gateway.finalization_receipt_id},
                "provider": PROVIDER,
            },
        )
        self.assert_schema("operation.schema.json", operation)
        return operation

    @staticmethod
    def evidence_id(operation: dict, kind: str) -> str:
        values = [item["id"] for item in operation.get("evidenceReferences", []) if item["kind"] == kind]
        if len(values) != 1:
            raise AssertionError("operation has no singular {0} evidence: {1}".format(kind, operation))
        return values[0]

    def test_stop_export_and_delete_are_explicit_and_no_lab_orphan_remains(self) -> None:
        runtime = self.start()
        initial = self.read(runtime, "/v1/runtime/lab/sessions", "empty")
        self.assertNotIn("value", initial)
        session, recorders = self.create_stopped_session(runtime, 2, auto_archive=False)

        pre_export = self.read(runtime, "/v1/runtime/archive/manifests/artifact-manifest-not-created", "missing")
        self.assertNotIn("value", pre_export)
        export = self.export(runtime, recorders[0], "archive-export-success")
        self.assertEqual("succeeded", export["state"], export)
        manifest_id = self.evidence_id(export, "artifact-manifest")
        receipt_id = self.evidence_id(export, "export-receipt")
        manifest = self.read(runtime, "/v1/runtime/archive/manifests/{0}".format(manifest_id))["value"]
        receipt = self.read(runtime, "/v1/runtime/archive/export-receipts/{0}".format(receipt_id))["value"]
        self.assert_schema("artifact-manifest.schema.json", manifest)
        self.assert_schema("export-receipt.schema.json", receipt)
        self.assertEqual("succeeded", receipt["outcome"], receipt)
        self.assertEqual("succeeded", receipt["upload"]["state"], receipt)
        self.assertEqual("succeeded", receipt["indexing"]["state"], receipt)
        after_export = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
        self.assertEqual("stopped", after_export["state"], after_export)
        self.assertEqual(session["resourceRevision"], after_export["resourceRevision"], after_export)

        second = next(item for item in self.read(runtime, "/v1/runtime/lab/recorders")["value"] if item["id"] == recorders[1]["id"])
        hidden = self.post(
            runtime,
            "/v1/runtime/lab/resources:command",
            {
                "schemaVersion": "v1", "requestId": "lab-recorder-hide", "resourceType": "virtual-recorder",
                "resourceId": second["id"], "expectedResourceRevision": second["resourceRevision"], "action": "hide",
            },
        )
        self.assertEqual("succeeded", hidden["state"], hidden)
        second = self.read(runtime, "/v1/runtime/lab/recorders/{0}".format(second["id"]))["value"]
        self.assertEqual("hidden", second["visibility"], second)
        self.assertIn("bedReference", second, second)

        rejected = self.post(
            runtime,
            "/v1/runtime/lab/resources:command",
            {
                "schemaVersion": "v1", "requestId": "lab-recorder-delete-assigned", "resourceType": "virtual-recorder",
                "resourceId": second["id"], "expectedResourceRevision": second["resourceRevision"], "action": "delete", "cascade": "none",
            },
            400,
        )
        self.assert_schema("command-rejection.schema.json", rejected)
        self.assertEqual("virtual-recorder-still-assigned", rejected["issue"]["code"], rejected)
        second = self.read(runtime, "/v1/runtime/lab/recorders/{0}".format(second["id"]))["value"]
        self.assertEqual("hidden", second["visibility"], second)

        detached = self.post(
            runtime,
            "/v1/runtime/lab/resources:command",
            {
                "schemaVersion": "v1", "requestId": "lab-recorder-detach", "resourceType": "virtual-recorder",
                "resourceId": second["id"], "expectedResourceRevision": second["resourceRevision"], "action": "detach",
            },
        )
        self.assertEqual("succeeded", detached["state"], detached)
        detached_recorder = self.read(runtime, "/v1/runtime/lab/recorders/{0}".format(second["id"]))["value"]
        self.assertNotIn("bedReference", detached_recorder)
        self.assertEqual("hidden", detached_recorder["visibility"], detached_recorder)
        deleted_recorder = self.post(
            runtime,
            "/v1/runtime/lab/resources:command",
            {
                "schemaVersion": "v1", "requestId": "lab-recorder-delete-detached", "resourceType": "virtual-recorder",
                "resourceId": detached_recorder["id"], "expectedResourceRevision": detached_recorder["resourceRevision"], "action": "delete", "cascade": "none",
            },
        )
        self.assertEqual("succeeded", deleted_recorder["state"], deleted_recorder)
        self.read(runtime, "/v1/runtime/lab/recorders/{0}".format(second["id"]), "missing")

        deleted = self.post(
            runtime,
            "/v1/runtime/lab/resources:command",
            {
                "schemaVersion": "v1", "requestId": "lab-session-delete", "resourceType": "lab-session",
                "resourceId": after_export["id"], "expectedResourceRevision": after_export["resourceRevision"],
                "action": "delete", "cascade": "owned-resources",
            },
        )
        self.assertEqual("succeeded", deleted["state"], deleted)
        deletion_receipt_id = self.evidence_id(deleted, "deletion-receipt")
        deletion_receipt = self.read(runtime, "/v1/runtime/lab/deletion-receipts/{0}".format(deletion_receipt_id))["value"]
        self.assert_schema("deletion-receipt.schema.json", deletion_receipt)
        retained = {(item["resourceType"], item["resourceId"]) for item in deletion_receipt["retainedResources"]}
        self.assertIn(("artifact-manifest", manifest_id), retained)
        self.assertIn(("guest-archive-object", manifest["artifact"]["artifactId"]), retained)
        self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]), "missing")
        self.read(runtime, "/v1/runtime/lab/sessions", "empty")
        self.read(runtime, "/v1/runtime/lab/beds", "empty")
        self.read(runtime, "/v1/runtime/lab/recorders", "empty")
        self.assertEqual("available", self.read(runtime, "/v1/runtime/archive/manifests/{0}".format(manifest_id))["state"])

    def test_terminal_lab_stop_submits_and_completes_archive_export_without_claiming_it_is_lab_stop(self) -> None:
        runtime = self.start("succeed")
        session, recorders = self.create_stopped_session(runtime, 1, auto_archive=True)
        recorder = recorders[0]
        self.assertEqual("export-on-stop", recorder["terminalArchivePolicy"], recorder)
        intent = recorder.get("terminalArchiveIntent")
        self.assertIsNotNone(intent, recorder)
        self.assertEqual("submitted", intent["state"], intent)
        self.assertLess(intent["sourceResourceRevision"], recorder["resourceRevision"], intent)
        self.assertEqual(runtime.gateway.finalization_receipt_id, intent["coldPathFinalizationReceiptId"], intent)

        archive_operation_id = intent["archiveOperationReference"]["resourceId"]
        archive_operation = self.read(runtime, "/v1/runtime/operations/{0}".format(archive_operation_id))["value"]
        self.assert_schema("operation.schema.json", archive_operation)
        self.assertEqual("succeeded", archive_operation["state"], archive_operation)
        manifest_id = self.evidence_id(archive_operation, "artifact-manifest")
        receipt_id = self.evidence_id(archive_operation, "export-receipt")
        manifest = self.read(runtime, "/v1/runtime/archive/manifests/{0}".format(manifest_id))["value"]
        receipt = self.read(runtime, "/v1/runtime/archive/export-receipts/{0}".format(receipt_id))["value"]
        self.assert_schema("artifact-manifest.schema.json", manifest)
        self.assert_schema("export-receipt.schema.json", receipt)
        self.assertEqual("succeeded", receipt["outcome"], receipt)

        current_session = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
        self.assertEqual("stopped", current_session["state"], current_session)
        self.assertEqual(session["resourceRevision"], current_session["resourceRevision"], current_session)

    def test_terminal_lab_stop_forms_uploads_and_indexes_vital_file_through_explicit_external_library_contract(self) -> None:
        runtime = self.start(None, use_external_indexed_library=True)
        session, recorders = self.create_stopped_session(runtime, 1, auto_archive=True)
        recorder = recorders[0]
        archive_operation_id = recorder["terminalArchiveIntent"]["archiveOperationReference"]["resourceId"]
        archive_operation = self.read(runtime, "/v1/runtime/operations/{0}".format(archive_operation_id))["value"]
        self.assertEqual("succeeded", archive_operation["state"], {"operation": archive_operation, "libraryRequests": runtime.indexed_library.request_paths if runtime.indexed_library is not None else [], "libraryUploadError": runtime.indexed_library.upload_error if runtime.indexed_library is not None else ""})
        manifest_id = self.evidence_id(archive_operation, "artifact-manifest")
        receipt_id = self.evidence_id(archive_operation, "export-receipt")
        manifest = self.read(runtime, "/v1/runtime/archive/manifests/{0}".format(manifest_id))["value"]
        receipt = self.read(runtime, "/v1/runtime/archive/export-receipts/{0}".format(receipt_id))["value"]
        self.assertEqual("application/x-vital", manifest["artifact"]["mediaType"], manifest)
        self.assertEqual("succeeded", receipt["upload"]["state"], receipt)
        self.assertEqual("succeeded", receipt["indexing"]["state"], receipt)
        receipt_suffix = hashlib.sha256((manifest["artifact"]["artifactId"] + "\0" + manifest["artifact"]["digest"]).encode("utf-8")).hexdigest()[:32]
        self.assertEqual("vitalserver-upload-" + receipt_suffix, receipt["upload"]["receiptId"], receipt)
        self.assertEqual("vitalserver-index-" + receipt_suffix, receipt["indexing"]["receiptId"], receipt)
        self.assertIsNotNone(runtime.indexed_library)
        self.assertIn(manifest["artifact"]["artifactId"] + ".vital", runtime.indexed_library.uploaded_file_names)
        current_session = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
        self.assertEqual("stopped", current_session["state"], current_session)

    def test_known_upload_and_index_failures_leave_lab_stopped_and_receipts_explicit(self) -> None:
        for mode, failed_step in (("upload-failed", "upload"), ("index-failed", "indexing")):
            with self.subTest(mode=mode):
                runtime = self.start(mode)
                session, recorders = self.create_stopped_session(runtime, 1, auto_archive=False)
                export = self.export(runtime, recorders[0], "archive-export-{0}".format(mode))
                self.assertEqual("failed", export["state"], export)
                manifest_id = self.evidence_id(export, "artifact-manifest")
                receipt_id = self.evidence_id(export, "export-receipt")
                manifest = self.read(runtime, "/v1/runtime/archive/manifests/{0}".format(manifest_id))["value"]
                receipt = self.read(runtime, "/v1/runtime/archive/export-receipts/{0}".format(receipt_id))["value"]
                self.assert_schema("artifact-manifest.schema.json", manifest)
                self.assert_schema("export-receipt.schema.json", receipt)
                self.assertEqual("failed", receipt["outcome"], receipt)
                self.assertEqual("failed", receipt[failed_step]["state"], receipt)
                if failed_step == "upload":
                    self.assertEqual("not-requested", receipt["indexing"]["state"], receipt)
                else:
                    self.assertEqual("succeeded", receipt["upload"]["state"], receipt)
                current = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
                self.assertEqual("stopped", current["state"], current)
                self.assertEqual(session["resourceRevision"], current["resourceRevision"], current)

    def test_unknown_provider_outcome_remains_running_without_a_guessed_receipt(self) -> None:
        runtime = self.start("upload-outcome-unknown")
        session, recorders = self.create_stopped_session(runtime, 1, auto_archive=False)
        command_request_id = "archive-export-upload-outcome-unknown"
        export = self.export(runtime, recorders[0], command_request_id)
        self.assertEqual("running", export["state"], export)
        manifest_id = self.evidence_id(export, "artifact-manifest")
        self.assertFalse(any(item["kind"] == "export-receipt" for item in export.get("evidenceReferences", [])), export)
        manifest = self.read(runtime, "/v1/runtime/archive/manifests/{0}".format(manifest_id))["value"]
        self.assert_schema("artifact-manifest.schema.json", manifest)
        operation = self.read(runtime, "/v1/runtime/operations/{0}".format(export["id"]))["value"]
        self.assert_schema("operation.schema.json", operation)
        self.assertEqual("running", operation["state"], operation)
        self.assertFalse(any(item["kind"] == "export-receipt" for item in operation.get("evidenceReferences", [])), operation)

        repeated = self.export(runtime, recorders[0], command_request_id)
        self.assertEqual(export["id"], repeated["id"], repeated)
        self.assertEqual("running", repeated["state"], repeated)
        current = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
        self.assertEqual("stopped", current["state"], current)
        self.assertEqual(session["resourceRevision"], current["resourceRevision"], current)


if __name__ == "__main__":
    unittest.main()
