"""Compile one explicit arm64 or amd64 Guest artifact set through a selected builder.

GuestArtifactCompiler owns release-build orchestration only. C35 names every
immutable input and the selected bootstrap-artifact composer identity; that
composer copies the declared raw root and creates the NoCloud bootstrap volume.
This module never searches a VM cache, downloads a base image, chooses a
builder, or turns a missing input into a placeholder Guest.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Iterable, Mapping, Sequence

from tooling import macos_guest_artifact_manifest_composer as manifest_composer
from tooling import native_guest_artifact_manifest_composer as native_manifest_composer


MAXIMUM_COMMAND_BYTES = 1 << 20
MAXIMUM_BUILDER_DIAGNOSTIC_BYTES = 1 << 16
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
PATH_COMPONENT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class GuestArtifactCompilationError(RuntimeError):
    """A C35 compilation cannot safely publish a Guest artifact set."""

    def __init__(self, compilation_id: str, stage: str, reason: str) -> None:
        super().__init__(
            "Guest artifact compilation failed "
            f"compilationId={compilation_id or 'unknown'} stage={stage} reason={reason}"
        )
        self.compilation_id = compilation_id
        self.stage = stage
        self.reason = reason


@dataclass(frozen=True)
class InputArtifact:
    """One immutable C35 source below the caller-selected input root."""

    identifier: str
    input_relative_path: PurePosixPath
    size_bytes: int
    sha256: str


@dataclass(frozen=True)
class BootArtifactOutput:
    """One boot source and the deterministic compiler output path."""

    source: InputArtifact
    output_relative_path: PurePosixPath


@dataclass(frozen=True)
class GuestStorageArtifactOutput:
    """One explicit Guest storage role and deterministic compiled artifact."""

    identifier: str
    role: str
    storage_image_format: str
    guest_volume_file_system: str | None
    read_only: bool
    base_image: InputArtifact | None
    output_relative_path: PurePosixPath


@dataclass(frozen=True)
class GuestArtifactCompilationCommand:
    """Complete parsed C35 command; it contains no Host or build-machine state."""

    compilation_id: str
    artifact_set_id: str
    architecture: str
    build_environment_id: str
    builder_executable_size_bytes: int
    builder_executable_sha256: str
    kernel: BootArtifactOutput | None
    initial_ramdisk: BootArtifactOutput | None
    guest_runtime_artifact: InputArtifact
    guest_telemetry_collector_artifact: InputArtifact | None
    guest_telemetry_collector_configuration_artifact: InputArtifact | None
    guest_node_services_artifact: InputArtifact
    guest_product_process_supervisor_artifact: InputArtifact
    guest_product_process_deployment_configuration_artifact: InputArtifact
    guest_product_release_manager_artifact: InputArtifact
    guest_product_release_manager_configuration_artifact: InputArtifact
    guest_product_service_manager_deployment_configuration_artifact: InputArtifact
    guest_product_bootstrap_configuration_artifact: InputArtifact
    guest_product_vitalserver_topology_deployment_artifact: InputArtifact
    external_vitalserver_delivery_configuration_artifact: InputArtifact | None
    guest_bundled_upstream_image_set_manager_artifact: InputArtifact | None
    guest_bundled_upstream_image_set_manager_configuration_artifact: InputArtifact | None
    storage_devices: tuple[GuestStorageArtifactOutput, ...]

    def input_artifacts(self) -> tuple[InputArtifact, ...]:
        boot_artifacts: tuple[InputArtifact, ...] = ()
        if self.kernel is not None:
            boot_artifacts = (self.kernel.source,)
        if self.initial_ramdisk is not None:
            boot_artifacts += (self.initial_ramdisk.source,)
        artifacts: tuple[InputArtifact, ...] = (
            *boot_artifacts,
            self.guest_runtime_artifact,
        )
        if self.guest_telemetry_collector_artifact is not None:
            artifacts += (self.guest_telemetry_collector_artifact,)
        if self.guest_telemetry_collector_configuration_artifact is not None:
            artifacts += (self.guest_telemetry_collector_configuration_artifact,)
        artifacts += (
            self.guest_node_services_artifact,
            self.guest_product_process_supervisor_artifact,
            self.guest_product_process_deployment_configuration_artifact,
            self.guest_product_release_manager_artifact,
            self.guest_product_release_manager_configuration_artifact,
            self.guest_product_service_manager_deployment_configuration_artifact,
            self.guest_product_bootstrap_configuration_artifact,
            self.guest_product_vitalserver_topology_deployment_artifact,
        )
        if self.external_vitalserver_delivery_configuration_artifact is not None:
            artifacts += (self.external_vitalserver_delivery_configuration_artifact,)
        if self.guest_bundled_upstream_image_set_manager_artifact is not None:
            artifacts += (
                self.guest_bundled_upstream_image_set_manager_artifact,
                self.guest_bundled_upstream_image_set_manager_configuration_artifact,
            )
        return (*artifacts, *(storage.base_image for storage in self.storage_devices if storage.base_image is not None))


@dataclass(frozen=True)
class GuestArtifactCompilationExecution:
    """Explicit C35 effect inputs and bounds; no path has a default or fallback.

    The compiler records completion time after its selected-builder and C34
    effects succeed. Callers choose inputs and an output destination, but do
    not supply completion evidence for a compiler effect they did not run.
    """

    compilation_command_path: Path
    input_root: Path
    builder_executable: Path
    output_directory: Path
    builder_timeout_seconds: int


def compile_guest_artifact_set(
    execution: GuestArtifactCompilationExecution,
) -> dict[str, object]:
    """Run a selected builder and atomically publish C34/C65 plus C35 receipt.

    A successful return proves only that declared source bytes were supplied to
    the selected builder and that its declared outputs form C34 or C65. It does not
    claim Linux boot, Guest service readiness, or clean-Host installation.
    """

    command_bytes = read_regular_bounded_file(
        execution.compilation_command_path,
        "unknown",
        "command-read",
        MAXIMUM_COMMAND_BYTES,
    )
    command = parse_guest_artifact_compilation_command(command_bytes)
    validate_execution_paths(execution, command)
    validate_input_artifacts(execution.input_root, command)
    validate_builder_identity(execution.builder_executable, command)

    temporary_output_directory = Path(
        tempfile.mkdtemp(
            prefix=f".{execution.output_directory.name}.{command.compilation_id}.",
            dir=execution.output_directory.parent,
        )
    )
    try:
        run_selected_guest_product_bootstrap_artifact_composer(execution, command, temporary_output_directory)
        validate_selected_builder_outputs(command, temporary_output_directory)
        if command.architecture == "arm64":
            manifest_path = temporary_output_directory / "macos-guest-artifact-manifest.json"
            manifest = compose_macos_guest_artifact_manifest(command, temporary_output_directory, manifest_path)
            manifest_key = "macOSGuestArtifactManifest"
        else:
            manifest_path = temporary_output_directory / "native-guest-artifact-manifest.json"
            manifest = compose_native_guest_artifact_manifest(command, temporary_output_directory, manifest_path)
            manifest_key = "nativeGuestArtifactManifest"
        receipt_path = temporary_output_directory / "guest-artifact-compilation-receipt.json"
        compilation_completion_time = (
            record_utc_guest_artifact_compilation_completion_time()
        )
        receipt = compose_guest_artifact_compilation_receipt(
            command,
            command_bytes,
            manifest_path,
            compilation_completion_time,
        )
        write_json_document(receipt_path, receipt, command.compilation_id, "receipt-write")
        temporary_output_directory.replace(execution.output_directory)
    except Exception:
        shutil.rmtree(temporary_output_directory, ignore_errors=True)
        raise

    return {
        "compilationId": command.compilation_id,
        "artifactSetId": command.artifact_set_id,
        "outputDirectory": str(execution.output_directory),
        manifest_key: manifest,
        "guestArtifactCompilationReceipt": receipt,
    }


def parse_guest_artifact_compilation_command(contents: bytes) -> GuestArtifactCompilationCommand:
    """Decode C35 strictly before any external path or process is touched."""

    try:
        document = json.loads(contents.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestArtifactCompilationError("unknown", "command-decode", str(error)) from error
    if not isinstance(document, dict):
        raise GuestArtifactCompilationError("unknown", "command-decode", "C35 command must be a JSON object")
    compilation_id = string_field(document, "compilationId", "unknown", "command-validate")
    try:
        require_exact_object_keys_subset(
            document,
            {
                "schemaVersion",
                "compilationId",
                "artifactSetId",
                "architecture",
                "buildEnvironment",
                "boot",
                "guestRuntimeArtifact",
                "guestTelemetryCollectorArtifact",
                "guestTelemetryCollectorConfigurationArtifact",
                "guestNodeServicesArtifact",
                "guestProductProcessSupervisorArtifact",
                "guestProductProcessDeploymentConfigurationArtifact",
                "guestProductReleaseManagerArtifact",
                "guestProductReleaseManagerConfigurationArtifact",
                "guestProductServiceManagerDeploymentConfigurationArtifact",
                "guestProductBootstrapConfigurationArtifact",
                "guestProductVitalServerTopologyDeploymentArtifact",
                "externalVitalServerDeliveryConfigurationArtifact",
                "guestBundledUpstreamImageSetManagerArtifact",
                "guestBundledUpstreamImageSetManagerConfigurationArtifact",
                "storageDevices",
            },
            {
                "schemaVersion",
                "compilationId",
                "artifactSetId",
                "architecture",
                "buildEnvironment",
                "guestRuntimeArtifact",
                "guestNodeServicesArtifact",
                "guestProductProcessSupervisorArtifact",
                "guestProductProcessDeploymentConfigurationArtifact",
                "guestProductReleaseManagerArtifact",
                "guestProductReleaseManagerConfigurationArtifact",
                "guestProductServiceManagerDeploymentConfigurationArtifact",
                "guestProductBootstrapConfigurationArtifact",
                "guestProductVitalServerTopologyDeploymentArtifact",
                "storageDevices",
            },
            compilation_id,
            "command-validate",
            "C35 command",
        )
        if document["schemaVersion"] != "v1" or document["architecture"] not in {"arm64", "amd64"}:
            raise ValueError("schemaVersion must be v1 and architecture must be arm64 or amd64")
        architecture = document["architecture"]
        artifact_set_id = identifier_field(document, "artifactSetId", compilation_id, "command-validate")
        compilation_id = validate_identifier(compilation_id, compilation_id, "command-validate", "compilationId")
        build_environment = object_field(document, "buildEnvironment", compilation_id, "command-validate")
        require_exact_object_keys(
            build_environment,
            {"id", "builderExecutableSizeBytes", "builderExecutableSHA256"},
            compilation_id,
            "command-validate",
            "buildEnvironment",
        )
        build_environment_id = identifier_field(build_environment, "id", compilation_id, "command-validate")
        builder_size = positive_integer_field(build_environment, "builderExecutableSizeBytes", compilation_id, "command-validate")
        builder_sha256 = sha256_field(build_environment, "builderExecutableSHA256", compilation_id, "command-validate")

        if architecture == "arm64":
            boot = object_field(document, "boot", compilation_id, "command-validate")
            allowed_boot_keys = {"kernel", "initialRamdisk"}
            require_exact_object_keys_subset(boot, allowed_boot_keys, {"kernel"}, compilation_id, "command-validate", "boot")
            kernel = parse_boot_artifact_output(boot["kernel"], compilation_id, "kernel")
            initial_ramdisk = (
                parse_boot_artifact_output(boot["initialRamdisk"], compilation_id, "initialRamdisk")
                if "initialRamdisk" in boot
                else None
            )
        else:
            if "boot" in document:
                raise ValueError("amd64 C35 command must not declare macOS boot outputs")
            kernel = None
            initial_ramdisk = None
        guest_runtime = parse_input_artifact(document["guestRuntimeArtifact"], compilation_id, "guestRuntimeArtifact")
        guest_telemetry_collector = (
            parse_input_artifact(
                document["guestTelemetryCollectorArtifact"],
                compilation_id,
                "guestTelemetryCollectorArtifact",
            )
            if "guestTelemetryCollectorArtifact" in document
            else None
        )
        guest_telemetry_collector_configuration = (
            parse_input_artifact(
                document["guestTelemetryCollectorConfigurationArtifact"],
                compilation_id,
                "guestTelemetryCollectorConfigurationArtifact",
            )
            if "guestTelemetryCollectorConfigurationArtifact" in document
            else None
        )
        guest_node_services = parse_input_artifact(document["guestNodeServicesArtifact"], compilation_id, "guestNodeServicesArtifact")
        guest_product_process_supervisor = parse_input_artifact(document["guestProductProcessSupervisorArtifact"], compilation_id, "guestProductProcessSupervisorArtifact")
        guest_product_process_deployment_configuration = parse_input_artifact(document["guestProductProcessDeploymentConfigurationArtifact"], compilation_id, "guestProductProcessDeploymentConfigurationArtifact")
        guest_product_release_manager = parse_input_artifact(document["guestProductReleaseManagerArtifact"], compilation_id, "guestProductReleaseManagerArtifact")
        guest_product_release_manager_configuration = parse_input_artifact(document["guestProductReleaseManagerConfigurationArtifact"], compilation_id, "guestProductReleaseManagerConfigurationArtifact")
        guest_product_service_manager_deployment_configuration = parse_input_artifact(document["guestProductServiceManagerDeploymentConfigurationArtifact"], compilation_id, "guestProductServiceManagerDeploymentConfigurationArtifact")
        guest_product_bootstrap_configuration = parse_input_artifact(document["guestProductBootstrapConfigurationArtifact"], compilation_id, "guestProductBootstrapConfigurationArtifact")
        guest_product_vitalserver_topology_deployment = parse_input_artifact(document["guestProductVitalServerTopologyDeploymentArtifact"], compilation_id, "guestProductVitalServerTopologyDeploymentArtifact")
        external_vitalserver_delivery_configuration = (
            parse_input_artifact(
                document["externalVitalServerDeliveryConfigurationArtifact"],
                compilation_id,
                "externalVitalServerDeliveryConfigurationArtifact",
            )
            if "externalVitalServerDeliveryConfigurationArtifact" in document
            else None
        )
        guest_bundled_upstream_image_set_manager = (
            parse_input_artifact(
                document["guestBundledUpstreamImageSetManagerArtifact"],
                compilation_id,
                "guestBundledUpstreamImageSetManagerArtifact",
            )
            if "guestBundledUpstreamImageSetManagerArtifact" in document
            else None
        )
        guest_bundled_upstream_image_set_manager_configuration = (
            parse_input_artifact(
                document["guestBundledUpstreamImageSetManagerConfigurationArtifact"],
                compilation_id,
                "guestBundledUpstreamImageSetManagerConfigurationArtifact",
            )
            if "guestBundledUpstreamImageSetManagerConfigurationArtifact" in document
            else None
        )
        raw_storage_devices = document["storageDevices"]
        if not isinstance(raw_storage_devices, list) or not raw_storage_devices:
            raise ValueError("storageDevices must be a non-empty array")
        storage_devices = tuple(
            parse_storage_device_output(value, compilation_id, index)
            for index, value in enumerate(raw_storage_devices)
        )
        command = GuestArtifactCompilationCommand(
            compilation_id=compilation_id,
            artifact_set_id=artifact_set_id,
            architecture=architecture,
            build_environment_id=build_environment_id,
            builder_executable_size_bytes=builder_size,
            builder_executable_sha256=builder_sha256,
            kernel=kernel,
            initial_ramdisk=initial_ramdisk,
            guest_runtime_artifact=guest_runtime,
            guest_telemetry_collector_artifact=guest_telemetry_collector,
            guest_telemetry_collector_configuration_artifact=guest_telemetry_collector_configuration,
            guest_node_services_artifact=guest_node_services,
            guest_product_process_supervisor_artifact=guest_product_process_supervisor,
            guest_product_process_deployment_configuration_artifact=guest_product_process_deployment_configuration,
            guest_product_release_manager_artifact=guest_product_release_manager,
            guest_product_release_manager_configuration_artifact=guest_product_release_manager_configuration,
            guest_product_service_manager_deployment_configuration_artifact=guest_product_service_manager_deployment_configuration,
            guest_product_bootstrap_configuration_artifact=guest_product_bootstrap_configuration,
            guest_product_vitalserver_topology_deployment_artifact=guest_product_vitalserver_topology_deployment,
            external_vitalserver_delivery_configuration_artifact=external_vitalserver_delivery_configuration,
            guest_bundled_upstream_image_set_manager_artifact=guest_bundled_upstream_image_set_manager,
            guest_bundled_upstream_image_set_manager_configuration_artifact=guest_bundled_upstream_image_set_manager_configuration,
            storage_devices=storage_devices,
        )
        validate_command_semantics(command)
        return command
    except (KeyError, TypeError, ValueError) as error:
        raise GuestArtifactCompilationError(compilation_id, "command-validate", str(error)) from error


def parse_boot_artifact_output(value: Any, compilation_id: str, field_name: str) -> BootArtifactOutput:
    if not isinstance(value, dict):
        raise ValueError(f"boot.{field_name} must be an object")
    require_exact_object_keys(value, {"source", "outputRelativePath"}, compilation_id, "command-validate", f"boot.{field_name}")
    return BootArtifactOutput(
        source=parse_input_artifact(value["source"], compilation_id, f"boot.{field_name}.source"),
        output_relative_path=parse_safe_relative_path(value["outputRelativePath"], compilation_id, f"boot.{field_name}.outputRelativePath"),
    )


def parse_storage_device_output(value: Any, compilation_id: str, index: int) -> GuestStorageArtifactOutput:
    if not isinstance(value, dict):
        raise ValueError(f"storageDevices[{index}] must be an object")
    require_exact_object_keys_subset(value, {"id", "role", "storageImageFormat", "guestVolumeFileSystem", "readOnly", "baseImage", "outputRelativePath"}, {"id", "role", "storageImageFormat", "readOnly", "outputRelativePath"}, compilation_id, "command-validate", f"storageDevices[{index}]")
    return GuestStorageArtifactOutput(
        identifier=identifier_field(value, "id", compilation_id, "command-validate"),
        role=string_field(value, "role", compilation_id, "command-validate"),
        storage_image_format=string_field(value, "storageImageFormat", compilation_id, "command-validate"),
        guest_volume_file_system=string_field(value, "guestVolumeFileSystem", compilation_id, "command-validate") if "guestVolumeFileSystem" in value else None,
        read_only=boolean_field(value, "readOnly", compilation_id, "command-validate"),
        base_image=parse_input_artifact(value["baseImage"], compilation_id, f"storageDevices[{index}].baseImage") if "baseImage" in value else None,
        output_relative_path=parse_safe_relative_path(value["outputRelativePath"], compilation_id, f"storageDevices[{index}].outputRelativePath"),
    )


def parse_input_artifact(value: Any, compilation_id: str, field_name: str) -> InputArtifact:
    if not isinstance(value, dict):
        raise ValueError(f"{field_name} must be an object")
    require_exact_object_keys(value, {"id", "inputRelativePath", "sizeBytes", "sha256"}, compilation_id, "command-validate", field_name)
    return InputArtifact(
        identifier=identifier_field(value, "id", compilation_id, "command-validate"),
        input_relative_path=parse_input_relative_path(value["inputRelativePath"], compilation_id, f"{field_name}.inputRelativePath"),
        size_bytes=positive_integer_field(value, "sizeBytes", compilation_id, "command-validate"),
        sha256=sha256_field(value, "sha256", compilation_id, "command-validate"),
    )


def validate_command_semantics(command: GuestArtifactCompilationCommand) -> None:
    if command.architecture == "arm64" and (command.kernel is None or command.kernel.output_relative_path != PurePosixPath("boot/Image")):
        raise ValueError("boot.kernel.outputRelativePath must be boot/Image")
    if command.architecture == "amd64" and (command.kernel is not None or command.initial_ramdisk is not None):
        raise ValueError("amd64 C35 command must not declare macOS boot outputs")
    if command.initial_ramdisk is not None and command.initial_ramdisk.output_relative_path != PurePosixPath("boot/initrd.img"):
        raise ValueError("boot.initialRamdisk.outputRelativePath must be boot/initrd.img")
    artifact_ids = [artifact.identifier for artifact in command.input_artifacts()]
    input_paths = [artifact.input_relative_path for artifact in command.input_artifacts()]
    if len(artifact_ids) != len(set(artifact_ids)):
        raise ValueError("each C35 input artifact ID must be unique")
    if len(input_paths) != len(set(input_paths)):
        raise ValueError("each C35 input relative path must be unique")
    if (
        (command.guest_telemetry_collector_artifact is None)
        != (command.guest_telemetry_collector_configuration_artifact is None)
    ):
        raise ValueError(
            "C35 Guest telemetry Collector binary and configuration artifacts must be declared together"
        )
    if (
        command.guest_telemetry_collector_artifact is not None
        and command.guest_telemetry_collector_artifact.identifier
        != f"guest-telemetry-collector-linux-{command.architecture}"
    ):
        raise ValueError(
            "C35 guestTelemetryCollectorArtifact ID must match C35 architecture"
        )
    if (
        command.guest_telemetry_collector_configuration_artifact is not None
        and command.guest_telemetry_collector_configuration_artifact.identifier
        != "guest-telemetry-collector-configuration"
    ):
        raise ValueError(
            "C35 guestTelemetryCollectorConfigurationArtifact ID must be guest-telemetry-collector-configuration"
        )
    if (
        command.guest_product_release_manager_artifact.identifier
        != f"guest-product-release-manager-linux-{command.architecture}"
    ):
        raise ValueError(
            "C35 guestProductReleaseManagerArtifact ID must match C35 architecture"
        )
    if (
        command.guest_product_release_manager_configuration_artifact.identifier
        != "guest-product-release-manager-configuration"
    ):
        raise ValueError(
            "C35 guestProductReleaseManagerConfigurationArtifact ID must be guest-product-release-manager-configuration"
        )
    if (
        command.external_vitalserver_delivery_configuration_artifact is not None
        and command.external_vitalserver_delivery_configuration_artifact.identifier
        != "external-vitalserver-delivery-configuration"
    ):
        raise ValueError(
            "C35 externalVitalServerDeliveryConfigurationArtifact ID must be external-vitalserver-delivery-configuration"
        )
    if (
        (command.guest_bundled_upstream_image_set_manager_artifact is None)
        != (command.guest_bundled_upstream_image_set_manager_configuration_artifact is None)
    ):
        raise ValueError(
            "C35 Guest Bundled Upstream Image-set Manager binary and configuration artifacts must be declared together"
        )
    if (
        command.guest_bundled_upstream_image_set_manager_artifact is not None
        and command.guest_bundled_upstream_image_set_manager_artifact.identifier
        != f"guest-bundled-upstream-image-set-manager-linux-{command.architecture}"
    ):
        raise ValueError(
            "C35 guestBundledUpstreamImageSetManagerArtifact ID must match C35 architecture"
        )
    if (
        command.guest_bundled_upstream_image_set_manager_configuration_artifact is not None
        and command.guest_bundled_upstream_image_set_manager_configuration_artifact.identifier
        != "guest-bundled-upstream-image-set-manager-configuration"
    ):
        raise ValueError(
            "C35 guestBundledUpstreamImageSetManagerConfigurationArtifact ID must be guest-bundled-upstream-image-set-manager-configuration"
        )
    storage_ids = [storage.identifier for storage in command.storage_devices]
    output_paths = [*(storage.output_relative_path for storage in command.storage_devices)]
    if command.kernel is not None:
        output_paths.append(command.kernel.output_relative_path)
    if command.initial_ramdisk is not None:
        output_paths.append(command.initial_ramdisk.output_relative_path)
    if len(storage_ids) != len(set(storage_ids)):
        raise ValueError("each C35 storage device ID must be unique")
    if len(output_paths) != len(set(output_paths)):
        raise ValueError("each C35 output relative path must be unique")
    storage_by_id = {storage.identifier: storage for storage in command.storage_devices}
    if set(storage_by_id) != {"guest-root", "guest-product-bootstrap"}:
        raise ValueError("C35 requires exactly guest-root and guest-product-bootstrap storage outputs")
    root_storage = storage_by_id["guest-root"]
    if root_storage.role != "guest-root-storage" or root_storage.storage_image_format != "raw" or root_storage.guest_volume_file_system is not None or root_storage.read_only or root_storage.base_image is None or root_storage.output_relative_path != PurePosixPath("storage/guest-root.raw"):
        raise ValueError("C35 guest-root storage output must copy one writable raw base image")
    bootstrap_storage = storage_by_id["guest-product-bootstrap"]
    if bootstrap_storage.role != "guest-product-bootstrap-volume" or bootstrap_storage.storage_image_format != "raw" or bootstrap_storage.guest_volume_file_system != "iso9660" or not bootstrap_storage.read_only or bootstrap_storage.base_image is not None or bootstrap_storage.output_relative_path != PurePosixPath("storage/guest-product-bootstrap.raw"):
        raise ValueError("C35 guest-product-bootstrap storage output must be one generated read-only RAW storage image containing an ISO9660 Guest volume")


def validate_execution_paths(execution: GuestArtifactCompilationExecution, command: GuestArtifactCompilationCommand) -> None:
    if execution.builder_timeout_seconds < 1:
        raise GuestArtifactCompilationError(command.compilation_id, "execution-validate", "builder timeout seconds must be positive")
    for path, role, require_directory in (
        (execution.compilation_command_path, "C35 command path", False),
        (execution.input_root, "input root", True),
        (execution.builder_executable, "builder executable", False),
    ):
        if not path.is_absolute():
            raise GuestArtifactCompilationError(command.compilation_id, "execution-validate", f"{role} must be absolute")
        require_regular_path_without_symlink(path, command.compilation_id, "execution-validate", role, require_directory)
    if not execution.output_directory.is_absolute():
        raise GuestArtifactCompilationError(command.compilation_id, "execution-validate", "output directory must be absolute")
    if execution.output_directory.exists():
        raise GuestArtifactCompilationError(command.compilation_id, "execution-validate", "output directory already exists")
    if not execution.output_directory.parent.is_dir():
        raise GuestArtifactCompilationError(command.compilation_id, "execution-validate", "output directory parent is missing")
    if execution.output_directory.parent.is_symlink():
        raise GuestArtifactCompilationError(command.compilation_id, "execution-validate", "output directory parent must not be a symlink")


def validate_input_artifacts(input_root: Path, command: GuestArtifactCompilationCommand) -> None:
    for artifact in command.input_artifacts():
        source = resolve_input_artifact(input_root, artifact, command.compilation_id)
        actual_size = source.stat().st_size
        actual_sha256 = sha256_file(source)
        if actual_size != artifact.size_bytes:
            raise GuestArtifactCompilationError(command.compilation_id, "input-identity", f"input artifact {artifact.identifier} size does not match C35")
        if actual_sha256 != artifact.sha256:
            raise GuestArtifactCompilationError(command.compilation_id, "input-identity", f"input artifact {artifact.identifier} SHA-256 does not match C35")


def validate_builder_identity(builder_executable: Path, command: GuestArtifactCompilationCommand) -> None:
    if not os.access(builder_executable, os.X_OK):
        raise GuestArtifactCompilationError(command.compilation_id, "builder-identity", "builder executable is not executable")
    if builder_executable.stat().st_size != command.builder_executable_size_bytes:
        raise GuestArtifactCompilationError(command.compilation_id, "builder-identity", "builder executable size does not match C35")
    if sha256_file(builder_executable) != command.builder_executable_sha256:
        raise GuestArtifactCompilationError(command.compilation_id, "builder-identity", "builder executable SHA-256 does not match C35")


def run_selected_guest_product_bootstrap_artifact_composer(
    execution: GuestArtifactCompilationExecution,
    command: GuestArtifactCompilationCommand,
    temporary_output_directory: Path,
) -> None:
    try:
        completed = subprocess.run(
            [
                str(execution.builder_executable),
                "--guest-artifact-compilation-command", str(execution.compilation_command_path),
                "--input-root", str(execution.input_root),
                "--output-directory", str(temporary_output_directory),
            ],
            capture_output=True,
            check=False,
            text=True,
            timeout=execution.builder_timeout_seconds,
        )
    except OSError as error:
        raise GuestArtifactCompilationError(command.compilation_id, "guest-product-bootstrap-artifact-composer", str(error)) from error
    except subprocess.TimeoutExpired as error:
        raise GuestArtifactCompilationError(command.compilation_id, "guest-product-bootstrap-artifact-composer", f"timed out after {execution.builder_timeout_seconds} seconds; stdout={bounded_diagnostic(error.stdout)} stderr={bounded_diagnostic(error.stderr)}") from error
    if completed.returncode != 0:
        raise GuestArtifactCompilationError(command.compilation_id, "guest-product-bootstrap-artifact-composer", f"exit={completed.returncode} stdout={bounded_diagnostic(completed.stdout)} stderr={bounded_diagnostic(completed.stderr)}")


def validate_selected_builder_outputs(command: GuestArtifactCompilationCommand, output_directory: Path) -> None:
    expected_artifacts = {
        *(storage.output_relative_path for storage in command.storage_devices),
    }
    if command.kernel is not None:
        expected_artifacts.add(command.kernel.output_relative_path)
    if command.initial_ramdisk is not None:
        expected_artifacts.add(command.initial_ramdisk.output_relative_path)
    found_artifacts: set[PurePosixPath] = set()
    for path in output_directory.rglob("*"):
        relative_path = PurePosixPath(path.relative_to(output_directory).as_posix())
        if path.is_symlink():
            raise GuestArtifactCompilationError(command.compilation_id, "output-validate", f"builder output must not contain symlink {relative_path}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise GuestArtifactCompilationError(command.compilation_id, "output-validate", f"builder output is not a regular file {relative_path}")
        if relative_path not in expected_artifacts:
            raise GuestArtifactCompilationError(command.compilation_id, "output-validate", f"builder wrote undeclared output {relative_path}")
        if path.stat().st_size < 1:
            raise GuestArtifactCompilationError(command.compilation_id, "output-validate", f"builder output is empty {relative_path}")
        found_artifacts.add(relative_path)
    missing_artifacts = expected_artifacts - found_artifacts
    if missing_artifacts:
        raise GuestArtifactCompilationError(command.compilation_id, "output-validate", "builder omitted declared output " + ", ".join(str(path) for path in sorted(missing_artifacts)))


def compose_macos_guest_artifact_manifest(
    command: GuestArtifactCompilationCommand,
    output_directory: Path,
    manifest_path: Path,
) -> dict[str, object]:
    if command.kernel is None:
        raise GuestArtifactCompilationError(command.compilation_id, "C34-manifest-compose", "arm64 C35 command has no kernel output")
    try:
        return manifest_composer.compose_macos_guest_artifact_manifest(
            manifest_composer.MacOSGuestArtifactManifestComposition(
                artifact_set_id=command.artifact_set_id,
                kernel_source=output_directory / command.kernel.output_relative_path,
                initial_ramdisk_source=(output_directory / command.initial_ramdisk.output_relative_path) if command.initial_ramdisk is not None else None,
                storage_sources=tuple(
                    manifest_composer.MacOSGuestStorageArtifactSource(
                        storage_id=storage.identifier,
                        storage_role=storage.role,
                        storage_image_format=storage.storage_image_format,
                        guest_volume_file_system=storage.guest_volume_file_system,
                        source=output_directory / storage.output_relative_path,
                    )
                    for storage in command.storage_devices
                ),
                output_manifest=manifest_path,
                replace_output=False,
            )
        )
    except manifest_composer.MacOSGuestArtifactManifestCompositionError as error:
        raise GuestArtifactCompilationError(command.compilation_id, "C34-manifest-compose", str(error)) from error


def compose_native_guest_artifact_manifest(
    command: GuestArtifactCompilationCommand,
    output_directory: Path,
    manifest_path: Path,
) -> dict[str, object]:
    try:
        return native_manifest_composer.compose_native_guest_artifact_manifest(
            native_manifest_composer.NativeGuestArtifactManifestComposition(
                artifact_set_id=command.artifact_set_id,
                storage_sources=tuple(
                    native_manifest_composer.NativeGuestStorageArtifactSource(
                        storage_id=storage.identifier,
                        storage_role=storage.role,
                        storage_image_format=storage.storage_image_format,
                        guest_volume_file_system=storage.guest_volume_file_system,
                        source=output_directory / storage.output_relative_path,
                    )
                    for storage in command.storage_devices
                ),
                output_manifest=manifest_path,
            )
        )
    except native_manifest_composer.NativeGuestArtifactManifestCompositionError as error:
        raise GuestArtifactCompilationError(command.compilation_id, "C65-manifest-compose", str(error)) from error


def compose_guest_artifact_compilation_receipt(
    command: GuestArtifactCompilationCommand,
    command_bytes: bytes,
    manifest_path: Path,
    compilation_completion_time: datetime,
) -> dict[str, object]:
    if compilation_completion_time.tzinfo is None:
        raise GuestArtifactCompilationError(command.compilation_id, "receipt-compose", "completed timestamp must include timezone")
    return {
        "schemaVersion": "v1",
        "compilationId": command.compilation_id,
        "artifactSetId": command.artifact_set_id,
        "architecture": command.architecture,
        "compilationCommandSHA256": sha256_bytes(command_bytes),
        "buildEnvironment": {
            "id": command.build_environment_id,
            "builderExecutableSizeBytes": command.builder_executable_size_bytes,
            "builderExecutableSHA256": command.builder_executable_sha256,
        },
        "consumedInputArtifacts": [
            {"id": artifact.identifier, "sizeBytes": artifact.size_bytes, "sha256": artifact.sha256}
            for artifact in command.input_artifacts()
        ],
        **({
            "macOSGuestArtifactManifest": {
                "relativePath": "macos-guest-artifact-manifest.json",
                "sizeBytes": manifest_path.stat().st_size,
                "sha256": sha256_file(manifest_path),
            }
        } if command.architecture == "arm64" else {
            "nativeGuestArtifactManifest": {
                "relativePath": "native-guest-artifact-manifest.json",
                "sizeBytes": manifest_path.stat().st_size,
                "sha256": sha256_file(manifest_path),
            }
        }),
        "completedAt": compilation_completion_time.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }


def record_utc_guest_artifact_compilation_completion_time() -> datetime:
    """Record the compiler-owned time after C35 output validation succeeds."""

    return datetime.now(timezone.utc).replace(microsecond=0)


def resolve_input_artifact(input_root: Path, artifact: InputArtifact, compilation_id: str) -> Path:
    path = input_root.joinpath(*artifact.input_relative_path.parts)
    require_regular_path_without_symlink(path, compilation_id, "input-identity", f"input artifact {artifact.identifier}", False, input_root)
    return path


def require_regular_path_without_symlink(
    path: Path,
    compilation_id: str,
    stage: str,
    role: str,
    require_directory: bool,
    bounded_root: Path | None = None,
) -> None:
    chain: Iterable[Path]
    if bounded_root is not None:
        try:
            relative_parts = path.relative_to(bounded_root).parts
        except ValueError as error:
            raise GuestArtifactCompilationError(compilation_id, stage, f"{role} escapes input root") from error
        chain = (bounded_root, *(bounded_root.joinpath(*relative_parts[:index]) for index in range(1, len(relative_parts) + 1)))
    else:
        chain = (path,)
    for checked_path in chain:
        try:
            status = checked_path.lstat()
        except OSError as error:
            raise GuestArtifactCompilationError(compilation_id, stage, f"{role} is missing: {error}") from error
        if checked_path.is_symlink():
            raise GuestArtifactCompilationError(compilation_id, stage, f"{role} must not be a symlink")
        if checked_path != path and not checked_path.is_dir():
            raise GuestArtifactCompilationError(compilation_id, stage, f"{role} has a non-directory path component")
        del status
    if require_directory and not path.is_dir():
        raise GuestArtifactCompilationError(compilation_id, stage, f"{role} must be a directory")
    if not require_directory and not path.is_file():
        raise GuestArtifactCompilationError(compilation_id, stage, f"{role} must be a regular file")


def read_regular_bounded_file(path: Path, compilation_id: str, stage: str, maximum_bytes: int) -> bytes:
    if not path.is_absolute():
        raise GuestArtifactCompilationError(compilation_id, stage, "C35 command path must be absolute")
    require_regular_path_without_symlink(path, compilation_id, stage, "C35 command", False)
    try:
        with path.open("rb") as source:
            contents = source.read(maximum_bytes + 1)
    except OSError as error:
        raise GuestArtifactCompilationError(compilation_id, stage, f"could not read C35 command: {error}") from error
    if len(contents) > maximum_bytes:
        raise GuestArtifactCompilationError(compilation_id, stage, "C35 command exceeds maximum document size")
    return contents


def write_json_document(path: Path, document: Mapping[str, object], compilation_id: str, stage: str) -> None:
    try:
        path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except OSError as error:
        raise GuestArtifactCompilationError(compilation_id, stage, f"could not write output document: {error}") from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def bounded_diagnostic(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    return value[-MAXIMUM_BUILDER_DIAGNOSTIC_BYTES:].strip()


def string_field(document: Mapping[str, Any], name: str, compilation_id: str, stage: str) -> str:
    value = document.get(name)
    if not isinstance(value, str) or not value:
        raise GuestArtifactCompilationError(compilation_id, stage, f"{name} must be a non-empty string")
    return value


def boolean_field(document: Mapping[str, Any], name: str, compilation_id: str, stage: str) -> bool:
    value = document.get(name)
    if not isinstance(value, bool):
        raise GuestArtifactCompilationError(compilation_id, stage, f"{name} must be a boolean")
    return value


def identifier_field(document: Mapping[str, Any], name: str, compilation_id: str, stage: str) -> str:
    return validate_identifier(string_field(document, name, compilation_id, stage), compilation_id, stage, name)


def validate_identifier(value: str, compilation_id: str, stage: str, field_name: str) -> str:
    if not IDENTIFIER_PATTERN.fullmatch(value):
        raise GuestArtifactCompilationError(compilation_id, stage, f"{field_name} must be a contract identifier")
    return value


def positive_integer_field(document: Mapping[str, Any], name: str, compilation_id: str, stage: str) -> int:
    value = document.get(name)
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise GuestArtifactCompilationError(compilation_id, stage, f"{name} must be a positive integer")
    return value


def sha256_field(document: Mapping[str, Any], name: str, compilation_id: str, stage: str) -> str:
    value = string_field(document, name, compilation_id, stage)
    if not SHA256_PATTERN.fullmatch(value):
        raise GuestArtifactCompilationError(compilation_id, stage, f"{name} must be a lower-case SHA-256")
    return value


def object_field(document: Mapping[str, Any], name: str, compilation_id: str, stage: str) -> Mapping[str, Any]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise GuestArtifactCompilationError(compilation_id, stage, f"{name} must be an object")
    return value


def parse_input_relative_path(value: Any, compilation_id: str, field_name: str) -> PurePosixPath:
    path = parse_safe_relative_path(value, compilation_id, field_name)
    if not path.parts or path.parts[0] != "inputs":
        raise GuestArtifactCompilationError(compilation_id, "command-validate", f"{field_name} must stay below inputs")
    return path


def parse_safe_relative_path(value: Any, compilation_id: str, field_name: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or len(value) > 1024 or "\\" in value:
        raise GuestArtifactCompilationError(compilation_id, "command-validate", f"{field_name} must be a bounded POSIX relative path")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") or not PATH_COMPONENT_PATTERN.fullmatch(part) for part in path.parts):
        raise GuestArtifactCompilationError(compilation_id, "command-validate", f"{field_name} must not contain traversal")
    return path


def require_exact_object_keys(
    document: Mapping[str, Any],
    expected_keys: set[str],
    compilation_id: str,
    stage: str,
    name: str,
) -> None:
    if set(document) != expected_keys:
        raise ValueError(f"{name} must contain exactly {', '.join(sorted(expected_keys))}")


def require_exact_object_keys_subset(
    document: Mapping[str, Any],
    allowed_keys: set[str],
    required_keys: set[str],
    compilation_id: str,
    stage: str,
    name: str,
) -> None:
    if not required_keys.issubset(document) or not set(document).issubset(allowed_keys):
        raise ValueError(f"{name} has missing or unknown fields")


def parse_arguments(arguments: Sequence[str]) -> GuestArtifactCompilationExecution:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compilation-command", required=True, help="required absolute C35 GuestArtifactCompilationCommand path")
    parser.add_argument("--input-root", required=True, help="required absolute root containing only C35 inputRelativePath sources")
    parser.add_argument("--builder-executable", required=True, help="required absolute selected Guest Product bootstrap artifact composer executable")
    parser.add_argument("--output-directory", required=True, help="required absent absolute output directory to atomically publish")
    parser.add_argument("--builder-timeout-seconds", required=True, type=int, help="required positive selected-builder timeout")
    parsed = parser.parse_args(arguments)
    return GuestArtifactCompilationExecution(
        compilation_command_path=Path(parsed.compilation_command),
        input_root=Path(parsed.input_root),
        builder_executable=Path(parsed.builder_executable),
        output_directory=Path(parsed.output_directory),
        builder_timeout_seconds=parsed.builder_timeout_seconds,
    )


def main(arguments: Sequence[str]) -> int:
    try:
        result = compile_guest_artifact_set(parse_arguments(arguments))
    except GuestArtifactCompilationError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
