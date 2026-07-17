"""Black-box Lab, Archive, and deletion proof through Guest Runtime public HTTP contracts."""

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
from tooling.contracts import ContractRepository


ROOT = Path(__file__).resolve().parents[2]
GO = os.environ.get("RUNTIME_PLATFORM_GO", "go")
PROVIDER = {
    "kind": "lab-simulation-archive",
    "id": "bundled-archive",
    "capabilityRevision": 1,
}


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


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


class RunningGuest:
    def __init__(self, binary: Path, parent: Path, mode: str) -> None:
        self.work = Path(tempfile.mkdtemp(dir=parent))
        self.port = free_port()
        self.url = "http://127.0.0.1:{0}".format(self.port)
        self.process = subprocess.Popen(
            [
                str(binary),
                *compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
                    listen_address="127.0.0.1:{0}".format(self.port), state_database_path=str(self.work / "guest.sqlite"), service_version="lab-archive-acceptance", instance_id="guest-lab-archive-acceptance",
                    archive_export_outcome_mode=mode, external_upstream_outcome_mode="unsupported", outbound_relay_outcome_mode="unsupported",
                    guest_node_id="guest-lab-archive-acceptance", time_authority_id="guest-time-lab-archive-acceptance", time_probe_outcome_mode="unsupported",
                    telemetry_collector_probe_outcome_mode="unsupported", telemetry_export_outcome_mode="unavailable",
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

    def start(self, mode: str = "succeed") -> RunningGuest:
        runtime = RunningGuest(self.binary, self.work, mode)
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

    def create_stopped_session(self, runtime: RunningGuest, count: int = 2) -> tuple[dict, list[dict]]:
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
        self.assertFalse(any(item["kind"] == "artifact-manifest" for item in stopped.get("evidenceReferences", [])), stopped)
        session = self.read(runtime, "/v1/runtime/lab/sessions/{0}".format(session["id"]))["value"]
        self.assertEqual("stopped", session["state"], session)
        recorders = self.read(runtime, "/v1/runtime/lab/recorders")["value"]
        self.assertTrue(all(item["executionState"] == "stopped" for item in recorders), recorders)
        return session, recorders

    def export(self, runtime: RunningGuest, recorder: dict, request_id: str) -> dict:
        operation = self.post(
            runtime,
            "/v1/runtime/archive/exports",
            {
                "schemaVersion": "v1",
                "requestId": request_id,
                "virtualRecorderId": recorder["id"],
                "expectedResourceRevision": recorder["resourceRevision"],
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
        session, recorders = self.create_stopped_session(runtime, 2)

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

    def test_known_upload_and_index_failures_leave_lab_stopped_and_receipts_explicit(self) -> None:
        for mode, failed_step in (("upload-failed", "upload"), ("index-failed", "indexing")):
            with self.subTest(mode=mode):
                runtime = self.start(mode)
                session, recorders = self.create_stopped_session(runtime, 1)
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
        session, recorders = self.create_stopped_session(runtime, 1)
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
