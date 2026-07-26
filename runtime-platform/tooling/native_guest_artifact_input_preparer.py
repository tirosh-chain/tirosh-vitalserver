"""Prepare one explicit amd64 C41 input set for a native Guest provider.

Windows Hyper-V and Linux KVM/libvirt consume the same Guest Product bytes,
but neither Host has macOS Virtualization boot resources.  This adapter owns
only the release-workspace copy of selected desired documents and the C41
source declaration.  C41 subsequently owns input copying and C35 owns the
selected Guest build.  This module does not select a provider, start a VM,
compose a Host installer, or turn a missing source into a bundled default.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractRepository, ContractToolError


class NativeGuestArtifactInputPreparationError(RuntimeError):
    """One explicit amd64 C41 source selection cannot be prepared."""


@dataclass(frozen=True)
class NativeGuestArtifactInputPreparation:
    """All caller-owned source paths for one native Guest C41 declaration."""

    release_root: Path
    assembly_id: str
    compilation_id: str
    artifact_set_id: str
    guest_product_bootstrap_artifact_composer: Path
    guest_root_storage: Path
    guest_runtime: Path
    guest_telemetry_collector: Path
    guest_telemetry_collector_configuration: Path
    guest_node_services: Path
    guest_product_process_supervisor: Path
    guest_product_process_deployment_configuration: Path
    guest_product_release_manager: Path
    guest_product_release_manager_configuration: Path
    guest_product_service_manager_deployment_configuration: Path
    guest_product_bootstrap_configuration: Path
    guest_product_vitalserver_topology_deployment: Path
    external_vitalserver_delivery_configuration: Path | None
    guest_bundled_upstream_image_set_manager: Path | None = None
    guest_bundled_upstream_image_set_manager_configuration: Path | None = None


RELEASE_INPUT_DIRECTORY_NAME = "native-guest-release-input"
GUEST_INPUT_ASSEMBLY_DECLARATION_NAME = "guest-artifact-compilation-input-assembly.json"


def prepare_native_guest_artifact_input(
    preparation: NativeGuestArtifactInputPreparation,
) -> Mapping[str, Any]:
    """Atomically publish copied desired documents and one amd64 C41 source."""

    topology = validate_preparation(preparation)
    release_input_directory = preparation.release_root / RELEASE_INPUT_DIRECTORY_NAME
    temporary_directory = Path(
        tempfile.mkdtemp(
            prefix=f".{RELEASE_INPUT_DIRECTORY_NAME}.",
            dir=preparation.release_root,
        )
    )
    try:
        copied_documents = copy_selected_configuration_documents(
            preparation, temporary_directory / "documents"
        )
        documents = {
            name: release_input_directory / "documents" / path.name
            for name, path in copied_documents.items()
        }
        declaration = compose_guest_artifact_compilation_input_assembly_declaration(
            preparation, documents, topology
        )
        validate_contract_document(
            "guest-artifact-compilation-input-assembly-declaration.schema.json",
            declaration,
            "C41 GuestArtifactCompilationInputAssemblyDeclaration",
        )
        write_json(
            temporary_directory / GUEST_INPUT_ASSEMBLY_DECLARATION_NAME,
            declaration,
        )
        os.replace(temporary_directory, release_input_directory)
    except Exception:
        shutil.rmtree(temporary_directory, ignore_errors=True)
        raise

    declaration_path = release_input_directory / GUEST_INPUT_ASSEMBLY_DECLARATION_NAME
    return {
        "releaseInputDirectory": str(release_input_directory),
        "guestArtifactCompilationInputAssemblyDeclaration": {
            "path": str(declaration_path),
            "sha256": sha256_file(declaration_path),
        },
        "nextEffect": {
            "kind": "assemble-guest-artifact-compilation-input",
            "inputAssemblyDeclarationPath": str(declaration_path),
            "assembledInputRootPath": str(
                preparation.release_root / "guest-artifact-compilation-input"
            ),
        },
    }


def validate_preparation(
    preparation: NativeGuestArtifactInputPreparation,
) -> Mapping[str, Any]:
    """Validate exact source meaning before the release workspace changes."""

    require_absolute_directory(preparation.release_root, "release root")
    for name, identifier in (
        ("assembly id", preparation.assembly_id),
        ("compilation id", preparation.compilation_id),
        ("artifact set id", preparation.artifact_set_id),
    ):
        if not identifier:
            raise NativeGuestArtifactInputPreparationError(name + " is required")
    for name, path in input_files(preparation):
        require_absolute_regular_file(path, name)
    for name, path in executable_input_files(preparation):
        if not os.access(path, os.X_OK):
            raise NativeGuestArtifactInputPreparationError(name + " is not executable")

    release_input_directory = preparation.release_root / RELEASE_INPUT_DIRECTORY_NAME
    for name, path in (
        ("native Guest release input directory", release_input_directory),
        (
            "C41 assembled input directory",
            preparation.release_root / "guest-artifact-compilation-input",
        ),
        (
            "C35 Guest artifact output directory",
            preparation.release_root / "guest-artifact-output",
        ),
    ):
        if path.exists() or path.is_symlink():
            raise NativeGuestArtifactInputPreparationError(
                name + " already exists: " + str(path)
            )

    bootstrap = load_and_validate_contract_document(
        preparation.guest_product_bootstrap_configuration,
        "guest-product-bootstrap-configuration.schema.json",
        "C39 GuestProductBootstrapConfiguration",
    )
    if bootstrap.get("guestArchitecture") != "amd64":
        raise NativeGuestArtifactInputPreparationError(
            "C39 GuestProductBootstrapConfiguration must declare guestArchitecture amd64"
        )
    topology = load_and_validate_contract_document(
        preparation.guest_product_vitalserver_topology_deployment,
        "guest-product-vitalserver-topology-deployment.schema.json",
        "C44 GuestProductVitalServerTopologyDeployment",
    )
    validate_upstream_topology_input_selection(preparation, topology)
    return topology


def input_files(
    preparation: NativeGuestArtifactInputPreparation,
) -> tuple[tuple[str, Path], ...]:
    files: list[tuple[str, Path]] = [
        (
            "Guest Product bootstrap artifact composer",
            preparation.guest_product_bootstrap_artifact_composer,
        ),
        ("Guest root storage", preparation.guest_root_storage),
        ("Guest Runtime", preparation.guest_runtime),
        ("Guest telemetry Collector", preparation.guest_telemetry_collector),
        (
            "Guest telemetry Collector configuration",
            preparation.guest_telemetry_collector_configuration,
        ),
        ("Guest Node Services bundle", preparation.guest_node_services),
        (
            "Guest Product process supervisor",
            preparation.guest_product_process_supervisor,
        ),
        (
            "C37 Guest Product process deployment configuration",
            preparation.guest_product_process_deployment_configuration,
        ),
        (
            "Guest Product Release Manager",
            preparation.guest_product_release_manager,
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
    preparation: NativeGuestArtifactInputPreparation,
) -> tuple[tuple[str, Path], ...]:
    return (
        (
            "Guest Product bootstrap artifact composer",
            preparation.guest_product_bootstrap_artifact_composer,
        ),
        ("Guest Runtime", preparation.guest_runtime),
        ("Guest telemetry Collector", preparation.guest_telemetry_collector),
        (
            "Guest Product process supervisor",
            preparation.guest_product_process_supervisor,
        ),
        ("Guest Product Release Manager", preparation.guest_product_release_manager),
    )


def validate_upstream_topology_input_selection(
    preparation: NativeGuestArtifactInputPreparation, topology: Mapping[str, Any]
) -> None:
    """C44 selection alone decides whether C46 or the C64 pair is a C41 source."""

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
        raise NativeGuestArtifactInputPreparationError(
            "C64 Guest Bundled Upstream Image-set Manager executable and configuration must be selected together"
        )
    if external and preparation.external_vitalserver_delivery_configuration is None:
        raise NativeGuestArtifactInputPreparationError(
            "external C44 topology requires a C46 External VitalServer delivery configuration"
        )
    if external and bundled_manager_selected:
        raise NativeGuestArtifactInputPreparationError(
            "external C44 topology must not carry an unused C64 Guest Bundled Upstream Image-set Manager"
        )
    if not external and preparation.external_vitalserver_delivery_configuration is not None:
        raise NativeGuestArtifactInputPreparationError(
            "bundled C44 topology must not carry an unused C46 External VitalServer delivery configuration"
        )
    if not external:
        if not bundled_manager_selected:
            raise NativeGuestArtifactInputPreparationError(
                "bundled C44 topology requires the C64 Guest Bundled Upstream Image-set Manager executable and configuration"
            )
        return

    external_delivery = load_and_validate_contract_document(
        preparation.external_vitalserver_delivery_configuration,
        "external-vitalserver-delivery-configuration.schema.json",
        "C46 ExternalVitalServerDeliveryConfiguration",
    )
    deployment = topology["externalVitalServerDeploymentConfiguration"]
    if (
        deployment["externalUpstreamIntegrationReference"]
        != external_delivery["externalUpstreamIntegrationReference"]
        or deployment["externalVitalServerDeliveryConfigurationReference"]["resourceId"]
        != external_delivery["configurationId"]
        or topology["vitalServerDeliveryProvider"]
        != external_delivery["vitalServerDeliveryProvider"]
    ):
        raise NativeGuestArtifactInputPreparationError(
            "C44 external topology and C46 delivery configuration do not name the same integration, configuration, and provider"
        )


def copy_selected_configuration_documents(
    preparation: NativeGuestArtifactInputPreparation, destination_directory: Path
) -> Mapping[str, Path]:
    """Copy selected desired documents so C41 cannot observe later source edits."""

    destination_directory.mkdir(mode=0o700)
    selections: list[tuple[str, Path, str]] = [
        (
            "guestTelemetryCollector",
            preparation.guest_telemetry_collector_configuration,
            "guest-telemetry-collector.yaml",
        ),
        (
            "guestProductProcess",
            preparation.guest_product_process_deployment_configuration,
            "guest-product-process-deployment.json",
        ),
        (
            "guestProductReleaseManager",
            preparation.guest_product_release_manager_configuration,
            "guest-product-release-manager.json",
        ),
        (
            "guestProductServiceManager",
            preparation.guest_product_service_manager_deployment_configuration,
            "guest-product-service-manager-deployment.json",
        ),
        (
            "guestProductBootstrap",
            preparation.guest_product_bootstrap_configuration,
            "guest-product-bootstrap-configuration.json",
        ),
        (
            "guestProductVitalServerTopology",
            preparation.guest_product_vitalserver_topology_deployment,
            "guest-product-vitalserver-topology-deployment.json",
        ),
    ]
    if preparation.external_vitalserver_delivery_configuration is not None:
        selections.append(
            (
                "externalVitalServerDelivery",
                preparation.external_vitalserver_delivery_configuration,
                "external-vitalserver-delivery-configuration.json",
            )
        )
    if preparation.guest_bundled_upstream_image_set_manager is not None:
        selections.append(
            (
                "guestBundledUpstreamImageSetManager",
                preparation.guest_bundled_upstream_image_set_manager,
                "guest-bundled-upstream-image-set-manager",
            )
        )
    if preparation.guest_bundled_upstream_image_set_manager_configuration is not None:
        selections.append(
            (
                "guestBundledUpstreamImageSetManagerConfiguration",
                preparation.guest_bundled_upstream_image_set_manager_configuration,
                "guest-bundled-upstream-image-set-manager-configuration.json",
            )
        )
    paths: dict[str, Path] = {}
    for name, source, filename in selections:
        destination = destination_directory / filename
        copy_regular_file(source, destination)
        paths[name] = destination
    return paths


def compose_guest_artifact_compilation_input_assembly_declaration(
    preparation: NativeGuestArtifactInputPreparation,
    documents: Mapping[str, Path],
    topology: Mapping[str, Any],
) -> Mapping[str, Any]:
    """Compose C41 with no boot fields and only C44-selected upstream input."""

    def source(identifier: str, path: Path, relative_path: str) -> Mapping[str, str]:
        return {
            "id": identifier,
            "sourceAbsolutePath": str(path),
            "inputRelativePath": relative_path,
        }

    declaration: dict[str, Any] = {
        "schemaVersion": "v1",
        "assemblyId": preparation.assembly_id,
        "compilationId": preparation.compilation_id,
        "artifactSetId": preparation.artifact_set_id,
        "architecture": "amd64",
        "guestProductBootstrapArtifactComposer": source(
            "guest-product-bootstrap-artifact-composer",
            preparation.guest_product_bootstrap_artifact_composer,
            "builders/guest-product-bootstrap-artifact-composer",
        ),
        "guestRuntimeArtifact": source(
            "guest-runtime-linux-amd64",
            preparation.guest_runtime,
            "inputs/services/guest-runtime",
        ),
        "guestTelemetryCollectorArtifact": source(
            "guest-telemetry-collector-linux-amd64",
            preparation.guest_telemetry_collector,
            "inputs/services/guest-telemetry-collector",
        ),
        "guestTelemetryCollectorConfigurationArtifact": source(
            "guest-telemetry-collector-configuration",
            documents["guestTelemetryCollector"],
            "inputs/configuration/guest-telemetry-collector.yaml",
        ),
        "guestNodeServicesArtifact": source(
            "guest-node-services-linux-amd64",
            preparation.guest_node_services,
            "inputs/services/guest-node-services.tar.gz",
        ),
        "guestProductProcessSupervisorArtifact": source(
            "guest-product-process-supervisor-linux-amd64",
            preparation.guest_product_process_supervisor,
            "inputs/services/guest-product-process-supervisor",
        ),
        "guestProductProcessDeploymentConfigurationArtifact": source(
            "guest-product-process-deployment-configuration",
            documents["guestProductProcess"],
            "inputs/configuration/guest-product-process-deployment.json",
        ),
        "guestProductReleaseManagerArtifact": source(
            "guest-product-release-manager-linux-amd64",
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
                    "linux-amd64-root-storage-base",
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
            "guest-bundled-upstream-image-set-manager-linux-amd64",
            documents["guestBundledUpstreamImageSetManager"],
            "inputs/services/guest-bundled-upstream-image-set-manager",
        )
        declaration["guestBundledUpstreamImageSetManagerConfigurationArtifact"] = source(
            "guest-bundled-upstream-image-set-manager-configuration",
            documents["guestBundledUpstreamImageSetManagerConfiguration"],
            "inputs/configuration/guest-bundled-upstream-image-set-manager-configuration.json",
        )
    return declaration


def load_and_validate_contract_document(
    path: Path, schema_name: str, name: str
) -> Mapping[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise NativeGuestArtifactInputPreparationError(
            name + " cannot be decoded: " + str(error)
        ) from error
    if not isinstance(document, dict):
        raise NativeGuestArtifactInputPreparationError(name + " must be a JSON object")
    validate_contract_document(schema_name, document, name)
    return document


def validate_contract_document(
    schema_name: str, document: Mapping[str, Any], name: str
) -> None:
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        errors = repository.validate_instance(schema_name, document)
    except ContractToolError as error:
        raise NativeGuestArtifactInputPreparationError(
            name + " contract source is unavailable: " + str(error)
        ) from error
    if errors:
        raise NativeGuestArtifactInputPreparationError(
            name + " is invalid: " + "; ".join(errors)
        )


def require_absolute_directory(path: Path, name: str) -> None:
    if not path.is_absolute() or ".." in path.parts or not path.is_dir() or path.is_symlink():
        raise NativeGuestArtifactInputPreparationError(
            name + " must be an existing absolute non-symlink directory: " + str(path)
        )


def require_absolute_regular_file(path: Path, name: str) -> None:
    if not path.is_absolute() or ".." in path.parts or not path.is_file() or path.is_symlink():
        raise NativeGuestArtifactInputPreparationError(
            name + " must be an absolute regular non-symlink file: " + str(path)
        )


def copy_regular_file(source: Path, destination: Path) -> None:
    try:
        with source.open("rb") as input_file, destination.open("xb") as output_file:
            shutil.copyfileobj(input_file, output_file)
            output_file.flush()
            os.fsync(output_file.fileno())
    except OSError as error:
        raise NativeGuestArtifactInputPreparationError(
            "could not copy selected release document " + str(source) + ": " + str(error)
        ) from error


def write_json(path: Path, document: Mapping[str, Any]) -> None:
    try:
        with path.open("xb") as output_file:
            output_file.write(
                (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
            )
            output_file.flush()
            os.fsync(output_file.fileno())
    except OSError as error:
        raise NativeGuestArtifactInputPreparationError(
            "could not write C41 declaration " + str(path) + ": " + str(error)
        ) from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as input_file:
        for block in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_arguments(arguments: Sequence[str]) -> NativeGuestArtifactInputPreparation:
    parser = argparse.ArgumentParser(
        description="prepare an explicit amd64 C41 input set for a native Guest provider"
    )
    parser.add_argument("--release-root", required=True)
    parser.add_argument("--assembly-id", required=True)
    parser.add_argument("--compilation-id", required=True)
    parser.add_argument("--artifact-set-id", required=True)
    parser.add_argument("--guest-product-bootstrap-artifact-composer", required=True)
    parser.add_argument("--guest-root-storage", required=True)
    parser.add_argument("--guest-runtime", required=True)
    parser.add_argument("--guest-telemetry-collector", required=True)
    parser.add_argument("--guest-telemetry-collector-configuration", required=True)
    parser.add_argument("--guest-node-services", required=True)
    parser.add_argument("--guest-product-process-supervisor", required=True)
    parser.add_argument("--guest-product-process-deployment-configuration", required=True)
    parser.add_argument("--guest-product-release-manager", required=True)
    parser.add_argument("--guest-product-release-manager-configuration", required=True)
    parser.add_argument("--guest-product-service-manager-deployment-configuration", required=True)
    parser.add_argument("--guest-product-bootstrap-configuration", required=True)
    parser.add_argument("--guest-product-vitalserver-topology-deployment", required=True)
    parser.add_argument("--external-vitalserver-delivery-configuration")
    parser.add_argument("--guest-bundled-upstream-image-set-manager")
    parser.add_argument("--guest-bundled-upstream-image-set-manager-configuration")
    options = parser.parse_args(arguments)
    return NativeGuestArtifactInputPreparation(
        release_root=Path(options.release_root),
        assembly_id=options.assembly_id,
        compilation_id=options.compilation_id,
        artifact_set_id=options.artifact_set_id,
        guest_product_bootstrap_artifact_composer=Path(
            options.guest_product_bootstrap_artifact_composer
        ),
        guest_root_storage=Path(options.guest_root_storage),
        guest_runtime=Path(options.guest_runtime),
        guest_telemetry_collector=Path(options.guest_telemetry_collector),
        guest_telemetry_collector_configuration=Path(
            options.guest_telemetry_collector_configuration
        ),
        guest_node_services=Path(options.guest_node_services),
        guest_product_process_supervisor=Path(
            options.guest_product_process_supervisor
        ),
        guest_product_process_deployment_configuration=Path(
            options.guest_product_process_deployment_configuration
        ),
        guest_product_release_manager=Path(options.guest_product_release_manager),
        guest_product_release_manager_configuration=Path(
            options.guest_product_release_manager_configuration
        ),
        guest_product_service_manager_deployment_configuration=Path(
            options.guest_product_service_manager_deployment_configuration
        ),
        guest_product_bootstrap_configuration=Path(
            options.guest_product_bootstrap_configuration
        ),
        guest_product_vitalserver_topology_deployment=Path(
            options.guest_product_vitalserver_topology_deployment
        ),
        external_vitalserver_delivery_configuration=(
            Path(options.external_vitalserver_delivery_configuration)
            if options.external_vitalserver_delivery_configuration
            else None
        ),
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
        preparation = parse_arguments(sys.argv[1:] if arguments is None else arguments)
        result = prepare_native_guest_artifact_input(preparation)
    except NativeGuestArtifactInputPreparationError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
