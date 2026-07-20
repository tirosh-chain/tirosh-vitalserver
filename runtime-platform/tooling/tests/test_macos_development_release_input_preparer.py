"""Tests for explicit unsigned macOS development release input preparation."""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
import tempfile
import unittest

from tooling import macos_development_release_input_preparer as preparer


class MacOSDevelopmentReleaseInputPreparerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.release_root = self.root / "release"
        self.release_root.mkdir()
        self.source_root = self.root / "sources"
        self.source_root.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_prepares_c41_and_c47_from_only_declared_sources(self) -> None:
        result = preparer.prepare_macos_development_release_input(self.preparation())

        c41_path = Path(result["guestArtifactCompilationInputAssemblyDeclaration"]["path"])
        c47_path = Path(result["macOSReleasePackageAssemblyDeclaration"]["path"])
        self.assertTrue(c41_path.is_file())
        self.assertTrue(c47_path.is_file())
        c41 = json.loads(c41_path.read_text(encoding="utf-8"))
        c47 = json.loads(c47_path.read_text(encoding="utf-8"))
        documents = self.release_root / "release-input" / "documents"
        self.assertEqual(
            str(documents / "guest-product-bootstrap-configuration.json"),
            c41["guestProductBootstrapConfigurationArtifact"]["sourceAbsolutePath"],
        )
        self.assertEqual(
            str(documents / "release-delivery-plans.json"),
            c47["releaseDeliveryPlan"]["documentAbsolutePath"],
        )
        self.assertEqual(
            "unsigned",
            c47["macOSPackage"]["installerPackageSigning"]["mode"],
        )
        self.assertEqual(
            "ad-hoc",
            c47["macOSPackage"]["virtualMachineSupervisorCodeSigning"]["mode"],
        )
        self.assertEqual(
            str(self.release_root / "VitalServerRuntimePlatform-0.2.0-dev.pkg"),
            c47["macOSPackage"]["outputPackageAbsolutePath"],
        )
        self.assertEqual(
            str(self.source_root / "VitalServer Runtime Platform.app"),
            c47["hostArtifacts"]["operatorApplicationBundleAbsolutePath"],
        )
        self.assertFalse((self.release_root / "guest-artifact-compilation-input").exists())
        self.assertFalse((self.release_root / "guest-artifact-output").exists())

    def test_rejects_missing_input_before_creating_release_input_directory(self) -> None:
        preparation = self.preparation()
        missing = self.source_root / "guest-runtime"
        missing.unlink()
        preparation = preparer.MacOSDevelopmentReleaseInputPreparation(
            **{**preparation.__dict__, "guest_runtime": missing}
        )

        with self.assertRaisesRegex(
            preparer.MacOSDevelopmentReleaseInputPreparationError,
            "Guest Runtime must be a regular",
        ):
            preparer.prepare_macos_development_release_input(preparation)

        self.assertFalse((self.release_root / "release-input").exists())

    def test_rejects_existing_release_input_directory_without_overwriting_it(self) -> None:
        release_input = self.release_root / "release-input"
        release_input.mkdir()
        sentinel = release_input / "sentinel"
        sentinel.write_text("preserve", encoding="utf-8")

        with self.assertRaisesRegex(
            preparer.MacOSDevelopmentReleaseInputPreparationError,
            "release input directory already exists",
        ):
            preparer.prepare_macos_development_release_input(self.preparation())

        self.assertEqual("preserve", sentinel.read_text(encoding="utf-8"))

    def test_prepares_bundled_topology_with_only_the_paired_c64_inputs(self) -> None:
        external_preparation = self.preparation()
        bundled_topology = self.source_root / "bundled-topology.json"
        bundled_topology.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "topologyDeploymentId": "bundled-vitalserver-test-topology",
                    "topologyKind": "bundled-vitalserver",
                    "vitalServerDeliveryProvider": {
                        "kind": "bundled-vitalserver",
                        "id": "bundled-vitalserver-test",
                        "capabilityRevision": 1,
                    },
                    "publicBrowserExposure": "not-exposed",
                    "bundledUpstreamImageSetDeployment": {
                        "imageSetManagerConfigurationReference": {
                            "resourceType": "guest-bundled-upstream-image-set-manager-configuration",
                            "resourceId": "bundled-vitalserver-test",
                        },
                        "vitalServerPacketDeliveryEndpoint": {
                            "scheme": "http",
                            "host": "127.0.0.1",
                            "port": 18300,
                        },
                        "vitalServerDeliveryAcknowledgementTimeoutMilliseconds": 1000,
                        "vitalServerObservationEndpoint": {
                            "scheme": "http",
                            "host": "127.0.0.1",
                            "port": 18300,
                            "path": "/healthz",
                            "acceptedStatusCodes": [200],
                        },
                        "vitalServerArchiveProvider": {
                            "kind": "vitalserver-indexed-library",
                            "id": "bundled-vitalserver-test-library",
                            "capabilityRevision": 1,
                        },
                        "vitalServerIndexedLibraryEndpoint": {
                            "scheme": "http",
                            "host": "127.0.0.1",
                            "port": 18300,
                        },
                        "vitalServerArchiveCredentialReference": {
                            "kind": "vitalserver-library-credential",
                            "id": "bundled-vitalserver-test-library",
                        },
                        "vitalServerArchiveRequestTimeoutMilliseconds": 10000,
                    },
                }
            ),
            encoding="utf-8",
        )
        manager = self.source_root / "guest-bundled-upstream-image-set-manager"
        manager.write_text("manager", encoding="utf-8")
        manager.chmod(0o755)
        manager_configuration = self.source_root / "guest-bundled-upstream-image-set-manager-configuration.json"
        manager_configuration.write_text(
            (Path(__file__).resolve().parents[2]
             / "contracts/examples/v1/valid/guest-bundled-upstream-image-set-manager-configuration.json").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        preparation = preparer.MacOSDevelopmentReleaseInputPreparation(
            **{
                **external_preparation.__dict__,
                "guest_product_vitalserver_topology_deployment": bundled_topology,
                "external_vitalserver_delivery_configuration": None,
                "guest_bundled_upstream_image_set_manager": manager,
                "guest_bundled_upstream_image_set_manager_configuration": manager_configuration,
            }
        )

        result = preparer.prepare_macos_development_release_input(preparation)
        c41 = json.loads(
            Path(result["guestArtifactCompilationInputAssemblyDeclaration"]["path"]).read_text(
                encoding="utf-8"
            )
        )
        c47 = json.loads(
            Path(result["macOSReleasePackageAssemblyDeclaration"]["path"]).read_text(
                encoding="utf-8"
            )
        )

        self.assertNotIn("externalVitalServerDeliveryConfigurationArtifact", c41)
        self.assertEqual(
            "guest-bundled-upstream-image-set-manager-linux-arm64",
            c41["guestBundledUpstreamImageSetManagerArtifact"]["id"],
        )
        self.assertEqual(
            "guest-bundled-upstream-image-set-manager-configuration",
            c41["guestBundledUpstreamImageSetManagerConfigurationArtifact"]["id"],
        )
        self.assertNotIn(
            "externalVitalServerDeliveryConfigurationAbsolutePath",
            c47["deploymentDocuments"],
        )
        self.assertEqual(
            str(
                self.release_root
                / "release-input"
                / "documents"
                / "guest-bundled-upstream-image-set-manager-configuration.json"
            ),
            c47["deploymentDocuments"][
                "guestBundledUpstreamImageSetManagerConfigurationAbsolutePath"
            ],
        )

    def preparation(self) -> preparer.MacOSDevelopmentReleaseInputPreparation:
        executable_names = {
            "guest-product-bootstrap-artifact-composer",
            "guest-runtime",
            "guest-product-process-supervisor",
            "guest-product-release-manager",
            "host-agent",
            "host-edge-proxy",
            "host-installation-manager",
            "host-update-handoff-supervisor",
            "platformctl",
            "macos-virtual-machine-supervisor",
            "pkgbuild",
            "pkgutil",
            "codesign",
        }

        def source(name: str) -> Path:
            path = self.source_root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name, encoding="utf-8")
            if name in executable_names:
                path.chmod(0o755)
            return path

        def operator_application_bundle() -> Path:
            bundle = self.source_root / "VitalServer Runtime Platform.app"
            executable = bundle / "Contents" / "MacOS" / "VitalServer Runtime Platform"
            executable.parent.mkdir(parents=True, exist_ok=True)
            executable.write_text("operator-application", encoding="utf-8")
            executable.chmod(0o755)
            (bundle / "Contents" / "Info.plist").write_text(
                "operator-application-info",
                encoding="utf-8",
            )
            return bundle

        plans = self.source_root / "release-delivery-plans.json"
        plans.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "plans": [
                        {
                            "schemaVersion": "v1",
                            "id": "macos-runtime-platform-release",
                            "productVersion": "0.2.0-dev",
                            "platform": "macos",
                            "providerKind": "macos-virtualization",
                            "intendedInstallerArtifact": {
                                "kind": "pkg",
                                "expectedName": "VitalServerRuntimePlatform-0.2.0-dev.pkg",
                            },
                            "macOSInstallerPackageIdentifier": "com.tirosh.vitalserver.runtime-platform",
                            "macOSInstallerSignaturePolicy": "unsigned",
                            "requiredHostServiceRegistrations": [
                                {"role": "host-agent", "manager": "launchd", "name": "com.tirosh.vitalserver.host-agent"},
                                {"role": "host-edge-proxy", "manager": "launchd", "name": "com.tirosh.vitalserver.host-edge-proxy"},
                                {"role": "host-update-handoff-supervisor", "manager": "launchd", "name": "com.tirosh.vitalserver.host-update-handoff-supervisor"},
                            ],
                            "requiredProofStages": [
                                "artifact-integrity", "sbom-and-notices", "clean-install", "service-registration", "reboot", "update", "rollback", "uninstall-reinstall"
                            ],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        topology = source("guest-product-vitalserver-topology.json")
        topology.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "topologyDeploymentId": "external-vitalserver-test-topology",
                    "topologyKind": "external-vitalserver",
                    "vitalServerDeliveryProvider": {
                        "kind": "external-vitalserver",
                        "id": "external-vitalserver-test",
                        "capabilityRevision": 1,
                    },
                    "publicBrowserExposure": "not-exposed",
                    "externalVitalServerDeploymentConfiguration": {
                        "externalUpstreamIntegrationReference": {
                            "resourceType": "external-upstream-integration",
                            "resourceId": "external-vitalserver-test",
                        },
                        "externalVitalServerDeliveryConfigurationReference": {
                            "resourceType": "external-vitalserver-delivery-configuration",
                            "resourceId": "external-vitalserver-test-delivery",
                        },
                    },
                }
            ),
            encoding="utf-8",
        )
        return preparer.MacOSDevelopmentReleaseInputPreparation(
            release_root=self.release_root,
            assembly_id="macos-development-package-020",
            guest_input_assembly_id="guest-input-assembly-020",
            guest_compilation_id="guest-compilation-020",
            guest_artifact_set_id="guest-artifact-set-020",
            release_delivery_plans=plans,
            release_delivery_plan_id="macos-runtime-platform-release",
            payload_base_path=PurePosixPath("/Library/Application Support/VitalServerRuntimePlatform"),
            guest_product_bootstrap_artifact_composer=source("guest-product-bootstrap-artifact-composer"),
            guest_kernel=source("Image"),
            guest_initial_ramdisk=source("initrd.img"),
            guest_root_storage=source("guest-root.raw"),
            guest_runtime=source("guest-runtime"),
            guest_telemetry_collector=source("guest-telemetry-collector"),
            guest_node_services=source("guest-node-services.tar.gz"),
            guest_product_process_supervisor=source("guest-product-process-supervisor"),
            guest_product_release_manager=source("guest-product-release-manager"),
            host_agent=source("host-agent"),
            host_edge_proxy=source("host-edge-proxy"),
            host_installation_manager=source("host-installation-manager"),
            host_update_handoff_supervisor=source("host-update-handoff-supervisor"),
            platformctl=source("platformctl"),
            macos_virtual_machine_supervisor=source("macos-virtual-machine-supervisor"),
            operator_application_bundle=operator_application_bundle(),
            host_agent_deployment_configuration=source("host-agent-deployment.json"),
            operator_interface_bootstrap_configuration=source("operator-interface-bootstrap.json"),
            host_edge_proxy_deployment_configuration=source("host-edge-proxy-deployment.json"),
            host_update_handoff_supervisor_configuration=source("host-update-handoff-supervisor-configuration.json"),
            host_update_trust_store=source("update-trust-store.json"),
            macos_virtual_machine_configuration=source("macos-virtual-machine.json"),
            guest_product_process_deployment_configuration=source("guest-product-process-deployment.json"),
            guest_product_release_manager_configuration=source("guest-product-release-manager.json"),
            guest_product_service_manager_deployment_configuration=source("guest-product-service-manager-deployment.json"),
            guest_product_bootstrap_configuration=source("guest-product-bootstrap.json"),
            guest_product_vitalserver_topology_deployment=topology,
            external_vitalserver_delivery_configuration=source("external-vitalserver-delivery.json"),
            guest_telemetry_collector_configuration=source("guest-telemetry-collector.yaml"),
            virtualization_entitlements=source("macos-virtual-machine-supervisor.entitlements"),
            pkgbuild_executable=source("pkgbuild"),
            pkgutil_executable=source("pkgutil"),
            codesign_executable=source("codesign"),
            builder_timeout_seconds=120,
        )


if __name__ == "__main__":
    unittest.main()
