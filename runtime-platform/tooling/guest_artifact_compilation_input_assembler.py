"""Assemble one explicit C41 declaration into an immutable C35 input root.

This release-build adapter owns only source copying, immutable identity capture,
and C35/C41 receipt publication. It never compiles a Guest, chooses a base,
selects a builder/editor, or writes an output image. Those decisions already
belong to the C41 declaration and the later C35 selected builder.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tempfile
from typing import Any, Mapping, Sequence

from tooling import guest_artifact_compiler
from tooling.contracts import ContractRepository, ContractToolError


MAXIMUM_DECLARATION_BYTES = 1 << 20
ASSEMBLED_C35_RELATIVE_PATH = PurePosixPath("guest-artifact-compilation-command.json")
ASSEMBLED_C41_RECEIPT_RELATIVE_PATH = PurePosixPath(
    "guest-artifact-compilation-input-assembly-receipt.json"
)


class GuestArtifactCompilationInputAssemblyError(RuntimeError):
    """A C41 input assembly cannot publish a complete immutable C35 root."""

    def __init__(self, assembly_id: str, stage: str, reason: str) -> None:
        super().__init__(
            "Guest artifact compilation input assembly failed "
            f"assemblyId={assembly_id or 'unknown'} stage={stage} reason={reason}"
        )
        self.assembly_id = assembly_id
        self.stage = stage
        self.reason = reason


@dataclass(frozen=True)
class GuestArtifactCompilationInputAssemblyExecution:
    """Complete caller-owned paths for one C41 input-assembly effect.

    The assembler records receipt completion time only after its copy and C35
    command effects succeed. A caller may choose the source and destination,
    but cannot claim when this assembler completed them.
    """

    assembly_declaration_path: Path
    assembled_input_root: Path


@dataclass(frozen=True)
class DeclaredGuestArtifactCompilationSource:
    """One explicit C41 source and its destination under the new input root."""

    identifier: str
    source_absolute_path: Path
    input_relative_path: PurePosixPath


@dataclass(frozen=True)
class DeclaredGuestProductBootstrapArtifactComposerSource:
    """The selected C35 bootstrap-artifact composer, outside C35 payload input."""

    identifier: str
    source_absolute_path: Path
    builder_relative_path: PurePosixPath


def assemble_guest_artifact_compilation_input(
    execution: GuestArtifactCompilationInputAssemblyExecution,
) -> Mapping[str, Any]:
    """Atomically publish C35 sources, C35 command, and C41 assembly evidence."""

    declaration_bytes, declaration = load_guest_artifact_compilation_input_assembly_declaration(
        execution.assembly_declaration_path
    )
    assembly_id = require_assembly_string(declaration, "assemblyId", "C41")
    validate_assembly_execution(execution, assembly_id)
    builder_source = parse_declared_guest_product_bootstrap_artifact_composer_source(
        require_assembly_object(
            declaration.get("guestProductBootstrapArtifactComposer"),
            "C41 guestProductBootstrapArtifactComposer",
        ),
        assembly_id,
    )
    input_sources, boot, storage_devices = parse_declared_guest_artifact_compilation_input_sources(
        declaration, assembly_id
    )
    validate_declared_source_set(builder_source, input_sources, assembly_id)
    validate_declared_source_files(builder_source, input_sources, assembly_id)

    temporary_root = Path(
        tempfile.mkdtemp(
            prefix=f".{execution.assembled_input_root.name}.{assembly_id}.",
            dir=execution.assembled_input_root.parent,
        )
    )
    try:
        assembled_builder = copy_declared_builder_source(builder_source, temporary_root, assembly_id)
        assembled_artifacts = [
            copy_declared_input_source(source, temporary_root, assembly_id)
            for source in input_sources
        ]
        command_document = compose_guest_artifact_compilation_command(
            declaration, builder_source, assembled_builder, assembled_artifacts, boot, storage_devices, assembly_id
        )
        command_path = temporary_root / ASSEMBLED_C35_RELATIVE_PATH
        command_bytes = write_new_json_document(command_path, command_document, assembly_id, "C35-command-write")
        validate_assembled_c35_command(command_bytes, assembly_id)
        input_assembly_completion_time = record_utc_input_assembly_completion_time()
        receipt_document = compose_guest_artifact_compilation_input_assembly_receipt(
            declaration,
            declaration_bytes,
            command_path,
            assembled_builder,
            assembled_artifacts,
            input_assembly_completion_time,
        )
        validate_c41_receipt_document(receipt_document, assembly_id)
        receipt_path = temporary_root / ASSEMBLED_C41_RECEIPT_RELATIVE_PATH
        write_new_json_document(receipt_path, receipt_document, assembly_id, "C41-receipt-write")
        temporary_root.replace(execution.assembled_input_root)
    except Exception:
        shutil.rmtree(temporary_root, ignore_errors=True)
        raise

    return {
        "assemblyId": assembly_id,
        "compilationId": declaration["compilationId"],
        "artifactSetId": declaration["artifactSetId"],
        "assembledInputRoot": str(execution.assembled_input_root),
        "guestArtifactCompilationCommand": receipt_document[
            "guestArtifactCompilationCommand"
        ],
        "guestArtifactCompilationInputAssemblyReceipt": receipt_document,
    }


def load_guest_artifact_compilation_input_assembly_declaration(
    declaration_path: Path,
) -> tuple[bytes, Mapping[str, Any]]:
    """Read one C41 declaration without treating unreadable input as empty."""

    if not declaration_path.is_absolute():
        raise GuestArtifactCompilationInputAssemblyError(
            "unknown", "declaration-read", "C41 declaration path must be absolute"
        )
    require_regular_non_symlink_file(declaration_path, "C41 declaration", "unknown", "declaration-read")
    try:
        contents = declaration_path.read_bytes()
    except OSError as error:
        raise GuestArtifactCompilationInputAssemblyError(
            "unknown", "declaration-read", str(error)
        ) from error
    if len(contents) > MAXIMUM_DECLARATION_BYTES:
        raise GuestArtifactCompilationInputAssemblyError(
            "unknown", "declaration-read", "C41 declaration exceeds maximum size"
        )
    try:
        document = json.loads(contents.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestArtifactCompilationInputAssemblyError(
            "unknown", "declaration-decode", str(error)
        ) from error
    if not isinstance(document, dict):
        raise GuestArtifactCompilationInputAssemblyError(
            "unknown", "declaration-decode", "C41 declaration must be a JSON object"
        )
    assembly_id = require_assembly_string(document, "assemblyId", "C41")
    validate_c41_declaration_document(document, assembly_id)
    return contents, document


def validate_c41_declaration_document(
    document: Mapping[str, Any], assembly_id: str
) -> None:
    """Use the declared C41 schema before inspecting any source path."""

    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        errors = repository.validate_instance(
            "guest-artifact-compilation-input-assembly-declaration.schema.json", document
        )
    except ContractToolError as error:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-contract-validate", str(error)
        ) from error
    if errors:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-contract-validate", "; ".join(errors)
        )


def validate_assembly_execution(
    execution: GuestArtifactCompilationInputAssemblyExecution, assembly_id: str
) -> None:
    if not execution.assembled_input_root.is_absolute():
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "execution-validate", "assembled input root must be absolute"
        )
    if execution.assembled_input_root.exists() or execution.assembled_input_root.is_symlink():
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "execution-validate", "assembled input root already exists"
        )
    parent = execution.assembled_input_root.parent
    if not parent.is_dir() or parent.is_symlink():
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id,
            "execution-validate",
            "assembled input root parent must be an existing non-symlink directory",
        )


def record_utc_input_assembly_completion_time() -> datetime:
    """Record the assembler-owned time after all C41 assembly work succeeded."""

    return datetime.now(timezone.utc).replace(microsecond=0)


def parse_declared_guest_product_bootstrap_artifact_composer_source(
    source: Mapping[str, Any], assembly_id: str
) -> DeclaredGuestProductBootstrapArtifactComposerSource:
    return DeclaredGuestProductBootstrapArtifactComposerSource(
        identifier=require_assembly_string(
            source, "id", "C41 guestProductBootstrapArtifactComposer"
        ),
        source_absolute_path=require_declared_absolute_source_path(
            source,
            "sourceAbsolutePath",
            "C41 guestProductBootstrapArtifactComposer",
            assembly_id,
        ),
        builder_relative_path=require_builder_relative_path(
            source,
            "inputRelativePath",
            "C41 guestProductBootstrapArtifactComposer",
            assembly_id,
        ),
    )


def parse_declared_guest_artifact_compilation_input_sources(
    declaration: Mapping[str, Any], assembly_id: str
) -> tuple[list[DeclaredGuestArtifactCompilationSource], Mapping[str, Any] | None, list[Mapping[str, Any]]]:
    architecture = require_assembly_string(declaration, "architecture", "C41")
    if architecture not in {"arm64", "amd64"}:
        raise GuestArtifactCompilationInputAssemblyError(assembly_id, "C41-semantics", "C41 architecture is invalid")
    boot = require_assembly_object(declaration.get("boot"), "C41 boot") if architecture == "arm64" else None
    if architecture == "amd64" and "boot" in declaration:
        raise GuestArtifactCompilationInputAssemblyError(assembly_id, "C41-semantics", "amd64 C41 must not declare macOS boot outputs")
    input_sources = [
        parse_declared_input_source(declaration.get("guestRuntimeArtifact"), "C41 guestRuntimeArtifact", assembly_id),
        *(
            [parse_declared_input_source(declaration.get("guestTelemetryCollectorArtifact"), "C41 guestTelemetryCollectorArtifact", assembly_id)]
            if "guestTelemetryCollectorArtifact" in declaration
            else []
        ),
        *(
            [parse_declared_input_source(declaration.get("guestTelemetryCollectorConfigurationArtifact"), "C41 guestTelemetryCollectorConfigurationArtifact", assembly_id)]
            if "guestTelemetryCollectorConfigurationArtifact" in declaration
            else []
        ),
        parse_declared_input_source(declaration.get("guestNodeServicesArtifact"), "C41 guestNodeServicesArtifact", assembly_id),
        parse_declared_input_source(declaration.get("guestProductProcessSupervisorArtifact"), "C41 guestProductProcessSupervisorArtifact", assembly_id),
        parse_declared_input_source(declaration.get("guestProductProcessDeploymentConfigurationArtifact"), "C41 guestProductProcessDeploymentConfigurationArtifact", assembly_id),
        parse_declared_input_source(
            declaration.get("guestProductReleaseManagerArtifact"),
            "C41 guestProductReleaseManagerArtifact",
            assembly_id,
        ),
        parse_declared_input_source(
            declaration.get("guestProductReleaseManagerConfigurationArtifact"),
            "C41 guestProductReleaseManagerConfigurationArtifact",
            assembly_id,
        ),
        parse_declared_input_source(declaration.get("guestProductServiceManagerDeploymentConfigurationArtifact"), "C41 guestProductServiceManagerDeploymentConfigurationArtifact", assembly_id),
        parse_declared_input_source(
            declaration.get("guestProductBootstrapConfigurationArtifact"),
            "C41 guestProductBootstrapConfigurationArtifact",
            assembly_id,
        ),
        parse_declared_input_source(
            declaration.get("guestProductVitalServerTopologyDeploymentArtifact"),
            "C41 guestProductVitalServerTopologyDeploymentArtifact",
            assembly_id,
        ),
    ]
    if boot is not None:
        input_sources.insert(
            0,
            parse_declared_input_source(
                require_assembly_object(boot.get("kernel"), "C41 boot.kernel").get("source"),
                "C41 boot.kernel.source",
                assembly_id,
            ),
        )
    if "externalVitalServerDeliveryConfigurationArtifact" in declaration:
        input_sources.append(
            parse_declared_input_source(
                declaration.get("externalVitalServerDeliveryConfigurationArtifact"),
                "C41 externalVitalServerDeliveryConfigurationArtifact",
                assembly_id,
            )
        )
    bundled_manager_keys = (
        ("guestBundledUpstreamImageSetManagerArtifact", "C41 guestBundledUpstreamImageSetManagerArtifact"),
        ("guestBundledUpstreamImageSetManagerConfigurationArtifact", "C41 guestBundledUpstreamImageSetManagerConfigurationArtifact"),
    )
    declared_bundled_manager_keys = [key for key, _ in bundled_manager_keys if key in declaration]
    if declared_bundled_manager_keys and len(declared_bundled_manager_keys) != len(bundled_manager_keys):
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id,
            "C41-semantics",
            "C41 Guest Bundled Upstream Image-set Manager binary and configuration artifacts must be declared together",
        )
    for key, role in bundled_manager_keys:
        if key in declaration:
            input_sources.append(parse_declared_input_source(declaration.get(key), role, assembly_id))
    initial_ramdisk = boot.get("initialRamdisk") if boot is not None else None
    if initial_ramdisk is not None:
        input_sources.append(
            parse_declared_input_source(
                require_assembly_object(initial_ramdisk.get("source"), "C41 boot.initialRamdisk.source"),
                "C41 boot.initialRamdisk.source",
                assembly_id,
            )
        )
    raw_storage_devices = declaration.get("storageDevices")
    if not isinstance(raw_storage_devices, list) or not raw_storage_devices:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-semantics", "C41 requires storageDevices"
        )
    storage_devices: list[Mapping[str, Any]] = []
    for index, storage_device in enumerate(raw_storage_devices):
        storage = require_assembly_object(storage_device, f"C41 storageDevices[{index}]")
        if "baseImage" in storage:
            input_sources.append(
                parse_declared_input_source(
                    storage.get("baseImage"),
                    f"C41 storageDevices[{index}].baseImage",
                    assembly_id,
                )
            )
        storage_devices.append(storage)
    return input_sources, boot, storage_devices


def parse_declared_input_source(
    source: Any, role: str, assembly_id: str
) -> DeclaredGuestArtifactCompilationSource:
    source_object = require_assembly_object(source, role)
    return DeclaredGuestArtifactCompilationSource(
        identifier=require_assembly_string(source_object, "id", role),
        source_absolute_path=require_declared_absolute_source_path(
            source_object, "sourceAbsolutePath", role, assembly_id
        ),
        input_relative_path=require_input_relative_path(
            source_object, "inputRelativePath", role, assembly_id
        ),
    )


def validate_declared_source_set(
    builder: DeclaredGuestProductBootstrapArtifactComposerSource,
    input_sources: Sequence[DeclaredGuestArtifactCompilationSource],
    assembly_id: str,
) -> None:
    identifiers = [builder.identifier, *(source.identifier for source in input_sources)]
    destinations = [builder.builder_relative_path.as_posix(), *(source.input_relative_path.as_posix() for source in input_sources)]
    if len(identifiers) != len(set(identifiers)):
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-semantics", "C41 source IDs must be unique"
        )
    if len(destinations) != len(set(destinations)):
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-semantics", "C41 input-relative paths must be unique"
        )


def validate_declared_source_files(
    builder: DeclaredGuestProductBootstrapArtifactComposerSource,
    input_sources: Sequence[DeclaredGuestArtifactCompilationSource],
    assembly_id: str,
) -> None:
    require_regular_non_symlink_file(
        builder.source_absolute_path,
        "C41 GuestProductBootstrapArtifactComposer source",
        assembly_id,
        "source-validate",
    )
    if not os.access(builder.source_absolute_path, os.X_OK):
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id,
            "source-validate",
            "C41 GuestProductBootstrapArtifactComposer source is not executable",
        )
    for source in input_sources:
        require_regular_non_symlink_file(
            source.source_absolute_path,
            "C41 input source " + source.identifier,
            assembly_id,
            "source-validate",
        )


def copy_declared_builder_source(
    builder: DeclaredGuestProductBootstrapArtifactComposerSource,
    temporary_root: Path,
    assembly_id: str,
) -> Mapping[str, Any]:
    destination = temporary_root.joinpath(*builder.builder_relative_path.parts)
    copy_declared_source_file(builder.source_absolute_path, destination, assembly_id, builder.identifier)
    return file_identity(destination, builder.builder_relative_path.as_posix())


def copy_declared_input_source(
    source: DeclaredGuestArtifactCompilationSource,
    temporary_root: Path,
    assembly_id: str,
) -> Mapping[str, Any]:
    destination = temporary_root.joinpath(*source.input_relative_path.parts)
    copy_declared_source_file(source.source_absolute_path, destination, assembly_id, source.identifier)
    identity = file_identity(destination, source.input_relative_path.as_posix())
    return {"id": source.identifier, "inputRelativePath": identity["relativePath"], "sizeBytes": identity["sizeBytes"], "sha256": identity["sha256"]}


def copy_declared_source_file(source: Path, destination: Path, assembly_id: str, source_id: str) -> None:
    if destination.exists() or destination.is_symlink():
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "source-copy", "assembled destination already exists for " + source_id
        )
    try:
        destination.parent.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        # Existing parents are expected only when a prior declared source owns
        # the same directory. Files remain O_EXCL below and source paths remain
        # unique, so this does not permit a destination collision.
        if not destination.parent.is_dir() or destination.parent.is_symlink():
            raise GuestArtifactCompilationInputAssemblyError(
                assembly_id, "source-copy", "assembled source parent is unavailable for " + source_id
            )
    except OSError as error:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "source-copy", "cannot create destination parent for " + source_id + ": " + str(error)
        ) from error
    try:
        contents = source.read_bytes()
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as target:
            target.write(contents)
            target.flush()
            os.fsync(target.fileno())
        os.chmod(destination, source.stat().st_mode & 0o777)
    except OSError as error:
        destination.unlink(missing_ok=True)
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "source-copy", "cannot copy declared source " + source_id + ": " + str(error)
        ) from error


def compose_guest_artifact_compilation_command(
    declaration: Mapping[str, Any],
    builder_source: DeclaredGuestProductBootstrapArtifactComposerSource,
    assembled_builder: Mapping[str, Any],
    assembled_artifacts: Sequence[Mapping[str, Any]],
    boot: Mapping[str, Any] | None,
    storage_devices: Sequence[Mapping[str, Any]],
    assembly_id: str,
) -> Mapping[str, Any]:
    artifacts_by_id = {artifact["id"]: artifact for artifact in assembled_artifacts}
    if len(artifacts_by_id) != len(assembled_artifacts):
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C35-compose", "assembled artifact IDs are not unique"
        )
    def artifact(identifier: str) -> Mapping[str, Any]:
        try:
            return artifacts_by_id[identifier]
        except KeyError as error:
            raise GuestArtifactCompilationInputAssemblyError(
                assembly_id, "C35-compose", "C41 source was not assembled: " + identifier
            ) from error
    def boot_output(role: str) -> Mapping[str, Any]:
        if boot is None:
            raise GuestArtifactCompilationInputAssemblyError(assembly_id, "C35-compose", "amd64 C41 has no macOS boot output")
        output = require_assembly_object(boot[role], "C41 boot." + role)
        source = require_assembly_object(output.get("source"), "C41 boot." + role + ".source")
        return {"source": artifact(require_assembly_string(source, "id", "C41 boot." + role + ".source")), "outputRelativePath": require_assembly_string(output, "outputRelativePath", "C41 boot." + role)}
    architecture = require_assembly_string(declaration, "architecture", "C41")
    command: dict[str, Any] = {
        "schemaVersion": "v1",
        "compilationId": declaration["compilationId"],
        "artifactSetId": declaration["artifactSetId"],
        "architecture": declaration["architecture"],
        "buildEnvironment": {"id": builder_source.identifier, "builderExecutableSizeBytes": assembled_builder["sizeBytes"], "builderExecutableSHA256": assembled_builder["sha256"]},
        "guestRuntimeArtifact": artifact("guest-runtime-linux-" + architecture),
        "guestNodeServicesArtifact": artifact("guest-node-services-linux-" + architecture),
        "guestProductProcessSupervisorArtifact": artifact("guest-product-process-supervisor-linux-" + architecture),
        "guestProductProcessDeploymentConfigurationArtifact": artifact("guest-product-process-deployment-configuration"),
        "guestProductReleaseManagerArtifact": artifact("guest-product-release-manager-linux-" + architecture),
        "guestProductReleaseManagerConfigurationArtifact": artifact("guest-product-release-manager-configuration"),
        "guestProductServiceManagerDeploymentConfigurationArtifact": artifact("guest-product-service-manager-deployment-configuration"),
        "guestProductBootstrapConfigurationArtifact": artifact("guest-product-bootstrap-configuration"),
        "guestProductVitalServerTopologyDeploymentArtifact": artifact("guest-product-vitalserver-topology-deployment"),
        "storageDevices": [],
    }
    if boot is not None:
        command["boot"] = {"kernel": boot_output("kernel")}
    telemetry_artifact_keys = (
        ("guestTelemetryCollectorArtifact", "guest-telemetry-collector-linux-" + architecture),
        ("guestTelemetryCollectorConfigurationArtifact", "guest-telemetry-collector-configuration"),
    )
    declared_telemetry_artifact_keys = [key for key, _ in telemetry_artifact_keys if key in declaration]
    if declared_telemetry_artifact_keys and len(declared_telemetry_artifact_keys) != len(telemetry_artifact_keys):
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id,
            "C35-compose",
            "C41 telemetry Collector binary and configuration artifacts must be declared together",
        )
    for key, identifier in telemetry_artifact_keys:
        if key in declaration:
            command[key] = artifact(identifier)
    if "externalVitalServerDeliveryConfigurationArtifact" in declaration:
        command["externalVitalServerDeliveryConfigurationArtifact"] = artifact(
            "external-vitalserver-delivery-configuration"
        )
    bundled_manager_artifact_keys = (
        ("guestBundledUpstreamImageSetManagerArtifact", "guest-bundled-upstream-image-set-manager-linux-" + architecture),
        ("guestBundledUpstreamImageSetManagerConfigurationArtifact", "guest-bundled-upstream-image-set-manager-configuration"),
    )
    declared_bundled_manager_artifact_keys = [key for key, _ in bundled_manager_artifact_keys if key in declaration]
    if declared_bundled_manager_artifact_keys and len(declared_bundled_manager_artifact_keys) != len(bundled_manager_artifact_keys):
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id,
            "C35-compose",
            "C41 Guest Bundled Upstream Image-set Manager binary and configuration artifacts must be declared together",
        )
    for key, identifier in bundled_manager_artifact_keys:
        if key in declaration:
            command[key] = artifact(identifier)
    if boot is not None and "initialRamdisk" in boot:
        command["boot"]["initialRamdisk"] = boot_output("initialRamdisk")
    for index, storage_device in enumerate(storage_devices):
        storage_id = require_assembly_string(storage_device, "id", f"C41 storageDevices[{index}]")
        output = {
            "id": storage_id,
            "role": require_assembly_string(storage_device, "role", f"C41 storageDevices[{index}]"),
            "storageImageFormat": require_assembly_string(storage_device, "storageImageFormat", f"C41 storageDevices[{index}]"),
            "readOnly": storage_device.get("readOnly"),
            "outputRelativePath": require_assembly_string(storage_device, "outputRelativePath", f"C41 storageDevices[{index}]"),
        }
        if "guestVolumeFileSystem" in storage_device:
            output["guestVolumeFileSystem"] = require_assembly_string(storage_device, "guestVolumeFileSystem", f"C41 storageDevices[{index}]")
        if "baseImage" in storage_device:
            base_image = require_assembly_object(
                storage_device.get("baseImage"), f"C41 storageDevices[{index}].baseImage"
            )
            output["baseImage"] = artifact(
                require_assembly_string(
                    base_image, "id", f"C41 storageDevices[{index}].baseImage"
                )
            )
        command["storageDevices"].append(output)
    return command


def validate_assembled_c35_command(command_bytes: bytes, assembly_id: str) -> None:
    try:
        guest_artifact_compiler.parse_guest_artifact_compilation_command(command_bytes)
    except guest_artifact_compiler.GuestArtifactCompilationError as error:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C35-contract-validate", str(error)
        ) from error


def compose_guest_artifact_compilation_input_assembly_receipt(
    declaration: Mapping[str, Any],
    declaration_bytes: bytes,
    command_path: Path,
    builder_identity: Mapping[str, Any],
    input_artifact_identities: Sequence[Mapping[str, Any]],
    input_assembly_completion_time: datetime,
) -> Mapping[str, Any]:
    return {
        "schemaVersion": "v1",
        "assemblyId": declaration["assemblyId"],
        "compilationId": declaration["compilationId"],
        "artifactSetId": declaration["artifactSetId"],
        "assemblyDeclarationSHA256": sha256_bytes(declaration_bytes),
        "guestArtifactCompilationCommand": file_identity(
            command_path, ASSEMBLED_C35_RELATIVE_PATH.as_posix()
        ),
        "guestProductBootstrapArtifactComposer": builder_identity,
        "assembledInputArtifacts": list(input_artifact_identities),
        "completedAt": input_assembly_completion_time.isoformat().replace("+00:00", "Z"),
    }


def validate_c41_receipt_document(receipt: Mapping[str, Any], assembly_id: str) -> None:
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        errors = repository.validate_instance(
            "guest-artifact-compilation-input-assembly-receipt.schema.json", receipt
        )
    except ContractToolError as error:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-receipt-validate", str(error)
        ) from error
    if errors:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-receipt-validate", "; ".join(errors)
        )


def require_regular_non_symlink_file(path: Path, role: str, assembly_id: str, stage: str) -> None:
    try:
        status = path.lstat()
    except OSError as error:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, stage, role + " is missing: " + str(error)
        ) from error
    if path.is_symlink() or not path.is_file():
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, stage, role + " must be a regular non-symlink file"
        )
    del status


def require_declared_absolute_source_path(
    document: Mapping[str, Any], field_name: str, role: str, assembly_id: str
) -> Path:
    value = require_assembly_string(document, field_name, role)
    path = Path(value)
    if not path.is_absolute():
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-semantics", role + " sourceAbsolutePath must be absolute"
        )
    return path


def require_input_relative_path(
    document: Mapping[str, Any], field_name: str, role: str, assembly_id: str
) -> PurePosixPath:
    value = require_assembly_string(document, field_name, role)
    if not value.startswith("inputs/") or value != str(PurePosixPath(value)) or ".." in PurePosixPath(value).parts:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-semantics", role + " inputRelativePath is invalid"
        )
    return PurePosixPath(value)


def require_builder_relative_path(
    document: Mapping[str, Any], field_name: str, role: str, assembly_id: str
) -> PurePosixPath:
    value = require_assembly_string(document, field_name, role)
    if not value.startswith("builders/") or value != str(PurePosixPath(value)) or ".." in PurePosixPath(value).parts:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, "C41-semantics", role + " inputRelativePath is invalid"
        )
    return PurePosixPath(value)


def require_assembly_object(value: Any, role: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise GuestArtifactCompilationInputAssemblyError(
            "unknown", "C41-semantics", role + " must be an object"
        )
    return value


def require_assembly_string(document: Mapping[str, Any], field_name: str, role: str) -> str:
    value = document.get(field_name)
    if not isinstance(value, str) or not value:
        raise GuestArtifactCompilationInputAssemblyError(
            "unknown", "C41-semantics", role + " requires non-empty " + field_name
        )
    return value


def write_new_json_document(
    path: Path, document: Mapping[str, Any], assembly_id: str, stage: str
) -> bytes:
    try:
        contents = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        return contents
    except OSError as error:
        raise GuestArtifactCompilationInputAssemblyError(
            assembly_id, stage, str(error)
        ) from error


def file_identity(path: Path, relative_path: str) -> Mapping[str, Any]:
    contents = path.read_bytes()
    return {
        "relativePath": relative_path,
        "sizeBytes": len(contents),
        "sha256": sha256_bytes(contents),
    }


def sha256_bytes(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembly-declaration", required=True)
    parser.add_argument("--assembled-input-root", required=True)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        result = assemble_guest_artifact_compilation_input(
            GuestArtifactCompilationInputAssemblyExecution(
                assembly_declaration_path=Path(parsed.assembly_declaration),
                assembled_input_root=Path(parsed.assembled_input_root),
            )
        )
    except (GuestArtifactCompilationInputAssemblyError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
