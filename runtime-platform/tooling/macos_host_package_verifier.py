"""Verify one macOS Host PKG payload without installing it.

This release-tool adapter observes an explicit PKG's installer payload list,
rejects undeclared macOS AppleDouble metadata sidecars, expands it, verifies
C32/C33/C34/C35 payload provenance and
the launchd payload they name, and preserves any
external-topology C46 consumed-input identity in C35. It then reports package
identity. It does not install a package, launch a Host Agent, start a Guest VM,
or claim a C24 delivery proof.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import subprocess
import sys
import tempfile
from typing import Any, Mapping
import xml.etree.ElementTree as ElementTree

from tooling.product_delivery_release_plan import (
    MacOSHostPackageReleasePlan,
    ProductDeliveryReleasePlanError,
    load_selected_macos_host_package_release_plan,
)


class MacOSHostPackageVerificationError(RuntimeError):
    """An explicit macOS Host package cannot prove its declared payload."""


@dataclass(frozen=True)
class MacOSHostPackageVerification:
    package: Path
    pkgutil_executable: Path
    release_delivery_plans_document: Path
    release_delivery_plan_id: str
    payload_base_path: PurePosixPath


@dataclass(frozen=True)
class VerifiedMacOSHostPackageHostFilesystemPreparation:
    """Host filesystem preparation that C32/C33 explicitly authorize.

    These are directories only. A GuestRuntimeDiskWorkspace and its receipt
    must remain absent from a package payload until the installed Supervisor
    provisions them after C34 release-artifact verification.
    """

    guest_boot_console_capture_path: str
    declared_host_runtime_directories: tuple[PurePosixPath, ...]
    product_version: str


def verify_macos_host_package(verification: MacOSHostPackageVerification) -> dict[str, str]:
    """Validate C32/C33/C34/C35 provenance and launchd payload correspondence in one PKG."""

    try:
        macos_host_package_release_plan = (
            load_selected_macos_host_package_release_plan(
                verification.release_delivery_plans_document,
                verification.release_delivery_plan_id,
            )
        )
    except ProductDeliveryReleasePlanError as error:
        raise MacOSHostPackageVerificationError(str(error)) from error
    validate_macos_host_package_verification(
        verification,
        macos_host_package_release_plan,
    )
    verify_pkgutil_observed_payload_has_no_appledouble_sidecars(verification)
    with tempfile.TemporaryDirectory(prefix="vitalserver-macos-package-verify-") as temporary_directory:
        expanded_package = Path(temporary_directory) / "expanded-package"
        expand_package(verification, expanded_package)
        payload_root = expanded_package / "Payload"
        if not payload_root.is_dir():
            raise MacOSHostPackageVerificationError("pkgutil expansion did not produce a Payload directory")
        verify_expanded_payload_has_no_appledouble_sidecars(payload_root)
        host_filesystem_preparation = verify_payload_documents(verification, payload_root)
        verify_c23_macos_host_package_release_identity(
            verification,
            macos_host_package_release_plan,
            host_filesystem_preparation.product_version,
        )
        verify_launchd_service_definitions(
            verification,
            macos_host_package_release_plan,
            payload_root,
        )
        verify_package_info_release_identity(
            expanded_package,
            host_filesystem_preparation.product_version,
            macos_host_package_release_plan,
        )
        verify_postinstall_service_reconciliation(
            verification,
            macos_host_package_release_plan,
            expanded_package,
            host_filesystem_preparation,
        )
    return {
        "artifactPath": str(verification.package),
        "sha256": sha256_file(verification.package),
        "payloadBasePath": str(verification.payload_base_path),
        "releaseDeliveryPlanId": macos_host_package_release_plan.release_delivery_plan_id,
    }


def verify_pkgutil_observed_payload_has_no_appledouble_sidecars(
    verification: MacOSHostPackageVerification,
) -> None:
    """Reject AppleDouble entries in the installer-owned payload observation.

    `pkgutil --payload-files` is the macOS Installer contract for the paths a
    package carries. Inspecting only the expanded filesystem is insufficient:
    the archive can encode extended attributes as `._*` entries without a
    same-named ordinary file after expansion.
    """

    completed = subprocess.run(
        [
            str(verification.pkgutil_executable),
            "--payload-files",
            str(verification.package),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise MacOSHostPackageVerificationError(
            "pkgutil payload-file observation failed: " + completed.stderr.strip()
        )
    sidecars = sorted(
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip()
        and PurePosixPath(line.strip().removeprefix("./")).name.startswith("._")
    )
    if sidecars:
        raise MacOSHostPackageVerificationError(
            "package payload contains undeclared AppleDouble sidecar paths: "
            + ",".join(sidecars)
        )


def verify_expanded_payload_has_no_appledouble_sidecars(payload_root: Path) -> None:
    """Reject Host metadata files that are not a declared product payload role.

    AppleDouble `._*` files encode macOS extended attributes/resource forks.
    They are build-machine metadata rather than C23/C32–C46/C34/C35 product
    artifacts, so their presence means a package copied more than its declared
    byte inventory.
    """

    sidecars = sorted(
        (
            candidate.relative_to(payload_root).as_posix()
            for candidate in payload_root.rglob("._*")
        ),
    )
    if sidecars:
        raise MacOSHostPackageVerificationError(
            "package payload contains undeclared AppleDouble sidecar paths: "
            + ",".join(sidecars)
        )


def validate_macos_host_package_verification(
    verification: MacOSHostPackageVerification,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
) -> None:
    if not verification.package.is_absolute() or not verification.package.is_file():
        raise MacOSHostPackageVerificationError("package is missing or not a file")
    if not verification.pkgutil_executable.is_absolute() or not verification.pkgutil_executable.is_file():
        raise MacOSHostPackageVerificationError("pkgutil executable is missing or not a file")
    if not is_safe_absolute_path(str(verification.payload_base_path)):
        raise MacOSHostPackageVerificationError("payload base path must be an absolute path without traversal")
    if not verification.release_delivery_plan_id:
        raise MacOSHostPackageVerificationError(
            "C23 release delivery plan id is required"
        )
    if (
        macos_host_package_release_plan.host_agent_launchd_service_label
        == macos_host_package_release_plan.host_edge_proxy_launchd_service_label
    ):
        raise MacOSHostPackageVerificationError("Host Agent and Host Edge Proxy launchd service labels must differ")


def expand_package(verification: MacOSHostPackageVerification, expanded_package: Path) -> None:
    completed = subprocess.run(
        [str(verification.pkgutil_executable), "--expand-full", str(verification.package), str(expanded_package)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise MacOSHostPackageVerificationError("pkgutil expansion failed: " + completed.stderr.strip())


def verify_payload_documents(
    verification: MacOSHostPackageVerification, payload_root: Path
) -> VerifiedMacOSHostPackageHostFilesystemPreparation:
    base_path = verification.payload_base_path
    host_agent_path = payload_destination(payload_root, base_path / "bin" / "host-agent")
    host_edge_proxy_path = payload_destination(payload_root, base_path / "bin" / "host-edge-proxy")
    macos_virtual_machine_supervisor_path = payload_destination(payload_root, base_path / "bin" / "macos-virtual-machine-supervisor")
    c33_path = payload_destination(payload_root, base_path / "config" / "host-agent-deployment.json")
    c36_path = payload_destination(payload_root, base_path / "config" / "host-edge-proxy-deployment.json")
    c32_path = payload_destination(payload_root, base_path / "config" / "macos-virtual-machine.json")
    c34_path = payload_destination(payload_root, base_path / "release" / "macos-guest-artifact-manifest.json")
    c35_receipt_path = payload_destination(payload_root, base_path / "release" / "guest-artifact-compilation-receipt.json")
    for artifact_name, artifact_path in (
        ("Host Agent", host_agent_path),
        ("Host Edge Proxy", host_edge_proxy_path),
        ("macOS virtual machine supervisor", macos_virtual_machine_supervisor_path),
        ("C33 HostAgentDeploymentConfiguration", c33_path),
        ("C36 HostEdgeProxyDeploymentConfiguration", c36_path),
        ("C32 MacOSVirtualMachineConfiguration", c32_path),
        ("C34 MacOSGuestArtifactManifest", c34_path),
        ("C35 GuestArtifactCompilationReceipt", c35_receipt_path),
    ):
        if not artifact_path.is_file():
            raise MacOSHostPackageVerificationError(artifact_name + " is missing from the package payload")

    c33 = load_json_document(c33_path, "C33 HostAgentDeploymentConfiguration")
    c36 = load_json_document(c36_path, "C36 HostEdgeProxyDeploymentConfiguration")
    c32 = load_json_document(c32_path, "C32 MacOSVirtualMachineConfiguration")
    c34 = load_json_document(c34_path, "C34 MacOSGuestArtifactManifest")
    c35_receipt = load_json_document(c35_receipt_path, "C35 GuestArtifactCompilationReceipt")
    provider = required_object(c33, "provider", "C33")
    if c33.get("schemaVersion") != "v1" or provider.get("kind") != "macos-virtualization":
        raise MacOSHostPackageVerificationError("C33 must be a v1 macos-virtualization deployment configuration")
    if provider.get("macOSVirtualMachineSupervisorExecutablePath") != str(base_path / "bin" / "macos-virtual-machine-supervisor"):
        raise MacOSHostPackageVerificationError("C33 does not name the packaged macOS virtual machine supervisor")
    if provider.get("macOSVirtualMachineConfigurationPath") != str(base_path / "config" / "macos-virtual-machine.json"):
        raise MacOSHostPackageVerificationError("C33 does not name the packaged C32 configuration")
    verify_host_edge_proxy_deployment(c36)
    verify_host_edge_proxy_routes_target_c32_public_service_bridges(c36, c32)

    if c32.get("schemaVersion") != "v1":
        raise MacOSHostPackageVerificationError("C32 schemaVersion must be v1")
    guest_boot_console_capture_path = verify_c32_guest_boot_console_capture(c32, c33)
    guest_runtime_disk_provisioning = verify_c32_guest_runtime_disk_provisioning(
        c32,
        c33,
        base_path,
    )
    if c34.get("schemaVersion") != "v1" or c34.get("architecture") != "arm64" or not isinstance(c34.get("artifactSetId"), str) or not c34["artifactSetId"]:
        raise MacOSHostPackageVerificationError("C34 must identify one v1 arm64 Guest artifact set")
    verify_guest_artifact_compilation_receipt(c34_path, c34, c35_receipt)
    boot = required_object(c32, "boot", "C32")
    verify_manifested_payload_artifact(payload_root, base_path, boot.get("kernelPath"), required_object(c34, "kernel", "C34"), "C32 kernel")
    initial_ramdisk_path = boot.get("initialRamdiskPath")
    initial_ramdisk_digest = c34.get("initialRamdisk")
    if initial_ramdisk_path is None and initial_ramdisk_digest is not None:
        raise MacOSHostPackageVerificationError("C34 initial RAM disk exists but C32 does not name it")
    if initial_ramdisk_path is not None:
        if not isinstance(initial_ramdisk_digest, dict):
            raise MacOSHostPackageVerificationError("C32 initial RAM disk has no C34 digest")
        verify_manifested_payload_artifact(payload_root, base_path, initial_ramdisk_path, initial_ramdisk_digest, "C32 initial RAM disk")

    storage_devices = c32.get("storageDevices")
    storage_digests = c34.get("storageDevices")
    if not isinstance(storage_devices, list) or len(storage_devices) != 2 or not isinstance(storage_digests, list) or len(storage_digests) != 2:
        raise MacOSHostPackageVerificationError("C32/C34 require exactly the root and bootstrap storage declarations")
    storage_digest_by_id = {
        storage_digest.get("id"): storage_digest
        for storage_digest in storage_digests
        if isinstance(storage_digest, dict) and isinstance(storage_digest.get("id"), str)
    }
    if len(storage_digest_by_id) != len(storage_digests):
        raise MacOSHostPackageVerificationError("C34 storage device IDs must be explicit and unique")
    storage_ids: set[str] = set()
    for attachment_index, storage_device in enumerate(storage_devices):
        if not isinstance(storage_device, dict) or not isinstance(storage_device.get("id"), str):
            raise MacOSHostPackageVerificationError("C32 storage device IDs must be explicit")
        storage_id = storage_device["id"]
        storage_ids.add(storage_id)
        digest = storage_digest_by_id.get(storage_id)
        if not isinstance(digest, dict):
            raise MacOSHostPackageVerificationError("C32 storage device " + storage_id + " has no C34 digest")
        verify_c32_storage_device(storage_device, attachment_index)
        verify_c34_storage_digest(digest)
        if (
            storage_device.get("role") != digest.get("role")
            or storage_device.get("storageImageFormat") != digest.get("storageImageFormat")
            or storage_device.get("guestVolumeFileSystem") != digest.get("guestVolumeFileSystem")
        ):
            raise MacOSHostPackageVerificationError("C32 storage attachment intent differs from C34 storage artifact intent")
        if storage_id == "guest-root":
            if storage_device.get("diskImagePath") != guest_runtime_disk_provisioning["runtimeDiskImagePath"]:
                raise MacOSHostPackageVerificationError(
                    "C32 guest-root diskImagePath must name Guest Runtime disk provisioning runtimeDiskImagePath"
                )
            verify_manifested_payload_artifact(
                payload_root,
                base_path,
                guest_runtime_disk_provisioning["releaseArtifactPath"],
                digest,
                "C32 Guest Runtime immutable release root",
            )
            verify_absent_host_runtime_workspace_from_package_payload(
                payload_root,
                guest_runtime_disk_provisioning["runtimeDiskImagePath"],
                "C32 Guest Runtime disk workspace",
            )
            verify_absent_host_runtime_workspace_from_package_payload(
                payload_root,
                guest_runtime_disk_provisioning["provisioningReceiptPath"],
                "C32 Guest Runtime disk provisioning receipt",
            )
        else:
            verify_manifested_payload_artifact(
                payload_root,
                base_path,
                storage_device.get("diskImagePath"),
                digest,
                "C32 storage device " + storage_id,
            )
    if storage_ids != set(storage_digest_by_id):
        raise MacOSHostPackageVerificationError("C32 and C34 name different storage devices")
    return VerifiedMacOSHostPackageHostFilesystemPreparation(
        guest_boot_console_capture_path=guest_boot_console_capture_path,
        declared_host_runtime_directories=declared_host_runtime_directories(
            c33,
            guest_boot_console_capture_path,
            guest_runtime_disk_provisioning,
        ),
        product_version=required_string(
            required_object(c33, "installation", "C33"),
            "productVersion",
            "C33 installation",
        ),
    )


def verify_c32_guest_boot_console_capture(
    virtual_machine: Mapping[str, Any], host_agent_deployment: Mapping[str, Any]
) -> str:
    guest_boot_console_capture = required_object(
        virtual_machine, "guestBootConsoleCapture", "C32"
    )
    capture_path = required_string(
        guest_boot_console_capture, "capturePath", "C32 guestBootConsoleCapture"
    )
    if not is_safe_absolute_path(capture_path):
        raise MacOSHostPackageVerificationError(
            "C32 guestBootConsoleCapture capturePath must be an absolute path without traversal"
        )
    if guest_boot_console_capture.get("writeMode") != "append":
        raise MacOSHostPackageVerificationError(
            "C32 guestBootConsoleCapture writeMode must be append"
        )
    installation = required_object(host_agent_deployment, "installation", "C33")
    data_directory = required_string(installation, "dataDirectory", "C33 installation")
    if not is_safe_absolute_path(data_directory):
        raise MacOSHostPackageVerificationError(
            "C33 installation.dataDirectory must be an absolute path without traversal"
        )
    try:
        relative_path = PurePosixPath(capture_path).relative_to(PurePosixPath(data_directory))
    except ValueError as error:
        raise MacOSHostPackageVerificationError(
            "C32 guestBootConsoleCapture capturePath must be within C33 installation.dataDirectory"
        ) from error
    if relative_path == PurePosixPath("."):
        raise MacOSHostPackageVerificationError(
            "C32 guestBootConsoleCapture capturePath must name a file below C33 installation.dataDirectory"
        )
    return capture_path


def verify_c32_guest_runtime_disk_provisioning(
    virtual_machine: Mapping[str, Any],
    host_agent_deployment: Mapping[str, Any],
    payload_base_path: PurePosixPath,
) -> Mapping[str, str]:
    """Verify the C32 release-to-runtime boundary without materialising state.

    The package owns immutable release files.  The installed supervisor owns
    creation of the C33-data-directory runtime disk and receipt, so neither
    mutable resource may be mistaken for a package payload artifact.
    """

    provisioning = required_object(
        virtual_machine,
        "guestRuntimeDiskProvisioning",
        "C32",
    )
    values = {
        field_name: required_string(
            provisioning,
            field_name,
            "C32 guestRuntimeDiskProvisioning",
        )
        for field_name in (
            "releaseArtifactManifestPath",
            "releaseArtifactPath",
            "runtimeDiskImagePath",
            "provisioningReceiptPath",
        )
    }
    if not all(is_safe_absolute_path(value) for value in values.values()):
        raise MacOSHostPackageVerificationError(
            "C32 Guest Runtime disk provisioning paths must be absolute paths without traversal"
        )
    if len(set(values.values())) != 4:
        raise MacOSHostPackageVerificationError(
            "C32 Guest Runtime disk provisioning paths must name distinct Host resources"
        )
    if provisioning.get("existingRuntimeDiskPolicy") != "retain-when-receipt-matches-release-artifact":
        raise MacOSHostPackageVerificationError(
            "C32 Guest Runtime disk provisioning policy is invalid"
        )
    if values["releaseArtifactManifestPath"] != str(
        payload_base_path / "release" / "macos-guest-artifact-manifest.json"
    ):
        raise MacOSHostPackageVerificationError(
            "C32 Guest Runtime disk provisioning does not name the packaged C34 path"
        )
    if values["releaseArtifactPath"] != str(
        payload_base_path / "release" / "guest-root.raw"
    ):
        raise MacOSHostPackageVerificationError(
            "C32 Guest Runtime disk provisioning does not name the packaged immutable guest-root path"
        )
    installation = required_object(host_agent_deployment, "installation", "C33")
    data_directory = required_string(installation, "dataDirectory", "C33 installation")
    if not is_safe_absolute_path(data_directory):
        raise MacOSHostPackageVerificationError(
            "C33 installation.dataDirectory must be an absolute path without traversal"
        )
    for field_name in ("runtimeDiskImagePath", "provisioningReceiptPath"):
        try:
            relative_path = PurePosixPath(values[field_name]).relative_to(
                PurePosixPath(data_directory)
            )
        except ValueError as error:
            raise MacOSHostPackageVerificationError(
                "C32 Guest Runtime disk provisioning "
                + field_name
                + " must be within C33 installation.dataDirectory"
            ) from error
        if relative_path == PurePosixPath("."):
            raise MacOSHostPackageVerificationError(
                "C32 Guest Runtime disk provisioning "
                + field_name
                + " must name a file below C33 installation.dataDirectory"
            )
    return values


def declared_host_runtime_directories(
    host_agent_deployment: Mapping[str, Any],
    guest_boot_console_capture_path: str,
    guest_runtime_disk_provisioning: Mapping[str, str],
) -> tuple[PurePosixPath, ...]:
    """Return the exact directory-only preparation the postinstall must prove."""

    control = required_object(host_agent_deployment, "control", "C33")
    state_database_path = required_string(control, "stateDatabasePath", "C33 control")
    if not is_safe_absolute_path(state_database_path):
        raise MacOSHostPackageVerificationError(
            "C33 control.stateDatabasePath must be an absolute path without traversal"
        )
    installation = required_object(host_agent_deployment, "installation", "C33")
    data_directory = required_string(installation, "dataDirectory", "C33 installation")
    if not is_safe_absolute_path(data_directory):
        raise MacOSHostPackageVerificationError(
            "C33 installation.dataDirectory must be an absolute path without traversal"
        )
    candidate_directories = (
        PurePosixPath(state_database_path).parent,
        PurePosixPath(data_directory),
        PurePosixPath(guest_boot_console_capture_path).parent,
        PurePosixPath(guest_runtime_disk_provisioning["runtimeDiskImagePath"]).parent,
        PurePosixPath(guest_runtime_disk_provisioning["provisioningReceiptPath"]).parent,
    )
    ordered_directories: list[PurePosixPath] = []
    for directory in candidate_directories:
        if directory not in ordered_directories:
            ordered_directories.append(directory)
    return tuple(ordered_directories)


def verify_absent_host_runtime_workspace_from_package_payload(
    payload_root: Path,
    host_runtime_path: str,
    resource_name: str,
) -> None:
    """Reject a package that pre-populates mutable Guest Runtime Host state."""

    payload_path = payload_destination(payload_root, PurePosixPath(host_runtime_path))
    if payload_path.exists():
        raise MacOSHostPackageVerificationError(
            resource_name + " must not be materialized in the package payload"
        )


def verify_c32_storage_device(storage_device: Mapping[str, Any], attachment_index: int) -> None:
    declared = (
        storage_device.get("id"),
        storage_device.get("role"),
        storage_device.get("storageImageFormat"),
        storage_device.get("guestVolumeFileSystem"),
        storage_device.get("readOnly"),
        storage_device.get("attachmentIndex"),
    )
    expected_by_index = {
        0: ("guest-root", "guest-root-storage", "raw", None, False, 0),
        1: ("guest-product-bootstrap", "guest-product-bootstrap-volume", "raw", "iso9660", True, 1),
    }
    if declared != expected_by_index.get(attachment_index):
        raise MacOSHostPackageVerificationError("C32 storage role, storage image format, Guest volume filesystem, readOnly, and attachmentIndex are invalid")


def verify_c34_storage_digest(storage_digest: Mapping[str, Any]) -> None:
    if (
        storage_digest.get("id"),
        storage_digest.get("role"),
        storage_digest.get("storageImageFormat"),
        storage_digest.get("guestVolumeFileSystem"),
    ) not in {
        ("guest-root", "guest-root-storage", "raw", None),
        ("guest-product-bootstrap", "guest-product-bootstrap-volume", "raw", "iso9660"),
    }:
        raise MacOSHostPackageVerificationError("C34 storage digest role, storage image format, and Guest volume filesystem are invalid")


def verify_guest_artifact_compilation_receipt(
    c34_path: Path,
    c34: Mapping[str, Any],
    c35_receipt: Mapping[str, Any],
) -> None:
    """Keep C35→C34 provenance intact after package materialization."""

    if c35_receipt.get("schemaVersion") != "v1":
        raise MacOSHostPackageVerificationError("C35 receipt schemaVersion must be v1")
    if c35_receipt.get("artifactSetId") != c34.get("artifactSetId"):
        raise MacOSHostPackageVerificationError("C35 receipt artifactSetId does not match C34")
    for field in ("compilationId", "compilationCommandSHA256"):
        value = c35_receipt.get(field)
        if not isinstance(value, str) or not value:
            raise MacOSHostPackageVerificationError("C35 receipt requires " + field)
    verify_receipt_artifact_digest(required_object(c35_receipt, "buildEnvironment", "C35 receipt"), "C35 build environment", "builderExecutableSizeBytes", "builderExecutableSHA256")
    consumed_inputs = c35_receipt.get("consumedInputArtifacts")
    if not isinstance(consumed_inputs, list) or len(consumed_inputs) < 5:
        raise MacOSHostPackageVerificationError("C35 receipt requires at least five consumed input artifacts")
    consumed_ids: set[str] = set()
    for input_artifact in consumed_inputs:
        if not isinstance(input_artifact, dict) or not isinstance(input_artifact.get("id"), str) or not input_artifact["id"]:
            raise MacOSHostPackageVerificationError("C35 consumed input artifact requires id")
        if input_artifact["id"] in consumed_ids:
            raise MacOSHostPackageVerificationError("C35 consumed input artifact ids must be unique")
        consumed_ids.add(input_artifact["id"])
        verify_receipt_artifact_digest(input_artifact, "C35 consumed input artifact " + input_artifact["id"])
    required_guest_product_input_ids = {
        "guest-product-process-supervisor-linux-arm64",
        "guest-product-process-deployment-configuration",
        "guest-product-service-manager-deployment-configuration",
        "guest-product-bootstrap-configuration",
        "guest-product-vitalserver-topology-deployment",
    }
    missing_guest_product_input_ids = sorted(required_guest_product_input_ids - consumed_ids)
    if missing_guest_product_input_ids:
        raise MacOSHostPackageVerificationError(
            "C35 receipt is missing Guest Product process inputs: " + ", ".join(missing_guest_product_input_ids)
        )
    manifest_receipt = required_object(c35_receipt, "macOSGuestArtifactManifest", "C35 receipt")
    if manifest_receipt.get("relativePath") != "macos-guest-artifact-manifest.json":
        raise MacOSHostPackageVerificationError("C35 receipt must name canonical C34 path")
    verify_receipt_artifact_digest(manifest_receipt, "C35 receipt C34")
    if c34_path.stat().st_size != manifest_receipt["sizeBytes"] or sha256_file(c34_path) != manifest_receipt["sha256"]:
        raise MacOSHostPackageVerificationError("C35 receipt C34 digest does not match package C34")


def verify_receipt_artifact_digest(
    artifact: Mapping[str, Any],
    artifact_name: str,
    size_field: str = "sizeBytes",
    sha256_field: str = "sha256",
) -> None:
    size = artifact.get(size_field)
    sha256 = artifact.get(sha256_field)
    if not isinstance(size, int) or size < 1 or not isinstance(sha256, str) or len(sha256) != 64 or any(character not in "0123456789abcdef" for character in sha256):
        raise MacOSHostPackageVerificationError(artifact_name + " digest is invalid")


def verify_host_edge_proxy_deployment(deployment: Mapping[str, Any]) -> None:
    if deployment.get("schemaVersion") != "v1" or not isinstance(deployment.get("proxyId"), str) or not deployment["proxyId"]:
        raise MacOSHostPackageVerificationError("C36 must identify one v1 Host Edge Proxy deployment")
    listener = required_object(deployment, "listener", "C36")
    if listener.get("protocol") != "http" or not isinstance(listener.get("bindHost"), str) or not listener["bindHost"]:
        raise MacOSHostPackageVerificationError("C36 requires an explicit HTTP listener")
    require_port(listener.get("port"), "C36 listener port")
    readiness_path = required_string(deployment, "readinessPath", "C36")
    require_request_path_prefix(readiness_path, "C36 readinessPath")
    if deployment.get("clientIdentityHeaderPolicy") != "replace-with-remote-address":
        raise MacOSHostPackageVerificationError("C36 must explicitly replace inbound client identity headers")
    routes = deployment.get("routes")
    if not isinstance(routes, list) or not routes:
        raise MacOSHostPackageVerificationError("C36 requires at least one explicit route")
    route_ids: set[str] = set()
    route_prefixes: set[str] = set()
    previous_prefix_length = 2**31 - 1
    for route in routes:
        if not isinstance(route, dict):
            raise MacOSHostPackageVerificationError("C36 routes must be objects")
        route_id = required_string(route, "id", "C36 route")
        if route_id in route_ids:
            raise MacOSHostPackageVerificationError("C36 route ids must be unique")
        route_ids.add(route_id)
        prefix = required_string(route, "requestPathPrefix", "C36 route " + route_id)
        require_request_path_prefix(prefix, "C36 route " + route_id + " requestPathPrefix")
        if prefix in route_prefixes:
            raise MacOSHostPackageVerificationError("C36 route requestPathPrefix values must be unique")
        route_prefixes.add(prefix)
        if len(prefix) > previous_prefix_length:
            raise MacOSHostPackageVerificationError("C36 routes must be ordered from most-specific to least-specific requestPathPrefix")
        previous_prefix_length = len(prefix)
        target = required_object(route, "target", "C36 route " + route_id)
        if target.get("scheme") not in {"http", "https"} or not isinstance(target.get("host"), str) or not target["host"]:
            raise MacOSHostPackageVerificationError("C36 route " + route_id + " target is invalid")
        require_port(target.get("port"), "C36 route " + route_id + " target port")
        if route.get("forwardingProtocol") != "http-and-websocket":
            raise MacOSHostPackageVerificationError("C36 route " + route_id + " forwardingProtocol is invalid")
        if route.get("requestHostHeaderPolicy") not in {"preserve-client-host", "target-host"}:
            raise MacOSHostPackageVerificationError("C36 route " + route_id + " requestHostHeaderPolicy is invalid")
        require_positive_integer(route.get("maximumRequestBodyBytes"), "C36 route " + route_id + " maximumRequestBodyBytes")
        require_positive_integer(route.get("upstreamResponseHeaderTimeoutMilliseconds"), "C36 route " + route_id + " upstreamResponseHeaderTimeoutMilliseconds")


def verify_host_edge_proxy_routes_target_c32_public_service_bridges(
    host_edge_proxy_deployment: Mapping[str, Any],
    macos_virtual_machine_configuration: Mapping[str, Any],
) -> None:
    """Keep installed C36 routes bound to C32 Host-local transport names.

    Package composition already proves the three-way C32/C36/C37 relation.
    The expanded PKG contains C32 and C36, so this release verifier repeats the
    part it can observe directly.  It deliberately does not reconstruct C37
    from the compiled Guest artifact or infer a Guest NAT address.
    """

    declared_bridges = macos_virtual_machine_configuration.get(
        "guestPublicServiceHostLocalHTTPBridges"
    )
    if not isinstance(declared_bridges, list) or not declared_bridges:
        raise MacOSHostPackageVerificationError(
            "C32 requires explicit Guest public service Host-local HTTP bridges"
        )
    bridges_by_route_id: dict[str, Mapping[str, Any]] = {}
    for bridge in declared_bridges:
        if not isinstance(bridge, dict):
            raise MacOSHostPackageVerificationError(
                "C32 Guest public service Host-local HTTP bridges must be objects"
            )
        route_id = required_string(
            bridge,
            "routeId",
            "C32 Guest public service Host-local HTTP bridge",
        )
        if route_id in bridges_by_route_id:
            raise MacOSHostPackageVerificationError(
                "C32 Guest public service Host-local HTTP bridge route IDs must be unique"
            )
        if bridge.get("hostLoopbackAddress") != "127.0.0.1":
            raise MacOSHostPackageVerificationError(
                "C32 Guest public service Host-local HTTP bridge must bind 127.0.0.1"
            )
        require_port(
            bridge.get("hostLoopbackPort"),
            "C32 Guest public service Host-local HTTP bridge hostLoopbackPort",
        )
        require_port(
            bridge.get("guestVirtioSocketPort"),
            "C32 Guest public service Host-local HTTP bridge guestVirtioSocketPort",
        )
        bridges_by_route_id[route_id] = bridge

    declared_routes = host_edge_proxy_deployment.get("routes")
    if not isinstance(declared_routes, list):
        raise MacOSHostPackageVerificationError("C36 public routes must be an array")
    routes_by_route_id: dict[str, Mapping[str, Any]] = {}
    for route in declared_routes:
        if not isinstance(route, dict):
            raise MacOSHostPackageVerificationError("C36 public routes must be objects")
        route_id = required_string(route, "id", "C36 route")
        routes_by_route_id[route_id] = route
    if set(routes_by_route_id) != set(bridges_by_route_id):
        raise MacOSHostPackageVerificationError(
            "C32 Guest public service Host-local HTTP bridges and C36 public routes must name the same route IDs"
        )
    for route_id, bridge in bridges_by_route_id.items():
        target = required_object(
            routes_by_route_id[route_id],
            "target",
            "C36 route " + route_id,
        )
        if (
            target.get("scheme") != "http"
            or target.get("host") != bridge["hostLoopbackAddress"]
            or target.get("port") != bridge["hostLoopbackPort"]
        ):
            raise MacOSHostPackageVerificationError(
                "C36 route "
                + route_id
                + " target must match its C32 Guest public service Host-local HTTP bridge"
            )


def verify_c23_macos_host_package_release_identity(
    verification: MacOSHostPackageVerification,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
    c33_product_version: str,
) -> None:
    """Require the emitted PKG and packaged C33 to realize one selected C23 plan."""

    if verification.package.name != macos_host_package_release_plan.expected_package_file_name:
        raise MacOSHostPackageVerificationError(
            "package file name must match C23 MacOSHostPackageReleasePlan expected package file name"
        )
    if c33_product_version != macos_host_package_release_plan.product_version:
        raise MacOSHostPackageVerificationError(
            "C33 installation.productVersion must match C23 MacOSHostPackageReleasePlan product version"
        )


def verify_launchd_service_definitions(
    verification: MacOSHostPackageVerification,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
    payload_root: Path,
) -> None:
    verify_launchd_service_definition(
        payload_root,
        macos_host_package_release_plan.host_agent_launchd_service_label,
        [
            str(verification.payload_base_path / "bin" / "host-agent"),
            "--deployment-configuration",
            str(verification.payload_base_path / "config" / "host-agent-deployment.json"),
        ],
        "Host Agent",
    )
    verify_launchd_service_definition(
        payload_root,
        macos_host_package_release_plan.host_edge_proxy_launchd_service_label,
        [
            str(verification.payload_base_path / "bin" / "host-edge-proxy"),
            "--deployment-configuration",
            str(verification.payload_base_path / "config" / "host-edge-proxy-deployment.json"),
        ],
        "Host Edge Proxy",
    )


def verify_launchd_service_definition(payload_root: Path, service_label: str, expected_arguments: list[str], service_name: str) -> None:
    service_path = payload_root / "Library" / "LaunchDaemons" / (service_label + ".plist")
    if not service_path.is_file():
        raise MacOSHostPackageVerificationError("launchd service definition is missing from the package payload")
    try:
        with service_path.open("rb") as plist_file:
            service_definition = plistlib.load(plist_file)
    except (OSError, plistlib.InvalidFileException) as error:
        raise MacOSHostPackageVerificationError("launchd service definition cannot be read") from error
    if service_definition.get("Label") != service_label:
        raise MacOSHostPackageVerificationError(service_name + " launchd service label does not match the requested package service")
    if service_definition.get("ProgramArguments") != expected_arguments:
        raise MacOSHostPackageVerificationError(service_name + " launchd service does not start the declared packaged executable and deployment configuration")


def verify_package_info_release_identity(
    expanded_package: Path,
    c33_product_version: str,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
) -> None:
    """Require PKG metadata, C23 release identity, and C33 to agree.

    PackageInfo identifier identifies the macOS installer receipt.  It belongs
    to C23 because a clean-host runner must query that exact receipt before it
    can state that the Host was clean; it must not derive the identifier from a
    filename, install path, or launchd label.
    """

    package_info_path = expanded_package / "PackageInfo"
    try:
        package_info = ElementTree.parse(package_info_path).getroot()
    except (OSError, ElementTree.ParseError) as error:
        raise MacOSHostPackageVerificationError(
            "package PackageInfo cannot be read"
        ) from error
    if package_info.get("version") != c33_product_version:
        raise MacOSHostPackageVerificationError(
            "package PackageInfo version must match C33 installation.productVersion"
        )
    if (
        package_info.get("identifier")
        != macos_host_package_release_plan.macos_installer_package_identifier
    ):
        raise MacOSHostPackageVerificationError(
            "package PackageInfo identifier must match C23 MacOSHostPackageReleasePlan macOS installer package identifier"
        )


def verify_postinstall_service_reconciliation(
    verification: MacOSHostPackageVerification,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
    expanded_package: Path,
    host_filesystem_preparation: VerifiedMacOSHostPackageHostFilesystemPreparation,
) -> None:
    postinstall_path = expanded_package / "Scripts" / "postinstall"
    try:
        postinstall = postinstall_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise MacOSHostPackageVerificationError("package postinstall service reconciliation script is missing") from error
    required_lines = [
        "set -eu",
        "if [ \"$launchctl_bootout_status\" -ne 0 ] && [ \"$launchctl_bootout_status\" -ne 3 ]; then",
        "/usr/bin/install -d -m 0750",
        "/usr/bin/touch '"
        + host_filesystem_preparation.guest_boot_console_capture_path.replace("'", "'\\''")
        + "'",
    ]
    required_lines.extend(
        "'" + str(directory).replace("'", "'\\''") + "'"
        for directory in host_filesystem_preparation.declared_host_runtime_directories
    )
    for service_label in (
        macos_host_package_release_plan.host_agent_launchd_service_label,
        macos_host_package_release_plan.host_edge_proxy_launchd_service_label,
    ):
        service_target = "system/" + service_label
        required_lines.extend(
            [
                "/bin/launchctl bootout '" + service_target + "' >/dev/null 2>&1 || launchctl_bootout_status=$?",
                "/bin/launchctl bootstrap system '" + str(PurePosixPath("/Library/LaunchDaemons") / (service_label + ".plist")) + "'",
            ]
        )
    if any(line not in postinstall for line in required_lines):
        raise MacOSHostPackageVerificationError(
            "package postinstall does not explicitly prepare the Host filesystem and reconcile launchd services"
        )
    if "|| true" in postinstall:
        raise MacOSHostPackageVerificationError("package postinstall must not hide launchd reconciliation failures")


def verify_manifested_payload_artifact(
    payload_root: Path,
    payload_base_path: PurePosixPath,
    declared_path: Any,
    digest: Mapping[str, Any],
    artifact_name: str,
) -> None:
    if not isinstance(declared_path, str) or not is_safe_absolute_path(declared_path):
        raise MacOSHostPackageVerificationError(artifact_name + " path must be an absolute path without traversal")
    declared = PurePosixPath(declared_path)
    try:
        declared.relative_to(payload_base_path)
    except ValueError as error:
        raise MacOSHostPackageVerificationError(artifact_name + " path is outside the package payload base") from error
    artifact = payload_destination(payload_root, declared)
    if not artifact.is_file():
        raise MacOSHostPackageVerificationError(artifact_name + " is missing from the package payload")
    expected_size = digest.get("sizeBytes")
    expected_sha256 = digest.get("sha256")
    if not isinstance(expected_size, int) or expected_size < 1 or not isinstance(expected_sha256, str):
        raise MacOSHostPackageVerificationError(artifact_name + " C34 digest is invalid")
    if artifact.stat().st_size != expected_size or sha256_file(artifact) != expected_sha256:
        raise MacOSHostPackageVerificationError(artifact_name + " does not match C34")


def payload_destination(payload_root: Path, absolute_target_path: PurePosixPath) -> Path:
    if not absolute_target_path.is_absolute():
        raise MacOSHostPackageVerificationError("package target path must be absolute")
    return payload_root.joinpath(*absolute_target_path.parts[1:])


def load_json_document(path: Path, document_name: str) -> Mapping[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MacOSHostPackageVerificationError(document_name + " cannot be read as JSON") from error
    if not isinstance(document, dict):
        raise MacOSHostPackageVerificationError(document_name + " must be a JSON object")
    return document


def required_object(document: Mapping[str, Any], name: str, document_name: str) -> Mapping[str, Any]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise MacOSHostPackageVerificationError(document_name + " requires object " + name)
    return value


def required_string(document: Mapping[str, Any], name: str, document_name: str) -> str:
    value = document.get(name)
    if not isinstance(value, str) or not value:
        raise MacOSHostPackageVerificationError(document_name + " requires non-empty " + name)
    return value


def require_positive_integer(value: Any, field_name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise MacOSHostPackageVerificationError(field_name + " must be a positive integer")


def require_port(value: Any, field_name: str) -> None:
    require_positive_integer(value, field_name)
    if value > 65535:
        raise MacOSHostPackageVerificationError(field_name + " must not exceed 65535")


def require_request_path_prefix(value: str, field_name: str) -> None:
    if not value.startswith("/") or "?" in value or "#" in value or ".." in PurePosixPath(value).parts:
        raise MacOSHostPackageVerificationError(field_name + " must be an absolute request path prefix without query, fragment, or traversal")


def is_safe_absolute_path(value: str) -> bool:
    return value.startswith("/") and "\\" not in value and ".." not in PurePosixPath(value).parts


def sha256_file(source: Path) -> str:
    digest = hashlib.sha256()
    with source.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_arguments(arguments: list[str]) -> MacOSHostPackageVerification:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True)
    parser.add_argument("--pkgutil-executable", required=True)
    parser.add_argument("--release-delivery-plans-document", required=True)
    parser.add_argument("--release-delivery-plan-id", required=True)
    parser.add_argument("--payload-base-path", required=True)
    parsed = parser.parse_args(arguments)
    return MacOSHostPackageVerification(
        package=Path(parsed.package),
        pkgutil_executable=Path(parsed.pkgutil_executable),
        release_delivery_plans_document=Path(parsed.release_delivery_plans_document),
        release_delivery_plan_id=parsed.release_delivery_plan_id,
        payload_base_path=PurePosixPath(parsed.payload_base_path),
    )


def main(arguments: list[str]) -> int:
    try:
        result = verify_macos_host_package(parse_arguments(arguments))
    except MacOSHostPackageVerificationError as error:
        print("macOS Host package verification failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
