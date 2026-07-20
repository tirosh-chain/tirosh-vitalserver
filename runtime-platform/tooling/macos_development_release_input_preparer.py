"""Prepare explicit unsigned macOS development-package inputs.

This release-build adapter creates the two existing desired-input documents
needed by :mod:`tooling.macos_release_package_assembly`:

* C41 selects the already-built Guest inputs; and
* C47 selects that C41 execution, the already-built Host artifacts, and the
  unsigned/ad-hoc macOS package policy.

It deliberately does not compile a service, acquire Linux or Node bytes,
execute C41/C35/C47, install a package, or claim clean-host evidence.  Those
effects retain their own owners.  Its only effect is one new ``release-input``
directory containing copied, release-selected configuration documents and the
two declarations.  The copy prevents a later source-tree edit from silently
changing the configuration selected by an already prepared development build.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tempfile
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractRepository, ContractToolError
from tooling.product_delivery_release_plan import (
    ProductDeliveryReleasePlanError,
    load_selected_macos_host_package_release_plan,
)


class MacOSDevelopmentReleaseInputPreparationError(RuntimeError):
    """One declared development-package input set cannot be prepared."""


@dataclass(frozen=True)
class MacOSDevelopmentReleaseInputPreparation:
    """All caller-owned bytes and paths for one development package input set."""

    release_root: Path
    assembly_id: str
    guest_input_assembly_id: str
    guest_compilation_id: str
    guest_artifact_set_id: str
    release_delivery_plans: Path
    release_delivery_plan_id: str
    payload_base_path: PurePosixPath
    guest_product_bootstrap_artifact_composer: Path
    guest_kernel: Path
    guest_initial_ramdisk: Path
    guest_root_storage: Path
    guest_runtime: Path
    guest_telemetry_collector: Path
    guest_node_services: Path
    guest_product_process_supervisor: Path
    guest_product_release_manager: Path
    host_agent: Path
    host_edge_proxy: Path
    host_installation_manager: Path
    host_update_handoff_supervisor: Path
    platformctl: Path
    macos_virtual_machine_supervisor: Path
    operator_application_bundle: Path
    host_agent_deployment_configuration: Path
    operator_interface_bootstrap_configuration: Path
    host_edge_proxy_deployment_configuration: Path
    host_update_handoff_supervisor_configuration: Path
    host_update_trust_store: Path
    macos_virtual_machine_configuration: Path
    guest_product_process_deployment_configuration: Path
    guest_product_release_manager_configuration: Path
    guest_product_service_manager_deployment_configuration: Path
    guest_product_bootstrap_configuration: Path
    guest_product_vitalserver_topology_deployment: Path
    external_vitalserver_delivery_configuration: Path | None
    guest_telemetry_collector_configuration: Path
    virtualization_entitlements: Path
    pkgbuild_executable: Path
    pkgutil_executable: Path
    codesign_executable: Path
    builder_timeout_seconds: int
    guest_bundled_upstream_image_set_manager: Path | None = None
    guest_bundled_upstream_image_set_manager_configuration: Path | None = None


RELEASE_INPUT_DIRECTORY_NAME = "release-input"
GUEST_INPUT_ASSEMBLY_DECLARATION_NAME = (
    "guest-artifact-compilation-input-assembly.json"
)
MACOS_PACKAGE_ASSEMBLY_DECLARATION_NAME = "macos-release-package-assembly.json"


def prepare_macos_development_release_input(
    preparation: MacOSDevelopmentReleaseInputPreparation,
) -> Mapping[str, Any]:
    """Publish one new C41/C47 input directory for an unsigned macOS build."""

    release_plan, topology = validate_preparation(preparation)
    release_input_directory = preparation.release_root / RELEASE_INPUT_DIRECTORY_NAME
    temporary_directory = Path(
        tempfile.mkdtemp(
            prefix="." + RELEASE_INPUT_DIRECTORY_NAME + ".",
            dir=preparation.release_root,
        )
    )
    try:
        copy_selected_configuration_documents(
            preparation,
            temporary_directory / "documents",
        )
        document_paths = selected_document_destination_paths(
            release_input_directory / "documents", preparation
        )
        c41 = compose_guest_artifact_compilation_input_assembly_declaration(
            preparation,
            document_paths,
            topology,
        )
        c47 = compose_macos_release_package_assembly_declaration(
            preparation,
            document_paths,
            release_plan.expected_package_file_name,
        )
        validate_declaration_contract(
            "guest-artifact-compilation-input-assembly-declaration.schema.json",
            c41,
            "C41",
        )
        validate_declaration_contract(
            "macos-release-package-assembly-declaration.schema.json",
            c47,
            "C47",
        )
        write_json(
            temporary_directory / GUEST_INPUT_ASSEMBLY_DECLARATION_NAME,
            c41,
        )
        write_json(
            temporary_directory / MACOS_PACKAGE_ASSEMBLY_DECLARATION_NAME,
            c47,
        )
        os.replace(temporary_directory, release_input_directory)
    except Exception:
        shutil.rmtree(temporary_directory, ignore_errors=True)
        raise

    c41_path = release_input_directory / GUEST_INPUT_ASSEMBLY_DECLARATION_NAME
    c47_path = release_input_directory / MACOS_PACKAGE_ASSEMBLY_DECLARATION_NAME
    return {
        "releaseRoot": str(preparation.release_root),
        "releaseInputDirectory": str(release_input_directory),
        "guestArtifactCompilationInputAssemblyDeclaration": {
            "path": str(c41_path),
            "sha256": sha256_file(c41_path),
        },
        "macOSReleasePackageAssemblyDeclaration": {
            "path": str(c47_path),
            "sha256": sha256_file(c47_path),
        },
        "intendedInstallerArtifact": {
            "fileName": release_plan.expected_package_file_name,
            "outputPath": str(
                preparation.release_root / release_plan.expected_package_file_name
            ),
        },
    }


def validate_preparation(
    preparation: MacOSDevelopmentReleaseInputPreparation,
) -> tuple[Any, Mapping[str, Any]]:
    """Reject an ambiguous or stale release workspace before any write."""

    require_absolute_directory(preparation.release_root, "release root")
    for field_name, identifier in (
        ("assembly id", preparation.assembly_id),
        ("Guest input assembly id", preparation.guest_input_assembly_id),
        ("Guest compilation id", preparation.guest_compilation_id),
        ("Guest artifact set id", preparation.guest_artifact_set_id),
        ("release delivery plan id", preparation.release_delivery_plan_id),
    ):
        if not identifier:
            raise MacOSDevelopmentReleaseInputPreparationError(
                field_name + " is required"
            )
    if not preparation.payload_base_path.is_absolute() or ".." in preparation.payload_base_path.parts:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "macOS payload base path must be an absolute non-traversing POSIX path"
        )
    if preparation.builder_timeout_seconds < 1:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "Guest bootstrap artifact composer timeout must be positive"
        )
    topology = load_and_validate_contract_document(
        preparation.guest_product_vitalserver_topology_deployment,
        "guest-product-vitalserver-topology-deployment.schema.json",
        "C44 GuestProductVitalServerTopologyDeployment",
    )
    validate_upstream_topology_input_selection(preparation, topology)
    for name, path in input_files(preparation):
        require_absolute_regular_file(path, name)
    require_absolute_macos_operator_application_bundle(
        preparation.operator_application_bundle,
        "macOS operator application bundle",
    )
    for name, path in executable_input_files(preparation):
        if not os.access(path, os.X_OK):
            raise MacOSDevelopmentReleaseInputPreparationError(
                name + " is not executable"
            )
    release_input_directory = preparation.release_root / RELEASE_INPUT_DIRECTORY_NAME
    output_paths = (
        ("release input directory", release_input_directory),
        (
            "C41 assembled input directory",
            preparation.release_root / "guest-artifact-compilation-input",
        ),
        (
            "C35 Guest artifact output directory",
            preparation.release_root / "guest-artifact-output",
        ),
        (
            "macOS package output",
            preparation.release_root / expected_package_name(preparation),
        ),
        (
            "C47 package assembly receipt",
            preparation.release_root / "macos-release-package-assembly-receipt.json",
        ),
    )
    for name, path in output_paths:
        if path.exists() or path.is_symlink():
            raise MacOSDevelopmentReleaseInputPreparationError(
                name + " already exists: " + str(path)
            )
    try:
        release_plan = load_selected_macos_host_package_release_plan(
            preparation.release_delivery_plans,
            preparation.release_delivery_plan_id,
        )
        return release_plan, topology
    except ProductDeliveryReleasePlanError as error:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "C23 release delivery plan selection failed: " + str(error)
        ) from error


def expected_package_name(preparation: MacOSDevelopmentReleaseInputPreparation) -> str:
    """Load C23 only to detect a stale output before creating release input."""

    try:
        return load_selected_macos_host_package_release_plan(
            preparation.release_delivery_plans,
            preparation.release_delivery_plan_id,
        ).expected_package_file_name
    except ProductDeliveryReleasePlanError as error:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "C23 release delivery plan selection failed: " + str(error)
        ) from error


def load_and_validate_contract_document(
    path: Path, schema_name: str, name: str
) -> Mapping[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MacOSDevelopmentReleaseInputPreparationError(
            name + " cannot be decoded: " + str(error)
        ) from error
    if not isinstance(document, dict):
        raise MacOSDevelopmentReleaseInputPreparationError(name + " must be a JSON object")
    validate_declaration_contract(schema_name, document, name)
    return document


def validate_upstream_topology_input_selection(
    preparation: MacOSDevelopmentReleaseInputPreparation,
    topology: Mapping[str, Any],
) -> None:
    """Make C44 select exactly C46 or the paired C64 Guest artifact inputs."""

    external = topology["topologyKind"] == "external-vitalserver"
    bundled_manager_selected = (
        preparation.guest_bundled_upstream_image_set_manager is not None
        or preparation.guest_bundled_upstream_image_set_manager_configuration
        is not None
    )
    if bundled_manager_selected and (
        preparation.guest_bundled_upstream_image_set_manager is None
        or preparation.guest_bundled_upstream_image_set_manager_configuration is None
    ):
        raise MacOSDevelopmentReleaseInputPreparationError(
            "C64 Guest Bundled Upstream Image-set Manager executable and configuration must be selected together"
        )
    if external:
        if preparation.external_vitalserver_delivery_configuration is None:
            raise MacOSDevelopmentReleaseInputPreparationError(
                "external C44 topology requires a C46 External VitalServer delivery configuration"
            )
        if bundled_manager_selected:
            raise MacOSDevelopmentReleaseInputPreparationError(
                "external C44 topology must not carry an unused C64 Guest Bundled Upstream Image-set Manager"
            )
        return
    if preparation.external_vitalserver_delivery_configuration is not None:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "bundled C44 topology must not carry an unused C46 External VitalServer delivery configuration"
        )
    if not bundled_manager_selected:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "bundled C44 topology requires the C64 Guest Bundled Upstream Image-set Manager executable and configuration"
        )


def input_files(
    preparation: MacOSDevelopmentReleaseInputPreparation,
) -> tuple[tuple[str, Path], ...]:
    """Return every byte selected by this preparer without discovery."""

    files: list[tuple[str, Path]] = [
        ("C23 release delivery plans", preparation.release_delivery_plans),
        (
            "Guest Product bootstrap artifact composer",
            preparation.guest_product_bootstrap_artifact_composer,
        ),
        ("Guest Linux kernel", preparation.guest_kernel),
        ("Guest Linux initial RAM disk", preparation.guest_initial_ramdisk),
        ("Guest root storage", preparation.guest_root_storage),
        ("Guest Runtime", preparation.guest_runtime),
        ("Guest telemetry Collector", preparation.guest_telemetry_collector),
        ("Guest Node Services bundle", preparation.guest_node_services),
        (
            "Guest Product process supervisor",
            preparation.guest_product_process_supervisor,
        ),
        ("Guest Product Release Manager", preparation.guest_product_release_manager),
        ("Host Agent", preparation.host_agent),
        ("Host Edge Proxy", preparation.host_edge_proxy),
        ("Host Installation Manager", preparation.host_installation_manager),
        (
            "Host Update Handoff Supervisor",
            preparation.host_update_handoff_supervisor,
        ),
        ("platformctl", preparation.platformctl),
        (
            "macOS Virtual Machine Supervisor",
            preparation.macos_virtual_machine_supervisor,
        ),
        (
            "C33 Host Agent deployment configuration",
            preparation.host_agent_deployment_configuration,
        ),
        (
            "C53 Operator Interface bootstrap configuration",
            preparation.operator_interface_bootstrap_configuration,
        ),
        (
            "C36 Host Edge Proxy deployment configuration",
            preparation.host_edge_proxy_deployment_configuration,
        ),
        (
            "C56 Host Update Handoff Supervisor configuration",
            preparation.host_update_handoff_supervisor_configuration,
        ),
        ("C58 Host Update Trust Store", preparation.host_update_trust_store),
        (
            "C32 macOS Virtual Machine configuration",
            preparation.macos_virtual_machine_configuration,
        ),
        (
            "C37 Guest Product process deployment configuration",
            preparation.guest_product_process_deployment_configuration,
        ),
        (
            "C59 Guest Product Release Manager configuration",
            preparation.guest_product_release_manager_configuration,
        ),
        (
            "C38 Guest Product service-manager deployment configuration",
            preparation.guest_product_service_manager_deployment_configuration,
        ),
        (
            "C39 Guest Product bootstrap configuration",
            preparation.guest_product_bootstrap_configuration,
        ),
        (
            "C44 Guest Product VitalServer topology deployment",
            preparation.guest_product_vitalserver_topology_deployment,
        ),
        (
            "Guest telemetry Collector configuration",
            preparation.guest_telemetry_collector_configuration,
        ),
        (
            "macOS Virtual Machine Supervisor entitlements",
            preparation.virtualization_entitlements,
        ),
        ("pkgbuild executable", preparation.pkgbuild_executable),
        ("pkgutil executable", preparation.pkgutil_executable),
        ("codesign executable", preparation.codesign_executable),
    ]
    if preparation.external_vitalserver_delivery_configuration is not None:
        files.append(
            (
                "C46 External VitalServer delivery configuration",
                preparation.external_vitalserver_delivery_configuration,
            )
        )
    if preparation.guest_bundled_upstream_image_set_manager is not None:
        files.append(
            (
                "C64 Guest Bundled Upstream Image-set Manager",
                preparation.guest_bundled_upstream_image_set_manager,
            )
        )
    if preparation.guest_bundled_upstream_image_set_manager_configuration is not None:
        files.append(
            (
                "C64 Guest Bundled Upstream Image-set Manager configuration",
                preparation.guest_bundled_upstream_image_set_manager_configuration,
            )
        )
    return tuple(files)


def executable_input_files(
    preparation: MacOSDevelopmentReleaseInputPreparation,
) -> tuple[tuple[str, Path], ...]:
    return (
        (
            "Guest Product bootstrap artifact composer",
            preparation.guest_product_bootstrap_artifact_composer,
        ),
        ("Guest Runtime", preparation.guest_runtime),
        (
            "Guest Product process supervisor",
            preparation.guest_product_process_supervisor,
        ),
        ("Guest Product Release Manager", preparation.guest_product_release_manager),
        *(
            (("C64 Guest Bundled Upstream Image-set Manager", preparation.guest_bundled_upstream_image_set_manager),)
            if preparation.guest_bundled_upstream_image_set_manager is not None
            else ()
        ),
        ("Host Agent", preparation.host_agent),
        ("Host Edge Proxy", preparation.host_edge_proxy),
        ("Host Installation Manager", preparation.host_installation_manager),
        (
            "Host Update Handoff Supervisor",
            preparation.host_update_handoff_supervisor,
        ),
        (
            "macOS Virtual Machine Supervisor",
            preparation.macos_virtual_machine_supervisor,
        ),
        ("pkgbuild executable", preparation.pkgbuild_executable),
        ("pkgutil executable", preparation.pkgutil_executable),
        ("codesign executable", preparation.codesign_executable),
    )


def copy_selected_configuration_documents(
    preparation: MacOSDevelopmentReleaseInputPreparation,
    destination_directory: Path,
) -> None:
    """Copy selected desired documents into the immutable release input set."""

    destination_directory.mkdir(mode=0o700)
    selections = (
        ("releaseDeliveryPlans", preparation.release_delivery_plans, "release-delivery-plans.json"),
        ("hostAgent", preparation.host_agent_deployment_configuration, "host-agent-deployment-configuration.json"),
        ("operatorInterface", preparation.operator_interface_bootstrap_configuration, "operator-interface-bootstrap-configuration.json"),
        ("hostEdgeProxy", preparation.host_edge_proxy_deployment_configuration, "host-edge-proxy-deployment-configuration.json"),
        ("hostUpdateHandoffSupervisor", preparation.host_update_handoff_supervisor_configuration, "host-update-handoff-supervisor-configuration.json"),
        ("hostUpdateTrustStore", preparation.host_update_trust_store, "update-trust-store.json"),
        ("macOSVirtualMachine", preparation.macos_virtual_machine_configuration, "macos-virtual-machine-configuration.json"),
        ("guestProductProcess", preparation.guest_product_process_deployment_configuration, "guest-product-process-deployment.json"),
        ("guestProductReleaseManager", preparation.guest_product_release_manager_configuration, "guest-product-release-manager.json"),
        ("guestProductServiceManager", preparation.guest_product_service_manager_deployment_configuration, "guest-product-service-manager-deployment.json"),
        ("guestProductBootstrap", preparation.guest_product_bootstrap_configuration, "guest-product-bootstrap-configuration.json"),
        ("guestProductVitalServerTopology", preparation.guest_product_vitalserver_topology_deployment, "guest-product-vitalserver-topology-deployment.json"),
        ("guestTelemetryCollector", preparation.guest_telemetry_collector_configuration, "guest-telemetry-collector.yaml"),
        ("virtualizationEntitlements", preparation.virtualization_entitlements, "macos-virtual-machine-supervisor.entitlements"),
    )
    selected: list[tuple[str, Path, str]] = list(selections)
    if preparation.external_vitalserver_delivery_configuration is not None:
        selected.append(("externalVitalServerDelivery", preparation.external_vitalserver_delivery_configuration, "external-vitalserver-delivery-configuration.json"))
    if preparation.guest_bundled_upstream_image_set_manager is not None:
        selected.append(("guestBundledUpstreamImageSetManager", preparation.guest_bundled_upstream_image_set_manager, "guest-bundled-upstream-image-set-manager"))
    if preparation.guest_bundled_upstream_image_set_manager_configuration is not None:
        selected.append(("guestBundledUpstreamImageSetManagerConfiguration", preparation.guest_bundled_upstream_image_set_manager_configuration, "guest-bundled-upstream-image-set-manager-configuration.json"))
    for name, source, file_name in selected:
        destination = destination_directory / file_name
        copy_regular_file(source, destination)


def selected_document_destination_paths(destination_directory: Path, preparation: MacOSDevelopmentReleaseInputPreparation) -> Mapping[str, Path]:
    """Return the final release-input paths without retaining a temporary path."""

    paths: dict[str, Path] = {
        "releaseDeliveryPlans": destination_directory / "release-delivery-plans.json",
        "hostAgent": destination_directory / "host-agent-deployment-configuration.json",
        "operatorInterface": destination_directory
        / "operator-interface-bootstrap-configuration.json",
        "hostEdgeProxy": destination_directory
        / "host-edge-proxy-deployment-configuration.json",
        "hostUpdateHandoffSupervisor": destination_directory
        / "host-update-handoff-supervisor-configuration.json",
        "hostUpdateTrustStore": destination_directory / "update-trust-store.json",
        "macOSVirtualMachine": destination_directory
        / "macos-virtual-machine-configuration.json",
        "guestProductProcess": destination_directory
        / "guest-product-process-deployment.json",
        "guestProductReleaseManager": destination_directory
        / "guest-product-release-manager.json",
        "guestProductServiceManager": destination_directory
        / "guest-product-service-manager-deployment.json",
        "guestProductBootstrap": destination_directory
        / "guest-product-bootstrap-configuration.json",
        "guestProductVitalServerTopology": destination_directory
        / "guest-product-vitalserver-topology-deployment.json",
        "guestTelemetryCollector": destination_directory / "guest-telemetry-collector.yaml",
        "virtualizationEntitlements": destination_directory
        / "macos-virtual-machine-supervisor.entitlements",
    }
    if preparation.external_vitalserver_delivery_configuration is not None:
        paths["externalVitalServerDelivery"] = destination_directory / "external-vitalserver-delivery-configuration.json"
    if preparation.guest_bundled_upstream_image_set_manager is not None:
        paths["guestBundledUpstreamImageSetManager"] = destination_directory / "guest-bundled-upstream-image-set-manager"
    if preparation.guest_bundled_upstream_image_set_manager_configuration is not None:
        paths["guestBundledUpstreamImageSetManagerConfiguration"] = destination_directory / "guest-bundled-upstream-image-set-manager-configuration.json"
    return paths


def compose_guest_artifact_compilation_input_assembly_declaration(
    preparation: MacOSDevelopmentReleaseInputPreparation,
    documents: Mapping[str, Path],
    topology: Mapping[str, Any],
) -> Mapping[str, Any]:
    """Compose C41 with exact fixed artifact roles consumed by C35/C39."""

    def source(identifier: str, path: Path, relative_path: str) -> Mapping[str, str]:
        return {
            "id": identifier,
            "sourceAbsolutePath": str(path),
            "inputRelativePath": relative_path,
        }

    declaration: dict[str, Any] = {
        "schemaVersion": "v1",
        "assemblyId": preparation.guest_input_assembly_id,
        "compilationId": preparation.guest_compilation_id,
        "artifactSetId": preparation.guest_artifact_set_id,
        "architecture": "arm64",
        "guestProductBootstrapArtifactComposer": source(
            "guest-product-bootstrap-artifact-composer",
            preparation.guest_product_bootstrap_artifact_composer,
            "builders/guest-product-bootstrap-artifact-composer",
        ),
        "boot": {
            "kernel": {
                "source": source(
                    "linux-arm64-kernel",
                    preparation.guest_kernel,
                    "inputs/boot/Image",
                ),
                "outputRelativePath": "boot/Image",
            },
            "initialRamdisk": {
                "source": source(
                    "linux-arm64-initrd",
                    preparation.guest_initial_ramdisk,
                    "inputs/boot/initrd.img",
                ),
                "outputRelativePath": "boot/initrd.img",
            },
        },
        "guestRuntimeArtifact": source(
            "guest-runtime-linux-arm64",
            preparation.guest_runtime,
            "inputs/services/guest-runtime",
        ),
        "guestTelemetryCollectorArtifact": source(
            "guest-telemetry-collector-linux-arm64",
            preparation.guest_telemetry_collector,
            "inputs/services/guest-telemetry-collector",
        ),
        "guestTelemetryCollectorConfigurationArtifact": source(
            "guest-telemetry-collector-configuration",
            documents["guestTelemetryCollector"],
            "inputs/configuration/guest-telemetry-collector.yaml",
        ),
        "guestNodeServicesArtifact": source(
            "guest-node-services-linux-arm64",
            preparation.guest_node_services,
            "inputs/services/guest-node-services.tar.gz",
        ),
        "guestProductProcessSupervisorArtifact": source(
            "guest-product-process-supervisor-linux-arm64",
            preparation.guest_product_process_supervisor,
            "inputs/services/guest-product-process-supervisor",
        ),
        "guestProductProcessDeploymentConfigurationArtifact": source(
            "guest-product-process-deployment-configuration",
            documents["guestProductProcess"],
            "inputs/configuration/guest-product-process-deployment.json",
        ),
        "guestProductReleaseManagerArtifact": source(
            "guest-product-release-manager-linux-arm64",
            preparation.guest_product_release_manager,
            "inputs/services/guest-product-release-manager",
        ),
        "guestProductReleaseManagerConfigurationArtifact": source(
            "guest-product-release-manager-configuration",
            documents["guestProductReleaseManager"],
            "inputs/configuration/guest-product-release-manager.json",
        ),
        "guestProductServiceManagerDeploymentConfigurationArtifact": source(
            "guest-product-service-manager-deployment-configuration",
            documents["guestProductServiceManager"],
            "inputs/configuration/guest-product-service-manager-deployment.json",
        ),
        "guestProductBootstrapConfigurationArtifact": source(
            "guest-product-bootstrap-configuration",
            documents["guestProductBootstrap"],
            "inputs/configuration/guest-product-bootstrap.json",
        ),
        "guestProductVitalServerTopologyDeploymentArtifact": source(
            "guest-product-vitalserver-topology-deployment",
            documents["guestProductVitalServerTopology"],
            "inputs/configuration/guest-product-vitalserver-topology-deployment.json",
        ),
        "storageDevices": [
            {
                "id": "guest-root",
                "role": "guest-root-storage",
                "storageImageFormat": "raw",
                "readOnly": False,
                "baseImage": source(
                    "linux-arm64-root-storage-base",
                    preparation.guest_root_storage,
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
    if topology["topologyKind"] == "external-vitalserver":
        declaration["externalVitalServerDeliveryConfigurationArtifact"] = source(
            "external-vitalserver-delivery-configuration",
            documents["externalVitalServerDelivery"],
            "inputs/configuration/external-vitalserver-delivery-configuration.json",
        )
    else:
        declaration["guestBundledUpstreamImageSetManagerArtifact"] = source(
            "guest-bundled-upstream-image-set-manager-linux-arm64",
            documents["guestBundledUpstreamImageSetManager"],
            "inputs/services/guest-bundled-upstream-image-set-manager",
        )
        declaration["guestBundledUpstreamImageSetManagerConfigurationArtifact"] = source(
            "guest-bundled-upstream-image-set-manager-configuration",
            documents["guestBundledUpstreamImageSetManagerConfiguration"],
            "inputs/configuration/guest-bundled-upstream-image-set-manager-configuration.json",
        )
    return declaration


def compose_macos_release_package_assembly_declaration(
    preparation: MacOSDevelopmentReleaseInputPreparation,
    documents: Mapping[str, Path],
    package_file_name: str,
) -> Mapping[str, Any]:
    """Compose C47 without inventing a second version or signature policy."""

    release_input_directory = preparation.release_root / RELEASE_INPUT_DIRECTORY_NAME
    declaration: dict[str, Any] = {
        "schemaVersion": "v1",
        "assemblyId": preparation.assembly_id,
        "releaseDeliveryPlan": {
            "documentAbsolutePath": str(documents["releaseDeliveryPlans"]),
            "id": preparation.release_delivery_plan_id,
        },
        "guestArtifactCompilationInputAssembly": {
            "declarationAbsolutePath": str(
                release_input_directory / GUEST_INPUT_ASSEMBLY_DECLARATION_NAME
            ),
            "assembledInputRootAbsolutePath": str(
                preparation.release_root / "guest-artifact-compilation-input"
            ),
        },
        "guestArtifactCompilation": {
            "outputDirectoryAbsolutePath": str(
                preparation.release_root / "guest-artifact-output"
            ),
            "builderTimeoutSeconds": preparation.builder_timeout_seconds,
        },
        "hostArtifacts": {
            "hostAgentBinaryAbsolutePath": str(preparation.host_agent),
            "hostEdgeProxyBinaryAbsolutePath": str(preparation.host_edge_proxy),
            "hostInstallationManagerBinaryAbsolutePath": str(
                preparation.host_installation_manager
            ),
            "hostUpdateHandoffSupervisorBinaryAbsolutePath": str(
                preparation.host_update_handoff_supervisor
            ),
            "platformctlBinaryAbsolutePath": str(preparation.platformctl),
            "macOSVirtualMachineSupervisorBinaryAbsolutePath": str(
                preparation.macos_virtual_machine_supervisor
            ),
            "operatorApplicationBundleAbsolutePath": str(
                preparation.operator_application_bundle
            ),
            "guestProductProcessSupervisorArtifactAbsolutePath": str(
                preparation.guest_product_process_supervisor
            ),
        },
        "deploymentDocuments": {
            "hostAgentDeploymentConfigurationAbsolutePath": str(
                documents["hostAgent"]
            ),
            "operatorInterfaceBootstrapConfigurationAbsolutePath": str(
                documents["operatorInterface"]
            ),
            "hostEdgeProxyDeploymentConfigurationAbsolutePath": str(
                documents["hostEdgeProxy"]
            ),
            "hostUpdateHandoffSupervisorConfigurationAbsolutePath": str(
                documents["hostUpdateHandoffSupervisor"]
            ),
            "hostUpdateTrustStoreAbsolutePath": str(
                documents["hostUpdateTrustStore"]
            ),
            "macOSVirtualMachineConfigurationAbsolutePath": str(
                documents["macOSVirtualMachine"]
            ),
            "guestProductProcessDeploymentConfigurationAbsolutePath": str(
                documents["guestProductProcess"]
            ),
            "guestProductServiceManagerDeploymentConfigurationAbsolutePath": str(
                documents["guestProductServiceManager"]
            ),
            "guestProductBootstrapConfigurationAbsolutePath": str(
                documents["guestProductBootstrap"]
            ),
            "guestProductVitalServerTopologyDeploymentAbsolutePath": str(
                documents["guestProductVitalServerTopology"]
            ),
        },
        "macOSPackage": {
            "payloadBasePath": str(preparation.payload_base_path),
            "outputPackageAbsolutePath": str(
                preparation.release_root / package_file_name
            ),
            "pkgbuildExecutableAbsolutePath": str(preparation.pkgbuild_executable),
            "installerPackageSigning": {"mode": "unsigned"},
            "virtualMachineSupervisorCodeSigning": {
                "mode": "ad-hoc",
                "codesignExecutableAbsolutePath": str(preparation.codesign_executable),
                "virtualizationEntitlementsAbsolutePath": str(
                    documents["virtualizationEntitlements"]
                ),
            },
        },
        "macOSPackageVerification": {
            "pkgutilExecutableAbsolutePath": str(preparation.pkgutil_executable)
        },
        "assemblyReceipt": {
            "outputAbsolutePath": str(
                preparation.release_root
                / "macos-release-package-assembly-receipt.json"
            )
        },
    }
    if preparation.external_vitalserver_delivery_configuration is not None:
        declaration["deploymentDocuments"][
            "externalVitalServerDeliveryConfigurationAbsolutePath"
        ] = str(documents["externalVitalServerDelivery"])
    if preparation.guest_bundled_upstream_image_set_manager_configuration is not None:
        declaration["deploymentDocuments"][
            "guestBundledUpstreamImageSetManagerConfigurationAbsolutePath"
        ] = str(documents["guestBundledUpstreamImageSetManagerConfiguration"])
    return declaration


def validate_declaration_contract(
    schema_name: str, document: Mapping[str, Any], contract_name: str
) -> None:
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        errors = repository.validate_instance(schema_name, document)
    except ContractToolError as error:
        raise MacOSDevelopmentReleaseInputPreparationError(
            contract_name + " contract source is unavailable: " + str(error)
        ) from error
    if errors:
        raise MacOSDevelopmentReleaseInputPreparationError(
            contract_name + " declaration is invalid: " + "; ".join(errors)
        )


def require_absolute_directory(path: Path, name: str) -> None:
    if not path.is_absolute() or ".." in path.parts:
        raise MacOSDevelopmentReleaseInputPreparationError(
            name + " must be an absolute non-traversing path"
        )
    if not path.is_dir() or path.is_symlink():
        raise MacOSDevelopmentReleaseInputPreparationError(
            name + " must be an existing non-symlink directory: " + str(path)
        )


def require_absolute_regular_file(path: Path, name: str) -> None:
    if not path.is_absolute() or ".." in path.parts:
        raise MacOSDevelopmentReleaseInputPreparationError(
            name + " must be an absolute non-traversing path"
        )
    if not path.is_file() or path.is_symlink():
        raise MacOSDevelopmentReleaseInputPreparationError(
            name + " must be a regular non-symlink file: " + str(path)
        )


def copy_regular_file(source: Path, destination: Path) -> None:
    """Copy only a previously validated regular source into the new input set."""

    try:
        with source.open("rb") as input_file, destination.open("xb") as output_file:
            shutil.copyfileobj(input_file, output_file)
            output_file.flush()
            os.fsync(output_file.fileno())
    except OSError as error:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "could not copy selected release document "
            + str(source)
            + ": "
            + str(error)
        ) from error


def write_json(path: Path, document: Mapping[str, Any]) -> None:
    try:
        with path.open("xb") as output:
            output.write((json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8"))
            output.flush()
            os.fsync(output.fileno())
    except OSError as error:
        raise MacOSDevelopmentReleaseInputPreparationError(
            "could not write release declaration " + str(path) + ": " + str(error)
        ) from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as input_file:
        for block in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_absolute_macos_operator_application_bundle(path: Path, name: str) -> None:
    """Keep C47's user-facing application input explicit and self-contained."""

    from tooling import macos_host_package_composer

    try:
        macos_host_package_composer.validate_declared_macos_operator_application_bundle(
            path,
            name,
        )
    except macos_host_package_composer.MacOSHostPackageCompositionError as error:
        raise MacOSDevelopmentReleaseInputPreparationError(str(error)) from error


