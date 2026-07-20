"""Cross-platform delivery-proof and source-inventory behavior."""

from __future__ import annotations

import json
import io
import shutil
import tempfile
import unittest
from unittest import mock
from pathlib import Path

from tooling import (
    generate_source_inventory_sbom,
    release_delivery_proof_attachment,
    verify_delivery_proofs,
)


class DeliveryProofTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]

    def test_pending_clean_host_proofs_are_explicit_and_structurally_valid(self) -> None:
        findings, pending = verify_delivery_proofs.validate(self.root)
        self.assertEqual([], findings)
        self.assertEqual(24, len(pending))
        self.assertTrue(any("windows-runtime-platform-release/clean-install=pending" == value for value in pending))

    def test_release_ready_gate_refuses_pending_evidence(self) -> None:
        findings, pending = verify_delivery_proofs.validate(self.root)
        release_ready_findings = findings + [f"release proof is not verified: {label}" for label in pending]
        self.assertTrue(release_ready_findings)
        self.assertIn("release proof is not verified: windows-runtime-platform-release/clean-install=pending", release_ready_findings)

    def test_c74_review_binds_the_exact_candidate_and_only_its_reviewed_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = Path(temporary_directory)
            source_proofs_path = temporary_root / "source-release-delivery-proofs.v1.json"
            source_proofs_path.write_bytes(
                (self.root / "product" / "delivery" / "release-delivery-proofs.v1.json").read_bytes()
            )
            artifact_evidence = temporary_root / "artifact-integrity.json"
            artifact_evidence.write_text('{"artifact":"reviewed"}\n', encoding="utf-8")
            source_proofs = json.loads(source_proofs_path.read_text(encoding="utf-8"))
            artifact_proof = next(
                proof
                for proof in source_proofs["proofs"]
                if proof["planId"] == "macos-runtime-platform-release"
                and proof["stage"] == "artifact-integrity"
            )
            artifact_proof.pop("issue")
            artifact_proof.update(
                {
                    "status": "verified",
                    "runner": {"kind": "macos-clean-host", "id": "macos-clean-host-01"},
                    "evidence": {
                        "uri": artifact_evidence.as_uri(),
                        "sha256": release_delivery_proof_attachment._sha256_file(artifact_evidence),
                    },
                    "observedInstallerArtifact": {
                        "kind": "pkg",
                        "fileName": "VitalServerRuntimePlatform-0.2.0-dev.pkg",
                        "productVersion": "0.2.0-dev",
                        "sha256": "a" * 64,
                        "observedAt": "2026-07-20T08:00:00Z",
                    },
                }
            )
            fragment_path = temporary_root / "artifact-integrity-fragment.json"
            fragment_path.write_text(
                json.dumps({"schemaVersion": "v1", "proofs": [artifact_proof]}),
                encoding="utf-8",
            )
            output_directory = temporary_root / "reviewed-candidate"
            release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
                release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentRequest(
                    contract_root=self.root,
                    release_delivery_plans_document=(self.root / "product" / "delivery" / "release-delivery-plans.v1.json").resolve(),
                    source_proof_set=source_proofs_path.resolve(),
                    proof_fragments=(fragment_path.resolve(),),
                    reviewed_evidence_materials=(
                        release_delivery_proof_attachment.ReviewedEvidenceMaterial(
                            uri=artifact_evidence.as_uri(), path=artifact_evidence.resolve()
                        ),
                    ),
                    output_directory=output_directory.resolve(),
                    review_id="macos-artifact-review",
                    reviewer_id="release-operator",
                    reviewed_at="2026-07-20T08:00:00Z",
                )
            )

            findings, pending = verify_delivery_proofs.validate_reviewed_candidate_document_paths(
                self.root,
                (self.root / "product" / "delivery" / "release-delivery-plans.v1.json").resolve(),
                source_proofs_path.resolve(),
                output_directory / "release-delivery-proofs.v1.json",
                output_directory / "release-delivery-proof-attachment-review.v1.json",
            )

            self.assertEqual([], findings)
            self.assertIn("windows-runtime-platform-release/clean-install=pending", pending)

            candidate_path = output_directory / "release-delivery-proofs.v1.json"
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            unrelated_proof = next(
                proof
                for proof in candidate["proofs"]
                if proof["planId"] == "linux-runtime-platform-release"
                and proof["stage"] == "artifact-integrity"
            )
            unrelated_proof["issue"]["message"] = "candidate bytes were altered after review"
            candidate_path.write_text(json.dumps(candidate), encoding="utf-8")

            findings, _ = verify_delivery_proofs.validate_reviewed_candidate_document_paths(
                self.root,
                (self.root / "product" / "delivery" / "release-delivery-plans.v1.json").resolve(),
                source_proofs_path.resolve(),
                candidate_path,
                output_directory / "release-delivery-proof-attachment-review.v1.json",
            )

            self.assertIn("C74 output proof-set SHA-256 does not match the selected C24 candidate", findings)

    def test_release_ready_requires_one_review_directly_from_canonical_c24_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = Path(temporary_directory)
            source_proofs_path = temporary_root / "intermediate-candidate.json"
            source_proofs_path.write_bytes(
                (self.root / "product" / "delivery" / "release-delivery-proofs.v1.json").read_bytes()
            )
            evidence = temporary_root / "artifact-integrity.json"
            evidence.write_text('{"artifact":"reviewed"}\n', encoding="utf-8")
            source_proofs = json.loads(source_proofs_path.read_text(encoding="utf-8"))
            artifact_proof = next(
                proof
                for proof in source_proofs["proofs"]
                if proof["planId"] == "macos-runtime-platform-release"
                and proof["stage"] == "artifact-integrity"
            )
            artifact_proof.pop("issue")
            artifact_proof.update(
                {
                    "status": "verified",
                    "runner": {"kind": "macos-clean-host", "id": "macos-clean-host-01"},
                    "evidence": {
                        "uri": evidence.as_uri(),
                        "sha256": release_delivery_proof_attachment._sha256_file(evidence),
                    },
                    "observedInstallerArtifact": {
                        "kind": "pkg",
                        "fileName": "VitalServerRuntimePlatform-0.2.0-dev.pkg",
                        "productVersion": "0.2.0-dev",
                        "sha256": "a" * 64,
                        "observedAt": "2026-07-20T08:00:00Z",
                    },
                }
            )
            fragment_path = temporary_root / "artifact-integrity-fragment.json"
            fragment_path.write_text(
                json.dumps({"schemaVersion": "v1", "proofs": [artifact_proof]}),
                encoding="utf-8",
            )
            output_directory = temporary_root / "reviewed-candidate"
            release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
                release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentRequest(
                    contract_root=self.root,
                    release_delivery_plans_document=(self.root / "product" / "delivery" / "release-delivery-plans.v1.json").resolve(),
                    source_proof_set=source_proofs_path.resolve(),
                    proof_fragments=(fragment_path.resolve(),),
                    reviewed_evidence_materials=(
                        release_delivery_proof_attachment.ReviewedEvidenceMaterial(
                            uri=evidence.as_uri(), path=evidence.resolve()
                        ),
                    ),
                    output_directory=output_directory.resolve(),
                    review_id="intermediate-candidate-review",
                    reviewer_id="release-operator",
                    reviewed_at="2026-07-20T08:00:00Z",
                )
            )

            output = io.StringIO()
            with mock.patch("sys.stdout", output):
                result = verify_delivery_proofs.main(
                    [
                        "--root",
                        str(self.root),
                        "--release-delivery-plans-document",
                        str(self.root / "product" / "delivery" / "release-delivery-plans.v1.json"),
                        "--source-release-delivery-proof-set-document",
                        str(source_proofs_path),
                        "--release-delivery-proof-set-document",
                        str(output_directory / "release-delivery-proofs.v1.json"),
                        "--release-delivery-proof-attachment-review-document",
                        str(output_directory / "release-delivery-proof-attachment-review.v1.json"),
                        "--require-verified",
                    ]
                )

            self.assertEqual(1, result)
            self.assertIn(
                "release-ready C74 review must bind the checked-in canonical C24 source proof set",
                output.getvalue(),
            )

    def test_checked_in_source_inventory_is_generated_from_policy(self) -> None:
        expected = generate_source_inventory_sbom.canonical(generate_source_inventory_sbom.build_document(self.root))
        actual = (self.root / "product" / "delivery" / "sbom" / "runtime-platform-source-inventory.spdx.json").read_text(encoding="utf-8")
        self.assertEqual(expected, actual)

    def test_verified_service_registration_proof_must_match_each_c23_host_service_registration(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            isolated_root = Path(temporary_directory)
            shutil.copytree(self.root / "contracts", isolated_root / "contracts")
            shutil.copytree(
                self.root / "product" / "delivery",
                isolated_root / "product" / "delivery",
            )
            plans_path = isolated_root / "product" / "delivery" / "release-delivery-plans.v1.json"
            proofs_path = isolated_root / "product" / "delivery" / "release-delivery-proofs.v1.json"
            plans = json.loads(plans_path.read_text(encoding="utf-8"))
            proofs = json.loads(proofs_path.read_text(encoding="utf-8"))
            macos_plan = next(
                plan
                for plan in plans["plans"]
                if plan["id"] == "macos-runtime-platform-release"
            )
            service_registration_proof = next(
                proof
                for proof in proofs["proofs"]
                if proof["planId"] == "macos-runtime-platform-release"
                and proof["stage"] == "service-registration"
            )
            service_registration_proof.pop("issue")
            service_registration_proof.update(
                {
                    "status": "verified",
                    "runner": {
                        "kind": "macos-clean-host",
                        "id": "macos-clean-host-01",
                    },
                    "evidence": {
                        "uri": "file:///evidence/macos-service-registration.json",
                        "sha256": "a" * 64,
                    },
                    "observedInstallerArtifact": {
                        "kind": macos_plan["intendedInstallerArtifact"]["kind"],
                        "fileName": macos_plan["intendedInstallerArtifact"][
                            "expectedName"
                        ],
                        "productVersion": macos_plan["productVersion"],
                        "sha256": "b" * 64,
                        "observedAt": "2026-07-18T00:00:00Z",
                    },
                    "observedHostServiceRegistrations": [
                        {
                            **registration,
                            "registrationState": "registered",
                            "observedAt": "2026-07-18T00:00:00Z",
                        }
                        for registration in macos_plan[
                            "requiredHostServiceRegistrations"
                        ]
                    ],
                }
            )
            proofs_path.write_text(json.dumps(proofs), encoding="utf-8")

            findings, _ = verify_delivery_proofs.validate(isolated_root)

            self.assertEqual([], findings)

            service_registration_proof["observedHostServiceRegistrations"][1][
                "name"
            ] = "com.tirosh.other.host-edge-proxy"
            proofs_path.write_text(json.dumps(proofs), encoding="utf-8")

            findings, _ = verify_delivery_proofs.validate(isolated_root)

            self.assertIn(
                "verified proof macos-runtime-platform-release/service-registration host-edge-proxy does not match its C23 required Host service registration",
                findings,
            )

            service_registration_proof["observedInstallerArtifact"][
                "fileName"
            ] = "VitalServerRuntimePlatform-other.pkg"
            proofs_path.write_text(json.dumps(proofs), encoding="utf-8")

            findings, _ = verify_delivery_proofs.validate(isolated_root)

            self.assertIn(
                "verified proof macos-runtime-platform-release/service-registration observed installer artifact fileName does not match C23 intended installer artifact",
                findings,
            )

    def test_verified_macos_clean_install_proof_must_match_c23_installer_receipt_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            isolated_root = Path(temporary_directory)
            shutil.copytree(self.root / "contracts", isolated_root / "contracts")
            shutil.copytree(
                self.root / "product" / "delivery",
                isolated_root / "product" / "delivery",
            )
            plans_path = isolated_root / "product" / "delivery" / "release-delivery-plans.v1.json"
            proofs_path = isolated_root / "product" / "delivery" / "release-delivery-proofs.v1.json"
            plans = json.loads(plans_path.read_text(encoding="utf-8"))
            proofs = json.loads(proofs_path.read_text(encoding="utf-8"))
            macos_plan = next(
                plan
                for plan in plans["plans"]
                if plan["id"] == "macos-runtime-platform-release"
            )
            clean_install_proof = next(
                proof
                for proof in proofs["proofs"]
                if proof["planId"] == "macos-runtime-platform-release"
                and proof["stage"] == "clean-install"
            )
            clean_install_proof.pop("issue")
            clean_install_proof.update(
                {
                    "status": "verified",
                    "runner": {
                        "kind": "macos-clean-host",
                        "id": "macos-clean-host-01",
                    },
                    "evidence": {
                        "uri": "file:///evidence/macos-clean-install.json",
                        "sha256": "a" * 64,
                    },
                    "observedInstallerArtifact": {
                        "kind": macos_plan["intendedInstallerArtifact"]["kind"],
                        "fileName": macos_plan["intendedInstallerArtifact"][
                            "expectedName"
                        ],
                        "productVersion": macos_plan["productVersion"],
                        "sha256": "b" * 64,
                        "observedAt": "2026-07-18T00:00:00Z",
                    },
                    "observedMacOSInstallerReceipt": {
                        "packageIdentifier": macos_plan[
                            "macOSInstallerPackageIdentifier"
                        ],
                        "productVersion": macos_plan["productVersion"],
                        "receiptState": "installed",
                        "observedAt": "2026-07-18T00:00:00Z",
                    },
                }
            )
            proofs_path.write_text(json.dumps(proofs), encoding="utf-8")

            findings, _ = verify_delivery_proofs.validate(isolated_root)

            self.assertEqual([], findings)

            clean_install_proof["observedMacOSInstallerReceipt"][
                "packageIdentifier"
            ] = "com.tirosh.other-product"
            proofs_path.write_text(json.dumps(proofs), encoding="utf-8")

            findings, _ = verify_delivery_proofs.validate(isolated_root)

            self.assertIn(
                "verified proof macos-runtime-platform-release/clean-install observed macOS installer package identifier does not match C23 macOS installer package identifier",
                findings,
            )


if __name__ == "__main__":
    unittest.main()
