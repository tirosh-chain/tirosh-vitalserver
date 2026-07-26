"""PostgreSQL-backed Guest Runtime through VitalServer replay acceptance.

This proof starts the production Guest Runtime acceptance executable, Lab
Recorder Runner, Recorder Gateway, and a Socket.IO VitalServer acknowledgement
fixture.  It admits one immutable synthetic .vital source through the public
Guest API and accepts success only after the Guest-owned replay operation has
persisted the upstream acknowledgement receipt.
"""

from __future__ import annotations

import base64
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid

from acceptance.harness.guest_runtime_control_http_acceptance_fixture_arguments import (
    compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments,
    require_recorder_catalog_test_database_url,
)
from acceptance.harness.test_lab_recorder_runner_gateway import (
    NODE,
    ROOT,
    RunningNodeProcess,
    free_port,
    request_json,
)
from tooling.vital_replay_corpus import verify_vital_replay_corpus


GO = os.environ.get("RUNTIME_PLATFORM_GO", "go")
FIXTURE = (
    ROOT
    / "services"
    / "guest-runtime"
    / "internal"
    / "adapters"
    / "vitalfilereplayparser"
    / "testdata"
    / "synthetic-v1.vital.base64"
)


def single_track_vital_source(
    track_kind: int,
    monitor_type: int,
    name: bytes,
) -> bytes:
    """Build a deterministic v3 source for one typed track decision."""
    track = (
        struct.pack("<HBBI", 1, track_kind, 1 if track_kind == 2 else 0, len(name))
        + name
        + struct.pack("<I", 0)
        + struct.pack("<ffIfddBI", 0, 100, 0, 0, 0, 0, monitor_type, 0)
    )
    packet = struct.pack("<BI", 0, len(track)) + track
    header = (
        b"VITA"
        + struct.pack("<IHhI", 3, 10, 0, 1)
        + bytes((1, 0, 0, 0))
    )
    return gzip.compress(header + packet, mtime=0)


def no_graph_compatible_vital_source() -> bytes:
    """Build a valid v3 source whose sole numeric track has no graph mapping."""
    return single_track_vital_source(2, 255, b"UNKNOWN_NUMERIC")


def unknown_track_vital_source() -> bytes:
    return single_track_vital_source(4, 0, b"UNKNOWN_TRACK")


def string_track_vital_source() -> bytes:
    return single_track_vital_source(5, 0, b"STRING_TRACK")


