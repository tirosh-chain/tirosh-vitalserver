"""Pure and staged-payload checks for the macOS Host package composer."""

from __future__ import annotations

import json
import os
from dataclasses import replace
from pathlib import Path, PurePosixPath
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from tooling import macos_host_package_composer as composer
from tooling import macos_host_package_verifier as verifier


MACOS_NATIVE_PACKAGE_TOOL_TESTS = (
    "test_developer_id_virtual_machine_supervisor_is_signed_and_verified_only_in_the_staged_payload",
    "test_unsigned_development_package_can_carry_an_ad_hoc_entitled_supervisor",
    "test_pkgbuild_composes_an_unsigned_package_without_installing_it",
    "test_package_verifier_requires_c23_product_version_to_match_packaged_c33",
    "test_package_verifier_requires_the_explicit_payload_base_path",
)
requires_macos_native_package_tools = unittest.skipUnless(
    sys.platform == "darwin",
    "requires the macOS pkgbuild and pkgutil tools",
)


class MacOSHostPackageComposerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.payload_base_path = PurePosixPath("/Library/Application Support/VitalServerRuntimePlatform")
        self.current_release_path = self.payload_base_path / "current"
        self.release_slot_id = "runtime-platform-0.1.0-dev-build-001"
        self.host_agent_binary = self.write_file("artifacts/host-agent", b"host-agent")
        self.host_edge_proxy_binary = self.write_file("artifacts/host-edge-proxy", b"host-edge-proxy")
        self.host_installation_manager_binary = self.write_file("artifacts/host-installation-manager", b"host-installation-manager")
        self.host_update_handoff_supervisor_binary = self.write_file(
            "artifacts/host-update-handoff-supervisor",
            b"host-update-handoff-supervisor",
        )
        self.platformctl_binary = self.write_file("artifacts/platformctl", b"platformctl")
        self.macos_virtual_machine_supervisor_binary = self.write_file("artifacts/macos-virtual-machine-supervisor", b"virtual-machine-supervisor")
        self.operator_application_bundle = self.write_operator_application_bundle()
        self.guest_product_process_supervisor_artifact = self.write_file("artifacts/guest-product-process-supervisor", b"guest-product-process-supervisor")
        self.guest_bundled_upstream_image_set_manager_artifact = self.write_file(
            "artifacts/guest-bundled-upstream-image-set-manager",
            b"guest-bundled-upstream-image-set-manager",
        )
        self.guest_product_release_manager_artifact = self.write_file(
            "artifacts/guest-product-release-manager", b"guest-product-release-manager"
        )
        self.guest_product_release_manager_configuration_artifact = self.write_file(
            "artifacts/guest-product-release-manager.json",
            b'{"schemaVersion":"v1"}',
        )
        self.guest_telemetry_collector_artifact = self.write_file(
            "artifacts/guest-telemetry-collector", b"guest-telemetry-collector"
        )
        self.guest_telemetry_collector_configuration_artifact = self.write_file(
            "artifacts/guest-telemetry-collector.yaml", b"receivers: {}\n"
        )
        self.guest_kernel = self.write_file("artifacts/Image", b"kernel")
        self.guest_initial_ramdisk = self.write_file("artifacts/initrd.img", b"initrd")
        self.guest_root_storage = self.write_file("artifacts/guest-root.raw", b"root disk")
        self.guest_product_bootstrap_volume = self.write_file("artifacts/guest-product-bootstrap.raw", b"bootstrap volume")
        self.pkgbuild = self.write_file("artifacts/pkgbuild", b"pkgbuild")
        self.virtual_machine_supervisor_virtualization_entitlements = self.write_file(
            "artifacts/macos-virtual-machine-supervisor.entitlements",
            b"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict><key>com.apple.security.virtualization</key><true/></dict></plist>
""",
        )
        self.c32_path = self.root / "configuration" / "macos-virtual-machine.json"
        self.c33_path = self.root / "configuration" / "host-agent-deployment.json"
        self.c53_path = self.root / "configuration" / "operator-interface-bootstrap.json"
        self.c36_path = self.root / "configuration" / "host-edge-proxy-deployment.json"
        self.c56_path = self.root / "configuration" / "host-update-handoff-supervisor-configuration.json"
        self.c58_path = self.root / "configuration" / "update-trust-store.json"
        self.c34_path = self.root / "configuration" / "macos-guest-artifact-manifest.json"
        self.c35_receipt_path = self.root / "configuration" / "guest-artifact-compilation-receipt.json"
        self.c37_path = self.root / "configuration" / "guest-product-process-deployment.json"
        self.c38_path = self.root / "configuration" / "guest-product-service-manager-deployment.json"
        self.c39_path = self.root / "configuration" / "guest-product-bootstrap-configuration.json"
        self.c44_path = self.root / "configuration" / "guest-product-vitalserver-topology-deployment.json"
        self.c46_path = self.root / "configuration" / "external-vitalserver-delivery-configuration.json"
        self.c64_path = (
            self.root
            / "configuration"
            / "guest-bundled-upstream-image-set-manager-configuration.json"
        )
        self.release_delivery_plans_document_path = (
            self.root / "configuration" / "release-delivery-plans.json"
        )
        self.write_json(self.c32_path, self.virtual_machine_document())
        self.write_json(self.c33_path, self.host_agent_deployment_document())
        self.write_json(self.c53_path, self.operator_interface_bootstrap_configuration_document())
        self.write_json(self.c36_path, self.host_edge_proxy_deployment_document())
        self.write_json(
            self.c56_path,
            self.host_update_handoff_supervisor_configuration_document(),
        )
        self.write_json(self.c58_path, self.host_update_trust_store_document())
        self.write_json(self.c34_path, self.guest_artifact_manifest_document())
        self.write_json(self.c37_path, self.guest_product_process_deployment_document())
        self.write_json(self.c38_path, self.guest_product_service_manager_deployment_document())
        self.write_json(self.c39_path, self.guest_product_bootstrap_configuration_document())
        self.write_json(self.c44_path, self.guest_product_vitalserver_topology_deployment_document())
        self.write_json(self.c46_path, self.external_vitalserver_delivery_configuration_document())
        self.write_json(self.c35_receipt_path, self.guest_artifact_compilation_receipt_document())
        self.write_json(
            self.release_delivery_plans_document_path,
            self.release_delivery_plans_document(),
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_file(self, relative_path: str, contents: bytes) -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        return path

    def write_json(self, path: Path, document: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(document), encoding="utf-8")

    def virtual_machine_document(self) -> dict:
        return {
            "schemaVersion": "v1",
            "machineId": "vitalserver-macos-guest",
            "cpuCount": 4,
            "memoryBytes": 8589934592,
            "boot": {
                "kernelPath": str(self.current_release_path / "vm" / "assets" / "Image"),
                "initialRamdiskPath": str(self.current_release_path / "vm" / "assets" / "initrd.img"),
                "guestRootDevicePath": "/dev/vda1",
                "commandLine": "console=hvc0 root=/dev/vda1",
            },
            "guestBootConsoleCapture": {
                "capturePath": "/var/lib/vitalserver/data/guest-boot-console.log",
                "writeMode": "append",
            },
            "guestRuntimeDiskProvisioning": {
                "releaseArtifactManifestPath": str(
                    self.current_release_path
                    / "release"
                    / "macos-guest-artifact-manifest.json"
                ),
                "releaseArtifactPath": str(
                    self.current_release_path / "release" / "guest-root.raw"
                ),
                "runtimeDiskImagePath": "/var/lib/vitalserver/data/vm/guest-root.raw",
                "provisioningReceiptPath": "/var/lib/vitalserver/data/vm/guest-root-provisioning-receipt.json",
                "existingRuntimeDiskPolicy": "retain-when-receipt-matches-release-artifact",
            },
            "guestRuntimeControlHostLocalHTTPBridge": {
                "hostLoopbackAddress": "127.0.0.1",
                "hostLoopbackPort": 18443,
                "guestVirtioSocketPort": 18443,
            },
            "guestProductReleaseManagerHostLocalHTTPBridge": {
                "hostLoopbackAddress": "127.0.0.1",
                "hostLoopbackPort": 18444,
                "guestVirtioSocketPort": 18444,
            },
            "guestPublicServiceHostLocalHTTPBridges": [
                {
                    "routeId": "recorder-gateway",
                    "hostLoopbackAddress": "127.0.0.1",
                    "hostLoopbackPort": 18090,
                    "guestVirtioSocketPort": 18090,
                },
            ],
            "storageDevices": [
                {
                    "id": "guest-root",
                    "role": "guest-root-storage",
                    "storageImageFormat": "raw",
                    "diskImagePath": "/var/lib/vitalserver/data/vm/guest-root.raw",
                    "readOnly": False,
                    "attachmentIndex": 0,
                },
                {
                    "id": "guest-product-bootstrap",
                    "role": "guest-product-bootstrap-volume",
                    "storageImageFormat": "raw",
                    "guestVolumeFileSystem": "iso9660",
                    "diskImagePath": str(self.current_release_path / "vm" / "disks" / "guest-product-bootstrap.raw"),
                    "readOnly": True,
                    "attachmentIndex": 1,
                },
            ],
            "network": {"attachment": "nat", "macAddress": "02:16:3e:00:00:01"},
        }

    def host_agent_deployment_document(self) -> dict:
        return {
            "schemaVersion": "v1",
            "control": {
                "localAdministration": {
                    "transport": "unix-domain-socket",
                    "endpointAddress": "/var/lib/vitalserver/control/host-agent.sock",
                    "descriptorPath": "/var/lib/vitalserver/control/host-agent.local.json",
                    "authorizedUserId": 501,
                },
                "loopbackHTTP": {"mode": "disabled"},
                "stateDatabasePath": "/var/lib/vitalserver/host-agent/host-agent.sqlite",
                "guestTimeoutMilliseconds": 5000,
            },
            "installation": {
                "installationId": "vitalserver-macos",
                "productVersion": "0.1.0-dev",
                "runtimeVersion": "0.1.0-dev",
                "dataDirectory": "/var/lib/vitalserver/data",
            },
            "guestRuntimeControlEndpoint": {"id": "vitalserver-guest", "scheme": "http", "host": "127.0.0.1", "port": 18443},
            "provider": {
                "kind": "macos-virtualization",
                "id": "vitalserver-macos-provider",
                "macOSVirtualMachineSupervisorExecutablePath": str(self.current_release_path / "bin" / "macos-virtual-machine-supervisor"),
                "macOSVirtualMachineConfigurationPath": str(self.current_release_path / "config" / "macos-virtual-machine.json"),
            },
            "time": {"hostNodeId": "vitalserver-macos-host", "timeAuthorityId": "vitalserver-host-time", "providerMode": "unsupported"},
            "telemetry": {"kind": "telemetry-export-outcome-profile", "pipelineMode": "unsupported", "exportMode": "unavailable"},
            "updateBootstrap": {
                "mode": "staged",
                "bundleStoreDirectory": "/var/lib/vitalserver/data/update-bundles",
                "stagingDirectory": "/var/lib/vitalserver/data/update-staging",
                "trustStorePath": str(
                    self.current_release_path / "config" / "update-trust-store.json"
                ),
            },
        }

    def operator_interface_bootstrap_configuration_document(self) -> dict:
        return {
            "schemaVersion": "v1",
            "bootstrapConfigurationPath": "/var/lib/vitalserver/control/runtime-console-bootstrap.json",
            "localAdministrationDescriptorPath": "/var/lib/vitalserver/control/host-agent.local.json",
        }

    def host_update_handoff_supervisor_configuration_document(self) -> dict:
        return {
            "schemaVersion": "v1",
            "id": "vitalserver-macos-update-handoff-supervisor",
            "stagingDirectory": "/var/lib/vitalserver/data/update-staging",
            "handoffQueueDirectory": "/var/lib/vitalserver/data/update-staging/handoff-queue",
            "executionEvidenceDirectory": "/var/lib/vitalserver/data/update-execution",
            "layerEffectReceiptDirectory": "/var/lib/vitalserver/data/update-layer-effects",
            "hostLocalAdministrationDescriptorPath": "/var/lib/vitalserver/control/host-agent.local.json",
            "layerEffectTimeoutMilliseconds": 300000,
            "completionTimeoutMilliseconds": 30000,
            "servicePollIntervalMilliseconds": 1000,
        }

    def host_update_trust_store_document(self) -> dict:
        return {
            "schemaVersion": "v1",
            "keys": [
                {
                    "id": "vitalserver-test-update-key",
                    "algorithm": "ed25519",
                    "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                }
            ],
        }

    def release_delivery_plans_document(self) -> dict:
        return {
            "schemaVersion": "v1",
            "plans": [
                {
                    "schemaVersion": "v1",
                    "id": "macos-runtime-platform-release",
                    "productVersion": "0.1.0-dev",
                    "platform": "macos",
                    "providerKind": "macos-virtualization",
                    "intendedInstallerArtifact": {
                        "kind": "pkg",
                        "expectedName": "VitalServerRuntimePlatform-0.1.0-dev.pkg",
                    },
                    "macOSInstallerPackageIdentifier": "com.tirosh.vitalserver.runtime-platform",
                    "macOSInstallerSignaturePolicy": "unsigned",
                    "requiredHostServiceRegistrations": [
                        {
                            "role": "host-agent",
                            "manager": "launchd",
                            "name": "com.tirosh.vitalserver.host-agent",
                        },
                        {
                            "role": "host-edge-proxy",
                            "manager": "launchd",
                            "name": "com.tirosh.vitalserver.host-edge-proxy",
                        },
                        {
                            "role": "host-update-handoff-supervisor",
                            "manager": "launchd",
                            "name": "com.tirosh.vitalserver.host-update-handoff-supervisor",
                        },
                    ],
                    "requiredProofStages": [
                        "artifact-integrity",
                        "sbom-and-notices",
                        "clean-install",
                        "service-registration",
                        "reboot",
                        "update",
                        "rollback",
                        "uninstall-reinstall",
                    ],
                }
            ],
        }

    def host_edge_proxy_deployment_document(self) -> dict:
        return {
            "schemaVersion": "v1",
            "proxyId": "vitalserver-macos-public-edge",
            "listener": {"protocol": "http", "bindHost": "0.0.0.0", "port": 8088},
            "readinessPath": "/ready",
            "clientIdentityHeaderPolicy": "replace-with-remote-address",
            "routes": [
                {
                    "id": "recorder-gateway",
                    "requestPathPrefix": "/socket.io/",
                    "target": {"scheme": "http", "host": "127.0.0.1", "port": 18090},
                    "forwardingProtocol": "http-and-websocket",
                    "requestHostHeaderPolicy": "preserve-client-host",
                    "maximumRequestBodyBytes": 4194304,
                    "upstreamResponseHeaderTimeoutMilliseconds": 30000,
                },
            ],
        }

    def guest_artifact_manifest_document(self) -> dict:
        def digest(source: Path) -> dict:
            return {"sizeBytes": source.stat().st_size, "sha256": composer.sha256_file(source)}

        return {
            "schemaVersion": "v1",
            "artifactSetId": "vitalserver-guest-arm64-acceptance",
            "architecture": "arm64",
            "kernel": digest(self.guest_kernel),
            "initialRamdisk": digest(self.guest_initial_ramdisk),
            "storageDevices": [
                {"id": "guest-root", "role": "guest-root-storage", "storageImageFormat": "raw", **digest(self.guest_root_storage)},
                {"id": "guest-product-bootstrap", "role": "guest-product-bootstrap-volume", "storageImageFormat": "raw", "guestVolumeFileSystem": "iso9660", **digest(self.guest_product_bootstrap_volume)},
            ],
        }

    def guest_product_process_deployment_document(self) -> dict:
        product_document_path = Path(__file__).resolve().parents[2] / "product" / "guest-product" / "guest-product-process-deployment.v1.json"
        return json.loads(product_document_path.read_text(encoding="utf-8"))

    def guest_product_service_manager_deployment_document(self) -> dict:
        product_document_path = Path(__file__).resolve().parents[2] / "product" / "guest-product" / "guest-product-service-manager-deployment.v1.json"
        return json.loads(product_document_path.read_text(encoding="utf-8"))

    def guest_product_bootstrap_configuration_document(self) -> dict:
        product_document_path = Path(__file__).resolve().parents[2] / "product" / "guest-product" / "guest-product-bootstrap-configuration.v1.json"
        return json.loads(product_document_path.read_text(encoding="utf-8"))

    def guest_product_vitalserver_topology_deployment_document(self) -> dict:
        product_document_path = Path(__file__).resolve().parents[2] / "product" / "guest-product" / "guest-product-vitalserver-topology-deployment.v1.json"
        return json.loads(product_document_path.read_text(encoding="utf-8"))

    def external_vitalserver_delivery_configuration_document(self) -> dict:
        product_document_path = Path(__file__).resolve().parents[2] / "product" / "guest-product" / "external-vitalserver-delivery-configuration.reference.v1.json"
        return json.loads(product_document_path.read_text(encoding="utf-8"))

    def bundled_vitalserver_product_document(self, file_name: str) -> dict:
        product_document_path = (
            Path(__file__).resolve().parents[2]
            / "product"
            / "guest-product"
            / file_name
        )
        return json.loads(product_document_path.read_text(encoding="utf-8"))

    def macos_virtualization_external_vitalserver_reference_deployment_document(
        self,
        file_name: str,
    ) -> dict:
        """Load one named Host deployment input from the reference profile."""

        product_document_path = (
            Path(__file__).resolve().parents[2]
            / "product"
            / "deployment-profiles"
            / "macos-virtualization-external-vitalserver-reference"
            / file_name
        )
        return json.loads(product_document_path.read_text(encoding="utf-8"))

    def guest_artifact_compilation_receipt_document(self) -> dict:
        def consumed(identifier: str, source: Path) -> dict:
            return {"id": identifier, "sizeBytes": source.stat().st_size, "sha256": composer.sha256_file(source)}

        return {
            "schemaVersion": "v1",
            "compilationId": "vitalserver-guest-artifact-acceptance",
            "artifactSetId": "vitalserver-guest-arm64-acceptance",
            "compilationCommandSHA256": "a" * 64,
            "buildEnvironment": {
                "id": "guest-product-bootstrap-artifact-composer",
                "builderExecutableSizeBytes": self.pkgbuild.stat().st_size,
                "builderExecutableSHA256": composer.sha256_file(self.pkgbuild),
            },
            "consumedInputArtifacts": [
                consumed("linux-arm64-kernel", self.guest_kernel),
                consumed("linux-arm64-initrd", self.guest_initial_ramdisk),
                consumed("guest-runtime-linux-arm64", self.host_agent_binary),
                consumed(
                    "guest-telemetry-collector-linux-arm64",
                    self.guest_telemetry_collector_artifact,
                ),
                consumed(
                    "guest-telemetry-collector-configuration",
                    self.guest_telemetry_collector_configuration_artifact,
                ),
                consumed("guest-node-services-linux-arm64", self.macos_virtual_machine_supervisor_binary),
                consumed("guest-product-process-supervisor-linux-arm64", self.guest_product_process_supervisor_artifact),
                consumed("guest-product-process-deployment-configuration", self.c37_path),
                consumed(
                    "guest-product-release-manager-linux-arm64",
                    self.guest_product_release_manager_artifact,
                ),
                consumed(
                    "guest-product-release-manager-configuration",
                    self.guest_product_release_manager_configuration_artifact,
                ),
                consumed("guest-product-service-manager-deployment-configuration", self.c38_path),
                consumed("guest-product-bootstrap-configuration", self.c39_path),
                consumed("guest-product-vitalserver-topology-deployment", self.c44_path),
                consumed("external-vitalserver-delivery-configuration", self.c46_path),
                consumed("linux-arm64-root-storage-base", self.guest_root_storage),
            ],
            "macOSGuestArtifactManifest": {
                "relativePath": "macos-guest-artifact-manifest.json",
                "sizeBytes": self.c34_path.stat().st_size,
                "sha256": composer.sha256_file(self.c34_path),
            },
            "completedAt": "2026-07-17T10:00:00Z",
        }

    def composition(self) -> composer.MacOSHostPackageComposition:
        return composer.MacOSHostPackageComposition(
            release_delivery_plans_document=self.release_delivery_plans_document_path,
            release_delivery_plan_id="macos-runtime-platform-release",
            payload_base_path=self.payload_base_path,
            release_slot_id=self.release_slot_id,
            host_agent_binary=self.host_agent_binary,
            host_edge_proxy_binary=self.host_edge_proxy_binary,
            host_installation_manager_binary=self.host_installation_manager_binary,
            host_update_handoff_supervisor_binary=(
                self.host_update_handoff_supervisor_binary
            ),
            platformctl_binary=self.platformctl_binary,
            macos_virtual_machine_supervisor_binary=self.macos_virtual_machine_supervisor_binary,
            operator_application_bundle=self.operator_application_bundle,
            host_agent_deployment_configuration=self.c33_path,
            operator_interface_bootstrap_configuration=self.c53_path,
            host_edge_proxy_deployment_configuration=self.c36_path,
            host_update_handoff_supervisor_configuration=self.c56_path,
            host_update_trust_store=self.c58_path,
            macos_virtual_machine_configuration=self.c32_path,
            guest_artifact_manifest=self.c34_path,
            guest_artifact_compilation_receipt=self.c35_receipt_path,
            guest_product_process_supervisor_artifact=self.guest_product_process_supervisor_artifact,
            guest_product_process_deployment_configuration=self.c37_path,
            guest_product_service_manager_deployment_configuration=self.c38_path,
            guest_product_bootstrap_configuration=self.c39_path,
            guest_product_vitalserver_topology_deployment=self.c44_path,
            external_vitalserver_delivery_configuration=self.c46_path,
            guest_kernel_source=self.guest_kernel,
            guest_initial_ramdisk_source=self.guest_initial_ramdisk,
            guest_storage_sources={
                "guest-root": self.guest_root_storage,
                "guest-product-bootstrap": self.guest_product_bootstrap_volume,
            },
            output_package=self.root / "output" / "VitalServerRuntimePlatform-0.1.0-dev.pkg",
            pkgbuild_executable=self.pkgbuild,
            macos_installer_package_signing=composer.MacOSInstallerPackageSigning(
                mode="unsigned",
                signing_identity=None,
                productsign_executable=None,
            ),
            macos_virtual_machine_supervisor_code_signing=composer.MacOSVirtualMachineSupervisorCodeSigning(
                mode="unsigned",
                signing_identity=None,
                codesign_executable=None,
                virtualization_entitlements=None,
            ),
            replace_output=False,
        )

    def write_operator_application_bundle(self) -> Path:
        bundle = self.root / "artifacts" / "VitalServer Runtime Platform.app"
        executable = bundle / "Contents" / "MacOS" / "VitalServer Runtime Platform"
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(b"operator-application")
        executable.chmod(0o755)
        info = bundle / "Contents" / "Info.plist"
        info.write_bytes(b"operator-application-info")
        framework_link = bundle / "Contents" / "Frameworks" / "runtime-entrypoint"
        framework_link.parent.mkdir(parents=True, exist_ok=True)
        framework_link.symlink_to("../MacOS/VitalServer Runtime Platform")
        return bundle

    def test_load_requires_c32_and_c33_to_name_the_exact_payload_resources(self) -> None:
        documents = composer.load_macos_host_package_documents(self.composition())
        self.assertEqual("macos-virtualization", documents.host_agent_deployment["provider"]["kind"])

        deployment = self.host_agent_deployment_document()
        deployment["provider"]["macOSVirtualMachineSupervisorExecutablePath"] = "/opt/unknown-provider-supervisor"
        self.write_json(self.c33_path, deployment)
        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "virtual machine supervisor path"):
            composer.load_macos_host_package_documents(self.composition())

    def test_macos_virtualization_external_vitalserver_reference_deployment_profile_preserves_cross_boundary_contracts(self) -> None:
        """The reference profile must be usable as one complete Host package input set."""

        self.write_json(
            self.c32_path,
            self.macos_virtualization_external_vitalserver_reference_deployment_document(
                "macos-virtual-machine-configuration.v1.json"
            ),
        )
        self.write_json(
            self.c33_path,
            self.macos_virtualization_external_vitalserver_reference_deployment_document(
                "host-agent-deployment-configuration.v1.json"
            ),
        )
        self.write_json(
            self.c53_path,
            self.macos_virtualization_external_vitalserver_reference_deployment_document(
                "operator-interface-bootstrap-configuration.v1.json"
            ),
        )
        self.write_json(
            self.c36_path,
            self.macos_virtualization_external_vitalserver_reference_deployment_document(
                "host-edge-proxy-deployment-configuration.v1.json"
            ),
        )
        self.write_json(
            self.c56_path,
            self.macos_virtualization_external_vitalserver_reference_deployment_document(
                "host-update-handoff-supervisor-configuration.v1.json"
            ),
        )
        self.write_json(
            self.c58_path,
            self.macos_virtualization_external_vitalserver_reference_deployment_document(
                "update-trust-store.v1.json"
            ),
        )
        release_delivery_plans = self.release_delivery_plans_document()
        selected_release_plan = release_delivery_plans["plans"][0]
        selected_release_plan["productVersion"] = "0.2.0-dev"
        selected_release_plan["intendedInstallerArtifact"]["expectedName"] = (
            "VitalServerRuntimePlatform-0.2.0-dev.pkg"
        )
        self.write_json(
            self.release_delivery_plans_document_path,
            release_delivery_plans,
        )

        documents = composer.load_macos_host_package_documents(
            replace(
                self.composition(),
                output_package=(
                    self.root
                    / "output"
                    / "VitalServerRuntimePlatform-0.2.0-dev.pkg"
                ),
            )
        )

        self.assertEqual(
            "vitalserver-macos-virtualization-external-vitalserver-reference",
            documents.virtual_machine["machineId"],
        )
        self.assertEqual(
            "vitalserver-runtime-platform-macos-reference",
            documents.host_agent_deployment["installation"]["installationId"],
        )
        self.assertEqual(
            "vitalserver-macos-public-edge",
            documents.host_edge_proxy_deployment["proxyId"],
        )

    def test_load_requires_c23_release_plan_product_version_to_match_c33_installation(self) -> None:
        deployment = self.host_agent_deployment_document()
        deployment["installation"]["productVersion"] = "0.2.0-dev"
        self.write_json(self.c33_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C23 MacOSHostPackageReleasePlan product version must match C33 installation.productVersion",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_composition_requires_c23_expected_package_file_name(self) -> None:
        output_directory = self.root / "output"
        output_directory.mkdir()
        composition = replace(
            self.composition(),
            output_package=output_directory / "different-product.pkg",
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "output package file name must match C23 MacOSHostPackageReleasePlan",
        ):
            composer.compose_macos_host_package(composition)

    def test_load_rejects_a_host_agent_control_endpoint_that_does_not_match_its_declared_host_local_bridge(self) -> None:
        deployment = self.host_agent_deployment_document()
        deployment["guestRuntimeControlEndpoint"]["port"] = 8080
        self.write_json(self.c33_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "Guest Runtime Control endpoint port must match C32 Guest Runtime control Host-local HTTP bridge hostLoopbackPort",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_load_rejects_a_guest_virtio_socket_listener_that_does_not_match_its_declared_host_local_bridge(self) -> None:
        deployment = self.guest_product_process_deployment_document()
        deployment["guestRuntime"]["controlVirtioSocketListener"]["port"] = 18444
        self.write_json(self.c37_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "guestVirtioSocketPort must match C37 Guest Runtime controlVirtioSocketListener port",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_load_requires_c37_external_topology_and_observation_paths_to_use_the_declared_c39_current_release_link(self) -> None:
        deployment = self.guest_product_process_deployment_document()
        deployment["recorderGateway"]["vitalServerTopologyDeploymentPath"] = (
            "/opt/vitalserver/releases/another-release/config/guest-product-vitalserver-topology-deployment.json"
        )
        self.write_json(self.c37_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C37 Recorder Gateway topology path must match C39 C44 installation destination through C39 guestProductRelease.currentReleaseLinkPath",
        ):
            composer.load_macos_host_package_documents(self.composition())

        deployment = self.guest_product_process_deployment_document()
        deployment["guestRuntime"]["externalUpstreamObservationProvider"][
            "externalVitalServerDeliveryConfigurationPath"
        ] = "/opt/vitalserver/current/config/wrong-external-vitalserver-delivery-configuration.json"
        self.write_json(self.c37_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C37 Guest Runtime external VitalServer observation configuration path must match C39 C46 installation destination through C39 guestProductRelease.currentReleaseLinkPath",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_load_rejects_a_guest_runtime_control_endpoint_that_claims_unimplemented_tls(self) -> None:
        deployment = self.host_agent_deployment_document()
        deployment["guestRuntimeControlEndpoint"]["scheme"] = "https"
        self.write_json(self.c33_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "scheme must be http because the packaged C37 Guest Runtime listener has no TLS adapter",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_load_requires_each_public_proxy_route_to_target_its_declared_host_local_bridge(self) -> None:
        deployment = self.host_edge_proxy_deployment_document()
        deployment["routes"][0]["target"]["host"] = "192.168.64.2"
        self.write_json(self.c36_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C36 public route recorder-gateway target must match its C32 Guest public service Host-local HTTP bridge",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_load_requires_each_public_bridge_to_target_its_declared_guest_virtio_socket_listener(self) -> None:
        deployment = self.guest_product_process_deployment_document()
        deployment["guestRuntime"]["publicServiceVirtioSocketBridges"][0][
            "virtioSocketPort"
        ] = 18091
        self.write_json(self.c37_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C32 Guest public service Host-local HTTP bridge recorder-gateway guestVirtioSocketPort must match its C37 public service virtio socket listener",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_load_rejects_a_public_bridge_that_names_an_unplanned_guest_product_process(self) -> None:
        deployment = self.guest_product_process_deployment_document()
        bridge = deployment["guestRuntime"]["publicServiceVirtioSocketBridges"][0]
        bridge["guestProductProcessName"] = "vitalserver-browser"
        bridge["targetPort"] = 8088
        self.write_json(self.c37_path, deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C37 Guest public service virtio socket bridge recorder-gateway must name a planned Guest Product process whose declared listener owns targetPort",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_load_requires_c32_c36_and_c37_to_name_the_same_public_service_routes(self) -> None:
        virtual_machine = self.virtual_machine_document()
        virtual_machine["guestPublicServiceHostLocalHTTPBridges"][0]["routeId"] = "undeclared-service"
        self.write_json(self.c32_path, virtual_machine)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C32 Guest public service bridges, C36 public routes, and C37 Guest public service virtio socket listeners must name the same route IDs",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_verifier_rejects_a_public_route_that_does_not_target_its_c32_host_local_bridge(self) -> None:
        c36 = self.host_edge_proxy_deployment_document()
        c36["routes"][0]["target"] = {
            "scheme": "http",
            "host": "192.168.64.2",
            "port": 8090,
        }
        with self.assertRaisesRegex(
            verifier.MacOSHostPackageVerificationError,
            "C36 route recorder-gateway target must match its C32 Guest public service Host-local HTTP bridge",
        ):
            verifier.verify_host_edge_proxy_routes_target_c32_public_service_bridges(
                c36,
                self.virtual_machine_document(),
            )

    def test_payload_copy_materializes_only_explicit_resources(self) -> None:
        documents = composer.load_macos_host_package_documents(self.composition())
        with tempfile.TemporaryDirectory() as payload_directory:
            payload_root = Path(payload_directory)
            composer.copy_package_payload(self.composition(), documents, payload_root)
            release_root = payload_root / "Library/Application Support/VitalServerRuntimePlatform/releases" / self.release_slot_id
            self.assertEqual(b"host-agent", (release_root / "bin/host-agent").read_bytes())
            self.assertEqual(b"host-edge-proxy", (release_root / "bin/host-edge-proxy").read_bytes())
            self.assertEqual(b"host-installation-manager", (release_root / "bin/host-installation-manager").read_bytes())
            self.assertEqual(
                b"host-update-handoff-supervisor",
                (release_root / "bin/host-update-handoff-supervisor").read_bytes(),
            )
            self.assertEqual(b"platformctl", (release_root / "bin/platformctl").read_bytes())
            self.assertEqual(b"virtual-machine-supervisor", (release_root / "bin/macos-virtual-machine-supervisor").read_bytes())
            self.assertEqual(b"kernel", (release_root / "vm/assets/Image").read_bytes())
            self.assertEqual(b"root disk", (release_root / "release/guest-root.raw").read_bytes())
            self.assertFalse((payload_root / "var/lib/vitalserver/data/vm/guest-root.raw").exists())
            self.assertFalse((payload_root / "var/lib/vitalserver/data/vm/guest-root-provisioning-receipt.json").exists())
            self.assertEqual(b"bootstrap volume", (release_root / "vm/disks/guest-product-bootstrap.raw").read_bytes())
            self.assertTrue((release_root / "release/macos-guest-artifact-manifest.json").is_file())
            self.assertTrue((release_root / "release/guest-artifact-compilation-receipt.json").is_file())
            self.assertTrue((payload_root / "Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist").is_file())
            self.assertTrue((payload_root / "Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist").is_file())
            self.assertTrue((payload_root / "Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist").is_file())
            staged_application = payload_root / "Applications/VitalServer Runtime Platform.app"
            self.assertEqual(
                b"operator-application",
                (staged_application / "Contents/MacOS/VitalServer Runtime Platform").read_bytes(),
            )
            self.assertEqual(
                composer.sha256_macos_application_bundle_tree(
                    self.operator_application_bundle
                ),
                composer.sha256_macos_application_bundle_tree(staged_application),
            )

    def test_operator_application_bundle_rejects_a_link_escaping_its_declared_tree(self) -> None:
        (self.operator_application_bundle / "Contents" / "escaped").symlink_to(
            "/etc/passwd"
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "symbolic link escaping the bundle",
        ):
            composer.validate_package_artifacts(
                self.composition(),
                composer.load_macos_host_package_documents(self.composition()),
            )

    def test_handoff_supervisor_launchd_definition_uses_the_persistent_c56_service_mode(self) -> None:
        documents = composer.load_macos_host_package_documents(self.composition())
        definition = composer.compose_host_update_handoff_supervisor_launchd_service_definition(
            self.composition(),
            documents.macos_host_package_release_plan,
        )
        self.assertEqual("service", definition["ProgramArguments"][-1])
        self.assertIs(True, definition["RunAtLoad"])
        self.assertIs(True, definition["KeepAlive"])
        self.assertNotIn("StartInterval", definition)

    def test_payload_copy_does_not_preserve_build_host_extended_attributes(self) -> None:
        attribute_name = "user.vitalserver.package-composer-test"
        if hasattr(os, "setxattr"):
            try:
                os.setxattr(
                    self.host_agent_binary,
                    attribute_name,
                    b"unowned-build-host-metadata",
                )
            except OSError as error:
                self.skipTest(
                    "test filesystem cannot create an extended attribute: "
                    + str(error)
                )
        elif Path("/usr/bin/xattr").is_file():
            subprocess.run(
                [
                    "/usr/bin/xattr",
                    "-w",
                    attribute_name,
                    "unowned-build-host-metadata",
                    str(self.host_agent_binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        else:
            self.skipTest(
                "test platform has no extended-attribute write interface"
            )

        documents = composer.load_macos_host_package_documents(self.composition())
        with tempfile.TemporaryDirectory() as payload_directory:
            payload_root = Path(payload_directory)
            composer.copy_package_payload(self.composition(), documents, payload_root)
            staged_host_agent = (
                payload_root
                / "Library/Application Support/VitalServerRuntimePlatform/releases"
                / self.release_slot_id
                / "bin/host-agent"
            )
            if hasattr(os, "listxattr"):
                staged_attributes = os.listxattr(staged_host_agent)
            else:
                staged_attributes = subprocess.run(
                    ["/usr/bin/xattr", str(staged_host_agent)],
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.splitlines()
            self.assertNotIn(attribute_name, staged_attributes)
            self.assertEqual(0o755, staged_host_agent.stat().st_mode & 0o777)
            staged_host_agent_configuration = (
                payload_root
                / "Library/Application Support/VitalServerRuntimePlatform/releases"
                / self.release_slot_id
                / "config/host-agent-deployment.json"
            )
            self.assertEqual(0o644, staged_host_agent_configuration.stat().st_mode & 0o777)

    def test_release_virtual_machine_supervisor_entitlements_name_the_required_apple_capability(self) -> None:
        entitlements_path = (
            Path(__file__).resolve().parents[2]
            / "providers"
            / "macos-virtualization"
            / "MacOSVirtualMachineSupervisor.entitlements"
        )
        with entitlements_path.open("rb") as entitlement_file:
            entitlement_document = plistlib.load(entitlement_file)

        self.assertIs(True, entitlement_document.get("com.apple.security.virtualization"))

    def test_storage_source_set_must_match_c32(self) -> None:
        composition = replace(self.composition(), guest_storage_sources={})
        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "exactly one source artifact"):
            composer.load_macos_host_package_documents(composition)

    def test_package_scripts_delegate_preflight_and_service_quiescence_to_the_installation_manager(self) -> None:
        documents = composer.load_macos_host_package_documents(self.composition())
        preinstall = composer.compose_preinstall_script(self.composition(), documents)
        script = composer.compose_postinstall_script(
            self.composition(),
            documents.host_agent_deployment,
            documents.host_update_handoff_supervisor_configuration,
            documents.virtual_machine,
        )
        self.assertIn("'/var/lib/vitalserver/host-agent'", script)
        self.assertIn("'/var/lib/vitalserver/data'", script)
        self.assertIn("'/var/lib/vitalserver/data/update-bundles'", script)
        self.assertIn("'/var/lib/vitalserver/data/vm'", script)
        self.assertIn("/usr/bin/touch '/var/lib/vitalserver/data/guest-boot-console.log'", script)
        self.assertNotIn("/usr/bin/touch '/var/lib/vitalserver/data/vm/guest-root.raw'", script)
        self.assertNotIn("/usr/bin/touch '/var/lib/vitalserver/data/vm/guest-root-provisioning-receipt.json'", script)
        self.assertIn('"$script_directory/host-installation-manager" --mode preflight', preinstall)
        self.assertNotIn('"$script_directory/host-installation-manager" --mode quiesce', preinstall)
        self.assertIn("--release-id 'runtime-platform-0.1.0-dev-build-001'", preinstall)
        self.assertNotIn("/bin/launchctl bootout", preinstall)
        self.assertNotIn("/bin/launchctl bootout", script)
        self.assertNotIn("/bin/launchctl bootstrap", script)
        self.assertIn("--mode quiesce", script)
        self.assertIn("--mode activate", script)
        self.assertIn("--mode finalize", script)
        self.assertIn("--mode recover", script)
        self.assertIn("trap recover_installation 0", script)
        self.assertNotIn("|| true", script)
        self.assertNotIn("guest:start", script)
        self.assertNotIn("curl", script)

    def test_package_verifier_requires_declared_staged_update_directories_before_service_activation(self) -> None:
        directories = verifier.declared_host_runtime_directories(
            self.host_agent_deployment_document(),
            "/var/lib/vitalserver/data/guest-boot-console.log",
            {
                "runtimeDiskImagePath": "/var/lib/vitalserver/data/vm/guest-root.raw",
                "provisioningReceiptPath": "/var/lib/vitalserver/data/vm/guest-root-provisioning-receipt.json",
            },
        )
        self.assertIn(PurePosixPath("/var/lib/vitalserver/data/update-bundles"), directories)
        self.assertIn(PurePosixPath("/var/lib/vitalserver/data/update-staging"), directories)

    def test_package_verifier_rejects_script_inputs_not_bound_to_immutable_payload(self) -> None:
        verification = verifier.MacOSHostPackageVerification(
            package=self.root / "artifact.pkg",
            pkgutil_executable=Path("/usr/sbin/pkgutil"),
            release_delivery_plans_document=self.release_delivery_plans_document_path,
            release_delivery_plan_id="macos-runtime-platform-release",
            payload_base_path=self.payload_base_path,
            release_slot_id=self.release_slot_id,
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            expanded_package = Path(temporary_directory)
            scripts_root = expanded_package / "Scripts"
            payload_release_root = (
                expanded_package
                / "Payload"
                / str(self.payload_base_path).lstrip("/")
                / "releases"
                / self.release_slot_id
            )
            scripts_root.mkdir(parents=True)
            (payload_release_root / "bin").mkdir(parents=True)
            payload_manager = payload_release_root / "bin" / "host-installation-manager"
            payload_manager.write_bytes(b"immutable-manager")
            payload_manager.chmod(0o755)
            payload_manifest = payload_release_root / "installation-manifest.json"
            payload_manifest.write_bytes(b'{"immutable":true}\n')
            script_manager = scripts_root / "host-installation-manager"
            script_manager.write_bytes(b"different-manager")
            script_manager.chmod(0o755)
            script_manifest = scripts_root / "installation-manifest.json"
            script_manifest.write_bytes(payload_manifest.read_bytes())
            (scripts_root / "preinstall").write_text(
                "\n".join(
                    [
                        "#!/bin/sh",
                        "set -eu",
                        '"$script_directory/host-installation-manager" --mode preflight',
                        "--release-id '" + self.release_slot_id + "'",
                        '--manifest "$script_directory/installation-manifest.json"',
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                verifier.MacOSHostPackageVerificationError,
                "Manager bytes do not match",
            ):
                verifier.verify_preinstall_host_installation_transaction(
                    verification, expanded_package
                )
            script_manager.write_bytes(payload_manager.read_bytes())
            script_manifest.write_bytes(b'{"different":true}\n')
            with self.assertRaisesRegex(
                verifier.MacOSHostPackageVerificationError,
                "manifest bytes do not match",
            ):
                verifier.verify_preinstall_host_installation_transaction(
                    verification, expanded_package
                )

    def test_package_verifier_rejects_a_pre_materialized_guest_runtime_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as payload_directory:
            payload_root = Path(payload_directory)
            runtime_disk_payload_path = payload_root / "var/lib/vitalserver/data/vm/guest-root.raw"
            runtime_disk_payload_path.parent.mkdir(parents=True)
            runtime_disk_payload_path.write_bytes(b"Guest-owned state must not be packaged")

            with self.assertRaisesRegex(
                verifier.MacOSHostPackageVerificationError,
                "Guest Runtime disk workspace must not be materialized",
            ):
                verifier.verify_absent_host_runtime_workspace_from_package_payload(
                    payload_root,
                    "/var/lib/vitalserver/data/vm/guest-root.raw",
                    "C32 Guest Runtime disk workspace",
                )

    def test_package_composition_rejects_boot_console_capture_outside_host_data_directory(self) -> None:
        virtual_machine = self.virtual_machine_document()
        virtual_machine["guestBootConsoleCapture"]["capturePath"] = "/var/log/vitalserver/guest-boot-console.log"
        self.write_json(self.c32_path, virtual_machine)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "must be within C33 installation.dataDirectory",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_a_runtime_disk_that_is_not_the_c32_guest_root_attachment(self) -> None:
        virtual_machine = self.virtual_machine_document()
        virtual_machine["guestRuntimeDiskProvisioning"]["runtimeDiskImagePath"] = "/var/lib/vitalserver/data/vm/other-guest-root.raw"
        self.write_json(self.c32_path, virtual_machine)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "guest-root diskImagePath must name Guest Runtime disk provisioning",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_guest_source_that_does_not_match_c34(self) -> None:
        manifest = self.guest_artifact_manifest_document()
        manifest["kernel"]["sha256"] = "0" * 64
        self.write_json(self.c34_path, manifest)
        self.write_json(self.c35_receipt_path, self.guest_artifact_compilation_receipt_document())
        output_directory = self.root / "output"
        output_directory.mkdir()
        composition = replace(
            self.composition(),
            output_package=output_directory / "VitalServerRuntimePlatform-0.1.0-dev.pkg",
            pkgbuild_executable=self.pkgbuild,
        )
        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "Guest kernel source SHA-256"):
            composer.compose_macos_host_package(composition)

    def test_package_composition_rejects_c35_receipt_that_does_not_name_the_supplied_c34(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        receipt["macOSGuestArtifactManifest"]["sha256"] = "0" * 64
        self.write_json(self.c35_receipt_path, receipt)

        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "C35 receipt C34 SHA-256"):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_c35_receipt_that_does_not_name_the_supplied_c37_input(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        for input_artifact in receipt["consumedInputArtifacts"]:
            if input_artifact["id"] == "guest-product-process-deployment-configuration":
                input_artifact["sha256"] = "0" * 64
        self.write_json(self.c35_receipt_path, receipt)

        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "Guest Product process deployment configuration SHA-256"):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_c35_receipt_without_guest_node_services_bundle_input(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        receipt["consumedInputArtifacts"] = [
            artifact
            for artifact in receipt["consumedInputArtifacts"]
            if artifact["id"] != "guest-node-services-linux-arm64"
        ]
        with self.assertRaisesRegex(
            verifier.MacOSHostPackageVerificationError,
            "missing Guest Product process inputs: guest-node-services-linux-arm64",
        ):
            verifier.verify_guest_artifact_compilation_receipt(
                self.c34_path,
                self.guest_artifact_manifest_document(),
                receipt,
            )

    def test_package_composition_rejects_c37_that_violates_the_canonical_contract(self) -> None:
        deployment = self.guest_product_process_deployment_document()
        del deployment["recorderGateway"]["replayPolicy"]
        self.write_json(self.c37_path, deployment)

        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "C37 is invalid"):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_c35_receipt_that_does_not_name_the_supplied_c38_input(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        for input_artifact in receipt["consumedInputArtifacts"]:
            if input_artifact["id"] == "guest-product-service-manager-deployment-configuration":
                input_artifact["sha256"] = "0" * 64
        self.write_json(self.c35_receipt_path, receipt)

        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "Guest Product service-manager deployment configuration SHA-256"):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_c35_receipt_that_does_not_name_the_supplied_c39_input(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        for input_artifact in receipt["consumedInputArtifacts"]:
            if input_artifact["id"] == "guest-product-bootstrap-configuration":
                input_artifact["sha256"] = "0" * 64
        self.write_json(self.c35_receipt_path, receipt)

        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "Guest Product bootstrap configuration SHA-256"):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_c35_receipt_without_declared_telemetry_collector_input(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        receipt["consumedInputArtifacts"] = [
            artifact
            for artifact in receipt["consumedInputArtifacts"]
            if artifact["id"] != "guest-telemetry-collector-linux-arm64"
        ]
        self.write_json(self.c35_receipt_path, receipt)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "Guest telemetry Collector binary",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_c35_receipt_that_does_not_name_the_supplied_c44_input(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        for input_artifact in receipt["consumedInputArtifacts"]:
            if input_artifact["id"] == "guest-product-vitalserver-topology-deployment":
                input_artifact["sha256"] = "0" * 64
        self.write_json(self.c35_receipt_path, receipt)

        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "Guest Product VitalServer topology deployment SHA-256"):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_external_topology_without_an_explicit_c46_source(self) -> None:
        composition = replace(
            self.composition(),
            external_vitalserver_delivery_configuration=None,
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C44 external topology requires one explicit C46",
        ):
            composer.load_macos_host_package_documents(composition)

    def test_package_composition_rejects_c37_archive_provider_that_does_not_match_c46(self) -> None:
        process_deployment = self.guest_product_process_deployment_document()
        process_deployment["guestRuntime"]["archiveExportProvider"][
            "id"
        ] = "other-indexed-library"
        self.write_json(self.c37_path, process_deployment)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C37 Archive Export provider must match C46 VitalServer archive provider",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_accepts_bundled_topology_owned_by_c64_image_set_manager(self) -> None:
        self.write_json(
            self.c37_path,
            self.bundled_vitalserver_product_document(
                "guest-product-process-deployment-bundled-vitalserver.v1.json"
            ),
        )
        self.write_json(
            self.c39_path,
            self.bundled_vitalserver_product_document(
                "guest-product-bootstrap-configuration-bundled-vitalserver.v1.json"
            ),
        )
        self.write_json(
            self.c44_path,
            self.bundled_vitalserver_product_document(
                "guest-product-vitalserver-topology-deployment-bundled.v1.json"
            ),
        )
        self.write_json(
            self.c64_path,
            self.bundled_vitalserver_product_document(
                "guest-bundled-upstream-image-set-manager-configuration.v1.json"
            ),
        )
        virtual_machine = self.virtual_machine_document()
        virtual_machine["guestBundledUpstreamImageSetManagerHostLocalHTTPBridge"] = {
            "hostLoopbackAddress": "127.0.0.1",
            "hostLoopbackPort": 18445,
            "guestVirtioSocketPort": 18445,
        }
        self.write_json(self.c32_path, virtual_machine)

        receipt = self.guest_artifact_compilation_receipt_document()
        receipt["consumedInputArtifacts"] = [
            artifact
            for artifact in receipt["consumedInputArtifacts"]
            if artifact["id"] != "external-vitalserver-delivery-configuration"
        ]
        receipt["consumedInputArtifacts"].extend(
            [
                {
                    "id": "guest-bundled-upstream-image-set-manager-linux-arm64",
                    "sizeBytes": self.guest_bundled_upstream_image_set_manager_artifact.stat().st_size,
                    "sha256": composer.sha256_file(
                        self.guest_bundled_upstream_image_set_manager_artifact
                    ),
                },
                {
                    "id": "guest-bundled-upstream-image-set-manager-configuration",
                    "sizeBytes": self.c64_path.stat().st_size,
                    "sha256": composer.sha256_file(self.c64_path),
                },
            ]
        )
        self.write_json(self.c35_receipt_path, receipt)

        documents = composer.load_macos_host_package_documents(
            replace(
                self.composition(),
                external_vitalserver_delivery_configuration=None,
                guest_bundled_upstream_image_set_manager_configuration=self.c64_path,
            )
        )

        self.assertEqual(
            "bundled-vitalserver",
            documents.guest_product_vitalserver_topology_deployment["topologyKind"],
        )
        self.assertEqual(
            "bundled-upstream-image-set-manager",
            documents.guest_bundled_upstream_image_set_manager_configuration[
                "managerId"
            ],
        )

    def test_package_composition_rejects_bundled_c64_bridge_port_mismatch(self) -> None:
        self.write_json(
            self.c37_path,
            self.bundled_vitalserver_product_document(
                "guest-product-process-deployment-bundled-vitalserver.v1.json"
            ),
        )
        self.write_json(
            self.c39_path,
            self.bundled_vitalserver_product_document(
                "guest-product-bootstrap-configuration-bundled-vitalserver.v1.json"
            ),
        )
        self.write_json(
            self.c44_path,
            self.bundled_vitalserver_product_document(
                "guest-product-vitalserver-topology-deployment-bundled.v1.json"
            ),
        )
        self.write_json(
            self.c64_path,
            self.bundled_vitalserver_product_document(
                "guest-bundled-upstream-image-set-manager-configuration.v1.json"
            ),
        )
        virtual_machine = self.virtual_machine_document()
        virtual_machine["guestBundledUpstreamImageSetManagerHostLocalHTTPBridge"] = {
            "hostLoopbackAddress": "127.0.0.1",
            "hostLoopbackPort": 18445,
            "guestVirtioSocketPort": 18446,
        }
        self.write_json(self.c32_path, virtual_machine)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "bundled Upstream image-set manager Host-local HTTP bridge guestVirtioSocketPort",
        ):
            composer.load_macos_host_package_documents(
                replace(
                    self.composition(),
                    external_vitalserver_delivery_configuration=None,
                    guest_bundled_upstream_image_set_manager_configuration=self.c64_path,
                )
            )

    def test_package_composition_rejects_c35_receipt_that_does_not_name_the_supplied_c46_input(self) -> None:
        receipt = self.guest_artifact_compilation_receipt_document()
        for input_artifact in receipt["consumedInputArtifacts"]:
            if input_artifact["id"] == "external-vitalserver-delivery-configuration":
                input_artifact["sha256"] = "0" * 64
        self.write_json(self.c35_receipt_path, receipt)

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C46 External VitalServer delivery configuration SHA-256",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_c44_c46_provider_identity_mismatch(self) -> None:
        delivery_configuration = self.external_vitalserver_delivery_configuration_document()
        delivery_configuration["vitalServerDeliveryProvider"]["id"] = "other-external-vitalserver"
        self.write_json(self.c46_path, delivery_configuration)
        self.write_json(
            self.c35_receipt_path,
            self.guest_artifact_compilation_receipt_document(),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C44 VitalServer delivery provider must match C46 delivery provider",
        ):
            composer.load_macos_host_package_documents(self.composition())

    def test_package_composition_rejects_proxy_without_explicit_client_identity_policy(self) -> None:
        deployment = self.host_edge_proxy_deployment_document()
        del deployment["clientIdentityHeaderPolicy"]
        self.write_json(self.c36_path, deployment)
        with self.assertRaisesRegex(composer.MacOSHostPackageCompositionError, "client identity headers"):
            composer.load_macos_host_package_documents(self.composition())

    def test_developer_id_package_requires_a_developer_id_virtual_machine_supervisor(self) -> None:
        productsign = self.write_file("artifacts/productsign", b"productsign")
        composition = replace(
            self.composition(),
            macos_installer_package_signing=composer.MacOSInstallerPackageSigning(
                mode="developer-id",
                signing_identity="Developer ID Installer: Tirosh",
                productsign_executable=productsign,
            ),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "requires a developer-id macOS virtual machine supervisor",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    def test_developer_id_installer_package_requires_an_explicit_productsign_executable(self) -> None:
        composition = replace(
            self.composition(),
            macos_installer_package_signing=composer.MacOSInstallerPackageSigning(
                mode="developer-id",
                signing_identity="Developer ID Installer: Tirosh",
                productsign_executable=None,
            ),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "productsign executable is missing or not a file",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    def test_developer_id_installer_package_rejects_a_non_developer_id_identity(self) -> None:
        composition = replace(
            self.composition(),
            macos_installer_package_signing=composer.MacOSInstallerPackageSigning(
                mode="developer-id",
                signing_identity="Apple Development: Tirosh",
                productsign_executable=Path("/usr/bin/productsign"),
            ),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "requires a Developer ID Installer identity",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    def test_unsigned_installer_package_rejects_hidden_productsign_inputs(self) -> None:
        composition = replace(
            self.composition(),
            macos_installer_package_signing=composer.MacOSInstallerPackageSigning(
                mode="unsigned",
                signing_identity=None,
                productsign_executable=Path("/usr/bin/productsign"),
            ),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "unsigned macOS Installer package signing must not supply signing inputs",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    def test_package_composition_rejects_a_signing_mode_that_disagrees_with_c23_policy(self) -> None:
        release_delivery_plans = self.release_delivery_plans_document()
        release_delivery_plans["plans"][0]["macOSInstallerSignaturePolicy"] = "developer-id"
        self.write_json(self.release_delivery_plans_document_path, release_delivery_plans)
        composition = self.composition()

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "C23 macOS installer signature policy must match",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    def test_unsigned_virtual_machine_supervisor_code_signing_rejects_hidden_signing_inputs(self) -> None:
        composition = replace(
            self.composition(),
            macos_virtual_machine_supervisor_code_signing=composer.MacOSVirtualMachineSupervisorCodeSigning(
                mode="unsigned",
                signing_identity="Developer ID Application: Tirosh",
                codesign_executable=Path("/usr/bin/codesign"),
                virtualization_entitlements=self.virtual_machine_supervisor_virtualization_entitlements,
            ),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "unsigned macOS virtual machine supervisor code signing must not supply signing inputs",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    def test_ad_hoc_virtual_machine_supervisor_code_signing_rejects_a_named_identity(self) -> None:
        composition = replace(
            self.composition(),
            macos_virtual_machine_supervisor_code_signing=(
                composer.MacOSVirtualMachineSupervisorCodeSigning(
                    mode="ad-hoc",
                    signing_identity="Developer ID Application: Tirosh",
                    codesign_executable=Path("/usr/bin/codesign"),
                    virtualization_entitlements=(
                        self.virtual_machine_supervisor_virtualization_entitlements
                    ),
                )
            ),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "ad-hoc macOS virtual machine supervisor code signing must not supply a signing identity",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    def test_developer_id_supervisor_rejects_a_non_developer_id_identity(self) -> None:
        composition = replace(
            self.composition(),
            macos_virtual_machine_supervisor_code_signing=(
                composer.MacOSVirtualMachineSupervisorCodeSigning(
                    mode="developer-id",
                    signing_identity="Apple Development: Tirosh",
                    codesign_executable=Path("/usr/bin/codesign"),
                    virtualization_entitlements=(
                        self.virtual_machine_supervisor_virtualization_entitlements
                    ),
                )
            ),
        )

        with self.assertRaisesRegex(
            composer.MacOSHostPackageCompositionError,
            "requires a Developer ID Application identity",
        ):
            composer.validate_package_artifacts(
                composition,
                composer.load_macos_host_package_documents(composition),
            )

    @requires_macos_native_package_tools
    def test_developer_id_virtual_machine_supervisor_is_signed_and_verified_only_in_the_staged_payload(self) -> None:
        codesign_log = self.root / "codesign.log"
        productsign_log = self.root / "productsign.log"
        fake_codesign = self.write_file(
            "artifacts/fake-codesign",
            (
                "#!/bin/sh\n"
                "set -eu\n"
                "printf 'arguments=%s\\n' \"$*\" >> \"$CODESIGN_LOG\"\n"
                "operation=\"$1\"\n"
                "target=\"\"\n"
                "entitlements=\"\"\n"
                "while [ \"$#\" -gt 0 ]; do\n"
                "  case \"$1\" in\n"
                "    --entitlements) entitlements=\"$2\"; shift 2 ;;\n"
                "    *) target=\"$1\"; shift ;;\n"
                "  esac\n"
                "done\n"
                "printf 'target=%s\\n' \"$target\" >> \"$CODESIGN_LOG\"\n"
                "if [ \"$operation\" = \"--force\" ]; then\n"
                "  cp \"$entitlements\" \"$CODESIGN_ENTITLEMENT_COPY\"\n"
                "elif [ \"$operation\" = \"--display\" ]; then\n"
                "  cat \"$CODESIGN_ENTITLEMENT_COPY\"\n"
                "fi\n"
            ).encode("utf-8"),
        )
        fake_codesign.chmod(0o755)
        fake_productsign = self.write_file(
            "artifacts/fake-productsign",
            (
                "#!/bin/sh\n"
                "set -eu\n"
                "printf 'arguments=%s\\n' \"$*\" >> \"$PRODUCTSIGN_LOG\"\n"
                "cp \"$3\" \"$4\"\n"
            ).encode("utf-8"),
        )
        fake_productsign.chmod(0o755)
        output_directory = self.root / "output"
        output_directory.mkdir()
        codesign_entitlement_copy = self.root / "codesign-entitlements.plist"
        source_digest_before_signing = composer.sha256_file(self.macos_virtual_machine_supervisor_binary)
        release_delivery_plans = self.release_delivery_plans_document()
        release_delivery_plans["plans"][0]["macOSInstallerSignaturePolicy"] = "developer-id"
        self.write_json(self.release_delivery_plans_document_path, release_delivery_plans)
        composition = replace(
            self.composition(),
            output_package=output_directory / "VitalServerRuntimePlatform-0.1.0-dev.pkg",
            pkgbuild_executable=Path("/usr/bin/pkgbuild"),
            macos_installer_package_signing=composer.MacOSInstallerPackageSigning(
                mode="developer-id",
                signing_identity="Developer ID Installer: Tirosh",
                productsign_executable=fake_productsign,
            ),
            macos_virtual_machine_supervisor_code_signing=composer.MacOSVirtualMachineSupervisorCodeSigning(
                mode="developer-id",
                signing_identity="Developer ID Application: Tirosh",
                codesign_executable=fake_codesign,
                virtualization_entitlements=self.virtual_machine_supervisor_virtualization_entitlements,
            ),
        )

        with mock.patch.dict(
            "os.environ",
            {
                "CODESIGN_LOG": str(codesign_log),
                "CODESIGN_ENTITLEMENT_COPY": str(codesign_entitlement_copy),
                "PRODUCTSIGN_LOG": str(productsign_log),
            },
        ):
            result = composer.compose_macos_host_package(composition)

        self.assertTrue(Path(result["artifactPath"]).is_file())
        self.assertEqual("developer-id", result["macOSInstallerPackageSigningMode"])
        self.assertEqual(
            "developer-id", result["macOSVirtualMachineSupervisorCodeSigningMode"]
        )
        self.assertEqual(source_digest_before_signing, composer.sha256_file(self.macos_virtual_machine_supervisor_binary))
        codesign_invocations = codesign_log.read_text(encoding="utf-8")
        self.assertIn("--force --sign Developer ID Application: Tirosh --entitlements", codesign_invocations)
        self.assertIn("--verify --strict --verbose=4", codesign_invocations)
        self.assertIn("--display --entitlements :-", codesign_invocations)
        signed_or_verified_targets = [
            line.removeprefix("target=")
            for line in codesign_invocations.splitlines()
            if line.startswith("target=")
        ]
        self.assertNotIn(str(self.macos_virtual_machine_supervisor_binary), signed_or_verified_targets)
        self.assertTrue(
            all("/payload/" in target for target in signed_or_verified_targets),
            signed_or_verified_targets,
        )
        productsign_invocation = productsign_log.read_text(encoding="utf-8")
        self.assertIn("--sign Developer ID Installer: Tirosh", productsign_invocation)
        self.assertIn("declared-payload-component-package.pkg", productsign_invocation)
        payload_listing = subprocess.run(
            ["/usr/sbin/pkgutil", "--payload-files", result["artifactPath"]],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, payload_listing.returncode, payload_listing.stderr)
        self.assertNotIn("/._", payload_listing.stdout)

    @requires_macos_native_package_tools
    def test_unsigned_development_package_can_carry_an_ad_hoc_entitled_supervisor(self) -> None:
        codesign_log = self.root / "codesign.log"
        fake_codesign = self.write_file(
            "artifacts/fake-codesign",
            (
                "#!/bin/sh\n"
                "set -eu\n"
                "printf 'arguments=%s\\n' \"$*\" >> \"$CODESIGN_LOG\"\n"
                "operation=\"$1\"\n"
                "target=\"\"\n"
                "entitlements=\"\"\n"
                "while [ \"$#\" -gt 0 ]; do\n"
                "  case \"$1\" in\n"
                "    --entitlements) entitlements=\"$2\"; shift 2 ;;\n"
                "    *) target=\"$1\"; shift ;;\n"
                "  esac\n"
                "done\n"
                "if [ \"$operation\" = \"--force\" ]; then\n"
                "  cp \"$entitlements\" \"$CODESIGN_ENTITLEMENT_COPY\"\n"
                "elif [ \"$operation\" = \"--display\" ]; then\n"
                "  cat \"$CODESIGN_ENTITLEMENT_COPY\"\n"
                "fi\n"
            ).encode("utf-8"),
        )
        fake_codesign.chmod(0o755)
        output_directory = self.root / "output"
        output_directory.mkdir()
        codesign_entitlement_copy = self.root / "codesign-entitlements.plist"
        composition = replace(
            self.composition(),
            output_package=output_directory / "VitalServerRuntimePlatform-0.1.0-dev.pkg",
            pkgbuild_executable=Path("/usr/bin/pkgbuild"),
            macos_virtual_machine_supervisor_code_signing=(
                composer.MacOSVirtualMachineSupervisorCodeSigning(
                    mode="ad-hoc",
                    signing_identity=None,
                    codesign_executable=fake_codesign,
                    virtualization_entitlements=(
                        self.virtual_machine_supervisor_virtualization_entitlements
                    ),
                )
            ),
        )

        with mock.patch.dict(
            "os.environ",
            {
                "CODESIGN_LOG": str(codesign_log),
                "CODESIGN_ENTITLEMENT_COPY": str(codesign_entitlement_copy),
            },
        ):
            result = composer.compose_macos_host_package(composition)

        self.assertTrue(Path(result["artifactPath"]).is_file())
        self.assertEqual("unsigned", result["macOSInstallerPackageSigningMode"])
        self.assertEqual(
            "ad-hoc", result["macOSVirtualMachineSupervisorCodeSigningMode"]
        )
        codesign_invocations = codesign_log.read_text(encoding="utf-8")
        self.assertIn("--force --sign - --entitlements", codesign_invocations)
        self.assertIn("--options runtime", codesign_invocations)
        self.assertNotIn("--timestamp", codesign_invocations)

    def test_entitlement_display_parser_ignores_codesign_diagnostics_outside_the_plist(self) -> None:
        display_output = (
            "Executable=/tmp/macos-virtual-machine-supervisor\n"
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"https://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>com.apple.security.virtualization</key><true/></dict></plist>\n"
            "Authority=adhoc\n"
        )
        self.assertEqual(
            {"com.apple.security.virtualization": True},
            composer.parse_displayed_macos_virtual_machine_supervisor_entitlement_plist(
                display_output
            ),
        )

    @requires_macos_native_package_tools
    def test_pkgbuild_composes_an_unsigned_package_without_installing_it(self) -> None:
        output_directory = self.root / "output"
        output_directory.mkdir()
        composition = replace(
            self.composition(),
            output_package=output_directory / "VitalServerRuntimePlatform-0.1.0-dev.pkg",
            pkgbuild_executable=Path("/usr/bin/pkgbuild"),
        )
        result = composer.compose_macos_host_package(composition)
        artifact = Path(result["artifactPath"])
        self.assertTrue(artifact.is_file())
        self.assertEqual(64, len(result["sha256"]))
        expanded_package = self.root / "expanded-package"
        expansion = subprocess.run(["/usr/sbin/pkgutil", "--expand-full", str(artifact), str(expanded_package)], capture_output=True, text=True, check=False)
        self.assertEqual(0, expansion.returncode, expansion.stderr)
        self.assertIn("com.tirosh.vitalserver.runtime-platform", (expanded_package / "PackageInfo").read_text(encoding="utf-8"))
        payload_listing = subprocess.run(
            ["/usr/sbin/pkgutil", "--payload-files", str(artifact)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, payload_listing.returncode, payload_listing.stderr)
        self.assertNotIn("/._", payload_listing.stdout)
        verifier.verify_expanded_payload_has_no_appledouble_sidecars(expanded_package / "Payload")

        verification = verifier.verify_macos_host_package(
            verifier.MacOSHostPackageVerification(
                package=artifact,
                pkgutil_executable=Path("/usr/sbin/pkgutil"),
                release_delivery_plans_document=self.release_delivery_plans_document_path,
                release_delivery_plan_id="macos-runtime-platform-release",
                payload_base_path=self.payload_base_path,
                release_slot_id=self.release_slot_id,
            )
        )
        self.assertEqual(str(artifact), verification["artifactPath"])
        self.assertEqual(str(self.payload_base_path), verification["payloadBasePath"])
        self.assertEqual("macos-runtime-platform-release", verification["releaseDeliveryPlanId"])

        release_root = (
            expanded_package
            / "Payload"
            / "Library/Application Support/VitalServerRuntimePlatform/releases"
            / self.release_slot_id
        )
        self.assertEqual(b"platformctl", (release_root / "bin/platformctl").read_bytes())
        installation_manifest = json.loads(
            (release_root / "installation-manifest.json").read_text(encoding="utf-8")
        )
        operator_application = (
            expanded_package
            / "Payload"
            / "Applications/VitalServer Runtime Platform.app"
        )
        self.assertEqual(
            b"operator-application",
            (
                operator_application
                / "Contents/MacOS/VitalServer Runtime Platform"
            ).read_bytes(),
        )
        self.assertEqual(
            "/Applications/VitalServer Runtime Platform.app",
            installation_manifest["operatorInterface"]["applicationBundlePath"],
        )
        self.assertEqual(
            composer.sha256_macos_application_bundle_tree(operator_application),
            installation_manifest["operatorInterface"]["applicationBundleTreeSha256"],
        )
        self.assertTrue(
            (operator_application / "Contents/Frameworks/runtime-entrypoint").is_symlink()
        )
        self.assertEqual(
            "/Library/Application Support/VitalServerRuntimePlatform/releases",
            installation_manifest["immutablePayload"]["releaseCatalogPath"],
        )
        installation_data_root = next(
            store
            for store in installation_manifest["mutableStores"]
            if store["id"] == "installation-data-root"
        )
        self.assertEqual(
            self.host_agent_deployment_document()["installation"]["dataDirectory"],
            installation_data_root["path"],
        )
        self.assertEqual("host-installation-manager", installation_data_root["owner"])
        self.assertEqual("directory", installation_data_root["kind"])
        self.assertEqual(
            "purge-only-by-explicit-command", installation_data_root["retention"]
        )
        for service in installation_manifest["requiredServices"]:
            service_definition = expanded_package / "Payload" / service["definitionPath"].lstrip("/")
            self.assertEqual(
                composer.sha256_file(service_definition),
                service["definitionSha256"],
            )

        preinstall = (expanded_package / "Scripts" / "preinstall").read_text(encoding="utf-8")
        postinstall = (expanded_package / "Scripts" / "postinstall").read_text(encoding="utf-8")
        self.assertIn('"$script_directory/host-installation-manager" --mode preflight', preinstall)
        self.assertNotIn('"$script_directory/host-installation-manager" --mode quiesce', preinstall)
        self.assertIn("--mode quiesce", postinstall)
        self.assertIn("--mode activate", postinstall)
        self.assertIn("--mode finalize", postinstall)
        self.assertIn("--mode recover", postinstall)
        self.assertNotIn("/bin/launchctl bootout", postinstall)
        self.assertNotIn("|| true", postinstall)

    def test_package_verifier_rejects_undeclared_appledouble_payload_sidecar(self) -> None:
        with tempfile.TemporaryDirectory() as payload_directory:
            payload_root = Path(payload_directory)
            sidecar = payload_root / "Library/Application Support/VitalServerRuntimePlatform/bin/._host-agent"
            sidecar.parent.mkdir(parents=True)
            sidecar.write_bytes(b"unowned-metadata")

            with self.assertRaisesRegex(
                verifier.MacOSHostPackageVerificationError,
                "undeclared AppleDouble sidecar",
            ):
                verifier.verify_expanded_payload_has_no_appledouble_sidecars(payload_root)

    @requires_macos_native_package_tools
    def test_package_verifier_requires_c23_product_version_to_match_packaged_c33(self) -> None:
        output_directory = self.root / "output"
        output_directory.mkdir()
        composition = replace(
            self.composition(),
            output_package=output_directory / "VitalServerRuntimePlatform-0.1.0-dev.pkg",
            pkgbuild_executable=Path("/usr/bin/pkgbuild"),
        )
        artifact = Path(composer.compose_macos_host_package(composition)["artifactPath"])
        release_delivery_plans = self.release_delivery_plans_document()
        release_delivery_plans["plans"][0]["productVersion"] = "0.2.0-dev"
        self.write_json(self.release_delivery_plans_document_path, release_delivery_plans)

        with self.assertRaisesRegex(
            verifier.MacOSHostPackageVerificationError,
            "C33 installation.productVersion must match C23 MacOSHostPackageReleasePlan product version",
        ):
            verifier.verify_macos_host_package(
                verifier.MacOSHostPackageVerification(
                    package=artifact,
                    pkgutil_executable=Path("/usr/sbin/pkgutil"),
                    release_delivery_plans_document=self.release_delivery_plans_document_path,
                    release_delivery_plan_id="macos-runtime-platform-release",
                    payload_base_path=self.payload_base_path,
                    release_slot_id=self.release_slot_id,
                )
            )

    @requires_macos_native_package_tools
    def test_package_verifier_requires_the_explicit_payload_base_path(self) -> None:
        output_directory = self.root / "output"
        output_directory.mkdir()
        composition = replace(
            self.composition(),
            output_package=output_directory / "VitalServerRuntimePlatform-0.1.0-dev.pkg",
            pkgbuild_executable=Path("/usr/bin/pkgbuild"),
        )
        artifact = Path(composer.compose_macos_host_package(composition)["artifactPath"])
        with self.assertRaisesRegex(verifier.MacOSHostPackageVerificationError, "Host Agent is missing"):
            verifier.verify_macos_host_package(
                verifier.MacOSHostPackageVerification(
                    package=artifact,
                    pkgutil_executable=Path("/usr/sbin/pkgutil"),
                    release_delivery_plans_document=self.release_delivery_plans_document_path,
                    release_delivery_plan_id="macos-runtime-platform-release",
                    payload_base_path=PurePosixPath("/Library/Application Support/OtherProduct"),
                    release_slot_id=self.release_slot_id,
                )
            )

    def test_package_verifier_rejects_package_metadata_version_that_differs_from_c33(self) -> None:
        with tempfile.TemporaryDirectory() as package_directory:
            package_info_path = Path(package_directory) / "PackageInfo"
            package_info_path.write_text(
                '<pkg-info identifier="com.tirosh.vitalserver.runtime-platform" version="0.1.0-dev"/>',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                verifier.MacOSHostPackageVerificationError,
                "PackageInfo version must match C33 installation.productVersion",
            ):
                verifier.verify_package_info_release_identity(
                    Path(package_directory),
                    "0.2.0-dev",
                    composer.load_macos_host_package_documents(
                        self.composition()
                    ).macos_host_package_release_plan,
                )

    def test_package_verifier_requires_package_metadata_identifier_to_match_c23(self) -> None:
        with tempfile.TemporaryDirectory() as package_directory:
            package_info_path = Path(package_directory) / "PackageInfo"
            package_info_path.write_text(
                '<pkg-info identifier="com.example.other-product" version="0.1.0-dev"/>',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                verifier.MacOSHostPackageVerificationError,
                "PackageInfo identifier must match C23 MacOSHostPackageReleasePlan macOS installer package identifier",
            ):
                verifier.verify_package_info_release_identity(
                    Path(package_directory),
                    "0.1.0-dev",
                    composer.load_macos_host_package_documents(
                        self.composition()
                    ).macos_host_package_release_plan,
                )


if __name__ == "__main__":
    unittest.main()
