"""Assemble and verify one explicit macOS product-release PKG.

`MacOSReleasePackageAssemblyWorkflow` is a release-build application boundary.
It coordinates C41 input assembly, C35 Guest artifact compilation, macOS PKG
composition, and uninstalled-PKG verification.  Each underlying adapter keeps
ownership of its own effects; this workflow supplies their already-declared
inputs and preserves the resulting provenance chain.

The workflow never selects a Linux source, service binary, topology, endpoint,
signing identity, product version, or output directory.  The caller supplies
all of those through C41 and `MacOSHostPackageComposition`.  A successful
return is package build evidence only.  It is not Guest boot, installer,
service-registration, update, or C24 clean-host proof.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
from typing import Any, Mapping

from tooling import guest_artifact_compilation_input_assembler
from tooling import guest_artifact_compiler
from tooling import macos_host_package_composer
from tooling import macos_host_package_verifier
from tooling.contracts import ContractRepository, ContractToolError
from tooling.product_delivery_release_plan import (
    ProductDeliveryReleasePlanError,
    load_selected_macos_host_package_release_plan,
)


class MacOSReleasePackageAssemblyError(RuntimeError):
    """One explicit product-release package assembly cannot continue."""


MAXIMUM_DECLARATION_BYTES = 1 << 20


@dataclass(frozen=True)
class MacOSReleasePackageAssemblyDeclaration:
    """Release-process-owned desired input for one C47 macOS package build.

    It deliberately refers to C41 rather than copying Guest source selection.
    C35-derived artifact paths are derived from C41's declared output roles and
    checked again against the actual C35 command after input assembly.
    """

    assembly_id: str
    release_delivery_plans_document: Path
    release_delivery_plan_id: str
    guest_artifact_compilation_input_assembly_declaration: Path
    assembled_guest_artifact_compilation_input_root: Path
    guest_artifact_compilation_output_directory: Path
    guest_artifact_builder_timeout_seconds: int
    host_agent_binary: Path
    host_edge_proxy_binary: Path
    host_installation_manager_binary: Path
    macos_virtual_machine_supervisor_binary: Path
    guest_product_process_supervisor_artifact: Path
    host_agent_deployment_configuration: Path
    host_edge_proxy_deployment_configuration: Path
    macos_virtual_machine_configuration: Path
    guest_product_process_deployment_configuration: Path
    guest_product_service_manager_deployment_configuration: Path
    guest_product_bootstrap_configuration: Path
    guest_product_vitalserver_topology_deployment: Path
    external_vitalserver_delivery_configuration: Path | None
    payload_base_path: PurePosixPath
    output_package: Path
    pkgbuild_executable: Path
    macos_installer_package_signing: macos_host_package_composer.MacOSInstallerPackageSigning
    macos_virtual_machine_supervisor_code_signing: (
        macos_host_package_composer.MacOSVirtualMachineSupervisorCodeSigning
    )
    pkgutil_executable: Path
    assembly_receipt_output: Path


@dataclass(frozen=True)
class DeclaredGuestArtifactOutputPaths:
    """C41-declared C35 output locations required by the package adapter."""

    kernel: Path
    initial_ramdisk: Path | None
    storage: Mapping[str, Path]


@dataclass(frozen=True)
class MacOSReleasePackageAssemblyRequest:
    """Complete caller-owned inputs for one macOS package build.

    C41 owns the named build-machine source selection and C35 input root.
    `host_package_composition` owns the selected C23 identity, Host deployment
    documents, Host artifacts, code-signing choice, and PKG destination.
    `host_package_verification` is deliberately separate because package
    expansion is a new observation, not an implicit result of pkgbuild.
    """

    guest_artifact_input_assembly_execution: (
        guest_artifact_compilation_input_assembler.GuestArtifactCompilationInputAssemblyExecution
    )
    guest_artifact_output_directory: Path
    guest_artifact_builder_timeout_seconds: int
    host_package_composition: macos_host_package_composer.MacOSHostPackageComposition
    host_package_verification: macos_host_package_verifier.MacOSHostPackageVerification


@dataclass(frozen=True)
class MacOSReleasePackageAssemblyResult:
    """Explicit build and verification observations returned to the caller."""

    guest_artifact_input_assembly: Mapping[str, Any]
    guest_artifact_compilation: Mapping[str, Any]
    host_package_composition: Mapping[str, str]
    host_package_verification: Mapping[str, str]


def assemble_and_verify_macos_release_package(
    request: MacOSReleasePackageAssemblyRequest,
) -> MacOSReleasePackageAssemblyResult:
    """Run the declared C41 → C35 → PKG → expansion-verification workflow."""

    validate_macos_release_package_assembly_request(request)
    assembled_input = guest_artifact_compilation_input_assembler.assemble_guest_artifact_compilation_input(
        request.guest_artifact_input_assembly_execution
    )
    builder_executable = declared_guest_product_bootstrap_artifact_composer_path(
        request.guest_artifact_input_assembly_execution.assembled_input_root,
        assembled_input,
    )
    compilation_execution = guest_artifact_compiler.GuestArtifactCompilationExecution(
        compilation_command_path=(
            request.guest_artifact_input_assembly_execution.assembled_input_root
            / guest_artifact_compilation_input_assembler.ASSEMBLED_C35_RELATIVE_PATH
        ),
        input_root=request.guest_artifact_input_assembly_execution.assembled_input_root,
        builder_executable=builder_executable,
        output_directory=request.guest_artifact_output_directory,
        builder_timeout_seconds=request.guest_artifact_builder_timeout_seconds,
    )
    guest_artifact_compilation = guest_artifact_compiler.compile_guest_artifact_set(
        compilation_execution
    )
    compilation_command = guest_artifact_compiler.parse_guest_artifact_compilation_command(
        compilation_execution.compilation_command_path.read_bytes()
    )
    validate_host_package_composition_guest_artifact_outputs(
        request.host_package_composition,
        compilation_execution,
        compilation_command,
    )
    validate_host_package_verification_output(
        request.host_package_composition,
        request.host_package_verification,
    )
    host_package_composition = macos_host_package_composer.compose_macos_host_package(
        request.host_package_composition
    )
    host_package_verification = macos_host_package_verifier.verify_macos_host_package(
        request.host_package_verification
    )
    return MacOSReleasePackageAssemblyResult(
        guest_artifact_input_assembly=assembled_input,
        guest_artifact_compilation=guest_artifact_compilation,
        host_package_composition=host_package_composition,
        host_package_verification=host_package_verification,
    )


def validate_macos_release_package_assembly_request(
    request: MacOSReleasePackageAssemblyRequest,
) -> None:
    """Reject ambiguous product-release paths before the first build effect."""

    assembly = request.guest_artifact_input_assembly_execution
    for field_name, path in (
        ("C41 assembly declaration", assembly.assembly_declaration_path),
        ("C41 assembled input root", assembly.assembled_input_root),
        ("C35 output directory", request.guest_artifact_output_directory),
    ):
        if not path.is_absolute():
            raise MacOSReleasePackageAssemblyError(field_name + " path must be absolute")
    if request.guest_artifact_builder_timeout_seconds < 1:
        raise MacOSReleasePackageAssemblyError(
            "C35 Guest Product bootstrap-artifact composer timeout must be positive"
        )
    expected_manifest_path = (
        request.guest_artifact_output_directory
        / "macos-guest-artifact-manifest.json"
    )
    expected_receipt_path = (
        request.guest_artifact_output_directory
        / "guest-artifact-compilation-receipt.json"
    )
    if request.host_package_composition.guest_artifact_manifest != expected_manifest_path:
        raise MacOSReleasePackageAssemblyError(
            "PKG composition C34 path must be the canonical C35 output path"
        )
    if (
        request.host_package_composition.guest_artifact_compilation_receipt
        != expected_receipt_path
    ):
        raise MacOSReleasePackageAssemblyError(
            "PKG composition C35 receipt path must be the canonical C35 output path"
        )


def declared_guest_product_bootstrap_artifact_composer_path(
    assembled_input_root: Path,
    assembly_result: Mapping[str, Any],
) -> Path:
    """Read the C41-owned selected builder location from assembly evidence."""

    receipt = assembly_result.get("guestArtifactCompilationInputAssemblyReceipt")
    if not isinstance(receipt, Mapping):
        raise MacOSReleasePackageAssemblyError(
            "C41 assembly returned no guest artifact compilation input receipt"
        )
    builder = receipt.get("guestProductBootstrapArtifactComposer")
    if not isinstance(builder, Mapping):
        raise MacOSReleasePackageAssemblyError(
            "C41 receipt has no selected Guest Product bootstrap-artifact composer"
        )
    relative_path = builder.get("relativePath")
    if not isinstance(relative_path, str) or not relative_path:
        raise MacOSReleasePackageAssemblyError(
            "C41 selected Guest Product bootstrap-artifact composer path is invalid"
        )
    relative_path_value = PurePosixPath(relative_path)
    if relative_path_value.is_absolute() or ".." in relative_path_value.parts:
        raise MacOSReleasePackageAssemblyError(
            "C41 selected Guest Product bootstrap-artifact composer path escapes the assembled input root"
        )
    return assembled_input_root / Path(relative_path_value)


def validate_host_package_composition_guest_artifact_outputs(
    composition: macos_host_package_composer.MacOSHostPackageComposition,
    compilation_execution: guest_artifact_compiler.GuestArtifactCompilationExecution,
    command: guest_artifact_compiler.GuestArtifactCompilationCommand,
) -> None:
    """Bind package payload sources to the explicit C35 output declarations."""

    expected_kernel_path = compilation_execution.output_directory / command.kernel.output_relative_path
    if composition.guest_kernel_source != expected_kernel_path:
        raise MacOSReleasePackageAssemblyError(
            "PKG composition kernel source must be the C35 declared kernel output"
        )
    expected_initial_ramdisk_path = (
        None
        if command.initial_ramdisk is None
        else compilation_execution.output_directory
        / command.initial_ramdisk.output_relative_path
    )
    if composition.guest_initial_ramdisk_source != expected_initial_ramdisk_path:
        raise MacOSReleasePackageAssemblyError(
            "PKG composition initial RAM disk source must be the C35 declared initial RAM disk output"
        )
    expected_storage_sources = {
        storage.identifier: compilation_execution.output_directory
        / storage.output_relative_path
        for storage in command.storage_devices
    }
    if dict(composition.guest_storage_sources) != expected_storage_sources:
        raise MacOSReleasePackageAssemblyError(
            "PKG composition storage sources must be exactly the C35 declared storage outputs"
        )


def validate_host_package_verification_output(
    composition: macos_host_package_composer.MacOSHostPackageComposition,
    verification: macos_host_package_verifier.MacOSHostPackageVerification,
) -> None:
    """Keep package expansion verification bound to this exact pkgbuild output."""

    if verification.package != composition.output_package:
        raise MacOSReleasePackageAssemblyError(
            "PKG verification package path must equal the PKG composition output path"
        )
    if verification.release_delivery_plans_document != composition.release_delivery_plans_document:
        raise MacOSReleasePackageAssemblyError(
            "PKG verification C23 release plans path must equal the PKG composition C23 path"
        )
    if verification.release_delivery_plan_id != composition.release_delivery_plan_id:
        raise MacOSReleasePackageAssemblyError(
            "PKG verification C23 release plan id must equal the PKG composition C23 plan id"
        )
    if verification.payload_base_path != composition.payload_base_path:
        raise MacOSReleasePackageAssemblyError(
            "PKG verification payload base path must equal the PKG composition payload base path"
        )
    if verification.release_slot_id != composition.release_slot_id:
        raise MacOSReleasePackageAssemblyError(
            "PKG verification immutable release slot must equal the PKG composition release slot"
        )


def assemble_declared_macos_release_package(
    declaration_path: Path,
) -> Mapping[str, Any]:
    """Execute one C47 declaration and publish its new immutable receipt.

    The declaration is the release-process input.  It names C41 instead of
    restating its Guest source choices, derives C35 output paths from that C41
    declaration, and then lets the existing workflow re-check those paths
    against the actual assembled C35 command before package composition.
    """

    declaration_bytes, declaration = load_macos_release_package_assembly_declaration(
        declaration_path
    )
    _, c41_declaration = (
        guest_artifact_compilation_input_assembler.load_guest_artifact_compilation_input_assembly_declaration(
            declaration.guest_artifact_compilation_input_assembly_declaration
        )
    )
    request = macos_release_package_assembly_request_from_declaration(
        declaration,
        c41_declaration,
    )
    result = assemble_and_verify_macos_release_package(request)
    receipt = compose_macos_release_package_assembly_receipt(
        declaration_bytes,
        declaration,
        result,
    )
    write_new_macos_release_package_assembly_receipt(
        declaration.assembly_receipt_output,
        receipt,
    )
    return {
        "assemblyId": declaration.assembly_id,
        "guestArtifactCompilationInputAssembly": result.guest_artifact_input_assembly,
        "guestArtifactCompilation": result.guest_artifact_compilation,
        "macOSHostPackage": result.host_package_composition,
        "macOSHostPackageVerification": result.host_package_verification,
        "macOSReleasePackageAssemblyReceipt": receipt,
    }


def load_macos_release_package_assembly_declaration(
    declaration_path: Path,
) -> tuple[bytes, MacOSReleasePackageAssemblyDeclaration]:
    """Decode one complete C47 declaration without ambient build defaults."""

    require_regular_absolute_file(
        declaration_path,
        "C47 macOS release package assembly declaration",
    )
    try:
        declaration_bytes = declaration_path.read_bytes()
    except OSError as error:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly declaration read failed: "
            + str(error)
        ) from error
    if len(declaration_bytes) > MAXIMUM_DECLARATION_BYTES:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly declaration exceeds maximum size"
        )
    try:
        document = json.loads(declaration_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly declaration cannot be decoded as JSON"
        ) from error
    if not isinstance(document, Mapping):
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly declaration must be a JSON object"
        )
    validate_macos_release_package_assembly_declaration_document(document)
    declaration = parse_macos_release_package_assembly_declaration(document)
    validate_macos_release_package_assembly_declaration_execution(declaration)
    return declaration_bytes, declaration


def validate_macos_release_package_assembly_declaration_document(
    document: Mapping[str, Any],
) -> None:
    """Validate the C47 source before resolving one build-machine path."""

    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        errors = repository.validate_instance(
            "macos-release-package-assembly-declaration.schema.json",
            document,
        )
    except ContractToolError as error:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly declaration contract is unavailable: "
            + str(error)
        ) from error
    if errors:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly declaration is invalid: "
            + "; ".join(errors)
        )


def parse_macos_release_package_assembly_declaration(
    document: Mapping[str, Any],
) -> MacOSReleasePackageAssemblyDeclaration:
    """Map fully named C47 fields into one application input value."""

    assembly_id = required_string(document, "assemblyId", "C47 declaration")
    release_delivery_plan = required_mapping(
        document,
        "releaseDeliveryPlan",
        "C47 declaration",
    )
    input_assembly = required_mapping(
        document,
        "guestArtifactCompilationInputAssembly",
        "C47 declaration",
    )
    compilation = required_mapping(
        document,
        "guestArtifactCompilation",
        "C47 declaration",
    )
    host_artifacts = required_mapping(document, "hostArtifacts", "C47 declaration")
    deployment_documents = required_mapping(
        document,
        "deploymentDocuments",
        "C47 declaration",
    )
    macos_package = required_mapping(document, "macOSPackage", "C47 declaration")
    package_signing = required_mapping(
        macos_package,
        "installerPackageSigning",
        "C47 macOSPackage",
    )
    virtual_machine_supervisor_code_signing = required_mapping(
        macos_package,
        "virtualMachineSupervisorCodeSigning",
        "C47 macOSPackage",
    )
    package_verification = required_mapping(
        document,
        "macOSPackageVerification",
        "C47 declaration",
    )
    assembly_receipt = required_mapping(document, "assemblyReceipt", "C47 declaration")

    macos_installer_package_signing = parse_macos_installer_package_signing(
        package_signing,
    )
    supervisor_code_signing = parse_virtual_machine_supervisor_code_signing(
        virtual_machine_supervisor_code_signing,
    )
    return MacOSReleasePackageAssemblyDeclaration(
        assembly_id=assembly_id,
        release_delivery_plans_document=required_absolute_path(
            release_delivery_plan,
            "documentAbsolutePath",
            "C47 releaseDeliveryPlan",
        ),
        release_delivery_plan_id=required_string(
            release_delivery_plan,
            "id",
            "C47 releaseDeliveryPlan",
        ),
        guest_artifact_compilation_input_assembly_declaration=required_absolute_path(
            input_assembly,
            "declarationAbsolutePath",
            "C47 guestArtifactCompilationInputAssembly",
        ),
        assembled_guest_artifact_compilation_input_root=required_absolute_path(
            input_assembly,
            "assembledInputRootAbsolutePath",
            "C47 guestArtifactCompilationInputAssembly",
        ),
        guest_artifact_compilation_output_directory=required_absolute_path(
            compilation,
            "outputDirectoryAbsolutePath",
            "C47 guestArtifactCompilation",
        ),
        guest_artifact_builder_timeout_seconds=required_positive_integer(
            compilation,
            "builderTimeoutSeconds",
            "C47 guestArtifactCompilation",
        ),
        host_agent_binary=required_absolute_path(
            host_artifacts,
            "hostAgentBinaryAbsolutePath",
            "C47 hostArtifacts",
        ),
        host_edge_proxy_binary=required_absolute_path(
            host_artifacts,
            "hostEdgeProxyBinaryAbsolutePath",
            "C47 hostArtifacts",
        ),
        host_installation_manager_binary=required_absolute_path(
            host_artifacts,
            "hostInstallationManagerBinaryAbsolutePath",
            "C47 hostArtifacts",
        ),
        macos_virtual_machine_supervisor_binary=required_absolute_path(
            host_artifacts,
            "macOSVirtualMachineSupervisorBinaryAbsolutePath",
            "C47 hostArtifacts",
        ),
        guest_product_process_supervisor_artifact=required_absolute_path(
            host_artifacts,
            "guestProductProcessSupervisorArtifactAbsolutePath",
            "C47 hostArtifacts",
        ),
        host_agent_deployment_configuration=required_absolute_path(
            deployment_documents,
            "hostAgentDeploymentConfigurationAbsolutePath",
            "C47 deploymentDocuments",
        ),
        host_edge_proxy_deployment_configuration=required_absolute_path(
            deployment_documents,
            "hostEdgeProxyDeploymentConfigurationAbsolutePath",
            "C47 deploymentDocuments",
        ),
        macos_virtual_machine_configuration=required_absolute_path(
            deployment_documents,
            "macOSVirtualMachineConfigurationAbsolutePath",
            "C47 deploymentDocuments",
        ),
        guest_product_process_deployment_configuration=required_absolute_path(
            deployment_documents,
            "guestProductProcessDeploymentConfigurationAbsolutePath",
            "C47 deploymentDocuments",
        ),
        guest_product_service_manager_deployment_configuration=required_absolute_path(
            deployment_documents,
            "guestProductServiceManagerDeploymentConfigurationAbsolutePath",
            "C47 deploymentDocuments",
        ),
        guest_product_bootstrap_configuration=required_absolute_path(
            deployment_documents,
            "guestProductBootstrapConfigurationAbsolutePath",
            "C47 deploymentDocuments",
        ),
        guest_product_vitalserver_topology_deployment=required_absolute_path(
            deployment_documents,
            "guestProductVitalServerTopologyDeploymentAbsolutePath",
            "C47 deploymentDocuments",
        ),
        external_vitalserver_delivery_configuration=optional_absolute_path(
            deployment_documents,
            "externalVitalServerDeliveryConfigurationAbsolutePath",
            "C47 deploymentDocuments",
        ),
        payload_base_path=required_safe_absolute_payload_path(
            macos_package,
            "payloadBasePath",
            "C47 macOSPackage",
        ),
        output_package=required_absolute_path(
            macos_package,
            "outputPackageAbsolutePath",
            "C47 macOSPackage",
        ),
        pkgbuild_executable=required_absolute_path(
            macos_package,
            "pkgbuildExecutableAbsolutePath",
            "C47 macOSPackage",
        ),
        macos_installer_package_signing=macos_installer_package_signing,
        macos_virtual_machine_supervisor_code_signing=supervisor_code_signing,
        pkgutil_executable=required_absolute_path(
            package_verification,
            "pkgutilExecutableAbsolutePath",
            "C47 macOSPackageVerification",
        ),
        assembly_receipt_output=required_absolute_path(
            assembly_receipt,
            "outputAbsolutePath",
            "C47 assemblyReceipt",
        ),
    )


def parse_macos_installer_package_signing(
    document: Mapping[str, Any],
) -> macos_host_package_composer.MacOSInstallerPackageSigning:
    """Map C47's final-installer signature inputs into the package adapter type."""

    mode = required_string(document, "mode", "C47 macOS Installer package signing")
    if mode == "unsigned":
        if (
            document.get("identity") is not None
            or document.get("productsignExecutableAbsolutePath") is not None
        ):
            raise MacOSReleasePackageAssemblyError(
                "C47 macOS Installer package signing unsigned mode must not include signing inputs"
            )
        return macos_host_package_composer.MacOSInstallerPackageSigning(
            mode=mode,
            signing_identity=None,
            productsign_executable=None,
        )
    if mode != "developer-id":
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS Installer package signing mode must be unsigned or developer-id"
        )
    identity = required_non_empty_signing_identity(
        document,
        "C47 macOS Installer package signing",
    )
    return macos_host_package_composer.MacOSInstallerPackageSigning(
        mode=mode,
        signing_identity=identity,
        productsign_executable=required_absolute_path(
            document,
            "productsignExecutableAbsolutePath",
            "C47 macOS Installer package signing",
        ),
    )


