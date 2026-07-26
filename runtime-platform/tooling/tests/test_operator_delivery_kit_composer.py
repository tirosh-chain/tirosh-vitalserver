"""C71/C72 delivery-kit composition and installed-byte verification tests."""

from __future__ import annotations

import hashlib
import json
from dataclasses import replace
from pathlib import Path
import tempfile
import unittest

from tooling.operator_delivery_kit_composer import (
    OperatorDeliveryKitComposition,
    OperatorDeliveryKitCompositionError,
    compose_operator_delivery_kit,
)
from tooling.operator_delivery_kit_verifier import (
    OperatorDeliveryKitVerification,
    OperatorDeliveryKitVerificationError,
    verify_operator_delivery_kit,
)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class OperatorDeliveryKitComposerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.plans = self.root / "release-delivery-plans.json"
        self.plans.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "plans": [
                        {
                            "schemaVersion": "v1",
                            "id": "linux-runtime-platform-release",
                            "productVersion": "0.2.0-dev",
                            "platform": "linux",
                            "providerKind": "linux-kvm-libvirt-systemd",
                            "intendedInstallerArtifact": {
                                "kind": "deb",
                                "expectedName": "vitalserver-runtime-platform_0.2.0-dev_amd64.deb",
                            },
                            "requiredHostServiceRegistrations": [
                                {"role": "host-agent", "manager": "systemd", "name": "vitalserver-host-agent.service"},
                                {"role": "host-edge-proxy", "manager": "systemd", "name": "vitalserver-host-edge-proxy.service"},
                                {"role": "host-update-handoff-supervisor", "manager": "systemd", "name": "vitalserver-host-update-handoff-supervisor.service"},
                            ],
                            "requiredProofStages": [
                                "artifact-integrity", "sbom-and-notices", "clean-install", "service-registration", "reboot", "update", "rollback", "uninstall-reinstall",
                            ],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.host_installer = self.root / "vitalserver-runtime-platform_0.2.0-dev_amd64.deb"
        self.host_installer.write_bytes(b"host-deb")
        self.console = self.root / "VitalServer Runtime Console-0.1.0-x86_64.AppImage"
        self.console.write_bytes(b"runtime-console")
        self.console_receipt = self.root / "runtime-console-receipt.json"
        self.console_receipt.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "artifact": {
                        "platform": "linux",
                        "kind": "appimage",
                        "fileName": self.console.name,
                        "sha256": sha256_bytes(self.console.read_bytes()),
                        "sizeBytes": self.console.stat().st_size,
                    },
                    "runtimeConsoleVersion": "0.1.0",
                    "localControlBootstrapContract": {"contractId": "C53", "schemaVersion": "v1"},
                }
            ),
            encoding="utf-8",
        )
        self.bootstrap = self.root / "runtime-console-bootstrap.json"
        self.bootstrap.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "bootstrapConfigurationPath": "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json",
                    "localAdministrationDescriptorPath": "/opt/vitalserver-runtime-platform/control/host-agent.local.json",
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def composition(self) -> OperatorDeliveryKitComposition:
        return OperatorDeliveryKitComposition(
            release_set_id="linux-runtime-platform-020-delivery",
            release_delivery_plans_document=self.plans,
            release_delivery_plan_id="linux-runtime-platform-release",
            host_installer_artifact=self.host_installer,
            runtime_console_artifact=self.console,
            runtime_console_artifact_receipt=self.console_receipt,
            operator_interface_bootstrap_configuration=self.bootstrap,
            output_directory=self.root / "linux-runtime-platform-delivery",
        )

    def test_composes_one_immutable_host_and_console_delivery_kit(self) -> None:
        result = compose_operator_delivery_kit(self.composition())
        output = self.root / "linux-runtime-platform-delivery"
        manifest = json.loads((output / "operator-delivery-kit-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(result["outputDirectory"], str(output))
        self.assertEqual(manifest["releaseDeliveryPlan"]["planId"], "linux-runtime-platform-release")
        self.assertEqual(manifest["installationOrder"], ["host-installer", "runtime-console"])
        self.assertEqual(manifest["hostInstallerArtifact"]["sha256"], sha256_bytes(b"host-deb"))
        self.assertEqual(manifest["runtimeConsoleArtifactReceipt"]["artifact"]["sha256"], sha256_bytes(b"runtime-console"))
        self.assertEqual((output / "artifacts" / "host-installer" / self.host_installer.name).read_bytes(), b"host-deb")
        self.assertEqual((output / "artifacts" / "runtime-console" / self.console.name).read_bytes(), b"runtime-console")

    def test_verifies_published_kit_bytes_and_one_explicit_bootstrap_file(self) -> None:
        compose_operator_delivery_kit(self.composition())
        result = verify_operator_delivery_kit(
            OperatorDeliveryKitVerification(
                delivery_kit_directory=self.composition().output_directory,
                operator_interface_bootstrap_configuration=self.bootstrap,
            )
        )
        self.assertEqual("verified", result["kitIntegrityState"])
        self.assertEqual("linux-runtime-platform-020-delivery", result["releaseSetId"])
        self.assertEqual("verified", result["operatorInterfaceBootstrapVerification"]["state"])
        self.assertEqual(sha256_bytes(b"host-deb"), result["verifiedArtifacts"]["hostInstaller"]["sha256"])

    def test_rejects_a_tampered_published_console_artifact(self) -> None:
        compose_operator_delivery_kit(self.composition())
        copied_console = self.composition().output_directory / "artifacts" / "runtime-console" / self.console.name
        copied_console.write_bytes(b"tampered-runtime-console")
        with self.assertRaisesRegex(OperatorDeliveryKitVerificationError, "Runtime Console artifact (size|SHA-256)"):
            verify_operator_delivery_kit(OperatorDeliveryKitVerification(self.composition().output_directory))

    def test_rejects_unexpected_entries_in_published_kit(self) -> None:
        compose_operator_delivery_kit(self.composition())
        (self.composition().output_directory / "operator-notes.txt").write_text("not a C72 member", encoding="utf-8")
        with self.assertRaisesRegex(OperatorDeliveryKitVerificationError, "files do not exactly match"):
            verify_operator_delivery_kit(OperatorDeliveryKitVerification(self.composition().output_directory))

    def test_rejects_a_symbolic_link_in_place_of_a_published_artifact(self) -> None:
        compose_operator_delivery_kit(self.composition())
        copied_host_installer = self.composition().output_directory / "artifacts" / "host-installer" / self.host_installer.name
        copied_host_installer.unlink()
        copied_host_installer.symlink_to(self.host_installer)
        with self.assertRaisesRegex(OperatorDeliveryKitVerificationError, "symbolic link"):
            verify_operator_delivery_kit(OperatorDeliveryKitVerification(self.composition().output_directory))

    def test_rejects_a_bootstrap_file_that_does_not_match_the_c72_identity(self) -> None:
        compose_operator_delivery_kit(self.composition())
        self.bootstrap.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "bootstrapConfigurationPath": "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json",
                    "localAdministrationDescriptorPath": "/opt/vitalserver-runtime-platform/control/another-host-agent.local.json",
                }
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(OperatorDeliveryKitVerificationError, "bootstrap SHA-256"):
            verify_operator_delivery_kit(
                OperatorDeliveryKitVerification(
                    delivery_kit_directory=self.composition().output_directory,
                    operator_interface_bootstrap_configuration=self.bootstrap,
                )
            )

    def test_rejects_a_console_receipt_that_does_not_describe_the_selected_bytes(self) -> None:
        receipt = json.loads(self.console_receipt.read_text(encoding="utf-8"))
        receipt["artifact"]["sha256"] = "a" * 64
        self.console_receipt.write_text(json.dumps(receipt), encoding="utf-8")
        with self.assertRaisesRegex(OperatorDeliveryKitCompositionError, "SHA-256"):
            compose_operator_delivery_kit(self.composition())
        self.assertFalse(self.composition().output_directory.exists())

    def test_rejects_a_linux_bootstrap_path_that_the_packaged_console_cannot_read(self) -> None:
        bootstrap = json.loads(self.bootstrap.read_text(encoding="utf-8"))
        bootstrap["bootstrapConfigurationPath"] = "/var/lib/vitalserver-runtime-platform/control/runtime-console-bootstrap.json"
        self.bootstrap.write_text(json.dumps(bootstrap), encoding="utf-8")
        with self.assertRaisesRegex(OperatorDeliveryKitCompositionError, "packaged Runtime Console path"):
            compose_operator_delivery_kit(self.composition())
        self.assertFalse(self.composition().output_directory.exists())

    def test_accepts_a_native_linux_console_deb_for_the_linux_delivery_kit(self) -> None:
        native_console = self.root / "vitalserver-runtime-console_0.1.0_amd64.deb"
        native_console.write_bytes(b"runtime-console-deb")
        receipt = json.loads(self.console_receipt.read_text(encoding="utf-8"))
        receipt["artifact"].update({
            "kind": "deb",
            "fileName": native_console.name,
            "sha256": sha256_bytes(native_console.read_bytes()),
            "sizeBytes": native_console.stat().st_size,
        })
        self.console_receipt.write_text(json.dumps(receipt), encoding="utf-8")
        composition = replace(
            self.composition(),
            runtime_console_artifact=native_console,
            output_directory=self.root / "linux-runtime-platform-deb-console-delivery",
        )
        result = compose_operator_delivery_kit(composition)
        manifest = json.loads(Path(result["manifestPath"]).read_text(encoding="utf-8"))
        self.assertEqual("deb", manifest["runtimeConsoleArtifactReceipt"]["artifact"]["kind"])


if __name__ == "__main__":
    unittest.main()
