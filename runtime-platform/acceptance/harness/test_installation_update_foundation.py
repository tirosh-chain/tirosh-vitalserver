"""Black-box proof for the Host-owned installation-update foundation.

This is intentionally not a package-install proof. It proves both the
deterministic test bootstrapper and the signed-bundle path: C25 through C31
admission, durable handoff, restart recovery, and next-updater planning before
native macOS package activation is added.
"""

from __future__ import annotations

import json
import hashlib
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


def request_json(url: str, method: str = "GET", payload: dict | None = None) -> tuple[int, dict]:
    body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(url, data=body, method=method)
    request.add_header("Accept", "application/json")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def wait_for_host(url: str, process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr is not None else ""
            raise AssertionError("acceptance Host Agent exited early ({0}): {1}".format(process.returncode, stderr))
        try:
            status, value = request_json(url + "/v1/platform/installation")
            if status == 200 and value.get("state") == "available":
                return
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    raise AssertionError("acceptance Host Agent did not become reachable: {0}".format(url))


class RunningHost:
    def __init__(self, binary: Path, work: Path, handoff_evidence: Path, mode: str = "staged", update_arguments: list[str] | None = None) -> None:
        self.port = free_port()
        self.url = "http://127.0.0.1:{0}".format(self.port)
        arguments = [
            str(binary), "--listen", "127.0.0.1:{0}".format(self.port),
            "--state-db", str(work / "host.sqlite"),
            "--installation-id", "host-installation", "--product-version", "installation-update-acceptance",
            "--runtime-version", "installation-update-acceptance", "--data-directory", str(work / "data"),
            "--guest-runtime-control-endpoint-id", "guest-control", "--guest-runtime-control-http-scheme", "http",
            "--guest-runtime-control-http-host", "127.0.0.1", "--guest-runtime-control-http-port", "18443",
            "--provider-kind", "macos-virtualization", "--provider-id", "guest-vm",
            "--update-bootstrap-mode", mode,
        ]
        if mode != "verified-staged-bundle":
            arguments.extend(["--update-handoff-evidence", str(handoff_evidence)])
        if update_arguments:
            arguments.extend(update_arguments)
        self.process = subprocess.Popen(
            arguments,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        wait_for_host(self.url, self.process)

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


class InstallationUpdateFoundationAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = ContractRepository(ROOT)
        cls.contracts.load()
        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.temporary_directory.name)
        cls.host_binary = cls.work / "acceptance-host-agent"
        cls.updater_binary = cls.work / "host-updater"
        cls.release_composer_binary = cls.work / "release-composer"
        cls.build(ROOT / "services" / "host-agent", "./cmd/acceptance-host-agent", cls.host_binary)
        cls.build(ROOT / "services" / "host-updater", "./cmd/host-updater", cls.updater_binary)
        cls.build(ROOT / "tooling" / "release-composer", "./cmd/release-composer", cls.release_composer_binary)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def build(cls, directory: Path, package: str, output: Path) -> None:
        completed = subprocess.run([GO, "build", "-o", str(output), package], cwd=directory, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            raise AssertionError("build {0} failed:\n{1}\n{2}".format(package, completed.stdout, completed.stderr))

    def setUp(self) -> None:
        self.test_work = Path(tempfile.mkdtemp(dir=self.work, prefix="installation-update-"))
        self.handoff_evidence = self.test_work / "handoff.jsonl"
        self.hosts: list[RunningHost] = []

    def tearDown(self) -> None:
        for host in reversed(self.hosts):
            host.close()

    def start_host(self, mode: str = "staged") -> RunningHost:
        host = RunningHost(self.host_binary, self.test_work, self.handoff_evidence, mode)
        self.hosts.append(host)
        return host

    def start_verified_bundle_host(self, bundle_store: Path, staging_directory: Path, trust_store: Path) -> RunningHost:
        host = RunningHost(
            self.host_binary,
            self.test_work,
            self.handoff_evidence,
            "verified-staged-bundle",
            [
                "--update-bundle-store", str(bundle_store),
                "--update-staging-directory", str(staging_directory),
                "--update-trust-store", str(trust_store),
            ],
        )
        self.hosts.append(host)
        return host

    def handoffs(self) -> list[str]:
        if not self.handoff_evidence.exists():
            return []
        return [line for line in self.handoff_evidence.read_text(encoding="utf-8").splitlines() if line]

    @staticmethod
    def sha(character: str) -> str:
        return character * 64

    def command(self, request_id: str, revision: int, target: str = "0.2.0", specification_sha256: str | None = None, specification_size: int | None = None) -> dict:
        return {
            "schemaVersion": "v1",
            "requestId": request_id,
            "installationId": "host-installation",
            "expectedInstallationRevision": revision,
            "bundleReferenceId": "offline-bundle-" + target.replace(".", ""),
            "bootstrapEnvelope": {
                "schemaVersion": "v1", "id": "release-bootstrap-" + target.replace(".", ""),
                "productId": "vitalserver-runtime-platform",
                "target": {"platform": "macos", "architecture": "arm64"},
                "targetRelease": {"productVersion": target, "runtimeVersion": target},
                "layerOrder": ["guest-runtime", "container", "host-platform"],
                "nextUpdaterArtifact": {"id": "host-updater-" + target.replace(".", ""), "relativePath": "payload/host-updater", "sha256": self.sha("a"), "sizeBytes": 42, "mediaType": "application/octet-stream"},
                "specification": {"id": "product-update-spec-" + target.replace(".", ""), "relativePath": "payload/product-update.json", "sha256": specification_sha256 or self.sha("b"), "sizeBytes": specification_size or 91, "mediaType": "application/json"},
                "signature": {"algorithm": "ed25519", "keyId": "release-key-2026", "signedSha256": self.sha("c"), "value": "acceptance-signature"},
                "issuedAt": "2026-07-17T00:00:00Z",
            },
        }

    def specification(self, bootstrap_envelope_id: str) -> dict:
        return {
            "schemaVersion": "v1", "id": "product-update-020", "bootstrapEnvelopeId": bootstrap_envelope_id,
            "layerPlan": [
                {"layer": "guest-runtime", "dependsOn": [], "artifact": {"id": "guest-runtime-020", "relativePath": "payload/guest-runtime.tar", "sha256": self.sha("d"), "sizeBytes": 1, "mediaType": "application/x-tar"}, "rollback": {"state": "available", "artifact": {"id": "guest-runtime-010", "relativePath": "payload/guest-runtime-rollback.tar", "sha256": self.sha("e"), "sizeBytes": 1, "mediaType": "application/x-tar"}}},
                {"layer": "container", "dependsOn": ["guest-runtime"], "artifact": {"id": "container-020", "relativePath": "payload/container.tar", "sha256": self.sha("f"), "sizeBytes": 1, "mediaType": "application/x-tar"}, "rollback": {"state": "available", "artifact": {"id": "container-010", "relativePath": "payload/container-rollback.tar", "sha256": self.sha("1"), "sizeBytes": 1, "mediaType": "application/x-tar"}}},
                {"layer": "host-platform", "dependsOn": ["container"], "artifact": {"id": "host-platform-020", "relativePath": "payload/host-platform.pkg", "sha256": self.sha("2"), "sizeBytes": 1, "mediaType": "application/vnd.apple.installer+xml"}, "rollback": {"state": "unsupported", "reason": "requires separately verified platform rollback bundle"}},
            ],
        }

    def compose_verified_bundle(self) -> tuple[Path, Path, Path, dict]:
        bundle_store = self.test_work / "verified-bundles"
        staging_directory = self.test_work / "verified-staging"
        payload_directory = self.test_work / "release-payload"
        bundle_store.mkdir()
        staging_directory.mkdir()
        payload_directory.mkdir()
        bundle_id = "release-bundle-verified-020"
        specification = self.specification(bundle_id)
        (payload_directory / "host-updater").write_bytes(b"verified-next-updater")
        (payload_directory / "product-update.json").write_text(json.dumps(specification, separators=(",", ":")), encoding="utf-8")
        composition = {
            "schemaVersion": "v1", "bundleId": bundle_id, "productId": "vitalserver-runtime-platform",
            "target": {"platform": "macos", "architecture": "arm64"},
            "targetRelease": {"productVersion": "0.2.0", "runtimeVersion": "0.2.0"},
            "layerOrder": ["guest-runtime", "container", "host-platform"],
            "nextUpdater": {"id": "host-updater-verified-020", "relativePath": "payload/host-updater", "mediaType": "application/octet-stream"},
            "specification": {"id": "product-update-verified-020", "relativePath": "payload/product-update.json", "mediaType": "application/json"},
            "signingKeyId": "acceptance-rfc8032-key", "issuedAt": "2026-07-17T00:00:00Z",
        }
        composition_path = self.test_work / "release-composition.json"
        private_key_path = self.test_work / "acceptance-rfc8032-key.base64"
        trust_store_path = self.test_work / "release-trust-store.json"
        composition_path.write_text(json.dumps(composition, separators=(",", ":")), encoding="utf-8")
        # RFC 8032 test vector only; this is not a release trust key.
        private_key_path.write_text("nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2DXWpgBgrEKt9VL/tPJZAc6DuFy89qmIyWvAhpo9wdRGg==", encoding="utf-8")
        trust_store_path.write_text(json.dumps({"schemaVersion": "v1", "keys": [{"id": "acceptance-rfc8032-key", "algorithm": "ed25519", "publicKey": "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="}]}, separators=(",", ":")), encoding="utf-8")
        composed = subprocess.run(
            [str(self.release_composer_binary), "--composition", str(composition_path), "--payload-directory", str(payload_directory), "--private-key", str(private_key_path), "--output-directory", str(bundle_store)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, composed.returncode, composed.stderr)
        envelope = json.loads((bundle_store / bundle_id / "bootstrap-envelope.json").read_text(encoding="utf-8"))
        return bundle_store, staging_directory, trust_store_path, envelope

    def verified_command(self, request_id: str, revision: int, envelope: dict) -> dict:
        return {
            "schemaVersion": "v1", "requestId": request_id, "installationId": "host-installation",
            "expectedInstallationRevision": revision, "bundleReferenceId": envelope["id"],
            "bootstrapEnvelope": envelope,
        }

    def staged_invocation(self, journal: dict, specification: dict, *, digest_override: str | None = None) -> Path:
        stage = self.test_work / "next-updater" / journal["id"]
        payload = stage / "payload"
        payload.mkdir(parents=True, exist_ok=True)
        specification_bytes = json.dumps(specification, separators=(",", ":")).encode("utf-8")
        (payload / "product-update.json").write_bytes(specification_bytes)
        invocation = {
            "schemaVersion": "v1", "updateId": journal["id"], "requestId": journal["requestId"],
            "expectedHandoffJournalRevision": journal["journalRevision"], "bootstrapEnvelopeId": journal["bootstrapEnvelopeId"],
            "updateSpecificationSha256": digest_override or hashlib.sha256(specification_bytes).hexdigest(),
            "layerOrder": journal["layerOrder"], "specificationRelativePath": "payload/product-update.json",
        }
        self.assert_schema("staged-update-invocation.schema.json", invocation)
        invocation_path = stage / "invocation.json"
        invocation_path.write_text(json.dumps(invocation, separators=(",", ":")), encoding="utf-8")
        return invocation_path

    def report(self, journal: dict, *, state: str = "succeeded", out_of_order: bool = False, terminal_evidence_state: str = "failed") -> dict:
        order = list(journal["layerOrder"])
        if out_of_order:
            order[0] = "container"
        artifact_sha256 = {
            "guest-runtime": self.sha("d"),
            "container": self.sha("f"),
            "host-platform": self.sha("2"),
        }
        evidence = []
        for index, layer in enumerate(order):
            evidence.append({
                "layer": layer, "state": "succeeded", "artifactSha256": artifact_sha256.get(layer, self.sha("0")),
                "observedAt": "2026-07-17T00:01:{0:02d}Z".format(index),
                "evidence": {"kind": "update-layer-proof", "id": "proof-" + layer},
            })
        if state == "failed":
            evidence[-1]["state"] = terminal_evidence_state
            evidence[-1]["issue"] = {"code": "fixture-layer-" + terminal_evidence_state, "dependency": "fixture"}
            rollback = {"state": "succeeded", "observedAt": "2026-07-17T00:02:00Z", "evidence": {"kind": "rollback-proof", "id": "rollback-1"}}
            failure = {"code": "fixture-layer-" + terminal_evidence_state, "dependency": "fixture"}
        else:
            rollback = {"state": "not-required", "observedAt": "2026-07-17T00:02:00Z"}
            failure = None
        report = {
            "schemaVersion": "v1", "updateId": journal["id"], "requestId": journal["requestId"],
            "bootstrapEnvelopeId": journal["bootstrapEnvelopeId"],
            "updateSpecificationSha256": journal["updateSpecificationSha256"],
            "state": state, "startedAt": "2026-07-17T00:01:00Z", "finishedAt": "2026-07-17T00:02:00Z",
            "layerEvidence": evidence, "rollback": rollback,
        }
        if failure is not None:
            report["failure"] = failure
        return report

    def completion(self, journal: dict, **report_options: bool | str) -> dict:
        return {
            "schemaVersion": "v1", "updateId": journal["id"],
            "expectedJournalRevision": journal["journalRevision"],
            "report": self.report(journal, **report_options),
        }

    def assert_schema(self, schema: str, value: dict) -> None:
        self.assertEqual([], self.contracts.validate_instance(schema, value), value)

    def test_handoff_next_updater_plan_idempotent_completion_and_failed_order(self) -> None:
        host = self.start_host()
        status, installation_read = request_json(host.url + "/v1/platform/installation")
        self.assertEqual(200, status, installation_read)
        installation = installation_read["value"]
        specification = self.specification("release-bootstrap-020")
        specification_bytes = json.dumps(specification, separators=(",", ":")).encode("utf-8")
        command = self.command("update-apply-1", installation["resourceRevision"], specification_sha256=hashlib.sha256(specification_bytes).hexdigest(), specification_size=len(specification_bytes))
        self.assert_schema("host-update-command.schema.json", command)

        status, admitted = request_json(host.url + "/v1/platform/updates", "POST", command)
        self.assertEqual(202, status, admitted)
        self.assert_schema("operation.schema.json", admitted["operation"])
        self.assert_schema("host-update-journal.schema.json", admitted["journal"])
        journal = admitted["journal"]
        self.assertEqual("handoff-pending", journal["state"])
        self.assertEqual(1, len(self.handoffs()), self.handoffs())

        status, replayed = request_json(host.url + "/v1/platform/updates", "POST", command)
        self.assertEqual(202, status, replayed)
        self.assertEqual(journal["id"], replayed["journal"]["id"])
        self.assertEqual(1, len(self.handoffs()), self.handoffs())

        specification["bootstrapEnvelopeId"] = journal["bootstrapEnvelopeId"]
        self.assert_schema("product-update-specification.schema.json", specification)
        invocation_path = self.staged_invocation(journal, specification)
        planned = subprocess.run(
            [str(self.updater_binary), "--mode", "plan", "--invocation", str(invocation_path)], capture_output=True, text=True, check=False,
        )
        self.assertEqual(0, planned.returncode, planned.stderr)
        self.assertEqual(journal["layerOrder"], json.loads(planned.stdout)["layerPlan"] and [item["layer"] for item in json.loads(planned.stdout)["layerPlan"]])

        report_path = self.test_work / "next-updater-report.json"
        report = self.report(journal)
        self.assert_schema("update-execution-report.schema.json", report)
        report_path.write_text(json.dumps(report, separators=(",", ":")), encoding="utf-8")
        completed_by_updater = subprocess.run(
            [str(self.updater_binary), "--mode", "complete", "--invocation", str(invocation_path), "--report", str(report_path), "--completion-endpoint", host.url],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, completed_by_updater.returncode, completed_by_updater.stderr)
        self.assert_schema("update-completion-command.schema.json", json.loads(completed_by_updater.stdout))

        status, completed = request_json(host.url + "/v1/platform/updates/{0}".format(journal["id"]))
        self.assertEqual(200, status, completed)
        self.assertEqual("succeeded", completed["value"]["state"])
        status, installed = request_json(host.url + "/v1/platform/installation")
        self.assertEqual(2, installed["value"]["resourceRevision"])
        self.assertEqual("0.2.0", installed["value"]["release"]["productVersion"])

        incompatible_specification = dict(specification)
        incompatible_specification["bootstrapEnvelopeId"] = "different-bootstrap-envelope"
        incompatible_path = self.staged_invocation(journal, incompatible_specification)
        incompatible = subprocess.run(
            [str(self.updater_binary), "--mode", "plan", "--invocation", str(incompatible_path)], capture_output=True, text=True, check=False,
        )
        self.assertNotEqual(0, incompatible.returncode)
        self.assertIn("does not match the bootstrap envelope", incompatible.stderr)

        completion = self.completion(journal)
        self.assert_schema("update-completion-command.schema.json", completion)
        status, completed_replay = request_json(host.url + "/v1/platform/updates/{0}:complete".format(journal["id"]), "POST", completion)
        self.assertEqual(202, status, completed_replay)
        self.assertEqual(completed["value"]["journalRevision"], completed_replay["journal"]["journalRevision"])

        failed_command = self.command("update-order", 2, "0.3.0")
        status, failed_admission = request_json(host.url + "/v1/platform/updates", "POST", failed_command)
        self.assertEqual(202, status, failed_admission)
        invalid_completion = self.completion(failed_admission["journal"], out_of_order=True)
        status, failed = request_json(host.url + "/v1/platform/updates/{0}:complete".format(failed_admission["journal"]["id"]), "POST", invalid_completion)
        self.assertEqual(202, status, failed)
        self.assertEqual("failed", failed["journal"]["state"])
        self.assertEqual("update-execution-report-invalid", failed["journal"]["failure"]["code"])
        status, unchanged = request_json(host.url + "/v1/platform/installation")
        self.assertEqual(2, unchanged["value"]["resourceRevision"])
        self.assertEqual("0.2.0", unchanged["value"]["release"]["productVersion"])

        unsupported_command = self.command("update-unsupported", 2, "0.3.0")
        status, unsupported_admission = request_json(host.url + "/v1/platform/updates", "POST", unsupported_command)
        self.assertEqual(202, status, unsupported_admission)
        unsupported_completion = self.completion(unsupported_admission["journal"], state="failed", terminal_evidence_state="unsupported")
        status, unsupported = request_json(host.url + "/v1/platform/updates/{0}:complete".format(unsupported_admission["journal"]["id"]), "POST", unsupported_completion)
        self.assertEqual(202, status, unsupported)
        self.assertEqual("failed", unsupported["journal"]["state"])
        self.assertEqual("unsupported", unsupported["journal"]["executionReport"]["layerEvidence"][-1]["state"])
        self.assertEqual("fixture-layer-unsupported", unsupported["journal"]["failure"]["code"])
        status, still_unchanged = request_json(host.url + "/v1/platform/installation")
        self.assertEqual(2, still_unchanged["value"]["resourceRevision"])

    def test_restart_reissues_only_durable_handoff(self) -> None:
        initial = self.start_host()
        status, installation = request_json(initial.url + "/v1/platform/installation")
        self.assertEqual(200, status, installation)
        status, admitted = request_json(initial.url + "/v1/platform/updates", "POST", self.command("update-recovery", installation["value"]["resourceRevision"]))
        self.assertEqual(202, status, admitted)
        journal = admitted["journal"]
        self.assertEqual("handoff-pending", journal["state"])
        self.assertEqual([journal["id"]], self.handoffs())
        initial.close()

        restarted = self.start_host()
        self.assertEqual([journal["id"], journal["id"]], self.handoffs())
        status, recovered = request_json(restarted.url + "/v1/platform/updates/" + journal["id"])
        self.assertEqual(200, status, recovered)
        self.assert_schema("read-result.schema.json", recovered)
        self.assertEqual("handoff-pending", recovered["value"]["state"])
        self.assertEqual(journal["journalRevision"], recovered["value"]["journalRevision"])

    def test_unavailable_bootstrap_is_terminal_and_never_handed_off(self) -> None:
        host = self.start_host("unavailable")
        status, installation = request_json(host.url + "/v1/platform/installation")
        self.assertEqual(200, status, installation)
        status, outcome = request_json(host.url + "/v1/platform/updates", "POST", self.command("update-unavailable", installation["value"]["resourceRevision"]))
        self.assertEqual(202, status, outcome)
        self.assertEqual("failed", outcome["operation"]["state"])
        self.assertEqual("failed", outcome["journal"]["state"])
        self.assertEqual("acceptance-update-bootstrap-unavailable", outcome["journal"]["failure"]["code"])
        self.assertEqual([], self.handoffs())
        status, unchanged = request_json(host.url + "/v1/platform/installation")
        self.assertEqual(1, unchanged["value"]["resourceRevision"])

    def test_signed_release_bundle_stages_original_invocation_and_queues_handoff_reference(self) -> None:
        bundle_store, staging_directory, trust_store, envelope = self.compose_verified_bundle()
        host = self.start_verified_bundle_host(bundle_store, staging_directory, trust_store)
        status, installation = request_json(host.url + "/v1/platform/installation")
        self.assertEqual(200, status, installation)
        command = self.verified_command("verified-bundle-admission", installation["value"]["resourceRevision"], envelope)
        self.assert_schema("host-update-command.schema.json", command)
        status, admitted = request_json(host.url + "/v1/platform/updates", "POST", command)
        self.assertEqual(202, status, admitted)
        journal = admitted["journal"]
        self.assertEqual("handoff-pending", journal["state"])
        handoff_path = staging_directory / "handoff-queue" / (journal["id"] + ".json")
        handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
        self.assert_schema("staged-update-handoff.schema.json", handoff)
        self.assertEqual(journal["id"], handoff["updateId"])
        invocation_path = staging_directory / handoff["invocationRelativePath"]
        invocation = json.loads(invocation_path.read_text(encoding="utf-8"))
        self.assert_schema("staged-update-invocation.schema.json", invocation)
        self.assertEqual(journal["id"], invocation["updateId"])
        self.assertEqual(journal["requestId"], invocation["requestId"])
        self.assertEqual(journal["journalRevision"], invocation["expectedHandoffJournalRevision"])
        planned = subprocess.run([str(self.updater_binary), "--mode", "plan", "--invocation", str(invocation_path)], capture_output=True, text=True, check=False)
        self.assertEqual(0, planned.returncode, planned.stderr)
        self.assertEqual(journal["layerOrder"], [entry["layer"] for entry in json.loads(planned.stdout)["layerPlan"]])
        queued_bytes = handoff_path.read_bytes()
        invocation_bytes = invocation_path.read_bytes()
        host.close()
        restarted = self.start_verified_bundle_host(bundle_store, staging_directory, trust_store)
        self.assertEqual(queued_bytes, handoff_path.read_bytes())
        self.assertEqual(invocation_bytes, invocation_path.read_bytes())
        status, recovered = request_json(restarted.url + "/v1/platform/updates/" + journal["id"])
        self.assertEqual(200, status, recovered)
        self.assertEqual("handoff-pending", recovered["value"]["state"])


if __name__ == "__main__":
    unittest.main()