def parse_arguments(arguments: Sequence[str]) -> MacOSDevelopmentReleaseInputPreparation:
    parser = argparse.ArgumentParser(
        description="prepare explicit C41/C47 inputs for one unsigned macOS development package"
    )
    parser.add_argument("--release-root", required=True)
    parser.add_argument("--assembly-id", required=True)
    parser.add_argument("--guest-input-assembly-id", required=True)
    parser.add_argument("--guest-compilation-id", required=True)
    parser.add_argument("--guest-artifact-set-id", required=True)
    parser.add_argument("--release-delivery-plans", required=True)
    parser.add_argument("--release-delivery-plan-id", required=True)
    parser.add_argument("--payload-base-path", required=True)
    parser.add_argument("--guest-product-bootstrap-artifact-composer", required=True)
    parser.add_argument("--guest-kernel", required=True)
    parser.add_argument("--guest-initial-ramdisk", required=True)
    parser.add_argument("--guest-root-storage", required=True)
    parser.add_argument("--guest-runtime", required=True)
    parser.add_argument("--guest-telemetry-collector", required=True)
    parser.add_argument("--guest-node-services", required=True)
    parser.add_argument("--guest-product-process-supervisor", required=True)
    parser.add_argument("--guest-product-release-manager", required=True)
    parser.add_argument("--host-agent", required=True)
    parser.add_argument("--host-edge-proxy", required=True)
    parser.add_argument("--host-installation-manager", required=True)
    parser.add_argument("--host-update-handoff-supervisor", required=True)
    parser.add_argument("--platformctl", required=True)
    parser.add_argument("--macos-virtual-machine-supervisor", required=True)
    parser.add_argument("--operator-application-bundle", required=True)
    parser.add_argument("--host-agent-deployment-configuration", required=True)
    parser.add_argument("--operator-interface-bootstrap-configuration", required=True)
    parser.add_argument("--host-edge-proxy-deployment-configuration", required=True)
    parser.add_argument("--host-update-handoff-supervisor-configuration", required=True)
    parser.add_argument("--host-update-trust-store", required=True)
    parser.add_argument("--macos-virtual-machine-configuration", required=True)
    parser.add_argument("--guest-product-process-deployment-configuration", required=True)
    parser.add_argument("--guest-product-release-manager-configuration", required=True)
    parser.add_argument("--guest-product-service-manager-deployment-configuration", required=True)
    parser.add_argument("--guest-product-bootstrap-configuration", required=True)
    parser.add_argument("--guest-product-vitalserver-topology-deployment", required=True)
    parser.add_argument("--external-vitalserver-delivery-configuration")
    parser.add_argument("--guest-bundled-upstream-image-set-manager")
    parser.add_argument("--guest-bundled-upstream-image-set-manager-configuration")
    parser.add_argument("--guest-telemetry-collector-configuration", required=True)
    parser.add_argument("--virtualization-entitlements", required=True)
    parser.add_argument("--pkgbuild", required=True)
    parser.add_argument("--pkgutil", required=True)
    parser.add_argument("--codesign", required=True)
    parser.add_argument("--builder-timeout-seconds", type=int, required=True)
    options = parser.parse_args(arguments)
    return MacOSDevelopmentReleaseInputPreparation(
        release_root=Path(options.release_root),
        assembly_id=options.assembly_id,
        guest_input_assembly_id=options.guest_input_assembly_id,
        guest_compilation_id=options.guest_compilation_id,
        guest_artifact_set_id=options.guest_artifact_set_id,
        release_delivery_plans=Path(options.release_delivery_plans),
        release_delivery_plan_id=options.release_delivery_plan_id,
        payload_base_path=PurePosixPath(options.payload_base_path),
        guest_product_bootstrap_artifact_composer=Path(options.guest_product_bootstrap_artifact_composer),
        guest_kernel=Path(options.guest_kernel),
        guest_initial_ramdisk=Path(options.guest_initial_ramdisk),
        guest_root_storage=Path(options.guest_root_storage),
        guest_runtime=Path(options.guest_runtime),
        guest_telemetry_collector=Path(options.guest_telemetry_collector),
        guest_node_services=Path(options.guest_node_services),
        guest_product_process_supervisor=Path(options.guest_product_process_supervisor),
        guest_product_release_manager=Path(options.guest_product_release_manager),
        host_agent=Path(options.host_agent),
        host_edge_proxy=Path(options.host_edge_proxy),
        host_installation_manager=Path(options.host_installation_manager),
        host_update_handoff_supervisor=Path(options.host_update_handoff_supervisor),
        platformctl=Path(options.platformctl),
        macos_virtual_machine_supervisor=Path(options.macos_virtual_machine_supervisor),
        operator_application_bundle=Path(options.operator_application_bundle),
        host_agent_deployment_configuration=Path(options.host_agent_deployment_configuration),
        operator_interface_bootstrap_configuration=Path(options.operator_interface_bootstrap_configuration),
        host_edge_proxy_deployment_configuration=Path(options.host_edge_proxy_deployment_configuration),
        host_update_handoff_supervisor_configuration=Path(options.host_update_handoff_supervisor_configuration),
        host_update_trust_store=Path(options.host_update_trust_store),
        macos_virtual_machine_configuration=Path(options.macos_virtual_machine_configuration),
        guest_product_process_deployment_configuration=Path(options.guest_product_process_deployment_configuration),
        guest_product_release_manager_configuration=Path(options.guest_product_release_manager_configuration),
        guest_product_service_manager_deployment_configuration=Path(options.guest_product_service_manager_deployment_configuration),
        guest_product_bootstrap_configuration=Path(options.guest_product_bootstrap_configuration),
        guest_product_vitalserver_topology_deployment=Path(options.guest_product_vitalserver_topology_deployment),
        external_vitalserver_delivery_configuration=(
            Path(options.external_vitalserver_delivery_configuration)
            if options.external_vitalserver_delivery_configuration
            else None
        ),
        guest_telemetry_collector_configuration=Path(options.guest_telemetry_collector_configuration),
        virtualization_entitlements=Path(options.virtualization_entitlements),
        pkgbuild_executable=Path(options.pkgbuild),
        pkgutil_executable=Path(options.pkgutil),
        codesign_executable=Path(options.codesign),
        builder_timeout_seconds=options.builder_timeout_seconds,
        guest_bundled_upstream_image_set_manager=(
            Path(options.guest_bundled_upstream_image_set_manager)
            if options.guest_bundled_upstream_image_set_manager
            else None
        ),
        guest_bundled_upstream_image_set_manager_configuration=(
            Path(options.guest_bundled_upstream_image_set_manager_configuration)
            if options.guest_bundled_upstream_image_set_manager_configuration
            else None
        ),
    )


def main(arguments: Sequence[str] | None = None) -> int:
    try:
        preparation = parse_arguments(
            sys.argv[1:] if arguments is None else arguments
        )
        result = prepare_macos_development_release_input(preparation)
    except MacOSDevelopmentReleaseInputPreparationError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
