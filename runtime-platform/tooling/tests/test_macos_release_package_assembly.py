"""Tests for the explicit macOS product-release package assembly workflow."""

from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path, PurePosixPath
import tempfile
import unittest
from unittest import mock

from tooling import guest_artifact_compilation_input_assembler
from tooling import guest_artifact_compiler
from tooling import macos_host_package_composer
from tooling import macos_host_package_verifier
from tooling import macos_release_package_assembly


class MacOSReleasePackageAssemblyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.assembled_input_root = self.root / "assembled-input"
        self.guest_artifact_output_directory = self.root / "guest-artifacts"
        self.package_path = self.root / "VitalServerRuntimePlatform-0.2.0-dev.pkg"
        self.operator_application_bundle = self.write_operator_application_bundle()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_operator_application_bundle(self) -> Path:
        bundle = self.root / "VitalServer Runtime Platform.app"
        executable = bundle / "Contents" / "MacOS" / "VitalServer Runtime Platform"
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(b"operator-application")
        executable.chmod(0o755)
        (bundle / "Contents" / "Info.plist").write_bytes(b"info")
        return bundle

    def request(self) -> macos_release_package_assembly.MacOSReleasePackageAssemblyRequest:
        expected_kernel = self.guest_artifact_output_directory / "boot" / "Image"
        expected_initial_ramdisk = self.guest_artifact_output_directory / "boot" / "initrd.img"
        expected_storage = {
            "guest-root": self.guest_artifact_output_directory / "storage" / "guest-root.raw",
            "guest-product-bootstrap": self.guest_artifact_output_directory / "storage" / "guest-product-bootstrap.raw",
        }
        composition = macos_host_package_composer.MacOSHostPackageComposition(
            release_delivery_plans_document=self.root / "release-delivery-plans.json",
            release_delivery_plan_id="macos-release",
            payload_base_path=PurePosixPath("/Library/Application Support/VitalServerRuntimePlatform"),
            release_slot_id="macos-release-package-assembly-020",
            host_agent_binary=self.root / "host-agent",
            host_edge_proxy_binary=self.root / "host-edge-proxy",
            host_installation_manager_binary=self.root / "host-installation-manager",
            host_update_handoff_supervisor_binary=(
                self.root / "host-update-handoff-supervisor"
            ),
            platformctl_binary=self.root / "platformctl",
            macos_virtual_machine_supervisor_binary=self.root / "macos-virtual-machine-supervisor",
            operator_application_bundle=self.operator_application_bundle,
            host_agent_deployment_configuration=self.root / "c33.json",
            operator_interface_bootstrap_configuration=self.root / "c53.json",
            host_edge_proxy_deployment_configuration=self.root / "c36.json",
            host_update_handoff_supervisor_configuration=self.root / "c56.json",
            host_update_trust_store=self.root / "c58.json",
            macos_virtual_machine_configuration=self.root / "c32.json",
            guest_artifact_manifest=self.guest_artifact_output_directory / "macos-guest-artifact-manifest.json",
            guest_artifact_compilation_receipt=self.guest_artifact_output_directory / "guest-artifact-compilation-receipt.json",
            guest_product_process_supervisor_artifact=self.root / "guest-product-process-supervisor",
            guest_product_process_deployment_configuration=self.root / "c37.json",
            guest_product_service_manager_deployment_configuration=self.root / "c38.json",
            guest_product_bootstrap_configuration=self.root / "c39.json",
            guest_product_vitalserver_topology_deployment=self.root / "c44.json",
            external_vitalserver_delivery_configuration=self.root / "c46.json",
            guest_kernel_source=expected_kernel,
            guest_initial_ramdisk_source=expected_initial_ramdisk,
            guest_storage_sources=expected_storage,
            output_package=self.package_path,
            pkgbuild_executable=self.root / "pkgbuild",
            macos_installer_package_signing=(
                macos_host_package_composer.MacOSInstallerPackageSigning(
                    mode="unsigned",
                    signing_identity=None,
                    productsign_executable=None,
                )
            ),
            macos_virtual_machine_supervisor_code_signing=(
                macos_host_package_composer.MacOSVirtualMachineSupervisorCodeSigning(
                    mode="unsigned",
                    signing_identity=None,
                    codesign_executable=None,
                    virtualization_entitlements=None,
                )
            ),
            replace_output=False,
        )
        verification = macos_host_package_verifier.MacOSHostPackageVerification(
            package=self.package_path,
            pkgutil_executable=self.root / "pkgutil",
            release_delivery_plans_document=composition.release_delivery_plans_document,
            release_delivery_plan_id=composition.release_delivery_plan_id,
            payload_base_path=composition.payload_base_path,
            release_slot_id=composition.release_slot_id,
        )
        return macos_release_package_assembly.MacOSReleasePackageAssemblyRequest(
            guest_artifact_input_assembly_execution=(
                guest_artifact_compilation_input_assembler.GuestArtifactCompilationInputAssemblyExecution(
                    assembly_declaration_path=self.root / "c41.json",
                    assembled_input_root=self.assembled_input_root,
                )
            ),
            guest_artifact_output_directory=self.guest_artifact_output_directory,
            guest_artifact_builder_timeout_seconds=120,
            host_package_composition=composition,
            host_package_verification=verification,
        )

    def compilation_command(self) -> guest_artifact_compiler.GuestArtifactCompilationCommand:
        def input_artifact(identifier: str, relative_path: str) -> guest_artifact_compiler.InputArtifact:
            return guest_artifact_compiler.InputArtifact(
                identifier=identifier,
                input_relative_path=PurePosixPath(relative_path),
                size_bytes=1,
                sha256="a" * 64,
            )

        return guest_artifact_compiler.GuestArtifactCompilationCommand(
            compilation_id="macos-release-candidate",
            artifact_set_id="macos-release-candidate-arm64",
            architecture="arm64",
            build_environment_id="guest-product-bootstrap-artifact-composer",
            builder_executable_size_bytes=1,
            builder_executable_sha256="b" * 64,
            kernel=guest_artifact_compiler.BootArtifactOutput(
                source=input_artifact("kernel", "inputs/boot/Image"),
                output_relative_path=PurePosixPath("boot/Image"),
            ),
            initial_ramdisk=guest_artifact_compiler.BootArtifactOutput(
                source=input_artifact("initial-ramdisk", "inputs/boot/initrd.img"),
                output_relative_path=PurePosixPath("boot/initrd.img"),
            ),
            guest_runtime_artifact=input_artifact("guest-runtime", "inputs/services/guest-runtime"),
            guest_telemetry_collector_artifact=input_artifact(
                "guest-telemetry-collector-linux-arm64",
                "inputs/services/guest-telemetry-collector",
            ),
            guest_telemetry_collector_configuration_artifact=input_artifact(
                "guest-telemetry-collector-configuration",
                "inputs/configuration/guest-telemetry-collector.yaml",
            ),
            guest_node_services_artifact=input_artifact("guest-node-services", "inputs/services/guest-node-services.tar.gz"),
            guest_product_process_supervisor_artifact=input_artifact("guest-product-process-supervisor", "inputs/services/guest-product-process-supervisor"),
            guest_product_process_deployment_configuration_artifact=input_artifact("guest-product-process-deployment", "inputs/configuration/c37.json"),
            guest_product_release_manager_artifact=input_artifact("guest-product-release-manager", "inputs/services/guest-product-release-manager"),
            guest_product_release_manager_configuration_artifact=input_artifact("guest-product-release-manager-configuration", "inputs/configuration/guest-product-release-manager.json"),
            guest_product_service_manager_deployment_configuration_artifact=input_artifact("guest-product-service-manager-deployment", "inputs/configuration/c38.json"),
            guest_product_bootstrap_configuration_artifact=input_artifact("guest-product-bootstrap", "inputs/configuration/c39.json"),
            guest_product_vitalserver_topology_deployment_artifact=input_artifact("guest-product-vitalserver-topology", "inputs/configuration/c44.json"),
            external_vitalserver_delivery_configuration_artifact=input_artifact("external-vitalserver-delivery", "inputs/configuration/c46.json"),
            guest_bundled_upstream_image_set_manager_artifact=None,
            guest_bundled_upstream_image_set_manager_configuration_artifact=None,
            storage_devices=(
                guest_artifact_compiler.GuestStorageArtifactOutput(
                    identifier="guest-root",
                    role="guest-root-storage",
                    storage_image_format="raw",
                    guest_volume_file_system=None,
                    read_only=False,
                    base_image=input_artifact("guest-root-base", "inputs/storage/guest-root.raw"),
                    output_relative_path=PurePosixPath("storage/guest-root.raw"),
                ),
                guest_artifact_compiler.GuestStorageArtifactOutput(
                    identifier="guest-product-bootstrap",
                    role="guest-product-bootstrap-volume",
                    storage_image_format="raw",
                    guest_volume_file_system="iso9660",
                    read_only=True,
                    base_image=None,
                    output_relative_path=PurePosixPath("storage/guest-product-bootstrap.raw"),
                ),
            ),
        )

    def test_coordinates_c41_c35_package_composition_and_separate_package_verification(self) -> None:
        request = self.request()
        assembled_result = {
            "guestArtifactCompilationInputAssemblyReceipt": {
                "guestProductBootstrapArtifactComposer": {
                    "relativePath": "builders/guest-product-bootstrap-artifact-composer"
                }
            }
        }
        compilation_result = {"compilationId": "macos-release-candidate"}
        composition_result = {"artifactPath": str(self.package_path), "sha256": "c" * 64}
        verification_result = {"artifactPath": str(self.package_path), "sha256": "c" * 64}
        command = self.compilation_command()
        self.assembled_input_root.mkdir()
        (
            self.assembled_input_root / "guest-artifact-compilation-command.json"
        ).write_bytes(b"declared-c35-command")

        with mock.patch.object(
            guest_artifact_compilation_input_assembler,
            "assemble_guest_artifact_compilation_input",
            return_value=assembled_result,
        ) as assemble_input, mock.patch.object(
            guest_artifact_compiler,
            "compile_guest_artifact_set",
            return_value=compilation_result,
        ) as compile_artifacts, mock.patch.object(
            guest_artifact_compiler,
            "parse_guest_artifact_compilation_command",
            return_value=command,
        ) as parse_command, mock.patch.object(
            macos_host_package_composer,
            "compose_macos_host_package",
            return_value=composition_result,
        ) as compose_package, mock.patch.object(
            macos_host_package_verifier,
            "verify_macos_host_package",
            return_value=verification_result,
        ) as verify_package:
            result = macos_release_package_assembly.assemble_and_verify_macos_release_package(
                request
            )

        self.assertEqual(assembled_result, result.guest_artifact_input_assembly)
        self.assertEqual(compilation_result, result.guest_artifact_compilation)
        self.assertEqual(composition_result, result.host_package_composition)
        self.assertEqual(verification_result, result.host_package_verification)
        assemble_input.assert_called_once_with(request.guest_artifact_input_assembly_execution)
        compile_execution = compile_artifacts.call_args.args[0]
        self.assertEqual(
            self.assembled_input_root / "builders/guest-product-bootstrap-artifact-composer",
            compile_execution.builder_executable,
        )
        self.assertEqual(self.guest_artifact_output_directory, compile_execution.output_directory)
        parse_command.assert_called_once_with(b"declared-c35-command")
        compose_package.assert_called_once_with(request.host_package_composition)
        verify_package.assert_called_once_with(request.host_package_verification)

    def test_rejects_package_verification_release_slot_drift(self) -> None:
        request = self.request()
        verification = replace(
            request.host_package_verification,
            release_slot_id="different-release-slot",
        )
        request = replace(request, host_package_verification=verification)

        with self.assertRaisesRegex(
            macos_release_package_assembly.MacOSReleasePackageAssemblyError,
            "immutable release slot",
        ):
            macos_release_package_assembly.validate_host_package_verification_output(
                request.host_package_composition,
                request.host_package_verification,
            )

    def test_rejects_package_composition_that_names_a_non_c35_manifest_path_before_build(self) -> None:
        request = self.request()
        invalid_composition = replace(
            request.host_package_composition,
            guest_artifact_manifest=self.root / "other-macos-guest-artifact-manifest.json",
        )
        invalid_request = replace(
            request,
            host_package_composition=invalid_composition,
        )

        with mock.patch.object(
            guest_artifact_compilation_input_assembler,
            "assemble_guest_artifact_compilation_input",
        ) as assemble_input:
            with self.assertRaisesRegex(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError,
                "canonical C35 output path",
            ):
                macos_release_package_assembly.assemble_and_verify_macos_release_package(
                    invalid_request
                )
        assemble_input.assert_not_called()

    def test_rejects_c41_receipt_builder_path_that_escapes_the_assembled_input_root(self) -> None:
        with self.assertRaisesRegex(
            macos_release_package_assembly.MacOSReleasePackageAssemblyError,
            "escapes the assembled input root",
        ):
            macos_release_package_assembly.declared_guest_product_bootstrap_artifact_composer_path(
                self.assembled_input_root,
                {
                    "guestArtifactCompilationInputAssemblyReceipt": {
                        "guestProductBootstrapArtifactComposer": {
                            "relativePath": "../untrusted-builder"
                        }
                    }
                },
            )

