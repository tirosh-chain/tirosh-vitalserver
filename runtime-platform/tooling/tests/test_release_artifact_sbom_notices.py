"""Release-artifact SBOM and notice evidence behavior."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from tooling import release_artifact_sbom_notices
from tooling.contracts import ContractRepository


class ReleaseArtifactSBOMAndNoticesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.runtime_platform_root = Path(__file__).resolve().parents[2]
        cls.delivery_plans = (
            cls.runtime_platform_root
            / "product"
            / "delivery"
            / "release-delivery-plans.v1.json"
        )
        cls.component_policy = (
            cls.runtime_platform_root / "product" / "delivery" / "sbom-policy.v1.json"
        )

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.artifact = self.root / "VitalServerRuntimePlatform-0.2.0-dev.pkg"
        self.artifact.write_bytes(b"macOS release artifact bytes")
        self.output_directory = self.root / "sbom-and-notices"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def composition(
        self, component_ids: tuple[str, ...] = ("host-agent", "modernc-sqlite")
    ) -> release_artifact_sbom_notices.ReleaseArtifactSBOMAndNoticesComposition:
        return release_artifact_sbom_notices.ReleaseArtifactSBOMAndNoticesComposition(
            release_delivery_plans_document=self.delivery_plans,
            release_delivery_plan_id="macos-runtime-platform-release",
            installer_artifact=self.artifact,
            component_policy=self.component_policy,
            component_ids=component_ids,
            output_directory=self.output_directory,
            runner_id="macos-clean-host-runner-01",
            recorded_at="2026-07-20T08:00:00Z",
        )

    def test_publishes_identity_bound_spdx_notices_evidence_and_c24_fragment(self) -> None:
        result = release_artifact_sbom_notices.compose_release_artifact_sbom_and_notices(
            self.composition()
        )

        sbom = json.loads(Path(result["sbomPath"]).read_text(encoding="utf-8"))
        notices = Path(result["noticesPath"]).read_text(encoding="utf-8")
        evidence = json.loads(Path(result["evidencePath"]).read_text(encoding="utf-8"))
        proof_document = json.loads(
            Path(result["c24ProofPath"]).read_text(encoding="utf-8")
        )

        self.assertEqual("SPDX-2.3", sbom["spdxVersion"])
        self.assertEqual(
            "VitalServerRuntimePlatform-0.2.0-dev.pkg",
            sbom["packages"][0]["packageFileName"],
        )
        self.assertEqual(
            "SHA256",
            sbom["packages"][0]["checksums"][0]["algorithm"],
        )
        self.assertIn("modernc.org/sqlite", notices)
        self.assertEqual(
            "sbom-and-notices", evidence["stage"],
        )
        self.assertEqual(
            result["sbomSHA256"], evidence["sbom"]["sha256"]
        )
        self.assertEqual(
            "verified", result["c24Proof"]["status"]
        )
        self.assertEqual(
            "macos-clean-host", result["c24Proof"]["runner"]["kind"]
        )
        self.assertEqual(
            {"schemaVersion": "v1", "proofs": [result["c24Proof"]]},
            proof_document,
        )

        repository = ContractRepository(self.runtime_platform_root)
        repository.load()
        self.assertEqual(
            [],
            repository.validate_instance(
                "release-delivery-proof.schema.json",
                {"schemaVersion": "v1", "proofs": [result["c24Proof"]]},
            ),
        )

    def test_rejects_artifact_that_does_not_match_c23_file_name(self) -> None:
        wrong_artifact = self.root / "other.pkg"
        wrong_artifact.write_bytes(b"wrong package")
        composition = self.composition()
        composition = release_artifact_sbom_notices.ReleaseArtifactSBOMAndNoticesComposition(
            **{**composition.__dict__, "installer_artifact": wrong_artifact}
        )

        with self.assertRaisesRegex(
            release_artifact_sbom_notices.ReleaseArtifactSBOMAndNoticesError,
            "file name does not match C23",
        ):
            release_artifact_sbom_notices.compose_release_artifact_sbom_and_notices(
                composition
            )

    def test_rejects_ambiguous_component_selection(self) -> None:
        with self.assertRaisesRegex(
            release_artifact_sbom_notices.ReleaseArtifactSBOMAndNoticesError,
            "must not contain duplicates",
        ):
            release_artifact_sbom_notices.compose_release_artifact_sbom_and_notices(
                self.composition(("host-agent", "host-agent"))
            )


if __name__ == "__main__":
    unittest.main()