def parse_virtual_machine_supervisor_code_signing(
    document: Mapping[str, Any],
) -> macos_host_package_composer.MacOSVirtualMachineSupervisorCodeSigning:
    field_name = "C47 macOS virtual machine supervisor code signing"
    mode = required_string(document, "mode", field_name)
    if mode == "unsigned":
        if any(
            document.get(field) is not None
            for field in (
                "identity",
                "codesignExecutableAbsolutePath",
                "virtualizationEntitlementsAbsolutePath",
            )
        ):
            raise MacOSReleasePackageAssemblyError(
                field_name + " unsigned mode must not include signing inputs"
            )
        return macos_host_package_composer.MacOSVirtualMachineSupervisorCodeSigning(
            mode=mode,
            signing_identity=None,
            codesign_executable=None,
            virtualization_entitlements=None,
        )
    if mode == "ad-hoc":
        if document.get("identity") is not None:
            raise MacOSReleasePackageAssemblyError(
                field_name + " ad-hoc mode must not include a signing identity"
            )
        return macos_host_package_composer.MacOSVirtualMachineSupervisorCodeSigning(
            mode=mode,
            signing_identity=None,
            codesign_executable=required_absolute_path(
                document,
                "codesignExecutableAbsolutePath",
                field_name,
            ),
            virtualization_entitlements=required_absolute_path(
                document,
                "virtualizationEntitlementsAbsolutePath",
                field_name,
            ),
        )
    if mode != "developer-id":
        raise MacOSReleasePackageAssemblyError(
            field_name + " mode must be unsigned, ad-hoc, or developer-id"
        )
    return macos_host_package_composer.MacOSVirtualMachineSupervisorCodeSigning(
        mode=mode,
        signing_identity=required_non_empty_signing_identity(document, field_name),
        codesign_executable=required_absolute_path(
            document,
            "codesignExecutableAbsolutePath",
            field_name,
        ),
        virtualization_entitlements=required_absolute_path(
            document,
            "virtualizationEntitlementsAbsolutePath",
            field_name,
        ),
    )