def request_vital_source(
    url: str,
    command: dict,
    content: bytes,
) -> tuple[int, dict]:
    encoded_command = base64.urlsafe_b64encode(
        json.dumps(command, separators=(",", ":")).encode("utf-8")
    ).rstrip(b"=").decode("ascii")
    request = urllib.request.Request(
        url,
        data=content,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-vital",
            "X-Vital-Lab-Replay-Source-Command": encoded_command,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        try:
            return error.code, json.loads(error.read())
        finally:
            error.close()


def assert_public_typed_track_failure(
    testcase: unittest.TestCase,
    guest_endpoint: str,
    content: bytes,
    identity_prefix: str,
    expected_code: str,
) -> None:
    digest = hashlib.sha256(content).hexdigest()
    identity = identity_prefix + "-" + uuid.uuid4().hex
    status, receipt = request_vital_source(
        guest_endpoint + "/v1/runtime/lab/replay-sources",
        {
            "schemaVersion": "v1",
            "requestId": "source-request-" + identity,
            "sourceId": "source-" + identity,
            "originalFileName": identity_prefix + ".vital",
            "mediaType": "application/x-vital",
            "byteSize": len(content),
            "sha256": digest,
        },
        content,
    )
    testcase.assertEqual(202, status, receipt)
    testcase.assertEqual("accepted", receipt["outcome"])
    replay_id = "replay-" + identity
    status, admitted = request_json(
        guest_endpoint + "/v1/runtime/lab/replays",
        method="POST",
        payload={
            "schemaVersion": "v1",
            "requestId": "replay-request-" + identity,
            "replayId": replay_id,
            "sourceReference": receipt["sourceReference"],
            "sourceSha256": digest,
            "recorderGatewayRecorderCode": "LAB-" + identity_prefix.upper(),
            "requestedAt": datetime.now(timezone.utc)
            .isoformat(timespec="microseconds")
            .replace("+00:00", "Z"),
        },
    )
    testcase.assertEqual(202, status, admitted)
    deadline = time.monotonic() + 15
    operation: dict = {}
    while time.monotonic() < deadline:
        status, read = request_json(
            guest_endpoint + "/v1/runtime/lab/replays/" + replay_id
        )
        testcase.assertEqual(200, status, read)
        testcase.assertEqual("available", read["state"])
        operation = read["value"]
        if operation["state"] in {"succeeded", "failed"}:
            break
        time.sleep(0.05)
    testcase.assertEqual("failed", operation.get("state"), operation)
    testcase.assertEqual("track-decode", operation["failure"]["stage"])
    testcase.assertEqual(expected_code, operation["failure"]["code"])
    testcase.assertEqual(0, operation["messagesSent"])
    testcase.assertEqual("not-attempted", operation["lastSendState"])


def assert_public_successful_replay(
    testcase: unittest.TestCase,
    guest_endpoint: str,
    content: bytes,
    original_file_name: str,
    expected_format_version: int,
    minimum_graph_compatible_signal_count: int,
) -> dict:
    digest = hashlib.sha256(content).hexdigest()
    identity = uuid.uuid4().hex
    status, receipt = request_vital_source(
        guest_endpoint + "/v1/runtime/lab/replay-sources",
        {
            "schemaVersion": "v1",
            "requestId": "approved-source-request-" + identity,
            "sourceId": "approved-source-" + identity,
            "originalFileName": original_file_name,
            "mediaType": "application/x-vital",
            "byteSize": len(content),
            "sha256": digest,
        },
        content,
    )
    testcase.assertEqual(202, status, receipt)
    testcase.assertEqual("accepted", receipt["outcome"])
    testcase.assertEqual(digest, receipt["sha256"])
    replay_id = "approved-replay-" + identity
    status, admitted = request_json(
        guest_endpoint + "/v1/runtime/lab/replays",
        method="POST",
        payload={
            "schemaVersion": "v1",
            "requestId": "approved-replay-request-" + identity,
            "replayId": replay_id,
            "sourceReference": receipt["sourceReference"],
            "sourceSha256": digest,
            "recorderGatewayRecorderCode": "LAB-APPROVED-" + identity[:16],
            "requestedAt": datetime.now(timezone.utc)
            .isoformat(timespec="microseconds")
            .replace("+00:00", "Z"),
        },
    )
    testcase.assertEqual(202, status, admitted)
    deadline = time.monotonic() + 60
    operation: dict = {}
    while time.monotonic() < deadline:
        status, read = request_json(
            guest_endpoint + "/v1/runtime/lab/replays/" + replay_id
        )
        testcase.assertEqual(200, status, read)
        testcase.assertEqual("available", read["state"])
        operation = read["value"]
        if operation["state"] in {"succeeded", "failed"}:
            break
        time.sleep(0.05)
    testcase.assertEqual("succeeded", operation.get("state"), operation)
    testcase.assertEqual(
        "vital-v" + str(expected_format_version),
        operation["validationReceipt"]["fileFormatVersion"],
    )
    testcase.assertGreaterEqual(
        operation["validationReceipt"]["graphCompatibleSignalCount"],
        minimum_graph_compatible_signal_count,
    )
    testcase.assertEqual("sent", operation["lastSendState"])
    testcase.assertGreater(operation["messagesSent"], 0)
    testcase.assertGreater(
        operation["upstreamDeliveryReceipt"]["deliveredFrameCount"],
        0,
    )
    return operation


class RunningGuestRuntime:
    def __init__(self, command: list[str], ready_url: str) -> None:
        self.process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            self.wait_for_ready(ready_url)
        except BaseException:
            self.close()
            raise

    def wait_for_ready(self, ready_url: str) -> None:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                stderr = (
                    self.process.stderr.read()
                    if self.process.stderr is not None
                    else ""
                )
                raise AssertionError(
                    "Guest Runtime exited before readiness "
                    f"({self.process.returncode}): {stderr}"
                )
            try:
                status, document = request_json(ready_url)
                if status == 200 and document.get("state") == "available":
                    return
            except (OSError, ValueError):
                pass
            time.sleep(0.05)
        raise AssertionError("Guest Runtime did not expose available readiness")

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


class LabReplayGuestRuntimeAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        require_recorder_catalog_test_database_url()
        cls.build_directory = tempfile.TemporaryDirectory()
        cls.guest_binary = (
            Path(cls.build_directory.name)
            / "guest-runtime-control-http-acceptance-fixture"
        )
        subprocess.run(
            [
                GO,
                "build",
                "-o",
                str(cls.guest_binary),
                "./cmd/guest-runtime-control-http-acceptance-fixture",
            ],
            cwd=ROOT / "services" / "guest-runtime",
            check=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.work = Path(self.temporary_directory.name)
        self.node_processes: list[RunningNodeProcess] = []
        self.guest: RunningGuestRuntime | None = None
        self.catalog_token = "guest-replay-catalog-token"
        self.archive_token = "guest-replay-archive-token"
        self.catalog_token_path = self.work / "catalog.token"
        self.archive_token_path = self.work / "archive.token"
        self.catalog_token_path.write_text(self.catalog_token, encoding="utf-8")
        self.archive_token_path.write_text(self.archive_token, encoding="utf-8")

    def tearDown(self) -> None:
        if self.guest is not None:
            self.guest.close()
        for process in reversed(self.node_processes):
            process.close()
        self.temporary_directory.cleanup()

    def start_node(
        self,
        command: list[str],
        ready_url: str,
        expected_states: set[str],
    ) -> str:
        process = RunningNodeProcess(command, ready_url, expected_states)
        self.node_processes.append(process)
        return ready_url.rsplit("/", 1)[0]

    def test_guest_worker_persists_vitalserver_acknowledged_replay(self) -> None:
        corpus_manifest = os.environ.get(
            "RUNTIME_PLATFORM_VITAL_REPLAY_CORPUS_MANIFEST"
        )
        corpus_directory = os.environ.get(
            "RUNTIME_PLATFORM_VITAL_REPLAY_CORPUS_DIRECTORY"
        )
        if (corpus_manifest is None) != (corpus_directory is None):
            self.fail(
                "approved C79 replay requires both corpus manifest and directory"
            )
        approved_corpus = None
        if corpus_manifest is not None and corpus_directory is not None:
            approved_corpus = verify_vital_replay_corpus(
                ROOT,
                Path(corpus_manifest),
                Path(corpus_directory),
            )

        guest_port = free_port()
        guest_endpoint = f"http://127.0.0.1:{guest_port}"

        vitalserver_port = free_port()
        vitalserver_endpoint = f"http://127.0.0.1:{vitalserver_port}"
        self.start_node(
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
                f"127.0.0.1:{vitalserver_port}",
            ],
            vitalserver_endpoint + "/healthz",
            {"ready"},
        )

        gateway_port = free_port()
        gateway_endpoint = f"http://127.0.0.1:{gateway_port}"
        self.start_node(
            [
                NODE,
                str(
                    ROOT
                    / "services"
                    / "recorder-gateway"
                    / "dist"
                    / "cmd"
                    / "recorder-gateway.js"
                ),
                "--listen",
                f"127.0.0.1:{gateway_port}",
                "--state-dir",
                str(self.work / "gateway-state"),
                "--vitalserver-delivery-url",
                vitalserver_endpoint,
                "--provider-kind",
                "vitalserver",
                "--provider-id",
                "guest-replay-vitalserver",
                "--capability-revision",
                "1",
                "--vitalserver-delivery-acknowledgement-timeout-ms",
                "1000",
                "--delivery-replay-max-items",
                "100",
                "--delivery-replay-max-bytes",
                "1048576",
                "--cold-path-capture-max-retained-packets",
                "100",
                "--cold-path-capture-max-retained-payload-bytes",
                "1048576",
                "--replay-interval-ms",
                "20",
                "--replay-max-attempts",
                "1",
                "--replay-retry-delay-ms",
                "100",
                "--replay-lease-duration-ms",
                "1000",
                "--guest-runtime-observation-catalog-endpoint",
                guest_endpoint,
                "--guest-runtime-observation-catalog-bearer-token-material-path",
                str(self.catalog_token_path),
                "--recorder-vital-upload-max-bytes",
                "1048576",
                "--recorder-vital-upload-recovery-interval-ms",
                "600000",
                "--recorder-vital-upload-recovery-max-items",
                "10",
                "--guest-runtime-archive-source-admission-endpoint",
                guest_endpoint + "/internal/v1/archive/recorder-uploads",
                "--guest-runtime-archive-source-admission-bearer-token-material-path",
                str(self.archive_token_path),
                "--guest-runtime-archive-source-admission-request-timeout-ms",
                "1000",
            ],
            gateway_endpoint + "/v1/recorder-cold-path/captures/unknown-capture",
            {"missing"},
        )

        runner_port = free_port()
        runner_endpoint = f"http://127.0.0.1:{runner_port}"
        self.start_node(
            [
                NODE,
                str(
                    ROOT
                    / "services"
                    / "lab-recorder-runner"
                    / "dist"
                    / "cmd"
                    / "lab-recorder-runner.js"
                ),
                "--listen",
                f"127.0.0.1:{runner_port}",
                "--recorder-gateway-endpoint",
                gateway_endpoint,
                "--scenario-catalog",
                str(
                    ROOT
                    / "product"
                    / "guest-product"
                    / "lab-scenario-catalog.v1.json"
                ),
                "--lab-replay-state-directory",
                str(self.work / "runner-state"),
            ],
            runner_endpoint + "/v1/lab-recorder-runs/readiness-probe",
            {"missing"},
        )

        self.guest = RunningGuestRuntime(
            [
                str(self.guest_binary),
                *compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
                    listen_address=f"127.0.0.1:{guest_port}",
                    state_database_path=str(self.work / "guest.sqlite"),
                    bootstrap_evidence_root_directory=str(
                        self.work / "bootstrap-evidence"
                    ),
                    recorder_catalog_database_url=require_recorder_catalog_test_database_url(),
                    recorder_catalog_admission_bearer_token=self.catalog_token,
                    recorder_observation_max_report_age_seconds=300,
                    archive_source_admission_bearer_token=self.archive_token,
                    archive_artifact_object_root_directory=str(
                        self.work / "archive-artifacts"
                    ),
                    archive_source_maximum_bytes=67108864,
                    lab_replay_source_object_root_directory=str(
                        self.work / "replay-sources"
                    ),
                    lab_replay_source_maximum_bytes=67108864,
                    lab_replay_spool_root_directory=str(self.work / "replay-spools"),
                    lab_replay_string_track_policy="skip",
                    lab_replay_gap_policy="fail-frame",
                    lab_replay_frame_batch_size=1,
                    recorder_attribution_policy_kind="recorder-assignment-owner",
                    service_version="guest-replay-acceptance",
                    instance_id="guest-replay-acceptance",
                    archive_export_outcome_mode="succeed",
                    recorder_gateway_cold_path_source_endpoint=gateway_endpoint,
                    lab_recorder_runner_endpoint=runner_endpoint,
                    external_upstream_outcome_mode="unsupported",
                    outbound_relay_outcome_mode="unsupported",
                    guest_node_id="guest-replay-acceptance",
                    time_authority_id="guest-replay-time",
                    time_probe_outcome_mode="unsupported",
                    telemetry_collector_probe_outcome_mode="unsupported",
                    telemetry_export_outcome_mode="unavailable",
                ),
            ],
            guest_endpoint + "/v1/runtime/readiness",
        )

        content = base64.b64decode(FIXTURE.read_text(encoding="utf-8").strip())
        source_sha256 = hashlib.sha256(content).hexdigest()
        identity = uuid.uuid4().hex
        source_id = "replay-source-" + identity
        status, receipt = request_vital_source(
            guest_endpoint + "/v1/runtime/lab/replay-sources",
            {
                "schemaVersion": "v1",
                "requestId": "replay-source-request-" + identity,
                "sourceId": source_id,
                "originalFileName": "synthetic-v1.vital",
                "mediaType": "application/x-vital",
                "byteSize": len(content),
                "sha256": source_sha256,
            },
            content,
        )
        self.assertEqual(202, status, receipt)
        self.assertEqual("accepted", receipt["outcome"])
        self.assertEqual(source_sha256, receipt["sha256"])

        replay_id = "guest-replay-" + identity
        status, admitted = request_json(
            guest_endpoint + "/v1/runtime/lab/replays",
            method="POST",
            payload={
                "schemaVersion": "v1",
                "requestId": "guest-replay-request-" + identity,
                "replayId": replay_id,
                "sourceReference": receipt["sourceReference"],
                "sourceSha256": source_sha256,
                "recorderGatewayRecorderCode": "LAB-GUEST-REPLAY",
                "requestedAt": datetime.now(timezone.utc)
                .isoformat(timespec="microseconds")
                .replace("+00:00", "Z"),
            },
        )
        self.assertEqual(202, status, admitted)
        self.assertEqual("pending-file-validation", admitted["state"])

        deadline = time.monotonic() + 15
        operation: dict = {}
        while time.monotonic() < deadline:
            status, read = request_json(
                guest_endpoint + "/v1/runtime/lab/replays/" + replay_id
            )
            self.assertEqual(200, status, read)
            self.assertEqual("available", read["state"])
            operation = read["value"]
            if operation["state"] in {"succeeded", "failed"}:
                break
            time.sleep(0.05)

        self.assertEqual("succeeded", operation.get("state"), operation)
        self.assertEqual("sent", operation["lastSendState"])
        self.assertGreater(operation["messagesSent"], 0)
        self.assertGreater(
            operation["upstreamDeliveryReceipt"]["deliveredFrameCount"],
            0,
        )
        self.assertTrue(
            operation["upstreamDeliveryReceipt"]["deliveryReceiptId"]
        )

        status, vitalserver_health = request_json(
            vitalserver_endpoint + "/healthz"
        )
        self.assertEqual(200, status, vitalserver_health)
        self.assertGreater(vitalserver_health["acceptedPacketCount"], 0)

        if approved_corpus is not None:
            for entry in approved_corpus.entries:
                assert_public_successful_replay(
                    self,
                    guest_endpoint,
                    entry.path.read_bytes(),
                    entry.path.name,
                    entry.format_version,
                    entry.minimum_graph_compatible_signal_count,
                )

        assert_public_typed_track_failure(
            self,
            guest_endpoint,
            no_graph_compatible_vital_source(),
            "no-graph",
            "no-vitalserver-graph-tracks",
        )
        assert_public_typed_track_failure(
            self,
            guest_endpoint,
            unknown_track_vital_source(),
            "unknown-track",
            "unsupported-track-type",
        )

        # Preserve the distinction between Runner send acceptance and
        # VitalServer delivery. Once the acknowledgement owner is unavailable,
        # the same valid source must become a typed upstream terminal failure,
        # never replay success.
        self.node_processes[0].close()
        upstream_failure_identity = uuid.uuid4().hex
        upstream_failure_replay_id = (
            "upstream-failure-replay-" + upstream_failure_identity
        )
        status, upstream_failure_admitted = request_json(
            guest_endpoint + "/v1/runtime/lab/replays",
            method="POST",
            payload={
                "schemaVersion": "v1",
                "requestId": (
                    "upstream-failure-request-" + upstream_failure_identity
                ),
                "replayId": upstream_failure_replay_id,
                "sourceReference": receipt["sourceReference"],
                "sourceSha256": source_sha256,
                "recorderGatewayRecorderCode": "LAB-UPSTREAM-FAILURE",
                "requestedAt": datetime.now(timezone.utc)
                .isoformat(timespec="microseconds")
                .replace("+00:00", "Z"),
            },
        )
        self.assertEqual(202, status, upstream_failure_admitted)
        deadline = time.monotonic() + 15
        upstream_failure_operation: dict = {}
        while time.monotonic() < deadline:
            status, read = request_json(
                guest_endpoint
                + "/v1/runtime/lab/replays/"
                + upstream_failure_replay_id
            )
            self.assertEqual(200, status, read)
            self.assertEqual("available", read["state"])
            upstream_failure_operation = read["value"]
            if upstream_failure_operation["state"] in {"succeeded", "failed"}:
                break
            time.sleep(0.05)
        gateway_process = self.node_processes[1].process
        gateway_exit = gateway_process.poll()
        gateway_stderr = ""
        if gateway_exit is not None and gateway_process.stderr is not None:
            gateway_stderr = gateway_process.stderr.read()
        self.assertIsNone(
            gateway_exit,
            "Recorder Gateway exited before terminal delivery evidence: "
            + gateway_stderr,
        )
        self.assertEqual(
            "failed",
            upstream_failure_operation.get("state"),
            upstream_failure_operation,
        )
        self.assertEqual(
            "upstream-delivery",
            upstream_failure_operation["failure"]["stage"],
        )
        self.assertEqual(
            "vitalserver-delivery-terminal-failure",
            upstream_failure_operation["failure"]["code"],
        )
        self.assertGreater(upstream_failure_operation["messagesSent"], 0)
        self.assertEqual(
            "sent",
            upstream_failure_operation["lastSendState"],
        )

    def test_guest_worker_persists_explicit_string_track_rejection(self) -> None:
        guest_port = free_port()
        guest_endpoint = f"http://127.0.0.1:{guest_port}"
        self.guest = RunningGuestRuntime(
            [
                str(self.guest_binary),
                *compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
                    listen_address=f"127.0.0.1:{guest_port}",
                    state_database_path=str(self.work / "string-reject-guest.sqlite"),
                    bootstrap_evidence_root_directory=str(
                        self.work / "string-reject-bootstrap-evidence"
                    ),
                    recorder_catalog_database_url=require_recorder_catalog_test_database_url(),
                    recorder_catalog_admission_bearer_token=self.catalog_token,
                    recorder_observation_max_report_age_seconds=300,
                    archive_source_admission_bearer_token=self.archive_token,
                    archive_artifact_object_root_directory=str(
                        self.work / "string-reject-archive-artifacts"
                    ),
                    archive_source_maximum_bytes=67108864,
                    lab_replay_source_object_root_directory=str(
                        self.work / "string-reject-replay-sources"
                    ),
                    lab_replay_source_maximum_bytes=67108864,
                    lab_replay_spool_root_directory=str(
                        self.work / "string-reject-replay-spools"
                    ),
                    lab_replay_string_track_policy="reject",
                    lab_replay_gap_policy="fail-frame",
                    lab_replay_frame_batch_size=1,
                    recorder_attribution_policy_kind="recorder-assignment-owner",
                    service_version="guest-replay-string-reject-acceptance",
                    instance_id="guest-replay-string-reject-acceptance",
                    archive_export_outcome_mode="succeed",
                    recorder_gateway_cold_path_source_endpoint=(
                        f"http://127.0.0.1:{free_port()}"
                    ),
                    lab_recorder_runner_endpoint=(
                        f"http://127.0.0.1:{free_port()}"
                    ),
                    external_upstream_outcome_mode="unsupported",
                    outbound_relay_outcome_mode="unsupported",
                    guest_node_id="guest-replay-string-reject",
                    time_authority_id="guest-replay-string-reject-time",
                    time_probe_outcome_mode="unsupported",
                    telemetry_collector_probe_outcome_mode="unsupported",
                    telemetry_export_outcome_mode="unavailable",
                ),
            ],
            guest_endpoint + "/v1/runtime/readiness",
        )
        assert_public_typed_track_failure(
            self,
            guest_endpoint,
            string_track_vital_source(),
            "string-track",
            "unsupported-string-track",
        )


if __name__ == "__main__":
    unittest.main()
