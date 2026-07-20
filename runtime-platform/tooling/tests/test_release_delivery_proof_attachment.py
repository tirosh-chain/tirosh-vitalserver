"""Reviewed C24 proof attachment behavior."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tooling import release_delivery_proof_attachment, verify_delivery_proofs
from tooling.contracts import ContractRepository, load_json
from tooling import release_artifact_sbom_notices


class ReleaseDeliveryProofAttachmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.runtime_platform_root = Path(__file__).resolve().parents[2]
        cls.release_delivery_plans_document = (
            cls.runtime_platform_root
            / "product"
            / "delivery"
            / "release-delivery-plans.v1.json"
        )
        cls.source_proof_set = (
            cls.runtime_platform_root
            / "product"
            / "delivery"
            / "release-delivery-proofs.v1.json"
        )

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.evidence = self.root / "sbom-and-notices-evidence.json"
        self.evidence.write_bytes(b"reviewed C24 evidence bytes")
        self.fragment = self.root / "sbom-proof-fragment.json"
        self.output_directory = self.root / "reviewed-c24-proof-set"
        self._write_verified_sbom_fragment()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def request(
        self,
        *,
        source_proof_set: Path | None = None,
        output_directory: Path | None = None,
        materials: tuple[
            release_delivery_proof_attachment.ReviewedEvidenceMaterial, ...
        ]
        | None = None,
    ) -> release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentRequest:
        return release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentRequest(
            contract_root=self.runtime_platform_root,
            release_delivery_plans_document=self.release_delivery_plans_document,
            source_proof_set=source_proof_set or self.source_proof_set,
            proof_fragments=(self.fragment,),
            reviewed_evidence_materials=materials
            if materials is not None
            else (
                release_delivery_proof_attachment.ReviewedEvidenceMaterial(
                    uri=self.evidence.as_uri(), path=self.evidence
                ),
            ),
            output_directory=output_directory or self.output_directory,
            review_id="macos-020-c24-review",
            reviewer_id="release-operator-01",
            reviewed_at="2026-07-20T08:00:00Z",
        )

    def test_publishes_new_valid_proof_set_and_c74_review_without_mutating_source(self) -> None:
        result = (
            release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
                self.request()
            )
        )

        source = load_json(self.source_proof_set)
        published = load_json(Path(result["proofSetPath"]))
        review = load_json(Path(result["reviewPath"]))
        source_stage = _proof(source, "macos-runtime-platform-release", "sbom-and-notices")
        published_stage = _proof(
            published, "macos-runtime-platform-release", "sbom-and-notices"
        )
        self.assertEqual("pending", source_stage["status"])
        self.assertEqual("verified", published_stage["status"])
        self.assertEqual(self.evidence.as_uri(), published_stage["evidence"]["uri"])
        self.assertEqual(1, result["attachedProofCount"])
        self.assertEqual("macos-020-c24-review", review["reviewId"])
        self.assertEqual(
            hashlib.sha256(self.source_proof_set.read_bytes()).hexdigest(),
            review["sourceProofSet"]["sha256"],
        )
        self.assertEqual(result["proofSetSHA256"], review["outputProofSet"]["sha256"])

        findings, _ = verify_delivery_proofs.validate_documents(
            self.runtime_platform_root,
            load_json(self.release_delivery_plans_document),
            published,
        )
        self.assertEqual([], findings)
        repository = ContractRepository(self.runtime_platform_root)
        repository.load()
        self.assertEqual(
            [],
            repository.validate_instance(
                "release-delivery-proof-attachment-review.schema.json", review
            ),
        )

    def test_attaches_the_sbom_composer_proof_set_and_verifies_the_new_candidate_path(self) -> None:
        artifact = self.root / "VitalServerRuntimePlatform-0.2.0-dev.pkg"
        artifact.write_bytes(b"C23-selected package bytes")
        sbom_directory = self.root / "sbom-output"
        sbom = release_artifact_sbom_notices.compose_release_artifact_sbom_and_notices(
            release_artifact_sbom_notices.ReleaseArtifactSBOMAndNoticesComposition(
                release_delivery_plans_document=self.release_delivery_plans_document,
                release_delivery_plan_id="macos-runtime-platform-release",
                installer_artifact=artifact,
                component_policy=self.runtime_platform_root
                / "product"
                / "delivery"
                / "sbom-policy.v1.json",
                component_ids=("host-agent",),
                output_directory=sbom_directory,
                runner_id="macos-clean-host-01",
                recorded_at="2026-07-20T08:00:00Z",
            )
        )
        result = (
            release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
                release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentRequest(
                    **{
                        **self.request().__dict__,
                        "proof_fragments": (Path(sbom["c24ProofPath"]),),
                        "reviewed_evidence_materials": (
                            release_delivery_proof_attachment.ReviewedEvidenceMaterial(
                                uri=sbom["c24Proof"]["evidence"]["uri"],
                                path=Path(sbom["evidencePath"]),
                            ),
                        ),
                    }
                )
            )
        )

        findings, pending = verify_delivery_proofs.validate_document_paths(
            self.runtime_platform_root,
            self.release_delivery_plans_document,
            Path(result["proofSetPath"]),
        )
        self.assertEqual([], findings)
        self.assertIn(
            "macos-runtime-platform-release/clean-install=pending", pending
        )

    def test_rejects_verified_fragment_without_exact_reviewed_evidence_bytes(self) -> None:
        changed_evidence = self.root / "changed-evidence.json"
        changed_evidence.write_bytes(b"different bytes")
        request = self.request(
            materials=(
                release_delivery_proof_attachment.ReviewedEvidenceMaterial(
                    uri=self.evidence.as_uri(), path=changed_evidence
                ),
            )
        )

        with self.assertRaisesRegex(
            release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentError,
            "SHA-256 does not match",
        ):
            release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
                request
            )
        self.assertFalse(self.output_directory.exists())

    def test_rejects_verified_fragment_when_reviewer_did_not_supply_evidence_material(self) -> None:
        with self.assertRaisesRegex(
            release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentError,
            "requires reviewed evidence material",
        ):
            release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
                self.request(materials=())
            )
        self.assertFalse(self.output_directory.exists())

    def test_rejects_attempt_to_replace_a_terminal_c24_stage(self) -> None:
        release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
            self.request()
        )
        second_output = self.root / "second-review"

        with self.assertRaisesRegex(
            release_delivery_proof_attachment.ReleaseDeliveryProofAttachmentError,
            "is not pending and cannot be replaced",
        ):
            release_delivery_proof_attachment.publish_reviewed_release_delivery_proof_set(
                self.request(
                    source_proof_set=self.output_directory
                    / "release-delivery-proofs.v1.json",
                    output_directory=second_output,
                )
            )
        self.assertFalse(second_output.exists())

    def _write_verified_sbom_fragment(self) -> None:
        evidence_sha256 = hashlib.sha256(self.evidence.read_bytes()).hexdigest()
        fragment = {
            "planId": "macos-runtime-platform-release",
            "platform": "macos",
            "providerKind": "macos-virtualization",
            "stage": "sbom-and-notices",
            "status": "verified",
            "recordedAt": "2026-07-20T08:00:00Z",
            "runner": {"kind": "macos-clean-host", "id": "macos-clean-host-01"},
            "evidence": {"uri": self.evidence.as_uri(), "sha256": evidence_sha256},
            "observedInstallerArtifact": {
                "kind": "pkg",
                "fileName": "VitalServerRuntimePlatform-0.2.0-dev.pkg",
                "productVersion": "0.2.0-dev",
                "sha256": "b" * 64,
                "observedAt": "2026-07-20T08:00:00Z",
            },
        }
        self.fragment.write_text(json.dumps(fragment), encoding="utf-8")


def _proof(document: dict[str, object], plan_id: str, stage: str) -> dict[str, object]:
    proofs = document["proofs"]
    assert isinstance(proofs, list)
    for proof in proofs:
        assert isinstance(proof, dict)
        if proof.get("planId") == plan_id and proof.get("stage") == stage:
            return proof
    raise AssertionError("proof was not found: " + plan_id + "/" + stage)


if __name__ == "__main__":
    unittest.main()