class MacOSReleasePackageAssemblyDeclarationTests(unittest.TestCase):
    """C47 turns a named release declaration into the existing workflow input."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.output_directory = self.root / "guest-artifact-output"
        self.assembled_input_root = self.root / "assembled-input"
        self.package_path = self.root / "VitalServerRuntimePlatform-0.2.0-dev.pkg"
        self.receipt_path = self.root / "macos-release-package-assembly-receipt.json"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_source_file(self, relative_path: str, contents: bytes = b"source") -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        return path

    def write_operator_application_bundle(self) -> Path:
        bundle = self.root / "artifacts" / "VitalServer Runtime Platform.app"
        executable = bundle / "Contents" / "MacOS" / "VitalServer Runtime Platform"
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(b"operator-application")
        executable.chmod(0o755)
        (bundle / "Contents" / "Info.plist").write_bytes(b"info")
        return bundle

    def release_delivery_plans_document(self) -> Path:
        path = self.write_source_file("release-delivery-plans.json")
        path.write_text(
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
                                "expectedName": self.package_path.name,
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
            ),
            encoding="utf-8",
        )
        return path

    def c41_declaration_document(self) -> Path:
        path = self.write_source_file("guest-input-assembly.json")

        def source(identifier: str, destination: str) -> dict[str, str]:
            return {
                "id": identifier,
                "sourceAbsolutePath": "/release/" + identifier,
                "inputRelativePath": destination,
            }

        path.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "assemblyId": "guest-input-assembly-020",
                    "compilationId": "guest-artifact-compilation-020",
                    "artifactSetId": "guest-artifact-set-020",
                    "architecture": "arm64",
                    "guestProductBootstrapArtifactComposer": source(
                        "guest-product-bootstrap-artifact-composer",
                        "builders/guest-product-bootstrap-artifact-composer",
                    ),
                    "boot": {
                        "kernel": {
                            "source": source("linux-arm64-kernel", "inputs/boot/Image"),
                            "outputRelativePath": "boot/Image",
                        },
                        "initialRamdisk": {
                            "source": source(
                                "linux-arm64-initial-ramdisk",
                                "inputs/boot/initrd.img",
                            ),
                            "outputRelativePath": "boot/initrd.img",
                        },
                    },
                    "guestRuntimeArtifact": source(
                        "guest-runtime-linux-arm64", "inputs/services/guest-runtime"
                    ),
                    "guestNodeServicesArtifact": source(
                        "guest-node-services-linux-arm64",
                        "inputs/services/guest-node-services.tar.gz",
                    ),
                    "guestProductProcessSupervisorArtifact": source(
                        "guest-product-process-supervisor-linux-arm64",
                        "inputs/services/guest-product-process-supervisor",
                    ),
                    "guestProductProcessDeploymentConfigurationArtifact": source(
                        "guest-product-process-deployment-configuration",
                        "inputs/configuration/guest-product-process-deployment.json",
                    ),
                    "guestProductReleaseManagerArtifact": source(
                        "guest-product-release-manager-linux-arm64",
                        "inputs/services/guest-product-release-manager",
                    ),
                    "guestProductReleaseManagerConfigurationArtifact": source(
                        "guest-product-release-manager-configuration",
                        "inputs/configuration/guest-product-release-manager.json",
                    ),
                    "guestProductServiceManagerDeploymentConfigurationArtifact": source(
                        "guest-product-service-manager-deployment-configuration",
                        "inputs/configuration/guest-product-service-manager-deployment.json",
                    ),
                    "guestProductBootstrapConfigurationArtifact": source(
                        "guest-product-bootstrap-configuration",
                        "inputs/configuration/guest-product-bootstrap.json",
                    ),
                    "guestProductVitalServerTopologyDeploymentArtifact": source(
                        "guest-product-vitalserver-topology-deployment",
                        "inputs/configuration/guest-product-vitalserver-topology.json",
                    ),
                    "storageDevices": [
                        {
                            "id": "guest-root",
                            "role": "guest-root-storage",
                            "storageImageFormat": "raw",
                            "readOnly": False,
                            "baseImage": source(
                                "linux-arm64-root-storage-base",
                                "inputs/storage/guest-root.raw",
                            ),
                            "outputRelativePath": "storage/guest-root.raw",
                        },
                        {
                            "id": "guest-product-bootstrap",
                            "role": "guest-product-bootstrap-volume",
                            "storageImageFormat": "raw",
                            "guestVolumeFileSystem": "iso9660",
                            "readOnly": True,
                            "outputRelativePath": "storage/guest-product-bootstrap.raw",
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        return path

    def declaration_document(self) -> Path:
        release_plans = self.release_delivery_plans_document()
        c41_declaration = self.c41_declaration_document()
        host_agent = self.write_source_file("artifacts/host-agent")
        host_edge_proxy = self.write_source_file("artifacts/host-edge-proxy")
        host_update_handoff_supervisor = self.write_source_file(
            "artifacts/host-update-handoff-supervisor"
        )
        platformctl = self.write_source_file("artifacts/platformctl")
        virtual_machine_supervisor = self.write_source_file(
            "artifacts/macos-virtual-machine-supervisor"
        )
        guest_process_supervisor = self.write_source_file(
            "artifacts/guest-product-process-supervisor"
        )
        deployment_documents = {
            "hostAgentDeploymentConfigurationAbsolutePath": self.write_source_file(
                "configuration/host-agent.json"
            ),
            "operatorInterfaceBootstrapConfigurationAbsolutePath": self.write_source_file(
                "configuration/operator-interface-bootstrap.json"
            ),
            "hostEdgeProxyDeploymentConfigurationAbsolutePath": self.write_source_file(
                "configuration/host-edge-proxy.json"
            ),
            "hostUpdateHandoffSupervisorConfigurationAbsolutePath": self.write_source_file(
                "configuration/host-update-handoff-supervisor.json"
            ),
            "hostUpdateTrustStoreAbsolutePath": self.write_source_file(
                "configuration/update-trust-store.json"
            ),
            "macOSVirtualMachineConfigurationAbsolutePath": self.write_source_file(
                "configuration/macos-virtual-machine.json"
            ),
            "guestProductProcessDeploymentConfigurationAbsolutePath": self.write_source_file(
                "configuration/guest-product-process-deployment.json"
            ),
            "guestProductServiceManagerDeploymentConfigurationAbsolutePath": self.write_source_file(
                "configuration/guest-product-service-manager-deployment.json"
            ),
            "guestProductBootstrapConfigurationAbsolutePath": self.write_source_file(
                "configuration/guest-product-bootstrap.json"
            ),
            "guestProductVitalServerTopologyDeploymentAbsolutePath": self.write_source_file(
                "configuration/guest-product-vitalserver-topology.json"
            ),
        }
        pkgbuild = self.write_source_file("tools/pkgbuild")
        pkgutil = self.write_source_file("tools/pkgutil")
        declaration_path = self.root / "macos-release-package-assembly.json"
        declaration_path.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "assemblyId": "macos-release-package-assembly-020",
                    "releaseDeliveryPlan": {
                        "documentAbsolutePath": str(release_plans),
                        "id": "macos-runtime-platform-release",
                    },
                    "guestArtifactCompilationInputAssembly": {
                        "declarationAbsolutePath": str(c41_declaration),
                        "assembledInputRootAbsolutePath": str(self.assembled_input_root),
                    },
                    "guestArtifactCompilation": {
                        "outputDirectoryAbsolutePath": str(self.output_directory),
                        "builderTimeoutSeconds": 120,
                    },
                    "hostArtifacts": {
                        "hostAgentBinaryAbsolutePath": str(host_agent),
                        "hostEdgeProxyBinaryAbsolutePath": str(host_edge_proxy),
                        "hostInstallationManagerBinaryAbsolutePath": str(
                            self.write_source_file("artifacts/host-installation-manager")
                        ),
                        "hostUpdateHandoffSupervisorBinaryAbsolutePath": str(
                            host_update_handoff_supervisor
                        ),
                        "platformctlBinaryAbsolutePath": str(platformctl),
                        "macOSVirtualMachineSupervisorBinaryAbsolutePath": str(
                            virtual_machine_supervisor
                        ),
                        "operatorApplicationBundleAbsolutePath": str(
                            self.write_operator_application_bundle()
                        ),
                        "guestProductProcessSupervisorArtifactAbsolutePath": str(
                            guest_process_supervisor
                        ),
                    },
                    "deploymentDocuments": {
                        key: str(value) for key, value in deployment_documents.items()
                    },
                    "macOSPackage": {
                        "payloadBasePath": "/Library/Application Support/VitalServerRuntimePlatform",
                        "outputPackageAbsolutePath": str(self.package_path),
                        "pkgbuildExecutableAbsolutePath": str(pkgbuild),
                        "installerPackageSigning": {"mode": "unsigned"},
                        "virtualMachineSupervisorCodeSigning": {"mode": "unsigned"},
                    },
                    "macOSPackageVerification": {
                        "pkgutilExecutableAbsolutePath": str(pkgutil)
                    },
                    "assemblyReceipt": {"outputAbsolutePath": str(self.receipt_path)},
                }
            ),
            encoding="utf-8",
        )
        return declaration_path

    def result_with_real_output_artifacts(
        self,
    ) -> macos_release_package_assembly.MacOSReleasePackageAssemblyResult:
        self.assembled_input_root.mkdir()
        self.output_directory.mkdir()
        c41_receipt = self.assembled_input_root / (
            guest_artifact_compilation_input_assembler.ASSEMBLED_C41_RECEIPT_RELATIVE_PATH
        )
        c41_receipt.write_text('{"receipt":"c41"}', encoding="utf-8")
        (self.output_directory / "guest-artifact-compilation-receipt.json").write_text(
            '{"receipt":"c35"}', encoding="utf-8"
        )
        (self.output_directory / "macos-guest-artifact-manifest.json").write_text(
            '{"manifest":"c34"}', encoding="utf-8"
        )
        self.package_path.write_bytes(b"macos package")
        digest = hashlib.sha256(self.package_path.read_bytes()).hexdigest()
        return macos_release_package_assembly.MacOSReleasePackageAssemblyResult(
            guest_artifact_input_assembly={
                "guestArtifactCompilationInputAssemblyReceipt": {
                    "assemblyId": "guest-input-assembly-020"
                }
            },
            guest_artifact_compilation={
                "compilationId": "guest-artifact-compilation-020",
                "artifactSetId": "guest-artifact-set-020",
            },
            host_package_composition={"sha256": digest},
            host_package_verification={
                "sha256": digest,
                "releaseDeliveryPlanId": "macos-runtime-platform-release",
                "payloadBasePath": "/Library/Application Support/VitalServerRuntimePlatform",
            },
        )

    def test_declared_assembly_derives_c35_output_paths_and_writes_c47_receipt(self) -> None:
        declaration_path = self.declaration_document()

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
            side_effect=lambda request: self.result_with_real_output_artifacts(),
        ) as assemble:
            result = macos_release_package_assembly.assemble_declared_macos_release_package(
                declaration_path
            )

        request = assemble.call_args.args[0]
        self.assertEqual(
            self.output_directory / "boot" / "Image",
            request.host_package_composition.guest_kernel_source,
        )
        self.assertEqual(
            self.output_directory / "boot" / "initrd.img",
            request.host_package_composition.guest_initial_ramdisk_source,
        )
        self.assertEqual(
            {
                "guest-root": self.output_directory / "storage" / "guest-root.raw",
                "guest-product-bootstrap": self.output_directory
                / "storage"
                / "guest-product-bootstrap.raw",
            },
            dict(request.host_package_composition.guest_storage_sources),
        )
        self.assertFalse(request.host_package_composition.replace_output)
        self.assertTrue(self.receipt_path.is_file())
        receipt = json.loads(self.receipt_path.read_text(encoding="utf-8"))
        self.assertEqual("macos-release-package-assembly-020", receipt["assemblyId"])
        self.assertEqual(
            "macos-runtime-platform-release", receipt["release"]["deliveryPlanId"]
        )
        self.assertEqual(
            hashlib.sha256(self.package_path.read_bytes()).hexdigest(),
            receipt["macOSHostPackage"]["sha256"],
        )
        self.assertNotIn(str(self.root), json.dumps(receipt, sort_keys=True))
        self.assertEqual(receipt, result["macOSReleasePackageAssemblyReceipt"])

    def test_c47_preserves_an_explicit_c64_manager_configuration_source(self) -> None:
        declaration_path = self.declaration_document()
        document = json.loads(declaration_path.read_text(encoding="utf-8"))
        c64_path = self.write_source_file(
            "configuration/guest-bundled-upstream-image-set-manager.json"
        )
        document["deploymentDocuments"][
            "guestBundledUpstreamImageSetManagerConfigurationAbsolutePath"
        ] = str(c64_path)

        declaration = (
            macos_release_package_assembly.parse_macos_release_package_assembly_declaration(
                document
            )
        )

        self.assertEqual(
            c64_path,
            declaration.guest_bundled_upstream_image_set_manager_configuration,
        )

    def test_declared_assembly_requires_the_host_installation_manager_binary_before_c41_effects(self) -> None:
        declaration_path = self.declaration_document()
        declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
        manager_path = Path(
            declaration["hostArtifacts"]["hostInstallationManagerBinaryAbsolutePath"]
        )
        manager_path.unlink()

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
        ) as assemble:
            with self.assertRaisesRegex(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError,
                "Host Installation Manager binary",
            ):
                macos_release_package_assembly.assemble_declared_macos_release_package(
                    declaration_path
                )
        assemble.assert_not_called()

    def test_declared_developer_id_installer_package_requires_its_productsign_contract_before_c41_effects(self) -> None:
        declaration_path = self.declaration_document()
        declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
        declaration["macOSPackage"]["installerPackageSigning"] = {
            "mode": "developer-id",
            "identity": "Developer ID Installer: Tirosh",
        }
        declaration_path.write_text(json.dumps(declaration), encoding="utf-8")

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
        ) as assemble:
            with self.assertRaisesRegex(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError,
                "productsignExecutableAbsolutePath",
            ):
                macos_release_package_assembly.assemble_declared_macos_release_package(
                    declaration_path
                )
        assemble.assert_not_called()

    def test_declared_ad_hoc_supervisor_requires_entitlements_without_a_named_identity(self) -> None:
        declaration_path = self.declaration_document()
        declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
        declaration["macOSPackage"]["virtualMachineSupervisorCodeSigning"] = {
            "mode": "ad-hoc",
            "identity": "Developer ID Application: Tirosh",
            "codesignExecutableAbsolutePath": "/usr/bin/codesign",
            "virtualizationEntitlementsAbsolutePath": "/release/entitlements/vm.entitlements",
        }
        declaration_path.write_text(json.dumps(declaration), encoding="utf-8")

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
        ) as assemble:
            with self.assertRaisesRegex(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError,
                "macOS release package assembly declaration is invalid",
            ):
                macos_release_package_assembly.assemble_declared_macos_release_package(
                    declaration_path
                )
        assemble.assert_not_called()

    def test_declared_developer_id_signing_rejects_a_non_developer_id_identity_before_c41_effects(self) -> None:
        declaration_path = self.declaration_document()
        declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
        declaration["macOSPackage"]["installerPackageSigning"] = {
            "mode": "developer-id",
            "identity": "Apple Development: Tirosh",
            "productsignExecutableAbsolutePath": "/usr/bin/productsign",
        }
        declaration["macOSPackage"]["virtualMachineSupervisorCodeSigning"] = {
            "mode": "developer-id",
            "identity": "Apple Development: Tirosh",
            "codesignExecutableAbsolutePath": "/usr/bin/codesign",
            "virtualizationEntitlementsAbsolutePath": "/release/entitlements/vm.entitlements",
        }
        declaration_path.write_text(json.dumps(declaration), encoding="utf-8")

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
        ) as assemble:
            with self.assertRaisesRegex(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError,
                "macOS release package assembly declaration is invalid",
            ):
                macos_release_package_assembly.assemble_declared_macos_release_package(
                    declaration_path
                )
        assemble.assert_not_called()

    def test_declared_assembly_rejects_an_existing_receipt_before_c41_effects(self) -> None:
        declaration_path = self.declaration_document()
        self.receipt_path.write_text("already recorded", encoding="utf-8")

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
        ) as assemble:
            with self.assertRaisesRegex(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError,
                "C47 assembly receipt destination already exists",
            ):
                macos_release_package_assembly.assemble_declared_macos_release_package(
                    declaration_path
                )
        assemble.assert_not_called()

    def test_declared_assembly_rejects_c23_package_name_drift_before_c41_effects(self) -> None:
        declaration_path = self.declaration_document()
        declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
        release_plan_path = Path(
            declaration["releaseDeliveryPlan"]["documentAbsolutePath"]
        )
        release_plans = json.loads(release_plan_path.read_text(encoding="utf-8"))
        release_plans["plans"][0]["intendedInstallerArtifact"][
            "expectedName"
        ] = "different-release.pkg"
        release_plan_path.write_text(json.dumps(release_plans), encoding="utf-8")

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
        ) as assemble:
            with self.assertRaisesRegex(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError,
                "output file name must match C23 intended installer artifact",
            ):
                macos_release_package_assembly.assemble_declared_macos_release_package(
                    declaration_path
                )
        assemble.assert_not_called()

    def test_declared_assembly_rejects_caller_supplied_c41_and_c35_completion_times_before_c41_effects(self) -> None:
        declaration_path = self.declaration_document()
        declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
        declaration["guestArtifactCompilationInputAssembly"]["completedAt"] = (
            "2026-07-18T08:00:00Z"
        )
        declaration["guestArtifactCompilation"]["completedAt"] = (
            "2026-07-18T08:01:00Z"
        )
        declaration_path.write_text(json.dumps(declaration), encoding="utf-8")

        with mock.patch.object(
            macos_release_package_assembly,
            "assemble_and_verify_macos_release_package",
        ) as assemble:
            with self.assertRaises(
                macos_release_package_assembly.MacOSReleasePackageAssemblyError
            ):
                macos_release_package_assembly.assemble_declared_macos_release_package(
                    declaration_path
                )
        assemble.assert_not_called()


if __name__ == "__main__":
    unittest.main()
