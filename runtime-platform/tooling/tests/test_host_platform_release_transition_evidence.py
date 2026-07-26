"""Tests for C24 transition evidence correlation without an OS fallback."""

from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from contextlib import redirect_stdout

from tooling import host_platform_release_transition_evidence as transition_evidence


class HostPlatformReleaseTransitionEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]

    def write_document(self, directory: Path, name: str, document: dict) -> Path:
        path = directory / name
        path.write_text(json.dumps(document), encoding="utf-8")
        return path.resolve()

    def journal(self, *, state: str = "succeeded", report_state: str = "succeeded") -> dict:
        report = {
            "schemaVersion": "v1",
            "updateId": "update-020",
            "requestId": "request-020",
            "bootstrapEnvelopeId": "bootstrap-020",
            "updateSpecificationSha256": "b" * 64,
            "state": report_state,
            "startedAt": "2026-07-20T00:00:00Z",
            "finishedAt": "2026-07-20T00:01:00Z",
            "layerEvidence": [
                {
                    "layer": "host-platform",
                    "state": "succeeded",
                    "artifactSha256": "a" * 64,
                    "observedAt": "2026-07-20T00:00:30Z",
                    "evidence": {"kind": "host-platform-operation", "id": "update-020-apply"},
                }
            ],
            "rollback": {"state": "not-required", "observedAt": "2026-07-20T00:01:00Z"},
        }
        if report_state == "failed":
            report["rollback"] = {
                "state": "succeeded",
                "observedAt": "2026-07-20T00:01:00Z",
                "evidence": {"kind": "staged-update-rollback", "id": "update-020:rollback"},
            }
            report["failure"] = {"code": "fixture-failed", "dependency": "fixture"}
        journal = json.loads(
            (
                self.root
                / "contracts"
                / "examples"
                / "v1"
                / "valid"
                / "host-update-journal-handoff-pending.json"
            ).read_text(encoding="utf-8")
        )
        journal.update(
            {
                "id": "update-020",
                "operationId": "operation-020",
                "requestId": "request-020",
                "bootstrapEnvelopeId": "bootstrap-020",
                "updateSpecificationSha256": "b" * 64,
                "targetRelease": {"productVersion": "0.2.0-dev", "runtimeVersion": "0.2.0"},
                "layerOrder": ["host-platform"],
                "state": state,
                "executionReport": report,
                "updatedAt": "2026-07-20T00:01:00Z",
            }
        )
        journal["bootstrapEnvelope"].update(
            {
                "id": "bootstrap-020",
                "target": {"platform": "macos", "architecture": "arm64"},
                "targetRelease": {"productVersion": "0.2.0-dev", "runtimeVersion": "0.2.0"},
                "layerOrder": ["host-platform"],
            }
        )
        journal["bootstrapEnvelope"]["specification"]["sha256"] = "b" * 64
        journal["bootstrapReceipt"].update(
            {
                "updateId": "update-020",
                "requestId": "request-020",
                "bootstrapEnvelopeId": "bootstrap-020",
            }
        )
        if state == "failed":
            journal["failure"] = {"code": "fixture-failed", "dependency": "fixture"}
        return journal

    def receipt(self, operation: str) -> dict:
        return {
            "schemaVersion": "v1",
            "updateId": "update-020",
            "layer": "host-platform",
            "effectExecutorId": "host-platform-executor",
            "operation": operation,
            "artifactSha256": "a" * 64,
            "state": "succeeded",
            "observedAt": "2026-07-20T00:00:30Z",
            "evidence": {"kind": "host-platform-operation", "id": "update-020-apply"},
        }

    def plans_path(self) -> Path:
        return (self.root / "product/delivery/release-delivery-plans.v1.json").resolve()

    def host_installation_manifest(self) -> dict:
        return json.loads(
            (
                self.root
                / "contracts"
                / "examples"
                / "v1"
                / "valid"
                / "host-product-installation-manifest.json"
            ).read_text(encoding="utf-8")
        )

    def host_installation_footprint(self, manifest: dict) -> dict:
        transaction_store = next(
            store for store in manifest["mutableStores"] if store["id"] == "installation-manager-journal"
        )
        return {
            "schemaVersion": "v1",
            "installationId": manifest["installationId"],
            "expectedReleaseId": manifest["release"]["id"],
            "platform": manifest["platform"],
            "observedAt": "2026-07-20T00:02:00Z",
            "packageReceipt": {
                "state": "installed",
                "identifier": manifest["package"]["identifier"],
                "productVersion": manifest["package"]["productVersion"],
            },
            "releaseCatalog": {
                "state": "only-expected-release",
                "releaseCatalogPath": manifest["immutablePayload"]["releaseCatalogPath"],
                "releaseIds": [manifest["release"]["id"]],
            },
            "immutableRelease": {
                "state": "matching",
                "releaseRootPath": manifest["immutablePayload"]["releaseRootPath"],
            },
            "activation": {
                "state": "points-to-expected-release",
                "currentReleaseLinkPath": manifest["activation"]["currentReleaseLinkPath"],
                "observedTargetPath": manifest["activation"]["expectedReleaseRootPath"],
            },
            "operatorApplication": {
                "state": "matching",
                "applicationBundlePath": manifest["operatorInterface"][
                    "applicationBundlePath"
                ],
            },
            "requiredServices": [
                {
                    "role": service["role"],
                    "name": service["name"],
                    "state": "registered",
                    "definitionState": "matching",
                }
                for service in manifest["requiredServices"]
            ],
            "mutableStores": [
                {"id": store["id"], "state": "compatible"}
                for store in manifest["mutableStores"]
            ],
            "installationTransaction": {
                "state": "completed",
                "journalPath": transaction_store["path"] + "/current-transaction.json",
                "receiptPath": transaction_store["path"] + "/latest-installation-receipt.json",
            },
        }

    def write_host_installation_inputs(self, directory: Path) -> tuple[Path, Path]:
        manifest = self.host_installation_manifest()
        return (
            self.write_document(directory, "installation-manifest.json", manifest),
            self.write_document(directory, "installation-footprint.json", self.host_installation_footprint(manifest)),
        )

    def test_successful_update_binds_c29_c28_c55_and_c23(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path, footprint_path = self.write_host_installation_inputs(root)
            evidence = transition_evidence.inspect_host_platform_update_transition(
                self.plans_path(),
                "macos-runtime-platform-release",
                self.write_document(root, "journal.json", self.journal()),
                self.write_document(root, "receipt.json", self.receipt("apply")),
                manifest_path,
                footprint_path,
            )
            output_path, digest = transition_evidence.write_new_release_transition_evidence(
                (root / "update-evidence.json").resolve(), evidence
            )

            document = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual("update", document["stage"])
            self.assertEqual("macos-runtime-platform-release", document["releaseDeliveryPlanId"])
            self.assertEqual("0.2.0-dev", document["targetProductVersion"])
            self.assertEqual(hashlib.sha256(output_path.read_bytes()).hexdigest(), digest)
            self.assertEqual(4, len(document["observedInputs"]))
            self.assertEqual("runtime-platform-0.2.0-dev-build-001", document["observedHostInstallation"]["releaseId"])

    def test_update_rejects_a_c55_receipt_for_a_different_c28_evidence_reference(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path, footprint_path = self.write_host_installation_inputs(root)
            receipt = self.receipt("apply")
            receipt["evidence"] = {"kind": "other", "id": "other"}
            with self.assertRaisesRegex(
                transition_evidence.HostPlatformReleaseTransitionEvidenceError,
                "does not match C28",
            ):
                transition_evidence.inspect_host_platform_update_transition(
                    self.plans_path(),
                    "macos-runtime-platform-release",
                    self.write_document(root, "journal.json", self.journal()),
                    self.write_document(root, "receipt.json", receipt),
                    manifest_path,
                    footprint_path,
                )

    def test_update_rejects_a_source_document_that_does_not_satisfy_c29(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path, footprint_path = self.write_host_installation_inputs(root)
            journal = self.journal()
            del journal["operationId"]
            with self.assertRaisesRegex(
                transition_evidence.HostPlatformReleaseTransitionEvidenceError,
                "violates host-update-journal.schema.json",
            ):
                transition_evidence.inspect_host_platform_update_transition(
                    self.plans_path(),
                    "macos-runtime-platform-release",
                    self.write_document(root, "journal.json", journal),
                    self.write_document(root, "receipt.json", self.receipt("apply")),
                    manifest_path,
                    footprint_path,
                )

    def test_rollback_requires_a_failed_update_and_explicit_c28_rollback(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path, footprint_path = self.write_host_installation_inputs(root)
            receipt = self.receipt("rollback")
            receipt["evidence"] = {"kind": "host-platform-operation", "id": "update-020-rollback"}
            evidence = transition_evidence.inspect_host_platform_rollback_transition(
                self.plans_path(),
                "macos-runtime-platform-release",
                self.write_document(root, "journal.json", self.journal(state="failed", report_state="failed")),
                self.write_document(root, "receipt.json", receipt),
                manifest_path,
                footprint_path,
            )

            self.assertEqual("rollback", evidence.stage)
            self.assertEqual(
                {"kind": "staged-update-rollback", "id": "update-020:rollback"},
                evidence.rollback_evidence,
            )

    def test_rollback_rejects_a_successful_update(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path, footprint_path = self.write_host_installation_inputs(root)
            with self.assertRaisesRegex(
                transition_evidence.HostPlatformReleaseTransitionEvidenceError,
                "requires failed C29",
            ):
                transition_evidence.inspect_host_platform_rollback_transition(
                    self.plans_path(),
                    "macos-runtime-platform-release",
                    self.write_document(root, "journal.json", self.journal()),
                    self.write_document(root, "receipt.json", self.receipt("rollback")),
                    manifest_path,
                    footprint_path,
                )

    def test_cli_writes_new_update_evidence_without_editing_any_c24_proof(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = (root / "transition.json").resolve()
            manifest_path, footprint_path = self.write_host_installation_inputs(root)
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                exit_code = transition_evidence.main(
                    [
                        "update",
                        "--release-delivery-plans-document", str(self.plans_path()),
                        "--release-delivery-plan-id", "macos-runtime-platform-release",
                        "--host-update-journal", str(self.write_document(root, "journal.json", self.journal())),
                        "--host-platform-effect-receipt", str(self.write_document(root, "receipt.json", self.receipt("apply"))),
                        "--host-installation-manifest", str(manifest_path),
                        "--host-installation-footprint", str(footprint_path),
                        "--output", str(output),
                    ]
                )

            self.assertEqual(0, exit_code)
            self.assertTrue(output.is_file())
            self.assertEqual(str(output), json.loads(stdout.getvalue())["output"])

    def test_update_rejects_c49_that_does_not_prove_current_c48_activation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.host_installation_manifest()
            footprint = self.host_installation_footprint(manifest)
            footprint["activation"]["state"] = "points-to-other-release"
            with self.assertRaisesRegex(
                transition_evidence.HostPlatformReleaseTransitionEvidenceError,
                "does not point to the expected C48 release",
            ):
                transition_evidence.inspect_host_platform_update_transition(
                    self.plans_path(),
                    "macos-runtime-platform-release",
                    self.write_document(root, "journal.json", self.journal()),
                    self.write_document(root, "receipt.json", self.receipt("apply")),
                    self.write_document(root, "installation-manifest.json", manifest),
                    self.write_document(root, "installation-footprint.json", footprint),
                )

    def test_update_rejects_c48_product_version_other_than_the_selected_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.host_installation_manifest()
            manifest["release"]["productVersion"] = "0.1.0"
            manifest["package"]["productVersion"] = "0.1.0"
            footprint = self.host_installation_footprint(manifest)
            with self.assertRaisesRegex(
                transition_evidence.HostPlatformReleaseTransitionEvidenceError,
                "observed product version does not match",
            ):
                transition_evidence.inspect_host_platform_update_transition(
                    self.plans_path(),
                    "macos-runtime-platform-release",
                    self.write_document(root, "journal.json", self.journal()),
                    self.write_document(root, "receipt.json", self.receipt("apply")),
                    self.write_document(root, "installation-manifest.json", manifest),
                    self.write_document(root, "installation-footprint.json", footprint),
                )


if __name__ == "__main__":
    unittest.main()