def required_non_empty_signing_identity(
    document: Mapping[str, Any],
    field_name: str,
) -> str:
    identity = document.get("identity")
    if not isinstance(identity, str) or not identity.strip():
        raise MacOSReleasePackageAssemblyError(
            field_name + " developer-id mode requires a signing identity"
        )
    return identity


def validate_macos_release_package_assembly_declaration_execution(
    declaration: MacOSReleasePackageAssemblyDeclaration,
) -> None:
    """Reject ambiguous or already-consumed C47 destinations before C41 effects."""

    input_files = (
        ("C23 release delivery plans document", declaration.release_delivery_plans_document),
        (
            "C41 Guest artifact compilation input assembly declaration",
            declaration.guest_artifact_compilation_input_assembly_declaration,
        ),
        ("Host Agent binary", declaration.host_agent_binary),
        ("Host Edge Proxy binary", declaration.host_edge_proxy_binary),
        (
            "Host Installation Manager binary",
            declaration.host_installation_manager_binary,
        ),
        (
            "macOS virtual machine supervisor binary",
            declaration.macos_virtual_machine_supervisor_binary,
        ),
        (
            "Guest Product process supervisor artifact",
            declaration.guest_product_process_supervisor_artifact,
        ),
        (
            "C33 HostAgentDeploymentConfiguration",
            declaration.host_agent_deployment_configuration,
        ),
        (
            "C36 HostEdgeProxyDeploymentConfiguration",
            declaration.host_edge_proxy_deployment_configuration,
        ),
        (
            "C32 MacOSVirtualMachineConfiguration",
            declaration.macos_virtual_machine_configuration,
        ),
        (
            "C37 GuestProductProcessDeploymentConfiguration",
            declaration.guest_product_process_deployment_configuration,
        ),
        (
            "C38 GuestProductServiceManagerDeploymentConfiguration",
            declaration.guest_product_service_manager_deployment_configuration,
        ),
        (
            "C39 GuestProductBootstrapConfiguration",
            declaration.guest_product_bootstrap_configuration,
        ),
        (
            "C44 GuestProductVitalServerTopologyDeployment",
            declaration.guest_product_vitalserver_topology_deployment,
        ),
        ("pkgbuild executable", declaration.pkgbuild_executable),
        ("pkgutil executable", declaration.pkgutil_executable),
    )
    for name, path in input_files:
        require_regular_absolute_file(path, name)
    try:
        release_plan = load_selected_macos_host_package_release_plan(
            declaration.release_delivery_plans_document,
            declaration.release_delivery_plan_id,
        )
    except ProductDeliveryReleasePlanError as error:
        raise MacOSReleasePackageAssemblyError(
            "C47 release delivery plan selection failed: " + str(error)
        ) from error
    if declaration.output_package.name != release_plan.expected_package_file_name:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS package output file name must match C23 intended installer artifact"
        )
    if declaration.external_vitalserver_delivery_configuration is not None:
        require_regular_absolute_file(
            declaration.external_vitalserver_delivery_configuration,
            "C46 ExternalVitalServerDeliveryConfiguration",
        )
    code_signing = declaration.macos_virtual_machine_supervisor_code_signing
    if code_signing.mode in {"ad-hoc", "developer-id"}:
        assert code_signing.codesign_executable is not None
        assert code_signing.virtualization_entitlements is not None
        require_regular_absolute_file(
            code_signing.codesign_executable,
            "codesign executable",
        )
        require_regular_absolute_file(
            code_signing.virtualization_entitlements,
            "macOS virtual machine supervisor virtualization entitlements",
        )
    package_signing = declaration.macos_installer_package_signing
    if package_signing.mode == "developer-id":
        assert package_signing.productsign_executable is not None
        require_regular_absolute_file(
            package_signing.productsign_executable,
            "macOS Installer package productsign executable",
        )

    output_paths = (
        (
            "C41 assembled Guest artifact compilation input root",
            declaration.assembled_guest_artifact_compilation_input_root,
        ),
        (
            "C35 Guest artifact compilation output directory",
            declaration.guest_artifact_compilation_output_directory,
        ),
        ("macOS release package", declaration.output_package),
        ("C47 assembly receipt", declaration.assembly_receipt_output),
    )
    for name, path in output_paths:
        require_new_output_path(path, name)
    reject_overlapping_release_assembly_output_paths(output_paths)


