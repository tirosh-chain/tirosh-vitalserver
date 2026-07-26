"""Focused proof for the explicit amd64 native Guest C41 preparation boundary."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tooling import native_guest_artifact_input_preparer as preparer


class NativeGuestArtifactInputPreparerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.release_root = self.root / "release"
        self.release_root.mkdir()
        self.sources = self.root / "sources"
        self.sources.mkdir()
        self.product_root = Path(__file__).resolve().parents[2] / "product"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_prepares_amd64_c41_without_macos_boot_inputs(self) -> None:
        result = preparer.prepare_native_guest_artifact_input(self.preparation())

        declaration_path = Path(
            result["guestArtifactCompilationInputAssemblyDeclaration"]["path"]
        )
        declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
        documents = self.release_root / "native-guest-release-input" / "documents"

        self.assertEqual("amd64", declaration["architecture"])
        self.assertNotIn("boot", declaration)
        self.assertEqual(
            str(documents / "guest-product-bootstrap-configuration.json"),
            declaration["guestProductBootstrapConfigurationArtifact"][
                "sourceAbsolutePath"
            ],
        )
        self.assertIn("externalVitalServerDeliveryConfigurationArtifact", declaration)
        self.assertEqual(
            "guest-runtime-linux-amd64", declaration["guestRuntimeArtifact"]["id"]
        )
        self.assertEqual(
            str(self.release_root / "guest-artifact-compilation-input"),
            result["nextEffect"]["assembledInputRootPath"],
        )

    def test_rejects_non_amd64_c39_before_writing_release_input(self) -> None:
        preparation = self.preparation()
        arm64_configuration = self.sources / "guest-product-bootstrap-arm64.json"
        shutil.copyfile(
            self.product_root
            / "guest-product"
            / "guest-product-bootstrap-configuration.v1.json",
            arm64_configuration,
        )
        preparation = preparer.NativeGuestArtifactInputPreparation(
            **{
                **preparation.__dict__,
                "guest_product_bootstrap_configuration": arm64_configuration,
            }
        )

        with self.assertRaisesRegex(
            preparer.NativeGuestArtifactInputPreparationError,
            "guestArchitecture amd64",
        ):
            preparer.prepare_native_guest_artifact_input(preparation)

        self.assertFalse((self.release_root / "native-guest-release-input").exists())

    def test_rejects_external_topology_without_c46_instead_of_falling_back(self) -> None:
        preparation = self.preparation()
        preparation = preparer.NativeGuestArtifactInputPreparation(
            **{
                **preparation.__dict__,
                "external_vitalserver_delivery_configuration": None,
            }
        )

        with self.assertRaisesRegex(
            preparer.NativeGuestArtifactInputPreparationError,
            "requires a C46",
        ):
            preparer.prepare_native_guest_artifact_input(preparation)

        self.assertFalse((self.release_root / "native-guest-release-input").exists())

    def test_prepares_bundled_topology_with_only_the_paired_c64_inputs(self) -> None:
        preparation = self.preparation()
        bundled_topology = self.sources / "bundled-topology.json"
        bundled_topology.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "topologyDeploymentId": "bundled-vitalserver-native-test",
                    "topologyKind": "bundled-vitalserver",
                    "vitalServerDeliveryProvider": {"kind": "bundled-vitalserver", "id": "bundled-vitalserver-native", "capabilityRevision": 1},
                    "publicBrowserExposure": "not-exposed",
                    "bundledUpstreamImageSetDeployment": {
                        "imageSetManagerConfigurationReference": {"resourceType": "guest-bundled-upstream-image-set-manager-configuration", "resourceId": "bundled-upstream-image-set-manager"},
                        "vitalServerPacketDeliveryEndpoint": {"scheme": "http", "host": "127.0.0.1", "port": 18300},
                        "vitalServerDeliveryAcknowledgementTimeoutMilliseconds": 5000,
                        "vitalServerObservationEndpoint": {"scheme": "http", "host": "127.0.0.1", "port": 18300, "path": "/healthz", "acceptedStatusCodes": [200]},
                        "vitalServerArchiveProvider": {"kind": "vitalserver-indexed-library", "id": "bundled-library", "capabilityRevision": 1},
                        "vitalServerIndexedLibraryEndpoint": {"scheme": "http", "host": "127.0.0.1", "port": 18300},
                        "vitalServerArchiveCredentialReference": {"kind": "vitalserver-library-credential", "id": "bundled-library"},
                        "vitalServerArchiveRequestTimeoutMilliseconds": 5000,
                    },
                }
            ),
            encoding="utf-8",
        )
        bundled_bootstrap = self.sources / "bundled-bootstrap.json"
        bootstrap = json.loads(preparation.guest_product_bootstrap_configuration.read_text(encoding="utf-8"))
        bootstrap.pop("externalVitalServerDeliveryConfiguration")
        bootstrap["guestBundledUpstreamImageSetManager"] = {
            "managerId": "bundled-upstream-image-set-manager",
            "executable": {"artifactId": "guest-bundled-upstream-image-set-manager-linux-amd64", "destinationPath": "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-bundled-upstream-image-set-manager", "fileMode": "0755"},
            "configuration": {"artifactId": "guest-bundled-upstream-image-set-manager-configuration", "destinationPath": "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-bundled-upstream-image-set-manager-configuration.json", "fileMode": "0644"},
            "stateDirectory": {"directoryPath": "/var/lib/vitalserver/bundled-upstream-image-sets", "directoryMode": "0700"},
            "containerEngineBootstrap": {"packageManager": "apt", "packageName": "docker.io", "serviceName": "docker.service"},
            "serviceUnit": {"serviceUnitName": "vitalserver-guest-bundled-upstream-image-set-manager.service", "unitDestinationPath": "/etc/systemd/system/vitalserver-guest-bundled-upstream-image-set-manager.service", "enabledUnitLinkPath": "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-bundled-upstream-image-set-manager.service", "enabledUnitLinkTargetPath": "/etc/systemd/system/vitalserver-guest-bundled-upstream-image-set-manager.service", "restart": {"mode": "on-failure", "delayMilliseconds": 1000}, "logging": {"standardOutput": "journal+console", "standardError": "journal+console"}, "install": {"wantedByTarget": "multi-user.target"}},
            "initialActiveImageSetState": "unprovisioned",
        }
        bundled_bootstrap.write_text(json.dumps(bootstrap), encoding="utf-8")
        manager = self.sources / "guest-bundled-upstream-image-set-manager"
        manager.write_text("manager", encoding="utf-8")
        manager.chmod(0o755)
        manager_configuration = self.sources / "guest-bundled-upstream-image-set-manager-configuration.json"
        shutil.copyfile(
            self.product_root.parent
            / "contracts/examples/v1/valid/guest-bundled-upstream-image-set-manager-configuration.json",
            manager_configuration,
        )
        preparation = preparer.NativeGuestArtifactInputPreparation(
            **{
                **preparation.__dict__,
                "guest_product_bootstrap_configuration": bundled_bootstrap,
                "guest_product_vitalserver_topology_deployment": bundled_topology,
                "external_vitalserver_delivery_configuration": None,
                "guest_bundled_upstream_image_set_manager": manager,
                "guest_bundled_upstream_image_set_manager_configuration": manager_configuration,
            }
        )

        result = preparer.prepare_native_guest_artifact_input(preparation)
        declaration = json.loads(
            Path(result["guestArtifactCompilationInputAssemblyDeclaration"]["path"]).read_text(encoding="utf-8")
        )

        self.assertNotIn("externalVitalServerDeliveryConfigurationArtifact", declaration)
        self.assertEqual("guest-bundled-upstream-image-set-manager-linux-amd64", declaration["guestBundledUpstreamImageSetManagerArtifact"]["id"])
        self.assertEqual("guest-bundled-upstream-image-set-manager-configuration", declaration["guestBundledUpstreamImageSetManagerConfigurationArtifact"]["id"])

    def preparation(self) -> preparer.NativeGuestArtifactInputPreparation:
        executable_names = {
            "guest-product-bootstrap-artifact-composer",
            "guest-runtime",
            "guest-telemetry-collector",
            "guest-product-process-supervisor",
            "guest-product-release-manager",
        }

        def source(name: str) -> Path:
            path = self.sources / name
            path.write_text(name, encoding="utf-8")
            if name in executable_names:
                path.chmod(0o755)
            return path

        def copied_product_document(relative_path: str, name: str) -> Path:
            target = self.sources / name
            shutil.copyfile(self.product_root / relative_path, target)
            return target

        return preparer.NativeGuestArtifactInputPreparation(
            release_root=self.release_root,
            assembly_id="native-guest-input-assembly-020",
            compilation_id="native-guest-compilation-020",
            artifact_set_id="native-guest-artifact-set-020",
            guest_product_bootstrap_artifact_composer=source(
                "guest-product-bootstrap-artifact-composer"
            ),
            guest_root_storage=source("guest-root.raw"),
            guest_runtime=source("guest-runtime"),
            guest_telemetry_collector=source("guest-telemetry-collector"),
            guest_telemetry_collector_configuration=source(
                "guest-telemetry-collector.yaml"
            ),
            guest_node_services=source("guest-node-services.tar.gz"),
            guest_product_process_supervisor=source(
                "guest-product-process-supervisor"
            ),
            guest_product_process_deployment_configuration=source(
                "guest-product-process-deployment.json"
            ),
            guest_product_release_manager=source("guest-product-release-manager"),
            guest_product_release_manager_configuration=source(
                "guest-product-release-manager.json"
            ),
            guest_product_service_manager_deployment_configuration=source(
                "guest-product-service-manager-deployment.json"
            ),
            guest_product_bootstrap_configuration=copied_product_document(
                "guest-product/guest-product-bootstrap-configuration-amd64.v1.json",
                "guest-product-bootstrap-configuration.json",
            ),
            guest_product_vitalserver_topology_deployment=copied_product_document(
                "guest-product/guest-product-vitalserver-topology-deployment.v1.json",
                "guest-product-vitalserver-topology-deployment.json",
            ),
            external_vitalserver_delivery_configuration=copied_product_document(
                "guest-product/external-vitalserver-delivery-configuration.reference.v1.json",
                "external-vitalserver-delivery-configuration.json",
            ),
        )


if __name__ == "__main__":
    unittest.main()
