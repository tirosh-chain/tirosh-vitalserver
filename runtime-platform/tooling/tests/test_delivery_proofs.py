"""Cross-platform delivery-proof and source-inventory behavior."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tooling import generate_source_inventory_sbom, verify_delivery_proofs


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