def macos_release_package_assembly_request_from_declaration(
    declaration: MacOSReleasePackageAssemblyDeclaration,
    c41_declaration: Mapping[str, Any],
) -> MacOSReleasePackageAssemblyRequest:
    """Derive one fully bound application request from C47 and C41 inputs."""

    output_paths = declared_guest_artifact_output_paths_from_c41_declaration(
        c41_declaration,
        declaration.guest_artifact_compilation_output_directory,
    )
    composition = macos_host_package_composer.MacOSHostPackageComposition(
        release_delivery_plans_document=declaration.release_delivery_plans_document,
        release_delivery_plan_id=declaration.release_delivery_plan_id,
        payload_base_path=declaration.payload_base_path,
        release_slot_id=declaration.assembly_id,
        host_agent_binary=declaration.host_agent_binary,
        host_edge_proxy_binary=declaration.host_edge_proxy_binary,
        host_installation_manager_binary=declaration.host_installation_manager_binary,
        macos_virtual_machine_supervisor_binary=(
            declaration.macos_virtual_machine_supervisor_binary
        ),
        host_agent_deployment_configuration=(
            declaration.host_agent_deployment_configuration
        ),
        host_edge_proxy_deployment_configuration=(
            declaration.host_edge_proxy_deployment_configuration
        ),
        macos_virtual_machine_configuration=(
            declaration.macos_virtual_machine_configuration
        ),
        guest_artifact_manifest=(
            declaration.guest_artifact_compilation_output_directory
            / "macos-guest-artifact-manifest.json"
        ),
        guest_artifact_compilation_receipt=(
            declaration.guest_artifact_compilation_output_directory
            / "guest-artifact-compilation-receipt.json"
        ),
        guest_product_process_supervisor_artifact=(
            declaration.guest_product_process_supervisor_artifact
        ),
        guest_product_process_deployment_configuration=(
            declaration.guest_product_process_deployment_configuration
        ),
        guest_product_service_manager_deployment_configuration=(
            declaration.guest_product_service_manager_deployment_configuration
        ),
        guest_product_bootstrap_configuration=(
            declaration.guest_product_bootstrap_configuration
        ),
        guest_product_vitalserver_topology_deployment=(
            declaration.guest_product_vitalserver_topology_deployment
        ),
        external_vitalserver_delivery_configuration=(
            declaration.external_vitalserver_delivery_configuration
        ),
        guest_kernel_source=output_paths.kernel,
        guest_initial_ramdisk_source=output_paths.initial_ramdisk,
        guest_storage_sources=output_paths.storage,
        output_package=declaration.output_package,
        pkgbuild_executable=declaration.pkgbuild_executable,
        macos_installer_package_signing=declaration.macos_installer_package_signing,
        macos_virtual_machine_supervisor_code_signing=(
            declaration.macos_virtual_machine_supervisor_code_signing
        ),
        replace_output=False,
    )
    verification = macos_host_package_verifier.MacOSHostPackageVerification(
        package=declaration.output_package,
        pkgutil_executable=declaration.pkgutil_executable,
        release_delivery_plans_document=declaration.release_delivery_plans_document,
        release_delivery_plan_id=declaration.release_delivery_plan_id,
        payload_base_path=declaration.payload_base_path,
        release_slot_id=declaration.assembly_id,
    )
    return MacOSReleasePackageAssemblyRequest(
        guest_artifact_input_assembly_execution=(
            guest_artifact_compilation_input_assembler.GuestArtifactCompilationInputAssemblyExecution(
                assembly_declaration_path=(
                    declaration.guest_artifact_compilation_input_assembly_declaration
                ),
                assembled_input_root=(
                    declaration.assembled_guest_artifact_compilation_input_root
                ),
            )
        ),
        guest_artifact_output_directory=(
            declaration.guest_artifact_compilation_output_directory
        ),
        guest_artifact_builder_timeout_seconds=(
            declaration.guest_artifact_builder_timeout_seconds
        ),
        host_package_composition=composition,
        host_package_verification=verification,
    )


def declared_guest_artifact_output_paths_from_c41_declaration(
    c41_declaration: Mapping[str, Any],
    output_directory: Path,
) -> DeclaredGuestArtifactOutputPaths:
    """Read only C41's declared C35 output layout before any build effect."""

    boot = required_mapping(c41_declaration, "boot", "C41 declaration")
    kernel = required_mapping(boot, "kernel", "C41 declaration boot")
    kernel_output = output_directory / required_relative_output_path(
        kernel,
        "outputRelativePath",
        "C41 declaration boot.kernel",
    )
    initial_ramdisk_document = boot.get("initialRamdisk")
    initial_ramdisk: Path | None = None
    if initial_ramdisk_document is not None:
        if not isinstance(initial_ramdisk_document, Mapping):
            raise MacOSReleasePackageAssemblyError(
                "C41 declaration boot.initialRamdisk must be an object"
            )
        initial_ramdisk = output_directory / required_relative_output_path(
            initial_ramdisk_document,
            "outputRelativePath",
            "C41 declaration boot.initialRamdisk",
        )
    raw_storage_devices = c41_declaration.get("storageDevices")
    if not isinstance(raw_storage_devices, list) or not raw_storage_devices:
        raise MacOSReleasePackageAssemblyError(
            "C41 declaration requires a non-empty storageDevices list"
        )
    storage: dict[str, Path] = {}
    for index, raw_storage in enumerate(raw_storage_devices):
        if not isinstance(raw_storage, Mapping):
            raise MacOSReleasePackageAssemblyError(
                "C41 declaration storageDevices["
                + str(index)
                + "] must be an object"
            )
        storage_id = required_string(
            raw_storage,
            "id",
            "C41 declaration storageDevices[" + str(index) + "]",
        )
        if storage_id in storage:
            raise MacOSReleasePackageAssemblyError(
                "C41 declaration has duplicate storage device id: " + storage_id
            )
        storage[storage_id] = output_directory / required_relative_output_path(
            raw_storage,
            "outputRelativePath",
            "C41 declaration storageDevices[" + str(index) + "]",
        )
    return DeclaredGuestArtifactOutputPaths(
        kernel=kernel_output,
        initial_ramdisk=initial_ramdisk,
        storage=storage,
    )


def compose_macos_release_package_assembly_receipt(
    declaration_bytes: bytes,
    declaration: MacOSReleasePackageAssemblyDeclaration,
    result: MacOSReleasePackageAssemblyResult,
) -> Mapping[str, Any]:
    """Compose C47 receipt from output files and adapter observations only."""

    try:
        release_plan = load_selected_macos_host_package_release_plan(
            declaration.release_delivery_plans_document,
            declaration.release_delivery_plan_id,
        )
    except ProductDeliveryReleasePlanError as error:
        raise MacOSReleasePackageAssemblyError(
            "C47 release delivery plan cannot be read after package assembly: "
            + str(error)
        ) from error
    c41_receipt = required_mapping(
        result.guest_artifact_input_assembly,
        "guestArtifactCompilationInputAssemblyReceipt",
        "C41 assembly result",
    )
    c41_assembly_id = required_string(c41_receipt, "assemblyId", "C41 receipt")
    c35_compilation_id = required_string(
        result.guest_artifact_compilation,
        "compilationId",
        "C35 compilation result",
    )
    c35_artifact_set_id = required_string(
        result.guest_artifact_compilation,
        "artifactSetId",
        "C35 compilation result",
    )
    c41_receipt_path = (
        declaration.assembled_guest_artifact_compilation_input_root
        / guest_artifact_compilation_input_assembler.ASSEMBLED_C41_RECEIPT_RELATIVE_PATH
    )
    c35_receipt_path = (
        declaration.guest_artifact_compilation_output_directory
        / "guest-artifact-compilation-receipt.json"
    )
    c34_manifest_path = (
        declaration.guest_artifact_compilation_output_directory
        / "macos-guest-artifact-manifest.json"
    )
    for name, path in (
        ("C41 receipt", c41_receipt_path),
        ("C35 receipt", c35_receipt_path),
        ("C34 manifest", c34_manifest_path),
        ("macOS package", declaration.output_package),
    ):
        require_regular_absolute_file(path, name)
    composed_package_sha256 = required_sha256(
        result.host_package_composition,
        "sha256",
        "macOS Host package composition result",
    )
    verified_package_sha256 = required_sha256(
        result.host_package_verification,
        "sha256",
        "macOS Host package verification result",
    )
    actual_package_sha256 = sha256_file(declaration.output_package)
    if composed_package_sha256 != actual_package_sha256:
        raise MacOSReleasePackageAssemblyError(
            "macOS Host package composition SHA-256 does not match the output package"
        )
    if verified_package_sha256 != actual_package_sha256:
        raise MacOSReleasePackageAssemblyError(
            "macOS Host package verification SHA-256 does not match the output package"
        )
    if result.host_package_verification.get("releaseDeliveryPlanId") != declaration.release_delivery_plan_id:
        raise MacOSReleasePackageAssemblyError(
            "macOS Host package verification release delivery plan does not match C47"
        )
    if result.host_package_verification.get("payloadBasePath") != str(
        declaration.payload_base_path
    ):
        raise MacOSReleasePackageAssemblyError(
            "macOS Host package verification payload base path does not match C47"
        )
    receipt: Mapping[str, Any] = {
        "schemaVersion": "v1",
        "assemblyId": declaration.assembly_id,
        "assemblyDeclarationSHA256": sha256_bytes(declaration_bytes),
        "release": {
            "deliveryPlanId": declaration.release_delivery_plan_id,
            "productVersion": release_plan.product_version,
        },
        "guestArtifactCompilationInputAssembly": {
            "assemblyId": c41_assembly_id,
            "receipt": {"sha256": sha256_file(c41_receipt_path)},
        },
        "guestArtifactCompilation": {
            "compilationId": c35_compilation_id,
            "artifactSetId": c35_artifact_set_id,
            "receipt": {"sha256": sha256_file(c35_receipt_path)},
            "macOSGuestArtifactManifest": {"sha256": sha256_file(c34_manifest_path)},
        },
        "macOSHostPackage": {
            "fileName": declaration.output_package.name,
            "sha256": actual_package_sha256,
        },
        "macOSHostPackageVerification": {
            "releaseDeliveryPlanId": declaration.release_delivery_plan_id,
            "payloadBasePath": str(declaration.payload_base_path),
            "sha256": verified_package_sha256,
        },
        "completedAt": utc_timestamp(),
    }
    validate_macos_release_package_assembly_receipt_document(receipt)
    return receipt


def validate_macos_release_package_assembly_receipt_document(
    receipt: Mapping[str, Any],
) -> None:
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        errors = repository.validate_instance(
            "macos-release-package-assembly-receipt.schema.json",
            receipt,
        )
    except ContractToolError as error:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly receipt contract is unavailable: "
            + str(error)
        ) from error
    if errors:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly receipt is invalid: "
            + "; ".join(errors)
        )


def write_new_macos_release_package_assembly_receipt(
    receipt_path: Path,
    receipt: Mapping[str, Any],
) -> None:
    """Create the C47 receipt once; a later build must use a new destination."""

    require_new_output_path(receipt_path, "C47 assembly receipt")
    contents = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        descriptor = os.open(receipt_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
    except OSError as error:
        raise MacOSReleasePackageAssemblyError(
            "C47 macOS release package assembly receipt write failed: " + str(error)
        ) from error


def require_regular_absolute_file(path: Path, name: str) -> None:
    if not path.is_absolute() or ".." in path.parts:
        raise MacOSReleasePackageAssemblyError(
            name + " path must be absolute and must not contain traversal"
        )
    if not path.is_file() or path.is_symlink():
        raise MacOSReleasePackageAssemblyError(name + " is missing or not a regular file")


def require_new_output_path(path: Path, name: str) -> None:
    if not path.is_absolute() or ".." in path.parts:
        raise MacOSReleasePackageAssemblyError(
            name + " path must be absolute and must not contain traversal"
        )
    if not path.parent.is_dir():
        raise MacOSReleasePackageAssemblyError(
            name + " parent directory is missing or not a directory"
        )
    if path.exists() or path.is_symlink():
        raise MacOSReleasePackageAssemblyError(
            name + " destination already exists; C47 requires a new destination"
        )


def reject_overlapping_release_assembly_output_paths(
    output_paths: tuple[tuple[str, Path], ...],
) -> None:
    for index, (left_name, left_path) in enumerate(output_paths):
        for right_name, right_path in output_paths[index + 1 :]:
            if paths_overlap(left_path, right_path):
                raise MacOSReleasePackageAssemblyError(
                    left_name + " and " + right_name + " must not overlap"
                )


def paths_overlap(left: Path, right: Path) -> bool:
    return left == right or is_path_within(left, right) or is_path_within(right, left)


def is_path_within(candidate: Path, parent: Path) -> bool:
    try:
        candidate.relative_to(parent)
    except ValueError:
        return False
    return True


def required_mapping(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> Mapping[str, Any]:
    value = document.get(field_name)
    if not isinstance(value, Mapping):
        raise MacOSReleasePackageAssemblyError(
            document_name + " requires object " + field_name
        )
    return value


def required_string(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> str:
    value = document.get(field_name)
    if not isinstance(value, str) or not value:
        raise MacOSReleasePackageAssemblyError(
            document_name + " requires non-empty " + field_name
        )
    return value


def required_positive_integer(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> int:
    value = document.get(field_name)
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise MacOSReleasePackageAssemblyError(
            document_name + " requires positive integer " + field_name
        )
    return value


def required_absolute_path(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> Path:
    return path_from_string(required_string(document, field_name, document_name), document_name + " " + field_name)


def optional_absolute_path(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> Path | None:
    value = document.get(field_name)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise MacOSReleasePackageAssemblyError(
            document_name + " " + field_name + " must be a non-empty absolute path"
        )
    return path_from_string(value, document_name + " " + field_name)


def path_from_string(value: str, field_name: str) -> Path:
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise MacOSReleasePackageAssemblyError(
            field_name + " must be an absolute path without traversal"
        )
    return path


def required_safe_absolute_payload_path(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> PurePosixPath:
    value = required_string(document, field_name, document_name)
    path = PurePosixPath(value)
    if not path.is_absolute() or ".." in path.parts or "\\" in value:
        raise MacOSReleasePackageAssemblyError(
            document_name + " " + field_name + " must be an absolute path without traversal"
        )
    return path


def required_relative_output_path(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> Path:
    value = required_string(document, field_name, document_name)
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path == PurePosixPath(".") or "\\" in value:
        raise MacOSReleasePackageAssemblyError(
            document_name + " " + field_name + " must be a relative path without traversal"
        )
    return Path(path)


def required_sha256(
    document: Mapping[str, Any],
    field_name: str,
    document_name: str,
) -> str:
    value = document.get(field_name)
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise MacOSReleasePackageAssemblyError(
            document_name + " requires lowercase SHA-256 " + field_name
        )
    return value


def sha256_bytes(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise MacOSReleasePackageAssemblyError(
            "macOS release package assembly artifact digest read failed: " + str(error)
        ) from error
    return digest.hexdigest()


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00",
        "Z",
    )


def parse_arguments(arguments: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--assembly-declaration",
        required=True,
        help="absolute C47 MacOSReleasePackageAssemblyDeclaration path",
    )
    return parser.parse_args(arguments)


def main(arguments: list[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        result = assemble_declared_macos_release_package(
            Path(parsed.assembly_declaration)
        )
    except (
        MacOSReleasePackageAssemblyError,
        guest_artifact_compilation_input_assembler.GuestArtifactCompilationInputAssemblyError,
        guest_artifact_compiler.GuestArtifactCompilationError,
        macos_host_package_composer.MacOSHostPackageCompositionError,
        macos_host_package_verifier.MacOSHostPackageVerificationError,
    ) as error:
        print("macOS release package assembly failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
