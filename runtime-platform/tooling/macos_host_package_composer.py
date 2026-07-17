"""Compose one explicit macOS Host PKG from C32–C44 and external-topology C46 artifacts.

This release-tool adapter owns staging directories and pkgbuild invocation. It
does not compile services, create deployment configuration, or claim a C24
clean-host proof. Callers must provide the already-built binaries, Guest assets,
the Host deployment documents, C34 Guest identity, C35 compiler receipt that
correlates C34 and the C37/C38/C39/C44 Guest Product inputs—and, when selected,
C46—to one selected Guest builder execution.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Iterable, Mapping
import xml.etree.ElementTree as ElementTree

from tooling.contracts import ContractRepository, ContractToolError
from tooling import macos_installer_component_cpio
from tooling.product_delivery_release_plan import (
    MacOSHostPackageReleasePlan,
    ProductDeliveryReleasePlanError,
    load_selected_macos_host_package_release_plan,
)


class MacOSHostPackageCompositionError(RuntimeError):
    """A package input is missing, invalid, or incompatible with C32/C33."""


MACOS_INSTALLER_XAR_EXECUTABLE = Path("/usr/bin/xar")
MACOS_INSTALLER_MKBOM_EXECUTABLE = Path("/usr/bin/mkbom")


@dataclass(frozen=True)
class MacOSVirtualMachineSupervisorCodeSigning:
    """The release-build signature required by the long-lived VM owner process.

    This is deliberately separate from the PKG signature.  `pkgbuild --sign`
    identifies an installer, whereas this signature gives the installed
    `macos-virtual-machine-supervisor` process its Apple Virtualization
    entitlement at the point where it creates `VZVirtualMachine`.
    """

    mode: str
    signing_identity: str | None
    codesign_executable: Path | None
    virtualization_entitlements: Path | None


@dataclass(frozen=True)
class MacOSInstallerPackageSigning:
    """The release-build signature applied after payload inventory recomposition.

    A component package must first be rebuilt from its declared Installer file
    inventory.  Signing the pre-recomposition ``pkgbuild`` candidate would
    make its signature stale, so the final installer signature is owned by
    ``productsign`` and is intentionally distinct from VM Supervisor code
    signing.
    """

    mode: str
    signing_identity: str | None
    productsign_executable: Path | None


@dataclass(frozen=True)
class MacOSHostPackageComposition:
    release_delivery_plans_document: Path
    release_delivery_plan_id: str
    payload_base_path: PurePosixPath
    host_agent_binary: Path
    host_edge_proxy_binary: Path
    macos_virtual_machine_supervisor_binary: Path
    host_agent_deployment_configuration: Path
    host_edge_proxy_deployment_configuration: Path
    macos_virtual_machine_configuration: Path
    guest_artifact_manifest: Path
    guest_artifact_compilation_receipt: Path
    guest_product_process_supervisor_artifact: Path
    guest_product_process_deployment_configuration: Path
    guest_product_service_manager_deployment_configuration: Path
    guest_product_bootstrap_configuration: Path
    guest_product_vitalserver_topology_deployment: Path
    external_vitalserver_delivery_configuration: Path | None
    guest_kernel_source: Path
    guest_initial_ramdisk_source: Path | None
    guest_storage_sources: Mapping[str, Path]
    output_package: Path
    pkgbuild_executable: Path
    macos_installer_package_signing: MacOSInstallerPackageSigning
    macos_virtual_machine_supervisor_code_signing: MacOSVirtualMachineSupervisorCodeSigning
    replace_output: bool


@dataclass(frozen=True)
class MacOSHostPackageDocuments:
    macos_host_package_release_plan: MacOSHostPackageReleasePlan
    host_agent_deployment: Mapping[str, Any]
    host_edge_proxy_deployment: Mapping[str, Any]
    virtual_machine: Mapping[str, Any]
    guest_artifact_manifest: Mapping[str, Any]
    guest_artifact_compilation_receipt: Mapping[str, Any]
    guest_product_process_deployment: Mapping[str, Any]
    guest_product_service_manager_deployment: Mapping[str, Any]
    guest_product_bootstrap_configuration: Mapping[str, Any]
    guest_product_vitalserver_topology_deployment: Mapping[str, Any]
    external_vitalserver_delivery_configuration: Mapping[str, Any] | None


def load_macos_host_package_documents(composition: MacOSHostPackageComposition) -> MacOSHostPackageDocuments:
    try:
        macos_host_package_release_plan = (
            load_selected_macos_host_package_release_plan(
                composition.release_delivery_plans_document,
                composition.release_delivery_plan_id,
            )
        )
    except ProductDeliveryReleasePlanError as error:
        raise MacOSHostPackageCompositionError(str(error)) from error
    host_agent_deployment = load_json_document(composition.host_agent_deployment_configuration, "C33 HostAgentDeploymentConfiguration")
    host_edge_proxy_deployment = load_json_document(composition.host_edge_proxy_deployment_configuration, "C36 HostEdgeProxyDeploymentConfiguration")
    virtual_machine = load_json_document(composition.macos_virtual_machine_configuration, "C32 MacOSVirtualMachineConfiguration")
    guest_artifact_manifest = load_json_document(composition.guest_artifact_manifest, "C34 MacOSGuestArtifactManifest")
    guest_artifact_compilation_receipt = load_json_document(composition.guest_artifact_compilation_receipt, "C35 GuestArtifactCompilationReceipt")
    guest_product_process_deployment = load_json_document(
        composition.guest_product_process_deployment_configuration,
        "C37 GuestProductProcessDeploymentConfiguration",
    )
    guest_product_service_manager_deployment = load_json_document(
        composition.guest_product_service_manager_deployment_configuration,
        "C38 GuestProductServiceManagerDeploymentConfiguration",
    )
    guest_product_bootstrap_configuration = load_json_document(
        composition.guest_product_bootstrap_configuration,
        "C39 GuestProductBootstrapConfiguration",
    )
    guest_product_vitalserver_topology_deployment = load_json_document(
        composition.guest_product_vitalserver_topology_deployment,
        "C44 GuestProductVitalServerTopologyDeployment",
    )
    external_vitalserver_delivery_configuration = (
        load_json_document(
            composition.external_vitalserver_delivery_configuration,
            "C46 ExternalVitalServerDeliveryConfiguration",
        )
        if composition.external_vitalserver_delivery_configuration is not None
        else None
    )
    validate_macos_host_package_documents(
        composition,
        host_agent_deployment,
        host_edge_proxy_deployment,
        virtual_machine,
        guest_artifact_manifest,
        guest_artifact_compilation_receipt,
        guest_product_process_deployment,
        guest_product_service_manager_deployment,
        guest_product_bootstrap_configuration,
        guest_product_vitalserver_topology_deployment,
        external_vitalserver_delivery_configuration,
        macos_host_package_release_plan,
    )
    return MacOSHostPackageDocuments(
        macos_host_package_release_plan=macos_host_package_release_plan,
        host_agent_deployment=host_agent_deployment,
        host_edge_proxy_deployment=host_edge_proxy_deployment,
        virtual_machine=virtual_machine,
        guest_artifact_manifest=guest_artifact_manifest,
        guest_artifact_compilation_receipt=guest_artifact_compilation_receipt,
        guest_product_process_deployment=guest_product_process_deployment,
        guest_product_service_manager_deployment=guest_product_service_manager_deployment,
        guest_product_bootstrap_configuration=guest_product_bootstrap_configuration,
        guest_product_vitalserver_topology_deployment=guest_product_vitalserver_topology_deployment,
        external_vitalserver_delivery_configuration=external_vitalserver_delivery_configuration,
    )


def validate_macos_host_package_documents(
    composition: MacOSHostPackageComposition,
    host_agent_deployment: Mapping[str, Any],
    host_edge_proxy_deployment: Mapping[str, Any],
    virtual_machine: Mapping[str, Any],
    guest_artifact_manifest: Mapping[str, Any],
    guest_artifact_compilation_receipt: Mapping[str, Any],
    guest_product_process_deployment: Mapping[str, Any],
    guest_product_service_manager_deployment: Mapping[str, Any],
    guest_product_bootstrap_configuration: Mapping[str, Any],
    guest_product_vitalserver_topology_deployment: Mapping[str, Any],
    external_vitalserver_delivery_configuration: Mapping[str, Any] | None,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
) -> None:
    if host_agent_deployment.get("schemaVersion") != "v1" or virtual_machine.get("schemaVersion") != "v1":
        raise MacOSHostPackageCompositionError("C32 and C33 schemaVersion must be v1")
    validate_product_contract_document(
        "macos-virtual-machine-configuration.schema.json",
        "C32",
        virtual_machine,
    )
    provider = required_object(host_agent_deployment, "provider", "C33")
    if provider.get("kind") != "macos-virtualization":
        raise MacOSHostPackageCompositionError("C33 provider kind must be macos-virtualization for the macOS package composer")
    expected_c32_path = composition.payload_base_path / "config" / "macos-virtual-machine.json"
    if provider.get("macOSVirtualMachineConfigurationPath") != str(expected_c32_path):
        raise MacOSHostPackageCompositionError("C33 must name the packaged C32 path exactly")
    expected_bridge_path = composition.payload_base_path / "bin" / "macos-virtual-machine-supervisor"
    if provider.get("macOSVirtualMachineSupervisorExecutablePath") != str(expected_bridge_path):
        raise MacOSHostPackageCompositionError("C33 must name the packaged macOS virtual machine supervisor path exactly")
    control = required_object(host_agent_deployment, "control", "C33")
    installation = required_object(host_agent_deployment, "installation", "C33")
    if (
        required_string(installation, "productVersion", "C33 installation")
        != macos_host_package_release_plan.product_version
    ):
        raise MacOSHostPackageCompositionError(
            "C23 MacOSHostPackageReleasePlan product version must match C33 installation.productVersion"
        )
    for field, value in (("stateDatabasePath", control.get("stateDatabasePath")), ("dataDirectory", installation.get("dataDirectory"))):
        require_safe_absolute_path(value, "C33 " + field)
    validate_host_edge_proxy_deployment(host_edge_proxy_deployment)
    validate_guest_product_process_deployment(guest_product_process_deployment)
    validate_packaged_guest_public_service_process_ownership(
        guest_product_process_deployment
    )
    validate_packaged_guest_runtime_control_transport(
        host_agent_deployment,
        virtual_machine,
        guest_product_process_deployment,
    )
    validate_packaged_guest_public_service_transport(
        host_edge_proxy_deployment,
        virtual_machine,
        guest_product_process_deployment,
    )
    validate_guest_product_service_manager_deployment(
        guest_product_service_manager_deployment
    )
    validate_guest_product_bootstrap_configuration(
        guest_product_bootstrap_configuration
    )
    validate_guest_product_vitalserver_topology_deployment(
        guest_product_vitalserver_topology_deployment
    )
    if external_vitalserver_delivery_configuration is not None:
        validate_external_vitalserver_delivery_configuration(
            external_vitalserver_delivery_configuration
        )
    validate_guest_product_vitalserver_delivery_bootstrap_composition(
        guest_product_process_deployment,
        guest_product_bootstrap_configuration,
        guest_product_vitalserver_topology_deployment,
        external_vitalserver_delivery_configuration,
    )

    boot = required_object(virtual_machine, "boot", "C32")
    kernel_path = boot.get("kernelPath")
    require_payload_path(composition.payload_base_path, kernel_path, "C32 boot.kernelPath")
    initial_ramdisk_path = boot.get("initialRamdiskPath")
    if initial_ramdisk_path is None and composition.guest_initial_ramdisk_source is not None:
        raise MacOSHostPackageCompositionError("C32 has no initialRamdiskPath but an initial RAM disk source was supplied")
    if initial_ramdisk_path is not None:
        require_payload_path(composition.payload_base_path, initial_ramdisk_path, "C32 boot.initialRamdiskPath")
        if composition.guest_initial_ramdisk_source is None:
            raise MacOSHostPackageCompositionError("C32 initialRamdiskPath requires an explicit initial RAM disk source")
    validate_c32_guest_boot_console_capture(virtual_machine, host_agent_deployment)
    validate_c32_guest_runtime_disk_provisioning(
        composition,
        virtual_machine,
        host_agent_deployment,
    )

    storage_devices = virtual_machine.get("storageDevices")
    if not isinstance(storage_devices, list) or len(storage_devices) != 2:
        raise MacOSHostPackageCompositionError("C32 storageDevices must declare exactly the root and bootstrap volumes")
    storage_ids: set[str] = set()
    for attachment_index, device in enumerate(storage_devices):
        if not isinstance(device, dict) or not isinstance(device.get("id"), str):
            raise MacOSHostPackageCompositionError("every C32 storage device must have an explicit id")
        storage_id = device["id"]
        if storage_id in storage_ids:
            raise MacOSHostPackageCompositionError("C32 storage device ids must be unique")
        storage_ids.add(storage_id)
        validate_c32_storage_device(device, attachment_index)
        if storage_id != "guest-root":
            require_payload_path(
                composition.payload_base_path,
                device.get("diskImagePath"),
                "C32 storage device " + storage_id,
            )
    if set(composition.guest_storage_sources) != storage_ids:
        raise MacOSHostPackageCompositionError("every C32 storage device must have exactly one source artifact")
    validate_guest_artifact_manifest(virtual_machine, guest_artifact_manifest)
    validate_guest_artifact_compilation_receipt(
        composition.guest_artifact_manifest,
        guest_artifact_manifest,
        guest_artifact_compilation_receipt,
        composition.guest_product_process_supervisor_artifact,
        composition.guest_product_process_deployment_configuration,
        composition.guest_product_service_manager_deployment_configuration,
        composition.guest_product_bootstrap_configuration,
        composition.guest_product_vitalserver_topology_deployment,
        composition.external_vitalserver_delivery_configuration,
    )


def validate_c32_guest_boot_console_capture(
    virtual_machine: Mapping[str, Any],
    host_agent_deployment: Mapping[str, Any],
) -> None:
    guest_boot_console_capture = required_object(
        virtual_machine, "guestBootConsoleCapture", "C32"
    )
    capture_path = required_string(
        guest_boot_console_capture, "capturePath", "C32 guestBootConsoleCapture"
    )
    require_safe_absolute_path(capture_path, "C32 guestBootConsoleCapture capturePath")
    if guest_boot_console_capture.get("writeMode") != "append":
        raise MacOSHostPackageCompositionError(
            "C32 guestBootConsoleCapture writeMode must be append"
        )
    installation = required_object(host_agent_deployment, "installation", "C33")
    data_directory = required_string(installation, "dataDirectory", "C33 installation")
    require_path_within_directory(
        capture_path,
        data_directory,
        "C32 guestBootConsoleCapture capturePath",
    )


def validate_c32_guest_runtime_disk_provisioning(
    composition: MacOSHostPackageComposition,
    virtual_machine: Mapping[str, Any],
    host_agent_deployment: Mapping[str, Any],
) -> None:
    """Keep immutable release bytes separate from Host-persistent VM state.

    C32 is the owner of this deployment declaration.  The package composer only
    accepts the release artifacts in its payload; the runtime disk and receipt
    belong below C33's Host data directory and are created by the macOS
    supervisor's GuestRuntimeDiskProvisioner after installation.
    """

    provisioning = required_object(
        virtual_machine,
        "guestRuntimeDiskProvisioning",
        "C32",
    )
    release_manifest_path = required_string(
        provisioning,
        "releaseArtifactManifestPath",
        "C32 guestRuntimeDiskProvisioning",
    )
    release_artifact_path = required_string(
        provisioning,
        "releaseArtifactPath",
        "C32 guestRuntimeDiskProvisioning",
    )
    runtime_disk_path = required_string(
        provisioning,
        "runtimeDiskImagePath",
        "C32 guestRuntimeDiskProvisioning",
    )
    receipt_path = required_string(
        provisioning,
        "provisioningReceiptPath",
        "C32 guestRuntimeDiskProvisioning",
    )
    for field_name, value in (
        ("releaseArtifactManifestPath", release_manifest_path),
        ("releaseArtifactPath", release_artifact_path),
        ("runtimeDiskImagePath", runtime_disk_path),
        ("provisioningReceiptPath", receipt_path),
    ):
        require_safe_absolute_path(
            value,
            "C32 guestRuntimeDiskProvisioning " + field_name,
        )
    if len({release_manifest_path, release_artifact_path, runtime_disk_path, receipt_path}) != 4:
        raise MacOSHostPackageCompositionError(
            "C32 guestRuntimeDiskProvisioning paths must name distinct Host resources"
        )
    if provisioning.get("existingRuntimeDiskPolicy") != "retain-when-receipt-matches-release-artifact":
        raise MacOSHostPackageCompositionError(
            "C32 guestRuntimeDiskProvisioning must declare retain-when-receipt-matches-release-artifact"
        )
    if release_manifest_path != str(
        composition.payload_base_path / "release" / "macos-guest-artifact-manifest.json"
    ):
        raise MacOSHostPackageCompositionError(
            "C32 guestRuntimeDiskProvisioning releaseArtifactManifestPath must name the packaged C34 path exactly"
        )
    if release_artifact_path != str(composition.payload_base_path / "release" / "guest-root.raw"):
        raise MacOSHostPackageCompositionError(
            "C32 guestRuntimeDiskProvisioning releaseArtifactPath must name the packaged immutable guest-root path exactly"
        )
    installation = required_object(host_agent_deployment, "installation", "C33")
    data_directory = required_string(installation, "dataDirectory", "C33 installation")
    require_path_within_directory(
        runtime_disk_path,
        data_directory,
        "C32 guestRuntimeDiskProvisioning runtimeDiskImagePath",
    )
    require_path_within_directory(
        receipt_path,
        data_directory,
        "C32 guestRuntimeDiskProvisioning provisioningReceiptPath",
    )
    storage_devices = virtual_machine.get("storageDevices")
    if not isinstance(storage_devices, list):
        raise MacOSHostPackageCompositionError(
            "C32 storageDevices must be declared before Guest Runtime disk provisioning is validated"
        )
    root_devices = [
        device
        for device in storage_devices
        if isinstance(device, dict) and device.get("id") == "guest-root"
    ]
    if len(root_devices) != 1 or root_devices[0].get("diskImagePath") != runtime_disk_path:
        raise MacOSHostPackageCompositionError(
            "C32 guest-root diskImagePath must name Guest Runtime disk provisioning runtimeDiskImagePath"
        )


def compose_host_agent_launchd_service_definition(
    composition: MacOSHostPackageComposition,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
) -> dict[str, Any]:
    return {
        "Label": macos_host_package_release_plan.host_agent_launchd_service_label,
        "ProgramArguments": [
            str(composition.payload_base_path / "bin" / "host-agent"),
            "--deployment-configuration",
            str(composition.payload_base_path / "config" / "host-agent-deployment.json"),
        ],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ProcessType": "Background",
    }


def compose_host_edge_proxy_launchd_service_definition(
    composition: MacOSHostPackageComposition,
    macos_host_package_release_plan: MacOSHostPackageReleasePlan,
) -> dict[str, Any]:
    return {
        "Label": macos_host_package_release_plan.host_edge_proxy_launchd_service_label,
        "ProgramArguments": [
            str(composition.payload_base_path / "bin" / "host-edge-proxy"),
            "--deployment-configuration",
            str(composition.payload_base_path / "config" / "host-edge-proxy-deployment.json"),
        ],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ProcessType": "Background",
    }


def validate_host_edge_proxy_deployment(deployment: Mapping[str, Any]) -> None:
    """Keep a packaged C36 complete; Host Edge Proxy has no implicit route."""

    if deployment.get("schemaVersion") != "v1":
        raise MacOSHostPackageCompositionError("C36 schemaVersion must be v1")
    required_string(deployment, "proxyId", "C36")
    listener = required_object(deployment, "listener", "C36")
    if listener.get("protocol") != "http":
        raise MacOSHostPackageCompositionError("C36 listener protocol must be http")
    required_string(listener, "bindHost", "C36 listener")
    require_port(listener.get("port"), "C36 listener port")
    readiness_path = required_string(deployment, "readinessPath", "C36")
    require_request_path_prefix(readiness_path, "C36 readinessPath")
    if deployment.get("clientIdentityHeaderPolicy") != "replace-with-remote-address":
        raise MacOSHostPackageCompositionError("C36 must explicitly replace inbound client identity headers")
    routes = deployment.get("routes")
    if not isinstance(routes, list) or not routes:
        raise MacOSHostPackageCompositionError("C36 requires at least one explicit route")
    route_ids: set[str] = set()
    route_prefixes: set[str] = set()
    previous_prefix_length = 2**31 - 1
    for route in routes:
        if not isinstance(route, dict):
            raise MacOSHostPackageCompositionError("C36 routes must be objects")
        route_id = required_string(route, "id", "C36 route")
        if route_id in route_ids:
            raise MacOSHostPackageCompositionError("C36 route ids must be unique")
        route_ids.add(route_id)
        prefix = required_string(route, "requestPathPrefix", "C36 route " + route_id)
        require_request_path_prefix(prefix, "C36 route " + route_id + " requestPathPrefix")
        if prefix in route_prefixes:
            raise MacOSHostPackageCompositionError("C36 route requestPathPrefix values must be unique")
        route_prefixes.add(prefix)
        if len(prefix) > previous_prefix_length:
            raise MacOSHostPackageCompositionError("C36 routes must be ordered from most-specific to least-specific requestPathPrefix")
        previous_prefix_length = len(prefix)
        target = required_object(route, "target", "C36 route " + route_id)
        if target.get("scheme") not in {"http", "https"}:
            raise MacOSHostPackageCompositionError("C36 route " + route_id + " target scheme is invalid")
        required_string(target, "host", "C36 route " + route_id + " target")
        require_port(target.get("port"), "C36 route " + route_id + " target port")
        if route.get("forwardingProtocol") != "http-and-websocket":
            raise MacOSHostPackageCompositionError("C36 route " + route_id + " forwardingProtocol must be http-and-websocket")
        if route.get("requestHostHeaderPolicy") not in {"preserve-client-host", "target-host"}:
            raise MacOSHostPackageCompositionError("C36 route " + route_id + " requestHostHeaderPolicy is invalid")
        require_positive_integer(route.get("maximumRequestBodyBytes"), "C36 route " + route_id + " maximumRequestBodyBytes")
        require_positive_integer(route.get("upstreamResponseHeaderTimeoutMilliseconds"), "C36 route " + route_id + " upstreamResponseHeaderTimeoutMilliseconds")


def validate_packaged_guest_runtime_control_transport(
    host_agent_deployment: Mapping[str, Any],
    virtual_machine: Mapping[str, Any],
    guest_product_process_deployment: Mapping[str, Any],
) -> None:
    """Bind C33, C32, and C37 without pretending a NAT address is a contract.

    C33 is the Host Agent's HTTP client endpoint. C32 owns the Host-loopback
    HTTP-to-virtio-socket bridge, and C37 owns the Guest's virtio-socket
    listener. The package must prove their explicit identities agree. The
    Guest Runtime TCP listener is a separate Guest network binding and must
    not be used to imply a macOS NAT-reachable Guest address.
    """

    guest_runtime_control_endpoint = required_object(
        host_agent_deployment,
        "guestRuntimeControlEndpoint",
        "C33",
    )
    if guest_runtime_control_endpoint.get("scheme") != "http":
        raise MacOSHostPackageCompositionError(
            "C33 Guest Runtime Control endpoint scheme must be http because the packaged C37 Guest Runtime listener has no TLS adapter"
        )
    bridge = required_object(
        virtual_machine,
        "guestRuntimeControlHostLocalHTTPBridge",
        "C32",
    )
    host_loopback_address = required_string(
        bridge,
        "hostLoopbackAddress",
        "C32 Guest Runtime control Host-local HTTP bridge",
    )
    host_loopback_port = bridge.get("hostLoopbackPort")
    guest_virtio_socket_port = bridge.get("guestVirtioSocketPort")
    require_port(host_loopback_port, "C32 Guest Runtime control Host-local HTTP bridge hostLoopbackPort")
    require_port(guest_virtio_socket_port, "C32 Guest Runtime control Host-local HTTP bridge guestVirtioSocketPort")
    if guest_runtime_control_endpoint.get("host") != host_loopback_address:
        raise MacOSHostPackageCompositionError(
            "C33 Guest Runtime Control endpoint host must match C32 Guest Runtime control Host-local HTTP bridge hostLoopbackAddress"
        )
    if guest_runtime_control_endpoint.get("port") != host_loopback_port:
        raise MacOSHostPackageCompositionError(
            "C33 Guest Runtime Control endpoint port must match C32 Guest Runtime control Host-local HTTP bridge hostLoopbackPort"
        )
    guest_runtime = required_object(
        guest_product_process_deployment,
        "guestRuntime",
        "C37",
    )
    guest_runtime_control_virtio_socket_listener = required_object(
        guest_runtime,
        "controlVirtioSocketListener",
        "C37 Guest Runtime",
    )
    if guest_runtime_control_virtio_socket_listener.get("port") != guest_virtio_socket_port:
        raise MacOSHostPackageCompositionError(
            "C32 Guest Runtime control Host-local HTTP bridge guestVirtioSocketPort must match C37 Guest Runtime controlVirtioSocketListener port"
        )


def validate_packaged_guest_public_service_transport(
    host_edge_proxy_deployment: Mapping[str, Any],
    virtual_machine: Mapping[str, Any],
    guest_product_process_deployment: Mapping[str, Any],
) -> None:
    """Bind each C36 public route to its C32 Host bridge and C37 listener.

    C36 owns public HTTP routing, C32 owns Host-loopback-to-virtio transport,
    and C37 owns the Guest public-service socket listener.  A macOS package
    cannot let any of the three infer a NAT Guest address or select a port from
    another declaration.
    """

    declared_host_local_bridges = virtual_machine.get(
        "guestPublicServiceHostLocalHTTPBridges"
    )
    declared_public_routes = host_edge_proxy_deployment.get("routes")
    guest_runtime = required_object(
        guest_product_process_deployment,
        "guestRuntime",
        "C37",
    )
    declared_guest_virtio_socket_listeners = guest_runtime.get(
        "publicServiceVirtioSocketBridges"
    )
    if not isinstance(declared_host_local_bridges, list):
        raise MacOSHostPackageCompositionError(
            "C32 Guest public service Host-local HTTP bridges must be an array"
        )
    if not isinstance(declared_public_routes, list):
        raise MacOSHostPackageCompositionError("C36 public routes must be an array")
    if not isinstance(declared_guest_virtio_socket_listeners, list):
        raise MacOSHostPackageCompositionError(
            "C37 Guest public service virtio socket listeners must be an array"
        )

    host_local_bridge_by_route_id: dict[str, Mapping[str, Any]] = {}
    for bridge in declared_host_local_bridges:
        if not isinstance(bridge, dict):
            raise MacOSHostPackageCompositionError(
                "every C32 Guest public service Host-local HTTP bridge must be an object"
            )
        route_id = required_string(
            bridge,
            "routeId",
            "C32 Guest public service Host-local HTTP bridge",
        )
        if route_id in host_local_bridge_by_route_id:
            raise MacOSHostPackageCompositionError(
                "C32 Guest public service Host-local HTTP bridge route IDs must be unique"
            )
        host_local_bridge_by_route_id[route_id] = bridge

    public_route_by_route_id: dict[str, Mapping[str, Any]] = {}
    for route in declared_public_routes:
        if not isinstance(route, dict):
            raise MacOSHostPackageCompositionError("every C36 public route must be an object")
        route_id = required_string(route, "id", "C36 public route")
        if route_id in public_route_by_route_id:
            raise MacOSHostPackageCompositionError("C36 public route IDs must be unique")
        public_route_by_route_id[route_id] = route

    guest_virtio_socket_listener_by_route_id: dict[str, Mapping[str, Any]] = {}
    for listener in declared_guest_virtio_socket_listeners:
        if not isinstance(listener, dict):
            raise MacOSHostPackageCompositionError(
                "every C37 Guest public service virtio socket listener must be an object"
            )
        route_id = required_string(
            listener,
            "routeId",
            "C37 Guest public service virtio socket listener",
        )
        if route_id in guest_virtio_socket_listener_by_route_id:
            raise MacOSHostPackageCompositionError(
                "C37 Guest public service virtio socket listener route IDs must be unique"
            )
        guest_virtio_socket_listener_by_route_id[route_id] = listener

    declared_route_ids = set(host_local_bridge_by_route_id)
    if (
        declared_route_ids != set(public_route_by_route_id)
        or declared_route_ids != set(guest_virtio_socket_listener_by_route_id)
    ):
        raise MacOSHostPackageCompositionError(
            "C32 Guest public service bridges, C36 public routes, and C37 Guest public service virtio socket listeners must name the same route IDs"
        )

    for route_id in sorted(declared_route_ids):
        host_local_bridge = host_local_bridge_by_route_id[route_id]
        public_route = public_route_by_route_id[route_id]
        guest_virtio_socket_listener = guest_virtio_socket_listener_by_route_id[
            route_id
        ]
        public_route_target = required_object(
            public_route,
            "target",
            "C36 public route " + route_id,
        )
        if (
            public_route_target.get("scheme") != "http"
            or public_route_target.get("host")
            != host_local_bridge.get("hostLoopbackAddress")
            or public_route_target.get("port")
            != host_local_bridge.get("hostLoopbackPort")
        ):
            raise MacOSHostPackageCompositionError(
                "C36 public route "
                + route_id
                + " target must match its C32 Guest public service Host-local HTTP bridge"
            )
        if (
            guest_virtio_socket_listener.get("virtioSocketPort")
            != host_local_bridge.get("guestVirtioSocketPort")
        ):
            raise MacOSHostPackageCompositionError(
                "C32 Guest public service Host-local HTTP bridge "
                + route_id
                + " guestVirtioSocketPort must match its C37 public service virtio socket listener"
            )


def validate_guest_product_process_deployment(deployment: Mapping[str, Any]) -> None:
    """Validate C37 against its one canonical contract source.

    Packaging owns the decision that a product package requires this input. It
    does not own a second hand-maintained interpretation of Guest process
    configuration; the C37 schema remains the language authority.
    """

    validate_product_contract_document(
        "guest-product-process-deployment-configuration.schema.json",
        "C37",
        deployment,
    )


def validate_packaged_guest_public_service_process_ownership(
    deployment: Mapping[str, Any],
) -> None:
    """Reject a package route whose target process is absent from C37's plan.

    C37's Go domain policy repeats this guard before it starts a child process.
    The package composer performs the same complete-input equality check so a
    package cannot be published with a public route that the Guest supervisor
    will reject.  It does not probe a process or turn a listener declaration
    into a readiness observation.
    """

    guest_runtime = required_object(deployment, "guestRuntime", "C37")
    recorder_gateway = required_object(deployment, "recorderGateway", "C37")
    planned_process_listeners = {
        "guest-runtime": required_object(
            guest_runtime,
            "listener",
            "C37 Guest Runtime",
        ),
        "recorder-gateway": required_object(
            recorder_gateway,
            "listener",
            "C37 Recorder Gateway",
        ),
    }
    bridges = guest_runtime.get("publicServiceVirtioSocketBridges")
    if not isinstance(bridges, list):
        raise MacOSHostPackageCompositionError(
            "C37 Guest Runtime publicServiceVirtioSocketBridges must be an array"
        )
    for bridge in bridges:
        if not isinstance(bridge, dict):
            raise MacOSHostPackageCompositionError(
                "C37 Guest Runtime public service virtio socket bridge must be an object"
            )
        route_id = required_string(
            bridge,
            "routeId",
            "C37 Guest public service virtio socket bridge",
        )
        process_name = required_string(
            bridge,
            "guestProductProcessName",
            "C37 Guest public service virtio socket bridge " + route_id,
        )
        listener = planned_process_listeners.get(process_name)
        if (
            listener is None
            or listener.get("port") != bridge.get("targetPort")
            or listener.get("bindHost") not in ("127.0.0.1", "0.0.0.0")
        ):
            raise MacOSHostPackageCompositionError(
                "C37 Guest public service virtio socket bridge "
                + route_id
                + " must name a planned Guest Product process whose declared listener owns targetPort"
            )


def validate_guest_product_service_manager_deployment(
    deployment: Mapping[str, Any],
) -> None:
    """Require C38 before the product package accepts its Guest builder input."""

    validate_product_contract_document(
        "guest-product-service-manager-deployment-configuration.schema.json",
        "C38",
        deployment,
    )


def validate_guest_product_bootstrap_configuration(
    bootstrap_configuration: Mapping[str, Any],
) -> None:
    """Require C39 before the package accepts Guest-owned bootstrap intent."""

    validate_product_contract_document(
        "guest-product-bootstrap-configuration.schema.json",
        "C39",
        bootstrap_configuration,
    )


def validate_guest_product_vitalserver_topology_deployment(
    topology_deployment: Mapping[str, Any],
) -> None:
    """Require C44 before a package accepts its topology installation intent."""

    validate_product_contract_document(
        "guest-product-vitalserver-topology-deployment.schema.json",
        "C44",
        topology_deployment,
    )


def validate_external_vitalserver_delivery_configuration(
    delivery_configuration: Mapping[str, Any],
) -> None:
    """Require C46 before a package accepts external delivery target intent."""

    validate_product_contract_document(
        "external-vitalserver-delivery-configuration.schema.json",
        "C46",
        delivery_configuration,
    )


def validate_guest_product_vitalserver_delivery_bootstrap_composition(
    process_deployment: Mapping[str, Any],
    bootstrap_configuration: Mapping[str, Any],
    topology_deployment: Mapping[str, Any],
    external_delivery_configuration: Mapping[str, Any] | None,
) -> None:
    """Bind C37/C39/C44/C46 without inferring a delivery endpoint.

    C37 owns the Supervisor's file paths, C39 owns their Guest installation,
    C44 selects placement, and C46 owns an external endpoint.  This release
    adapter verifies those independent declarations agree before it permits a
    package to carry the resulting immutable Guest artifact.
    """

    recorder_gateway = required_object(process_deployment, "recorderGateway", "C37")
    topology_payload = required_object(
        bootstrap_configuration,
        "guestProductVitalServerTopologyDeployment",
        "C39",
    )
    topology_path = required_string(
        recorder_gateway,
        "vitalServerTopologyDeploymentPath",
        "C37 recorderGateway",
    )
    if topology_path != required_string(
        topology_payload,
        "destinationPath",
        "C39 guestProductVitalServerTopologyDeployment",
    ):
        raise MacOSHostPackageCompositionError(
            "C37 Recorder Gateway topology path must match C39 C44 installation destination"
        )

    topology_kind = required_string(topology_deployment, "topologyKind", "C44")
    external_delivery_path = recorder_gateway.get(
        "externalVitalServerDeliveryConfigurationPath"
    )
    external_delivery_payload = bootstrap_configuration.get(
        "externalVitalServerDeliveryConfiguration"
    )

    if topology_kind == "bundled-vitalserver":
        if (
            external_delivery_configuration is not None
            or external_delivery_path is not None
            or external_delivery_payload is not None
        ):
            raise MacOSHostPackageCompositionError(
                "C44 bundled topology must not carry an unused C46 external delivery configuration"
            )
        raise MacOSHostPackageCompositionError(
            "C44 bundled topology requires an explicit C37 bundled VitalServer process launch plan; current C37 plans only Guest Runtime and Recorder Gateway"
        )

    if topology_kind != "external-vitalserver":
        raise MacOSHostPackageCompositionError("C44 topologyKind is not supported")
    if external_delivery_configuration is None:
        raise MacOSHostPackageCompositionError(
            "C44 external topology requires one explicit C46 ExternalVitalServerDeliveryConfiguration"
        )
    if not isinstance(external_delivery_path, str) or not external_delivery_path:
        raise MacOSHostPackageCompositionError(
            "C44 external topology requires C37 Recorder Gateway external delivery configuration path"
        )
    if not isinstance(external_delivery_payload, Mapping):
        raise MacOSHostPackageCompositionError(
            "C44 external topology requires C39 ExternalVitalServerDeliveryConfiguration installation"
        )
    if external_delivery_path != required_string(
        external_delivery_payload,
        "destinationPath",
        "C39 externalVitalServerDeliveryConfiguration",
    ):
        raise MacOSHostPackageCompositionError(
            "C37 Recorder Gateway external delivery configuration path must match C39 C46 installation destination"
        )

    external_topology = required_object(
        topology_deployment,
        "externalVitalServerDeploymentConfiguration",
        "C44",
    )
    topology_integration_reference = required_object(
        external_topology,
        "externalUpstreamIntegrationReference",
        "C44 external VitalServer deployment",
    )
    topology_delivery_reference = required_object(
        external_topology,
        "externalVitalServerDeliveryConfigurationReference",
        "C44 external VitalServer deployment",
    )
    delivery_integration_reference = required_object(
        external_delivery_configuration,
        "externalUpstreamIntegrationReference",
        "C46",
    )
    if topology_integration_reference != delivery_integration_reference:
        raise MacOSHostPackageCompositionError(
            "C44 external integration reference must match C46 external integration reference"
        )
    if topology_delivery_reference.get("resourceId") != external_delivery_configuration.get(
        "configurationId"
    ):
        raise MacOSHostPackageCompositionError(
            "C44 external delivery configuration reference must name C46 configurationId"
        )
    if required_object(
        topology_deployment,
        "vitalServerDeliveryProvider",
        "C44",
    ) != required_object(
        external_delivery_configuration,
        "vitalServerDeliveryProvider",
        "C46",
    ):
        raise MacOSHostPackageCompositionError(
            "C44 VitalServer delivery provider must match C46 delivery provider"
        )


def validate_product_contract_document(
    schema_name: str,
    contract_id: str,
    document: Mapping[str, Any],
) -> None:
    """Use the canonical contract source instead of a package-local schema copy."""

    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        validation_errors = repository.validate_instance(
            schema_name,
            document,
        )
    except ContractToolError as error:
        raise MacOSHostPackageCompositionError(
            contract_id + " contract source is unavailable: " + str(error)
        ) from error
    if validation_errors:
        raise MacOSHostPackageCompositionError(
            contract_id + " is invalid: " + "; ".join(validation_errors)
        )


def validate_guest_artifact_manifest(
    virtual_machine: Mapping[str, Any], guest_artifact_manifest: Mapping[str, Any]
) -> None:
    if guest_artifact_manifest.get("schemaVersion") != "v1" or guest_artifact_manifest.get("architecture") != "arm64":
        raise MacOSHostPackageCompositionError("C34 schemaVersion must be v1 and architecture must be arm64")
    if not isinstance(guest_artifact_manifest.get("artifactSetId"), str) or not guest_artifact_manifest["artifactSetId"]:
        raise MacOSHostPackageCompositionError("C34 artifactSetId is required")
    validate_artifact_digest(required_object(guest_artifact_manifest, "kernel", "C34"), "C34 kernel")
    boot = required_object(virtual_machine, "boot", "C32")
    c32_initial_ramdisk = boot.get("initialRamdiskPath")
    c34_initial_ramdisk = guest_artifact_manifest.get("initialRamdisk")
    if c32_initial_ramdisk is None and c34_initial_ramdisk is not None:
        raise MacOSHostPackageCompositionError("C34 initial RAM disk is present but C32 does not reference one")
    if c32_initial_ramdisk is not None:
        if not isinstance(c34_initial_ramdisk, dict):
            raise MacOSHostPackageCompositionError("C32 initial RAM disk requires a C34 initialRamdisk digest")
        validate_artifact_digest(c34_initial_ramdisk, "C34 initialRamdisk")
    storage_digests = guest_artifact_manifest.get("storageDevices")
    if not isinstance(storage_digests, list) or len(storage_digests) != 2:
        raise MacOSHostPackageCompositionError("C34 storageDevices must declare exactly the root and bootstrap artifacts")
    digest_ids: set[str] = set()
    for storage_digest in storage_digests:
        if not isinstance(storage_digest, dict) or not isinstance(storage_digest.get("id"), str) or not storage_digest["id"]:
            raise MacOSHostPackageCompositionError("every C34 storage digest must have an id")
        if storage_digest["id"] in digest_ids:
            raise MacOSHostPackageCompositionError("C34 storage digest ids must be unique")
        digest_ids.add(storage_digest["id"])
        validate_c34_storage_digest(storage_digest)
        validate_artifact_digest(storage_digest, "C34 storage digest " + storage_digest["id"])
    c32_storage_by_id = {device["id"]: device for device in virtual_machine["storageDevices"]}
    if digest_ids != set(c32_storage_by_id):
        raise MacOSHostPackageCompositionError("C32 storage devices and C34 storage digests must name the same ids")
    for storage_digest in storage_digests:
        storage_device = c32_storage_by_id[storage_digest["id"]]
        if (
            storage_device.get("role") != storage_digest.get("role")
            or storage_device.get("storageImageFormat") != storage_digest.get("storageImageFormat")
            or storage_device.get("guestVolumeFileSystem") != storage_digest.get("guestVolumeFileSystem")
        ):
            raise MacOSHostPackageCompositionError("C32 storage attachment intent must match C34 storage artifact intent")


def validate_c32_storage_device(device: Mapping[str, Any], attachment_index: int) -> None:
    """Preserve the explicit Host attachment role rather than inferring it from a path."""

    declared = (
        device.get("id"),
        device.get("role"),
        device.get("storageImageFormat"),
        device.get("guestVolumeFileSystem"),
        device.get("readOnly"),
        device.get("attachmentIndex"),
    )
    expected_by_index = {
        0: ("guest-root", "guest-root-storage", "raw", None, False, 0),
        1: ("guest-product-bootstrap", "guest-product-bootstrap-volume", "raw", "iso9660", True, 1),
    }
    if declared != expected_by_index.get(attachment_index):
        raise MacOSHostPackageCompositionError("C32 storage device role, storage image format, Guest volume filesystem, readOnly, and attachmentIndex must be explicit")


def validate_c34_storage_digest(storage_digest: Mapping[str, Any]) -> None:
    declared = (
        storage_digest.get("id"),
        storage_digest.get("role"),
        storage_digest.get("storageImageFormat"),
        storage_digest.get("guestVolumeFileSystem"),
    )
    if declared not in {
        ("guest-root", "guest-root-storage", "raw", None),
        ("guest-product-bootstrap", "guest-product-bootstrap-volume", "raw", "iso9660"),
    }:
        raise MacOSHostPackageCompositionError("C34 storage digest role, storage image format, and Guest volume filesystem are not supported")


def validate_guest_artifact_compilation_receipt(
    guest_artifact_manifest_path: Path,
    guest_artifact_manifest: Mapping[str, Any],
    guest_artifact_compilation_receipt: Mapping[str, Any],
    guest_product_process_supervisor_artifact: Path,
    guest_product_process_deployment_configuration: Path,
    guest_product_service_manager_deployment_configuration: Path,
    guest_product_bootstrap_configuration: Path,
    guest_product_vitalserver_topology_deployment: Path,
    external_vitalserver_delivery_configuration: Path | None,
) -> None:
    """Require C35 to identify exact C34 and Guest Product bootstrap inputs."""

    if guest_artifact_compilation_receipt.get("schemaVersion") != "v1":
        raise MacOSHostPackageCompositionError("C35 receipt schemaVersion must be v1")
    for field in ("compilationId", "artifactSetId", "compilationCommandSHA256"):
        value = guest_artifact_compilation_receipt.get(field)
        if not isinstance(value, str) or not value:
            raise MacOSHostPackageCompositionError("C35 receipt requires " + field)
    if guest_artifact_compilation_receipt["artifactSetId"] != guest_artifact_manifest["artifactSetId"]:
        raise MacOSHostPackageCompositionError("C35 receipt artifactSetId does not match C34")
    validate_artifact_digest(
        required_object(guest_artifact_compilation_receipt, "buildEnvironment", "C35 receipt"),
        "C35 receipt buildEnvironment",
        size_field="builderExecutableSizeBytes",
        sha256_field_name="builderExecutableSHA256",
    )
    consumed_inputs = guest_artifact_compilation_receipt.get("consumedInputArtifacts")
    if not isinstance(consumed_inputs, list) or len(consumed_inputs) < 5:
        raise MacOSHostPackageCompositionError("C35 receipt requires at least five consumed input artifacts")
    consumed_ids: set[str] = set()
    for input_artifact in consumed_inputs:
        if not isinstance(input_artifact, dict) or not isinstance(input_artifact.get("id"), str) or not input_artifact["id"]:
            raise MacOSHostPackageCompositionError("every C35 consumed input artifact requires an id")
        if input_artifact["id"] in consumed_ids:
            raise MacOSHostPackageCompositionError("C35 consumed input artifact ids must be unique")
        consumed_ids.add(input_artifact["id"])
        validate_artifact_digest(input_artifact, "C35 consumed input artifact " + input_artifact["id"])
    manifest_receipt = required_object(guest_artifact_compilation_receipt, "macOSGuestArtifactManifest", "C35 receipt")
    if manifest_receipt.get("relativePath") != "macos-guest-artifact-manifest.json":
        raise MacOSHostPackageCompositionError("C35 receipt must name the canonical C34 relative path")
    validate_artifact_digest(manifest_receipt, "C35 receipt C34")
    if guest_artifact_manifest_path.stat().st_size != manifest_receipt["sizeBytes"]:
        raise MacOSHostPackageCompositionError("C35 receipt C34 size does not match the supplied C34")
    if sha256_file(guest_artifact_manifest_path) != manifest_receipt["sha256"]:
        raise MacOSHostPackageCompositionError("C35 receipt C34 SHA-256 does not match the supplied C34")
    validate_receipt_consumed_input_identity(
        consumed_inputs,
        guest_product_process_supervisor_artifact,
        "guest-product-process-supervisor-linux-arm64",
        "Guest Product process supervisor",
    )
    validate_receipt_consumed_input_identity(
        consumed_inputs,
        guest_product_process_deployment_configuration,
        "guest-product-process-deployment-configuration",
        "Guest Product process deployment configuration",
    )
    validate_receipt_consumed_input_identity(
        consumed_inputs,
        guest_product_service_manager_deployment_configuration,
        "guest-product-service-manager-deployment-configuration",
        "Guest Product service-manager deployment configuration",
    )
    validate_receipt_consumed_input_identity(
        consumed_inputs,
        guest_product_bootstrap_configuration,
        "guest-product-bootstrap-configuration",
        "Guest Product bootstrap configuration",
    )
    validate_receipt_consumed_input_identity(
        consumed_inputs,
        guest_product_vitalserver_topology_deployment,
        "guest-product-vitalserver-topology-deployment",
        "Guest Product VitalServer topology deployment",
    )
    if external_vitalserver_delivery_configuration is None:
        if "external-vitalserver-delivery-configuration" in consumed_ids:
            raise MacOSHostPackageCompositionError(
                "C35 receipt must not name C46 when the selected C44 topology has no external delivery configuration"
            )
        return
    validate_receipt_consumed_input_identity(
        consumed_inputs,
        external_vitalserver_delivery_configuration,
        "external-vitalserver-delivery-configuration",
        "C46 External VitalServer delivery configuration",
    )


def validate_receipt_consumed_input_identity(
    consumed_inputs: list[Any],
    source: Path,
    expected_identifier: str,
    artifact_name: str,
) -> None:
    """Bind a supplied Guest Product source to the named C35 consumed input."""

    matching_artifacts = [
        artifact
        for artifact in consumed_inputs
        if isinstance(artifact, dict) and artifact.get("id") == expected_identifier
    ]
    if len(matching_artifacts) != 1:
        raise MacOSHostPackageCompositionError(
            "C35 receipt must contain exactly one " + artifact_name + " consumed input"
        )
    receipt_artifact = matching_artifacts[0]
    if source.stat().st_size != receipt_artifact["sizeBytes"]:
        raise MacOSHostPackageCompositionError(
            artifact_name + " size does not match C35 consumed input"
        )
    if sha256_file(source) != receipt_artifact["sha256"]:
        raise MacOSHostPackageCompositionError(
            artifact_name + " SHA-256 does not match C35 consumed input"
        )


def validate_artifact_digest(
    artifact_digest: Mapping[str, Any],
    artifact_name: str,
    size_field: str = "sizeBytes",
    sha256_field_name: str = "sha256",
) -> None:
    size_bytes = artifact_digest.get(size_field)
    sha256 = artifact_digest.get(sha256_field_name)
    if not isinstance(size_bytes, int) or size_bytes < 1:
        raise MacOSHostPackageCompositionError(artifact_name + " " + size_field + " must be a positive integer")
    if not isinstance(sha256, str) or len(sha256) != 64 or any(character not in "0123456789abcdef" for character in sha256):
        raise MacOSHostPackageCompositionError(artifact_name + " " + sha256_field_name + " must be a lowercase SHA-256")


def validate_manifested_artifact(source: Path, artifact_digest: Mapping[str, Any], artifact_name: str) -> None:
    expected_size = artifact_digest["sizeBytes"]
    expected_sha256 = artifact_digest["sha256"]
    if source.stat().st_size != expected_size:
        raise MacOSHostPackageCompositionError(artifact_name + " size does not match C34")
    if sha256_file(source) != expected_sha256:
        raise MacOSHostPackageCompositionError(artifact_name + " SHA-256 does not match C34")


def compose_postinstall_script(
    host_agent_deployment: Mapping[str, Any],
    virtual_machine: Mapping[str, Any],
    host_agent_launchd_service_label: str,
    edge_proxy_launchd_service_label: str,
) -> str:
    control = required_object(host_agent_deployment, "control", "C33")
    installation = required_object(host_agent_deployment, "installation", "C33")
    state_database_path = PurePosixPath(required_string(control, "stateDatabasePath", "C33 control"))
    data_directory = PurePosixPath(required_string(installation, "dataDirectory", "C33 installation"))
    guest_boot_console_capture = required_object(virtual_machine, "guestBootConsoleCapture", "C32")
    guest_boot_console_capture_path = required_string(guest_boot_console_capture, "capturePath", "C32 guestBootConsoleCapture")
    guest_runtime_disk_provisioning = required_object(
        virtual_machine,
        "guestRuntimeDiskProvisioning",
        "C32",
    )
    runtime_disk_image_path = PurePosixPath(
        required_string(
            guest_runtime_disk_provisioning,
            "runtimeDiskImagePath",
            "C32 guestRuntimeDiskProvisioning",
        )
    )
    provisioning_receipt_path = PurePosixPath(
        required_string(
            guest_runtime_disk_provisioning,
            "provisioningReceiptPath",
            "C32 guestRuntimeDiskProvisioning",
        )
    )
    host_runtime_directories = declared_host_runtime_directories(
        state_database_path.parent,
        data_directory,
        PurePosixPath(guest_boot_console_capture_path).parent,
        runtime_disk_image_path.parent,
        provisioning_receipt_path.parent,
    )
    host_agent_service_path = PurePosixPath("/Library/LaunchDaemons") / (host_agent_launchd_service_label + ".plist")
    host_agent_service_target = "system/" + host_agent_launchd_service_label
    edge_proxy_service_path = PurePosixPath("/Library/LaunchDaemons") / (edge_proxy_launchd_service_label + ".plist")
    edge_proxy_service_target = "system/" + edge_proxy_launchd_service_label
    return "\n".join(
        [
            "#!/bin/sh",
            "set -eu",
            *compose_launchd_bootout_lines(host_agent_service_target, "Host Agent"),
            *compose_launchd_bootout_lines(edge_proxy_service_target, "Host Edge Proxy"),
            "/usr/bin/install -d -m 0750 "
            + " ".join(
                shell_quote(str(directory)) for directory in host_runtime_directories
            ),
            "/usr/bin/touch " + shell_quote(guest_boot_console_capture_path),
            "/bin/launchctl bootstrap system " + shell_quote(str(host_agent_service_path)),
            "/bin/launchctl bootstrap system " + shell_quote(str(edge_proxy_service_path)),
            "",
        ]
    )


def declared_host_runtime_directories(*directories: PurePosixPath) -> list[PurePosixPath]:
    """Return only the Host filesystem directories named by C32 and C33.

    The installer can create these directories but deliberately never creates
    a Guest Runtime disk or its receipt. Those are Supervisor provisioning
    effects, guarded by C34 identity verification.
    """

    ordered_directories: list[PurePosixPath] = []
    for directory in directories:
        if directory not in ordered_directories:
            ordered_directories.append(directory)
    return ordered_directories


def compose_launchd_bootout_lines(service_target: str, service_name: str) -> list[str]:
    return [
        "/bin/launchctl bootout " + shell_quote(service_target) + " >/dev/null 2>&1 || launchctl_bootout_status=$?",
        "launchctl_bootout_status=${launchctl_bootout_status:-0}",
        "if [ \"$launchctl_bootout_status\" -ne 0 ] && [ \"$launchctl_bootout_status\" -ne 3 ]; then",
        "  echo \"VitalServer " + service_name + " launchd bootout failed: $launchctl_bootout_status\" >&2",
        "  exit \"$launchctl_bootout_status\"",
        "fi",
    ]


def compose_macos_host_package(composition: MacOSHostPackageComposition) -> dict[str, str]:
    documents = load_macos_host_package_documents(composition)
    validate_package_artifacts(composition, documents)
    if not composition.output_package.is_absolute():
        raise MacOSHostPackageCompositionError("output package path must be absolute")
    output_package = composition.output_package.resolve()
    if (
        output_package.name
        != documents.macos_host_package_release_plan.expected_package_file_name
    ):
        raise MacOSHostPackageCompositionError(
            "output package file name must match C23 MacOSHostPackageReleasePlan expected package file name"
        )
    if output_package.exists() and not composition.replace_output:
        raise MacOSHostPackageCompositionError("output package already exists; pass --replace-output explicitly to replace it")
    if not output_package.parent.is_dir():
        raise MacOSHostPackageCompositionError("output package parent directory is missing")

    with tempfile.TemporaryDirectory(prefix="vitalserver-macos-package-", dir=output_package.parent) as temporary_directory:
        temporary_root = Path(temporary_directory)
        payload_root = temporary_root / "payload"
        scripts_root = temporary_root / "scripts"
        copy_package_payload(composition, documents, payload_root)
        staged_virtual_machine_supervisor = payload_destination(
            payload_root,
            composition.payload_base_path / "bin" / "macos-virtual-machine-supervisor",
        )
        sign_staged_macos_virtual_machine_supervisor(
            composition.macos_virtual_machine_supervisor_code_signing,
            staged_virtual_machine_supervisor,
        )
        scripts_root.mkdir(parents=True)
        postinstall_path = scripts_root / "postinstall"
        postinstall_path.write_text(
            compose_postinstall_script(
                documents.host_agent_deployment,
                documents.virtual_machine,
                documents.macos_host_package_release_plan.host_agent_launchd_service_label,
                documents.macos_host_package_release_plan.host_edge_proxy_launchd_service_label,
            ),
            encoding="utf-8",
        )
        postinstall_path.chmod(0o755)
        pkgbuild_candidate_package = temporary_root / "pkgbuild-component-candidate.pkg"
        compose_pkgbuild_component_package_candidate(
            composition,
            documents,
            payload_root,
            scripts_root,
            pkgbuild_candidate_package,
        )
        declared_payload_component_package = (
            temporary_root / "declared-payload-component-package.pkg"
        )
        recompose_pkgbuild_component_package_with_declared_payload_inventory(
            pkgbuild_candidate_package,
            payload_root,
            declared_payload_component_package,
        )
        publish_macos_installer_package_with_selected_signature(
            composition.macos_installer_package_signing,
            declared_payload_component_package,
            output_package,
        )

    return {
        "artifactPath": str(output_package),
        "sha256": sha256_file(output_package),
        "releaseDeliveryPlanId": documents.macos_host_package_release_plan.release_delivery_plan_id,
        "macOSInstallerPackageSigningMode": composition.macos_installer_package_signing.mode,
        "macOSVirtualMachineSupervisorCodeSigningMode": composition.macos_virtual_machine_supervisor_code_signing.mode,
    }


def compose_pkgbuild_component_package_candidate(
    composition: MacOSHostPackageComposition,
    documents: MacOSHostPackageDocuments,
    payload_root: Path,
    scripts_root: Path,
    candidate_package: Path,
) -> None:
    """Ask pkgbuild for a candidate component package, never the final release.

    Modern macOS serializes build-Host extended attributes into that candidate
    as AppleDouble CPIO records.  The candidate is therefore an adapter input
    to the declared-payload recomposition step, not a product artifact that
    may be published or signed directly.
    """

    command = [
        str(composition.pkgbuild_executable),
        "--root",
        str(payload_root),
        "--scripts",
        str(scripts_root),
        "--identifier",
        documents.macos_host_package_release_plan.macos_installer_package_identifier,
        "--version",
        documents.macos_host_package_release_plan.product_version,
        "--install-location",
        "/",
        str(candidate_package),
    ]
    completed = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic output"
        raise MacOSHostPackageCompositionError("pkgbuild candidate composition failed: " + detail)
    if not candidate_package.is_file():
        raise MacOSHostPackageCompositionError(
            "pkgbuild candidate composition reported success without producing a package"
        )


def recompose_pkgbuild_component_package_with_declared_payload_inventory(
    pkgbuild_candidate_package: Path,
    declared_payload_root: Path,
    recomposed_component_package: Path,
) -> None:
    """Rebuild a component PKG so only declared Installer file roles remain.

    ``pkgbuild`` remains the macOS component-package compiler.  This adapter
    then observes its CPIO members, removes only AppleDouble carrier records,
    regenerates the BOM from the staged declared payload, updates the
    ``PackageInfo`` inventory, and uses XAR's distribution mode to omit outer
    build-Host metadata as well.  No product file bytes are regenerated.
    """

    require_macos_installer_archive_toolchain()
    if not pkgbuild_candidate_package.is_file():
        raise MacOSHostPackageCompositionError(
            "pkgbuild component candidate package is missing or not a file"
        )
    if not declared_payload_root.is_dir():
        raise MacOSHostPackageCompositionError(
            "declared package payload root is missing or not a directory"
        )
    if recomposed_component_package.exists():
        raise MacOSHostPackageCompositionError(
            "declared-payload component package destination already exists"
        )
    if not recomposed_component_package.parent.is_dir():
        raise MacOSHostPackageCompositionError(
            "declared-payload component package parent directory is missing"
        )

    component_directory = recomposed_component_package.parent / "pkgbuild-component-package"
    component_directory.mkdir()
    execute_macos_installer_archive_tool(
        MACOS_INSTALLER_XAR_EXECUTABLE,
        ["-x", "-f", str(pkgbuild_candidate_package)],
        "extract pkgbuild component package",
        cwd=component_directory,
    )
    payload_archive = required_component_archive(component_directory, "Payload")
    scripts_archive = required_component_archive(component_directory, "Scripts")
    package_info = required_component_archive(component_directory, "PackageInfo")

    recomposed_payload_archive = component_directory / "Payload.with-declared-file-inventory"
    try:
        payload_inventory = (
            macos_installer_component_cpio.recompose_macos_installer_component_cpio_archive_without_appledouble_carriers(
                payload_archive,
                recomposed_payload_archive,
                "Payload",
            )
        )
        recomposed_scripts_archive = component_directory / "Scripts.with-declared-file-inventory"
        macos_installer_component_cpio.recompose_macos_installer_component_cpio_archive_without_appledouble_carriers(
            scripts_archive,
            recomposed_scripts_archive,
            "Scripts",
        )
    except macos_installer_component_cpio.MacOSInstallerComponentCpioArchiveError as error:
        raise MacOSHostPackageCompositionError(
            "macOS Installer component archive inventory recomposition failed: "
            + str(error)
        ) from error

    recomposed_bom = component_directory / "Bom.with-declared-file-inventory"
    execute_macos_installer_archive_tool(
        MACOS_INSTALLER_MKBOM_EXECUTABLE,
        [str(declared_payload_root), str(recomposed_bom)],
        "compose declared package payload BOM",
    )
    if not recomposed_bom.is_file():
        raise MacOSHostPackageCompositionError(
            "declared package payload BOM composition reported success without a BOM"
        )
    recomposed_package_info = component_directory / "PackageInfo.with-declared-file-inventory"
    update_component_package_info_with_declared_payload_inventory(
        package_info,
        recomposed_package_info,
        payload_inventory,
    )

    os.replace(recomposed_payload_archive, payload_archive)
    os.replace(recomposed_scripts_archive, scripts_archive)
    os.replace(recomposed_bom, required_component_archive(component_directory, "Bom"))
    os.replace(recomposed_package_info, package_info)
    execute_macos_installer_archive_tool(
        MACOS_INSTALLER_XAR_EXECUTABLE,
        [
            "-c",
            "-f",
            str(recomposed_component_package),
            "--distribution",
            "--no-compress",
            "^Payload$",
            "--no-compress",
            "^Scripts$",
            "Bom",
            "Payload",
            "Scripts",
            "PackageInfo",
        ],
        "compose declared-payload component package",
        cwd=component_directory,
    )
    if not recomposed_component_package.is_file():
        raise MacOSHostPackageCompositionError(
            "declared-payload component package composition reported success without a package"
        )


def update_component_package_info_with_declared_payload_inventory(
    source_package_info: Path,
    destination_package_info: Path,
    payload_inventory: macos_installer_component_cpio.ReconstitutedMacOSInstallerComponentCpioArchive,
) -> None:
    """Make the Installer's documented Payload count match retained CPIO roles."""

    try:
        package_info = ElementTree.parse(source_package_info)
    except (OSError, ElementTree.ParseError) as error:
        raise MacOSHostPackageCompositionError(
            "pkgbuild component PackageInfo cannot be parsed"
        ) from error
    payload = package_info.getroot().find("payload")
    if payload is None:
        raise MacOSHostPackageCompositionError(
            "pkgbuild component PackageInfo does not declare a payload"
        )
    payload.set("numberOfFiles", str(payload_inventory.retained_entry_count))
    payload.set(
        "installKBytes",
        str((payload_inventory.retained_regular_file_bytes + 1023) // 1024),
    )
    try:
        package_info.write(destination_package_info, encoding="utf-8", xml_declaration=True)
    except OSError as error:
        raise MacOSHostPackageCompositionError(
            "declared package payload PackageInfo cannot be written"
        ) from error


def required_component_archive(component_directory: Path, member_name: str) -> Path:
    member = component_directory / member_name
    if not member.is_file():
        raise MacOSHostPackageCompositionError(
            "pkgbuild component package is missing " + member_name
        )
    return member


def require_macos_installer_archive_toolchain() -> None:
    for tool_name, tool_path in (
        ("macOS Installer XAR executable", MACOS_INSTALLER_XAR_EXECUTABLE),
        ("macOS Installer BOM executable", MACOS_INSTALLER_MKBOM_EXECUTABLE),
    ):
        if not tool_path.is_file():
            raise MacOSHostPackageCompositionError(tool_name + " is missing or not a file")


def execute_macos_installer_archive_tool(
    executable: Path,
    arguments: list[str],
    operation: str,
    cwd: Path | None = None,
) -> None:
    completed = subprocess.run(
        [str(executable), *arguments],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic output"
        raise MacOSHostPackageCompositionError(
            "macOS Installer archive " + operation + " failed: " + detail
        )


def publish_macos_installer_package_with_selected_signature(
    signing: MacOSInstallerPackageSigning,
    declared_payload_component_package: Path,
    output_package: Path,
) -> None:
    """Publish the recomposed package unsigned or apply its explicit signature."""

    if signing.mode == "unsigned":
        os.replace(declared_payload_component_package, output_package)
        return
    productsign_executable = signing.productsign_executable
    if productsign_executable is None:
        raise MacOSHostPackageCompositionError(
            "signed macOS Installer package signing inputs were not validated"
        )
    completed = subprocess.run(
        [
            str(productsign_executable),
            "--sign",
            require_macos_installer_package_signing_identity(signing.signing_identity),
            str(declared_payload_component_package),
            str(output_package),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic output"
        raise MacOSHostPackageCompositionError(
            "macOS Installer package signing failed: " + detail
        )
    if not output_package.is_file():
        raise MacOSHostPackageCompositionError(
            "macOS Installer package signing reported success without a package"
        )


def copy_package_payload(composition: MacOSHostPackageComposition, documents: MacOSHostPackageDocuments, payload_root: Path) -> None:
    base_path = composition.payload_base_path
    copy_declared_regular_file_to_package_payload(composition.host_agent_binary, payload_destination(payload_root, base_path / "bin" / "host-agent"), executable=True)
    copy_declared_regular_file_to_package_payload(composition.host_edge_proxy_binary, payload_destination(payload_root, base_path / "bin" / "host-edge-proxy"), executable=True)
    copy_declared_regular_file_to_package_payload(composition.macos_virtual_machine_supervisor_binary, payload_destination(payload_root, base_path / "bin" / "macos-virtual-machine-supervisor"), executable=True)
    copy_declared_regular_file_to_package_payload(composition.host_agent_deployment_configuration, payload_destination(payload_root, base_path / "config" / "host-agent-deployment.json"))
    copy_declared_regular_file_to_package_payload(composition.host_edge_proxy_deployment_configuration, payload_destination(payload_root, base_path / "config" / "host-edge-proxy-deployment.json"))
    copy_declared_regular_file_to_package_payload(composition.macos_virtual_machine_configuration, payload_destination(payload_root, base_path / "config" / "macos-virtual-machine.json"))
    copy_declared_regular_file_to_package_payload(composition.guest_artifact_manifest, payload_destination(payload_root, base_path / "release" / "macos-guest-artifact-manifest.json"))
    copy_declared_regular_file_to_package_payload(composition.guest_artifact_compilation_receipt, payload_destination(payload_root, base_path / "release" / "guest-artifact-compilation-receipt.json"))
    boot = required_object(documents.virtual_machine, "boot", "C32")
    copy_declared_regular_file_to_package_payload(composition.guest_kernel_source, payload_destination(payload_root, PurePosixPath(required_string(boot, "kernelPath", "C32 boot"))))
    initial_ramdisk_path = boot.get("initialRamdiskPath")
    if initial_ramdisk_path is not None and composition.guest_initial_ramdisk_source is not None:
        copy_declared_regular_file_to_package_payload(composition.guest_initial_ramdisk_source, payload_destination(payload_root, PurePosixPath(initial_ramdisk_path)))
    guest_runtime_disk_provisioning = required_object(
        documents.virtual_machine,
        "guestRuntimeDiskProvisioning",
        "C32",
    )
    copy_declared_regular_file_to_package_payload(
        composition.guest_storage_sources["guest-root"],
        payload_destination(
            payload_root,
            PurePosixPath(
                required_string(
                    guest_runtime_disk_provisioning,
                    "releaseArtifactPath",
                    "C32 guestRuntimeDiskProvisioning",
                )
            ),
        ),
    )
    for device in documents.virtual_machine["storageDevices"]:
        if device["id"] == "guest-root":
            continue
        copy_declared_regular_file_to_package_payload(
            composition.guest_storage_sources[device["id"]],
            payload_destination(payload_root, PurePosixPath(device["diskImagePath"])),
        )
    launchd_directory = payload_root / "Library" / "LaunchDaemons"
    launchd_directory.mkdir(parents=True, exist_ok=True)
    for service_label, definition in (
        (
            documents.macos_host_package_release_plan.host_agent_launchd_service_label,
            compose_host_agent_launchd_service_definition(
                composition,
                documents.macos_host_package_release_plan,
            ),
        ),
        (
            documents.macos_host_package_release_plan.host_edge_proxy_launchd_service_label,
            compose_host_edge_proxy_launchd_service_definition(
                composition,
                documents.macos_host_package_release_plan,
            ),
        ),
    ):
        with (launchd_directory / (service_label + ".plist")).open("wb") as plist_file:
            plistlib.dump(definition, plist_file, sort_keys=True)


def payload_destination(payload_root: Path, absolute_target_path: PurePosixPath) -> Path:
    if not absolute_target_path.is_absolute():
        raise MacOSHostPackageCompositionError("package target path must be absolute")
    return payload_root.joinpath(*absolute_target_path.parts[1:])


def validate_package_artifacts(composition: MacOSHostPackageComposition, documents: MacOSHostPackageDocuments) -> None:
    if (
        not composition.release_delivery_plan_id
    ):
        raise MacOSHostPackageCompositionError(
            "C23 release delivery plan id is required"
        )
    if (
        documents.macos_host_package_release_plan.host_agent_launchd_service_label
        == documents.macos_host_package_release_plan.host_edge_proxy_launchd_service_label
    ):
        raise MacOSHostPackageCompositionError("Host Agent and Host Edge Proxy launchd service labels must differ")
    require_safe_absolute_path(str(composition.payload_base_path), "payload base path")
    for name, path in (
        ("host Agent binary", composition.host_agent_binary),
        ("Host Edge Proxy binary", composition.host_edge_proxy_binary),
        ("C36 HostEdgeProxyDeploymentConfiguration", composition.host_edge_proxy_deployment_configuration),
        ("macOS virtual machine supervisor binary", composition.macos_virtual_machine_supervisor_binary),
        ("C35 GuestArtifactCompilationReceipt", composition.guest_artifact_compilation_receipt),
        ("Guest Product process supervisor artifact", composition.guest_product_process_supervisor_artifact),
        ("C37 GuestProductProcessDeploymentConfiguration", composition.guest_product_process_deployment_configuration),
        ("C38 GuestProductServiceManagerDeploymentConfiguration", composition.guest_product_service_manager_deployment_configuration),
        ("C39 GuestProductBootstrapConfiguration", composition.guest_product_bootstrap_configuration),
        ("C44 GuestProductVitalServerTopologyDeployment", composition.guest_product_vitalserver_topology_deployment),
        ("Guest kernel source", composition.guest_kernel_source),
        ("pkgbuild executable", composition.pkgbuild_executable),
    ):
        if not path.is_absolute() or not path.is_file():
            raise MacOSHostPackageCompositionError(name + " is missing or not a file")
    if composition.external_vitalserver_delivery_configuration is not None and (
        not composition.external_vitalserver_delivery_configuration.is_absolute()
        or not composition.external_vitalserver_delivery_configuration.is_file()
    ):
        raise MacOSHostPackageCompositionError(
            "C46 ExternalVitalServerDeliveryConfiguration is missing or not a file"
        )
    if composition.guest_initial_ramdisk_source is not None and (not composition.guest_initial_ramdisk_source.is_absolute() or not composition.guest_initial_ramdisk_source.is_file()):
        raise MacOSHostPackageCompositionError("Guest initial RAM disk source is missing or not a file")
    for storage_id, source in composition.guest_storage_sources.items():
        if not storage_id or not source.is_absolute() or not source.is_file():
            raise MacOSHostPackageCompositionError("Guest storage source is missing or invalid")
    manifest = documents.guest_artifact_manifest
    validate_manifested_artifact(composition.guest_kernel_source, required_object(manifest, "kernel", "C34"), "Guest kernel source")
    if composition.guest_initial_ramdisk_source is not None:
        validate_manifested_artifact(composition.guest_initial_ramdisk_source, required_object(manifest, "initialRamdisk", "C34"), "Guest initial RAM disk source")
    storage_digests = {device["id"]: device for device in manifest["storageDevices"]}
    for storage_id, source in composition.guest_storage_sources.items():
        validate_manifested_artifact(source, storage_digests[storage_id], "Guest storage source " + storage_id)
    validate_macos_installer_package_signing(composition)
    validate_macos_virtual_machine_supervisor_code_signing(
        composition.macos_virtual_machine_supervisor_code_signing
    )


def validate_macos_installer_package_signing(
    composition: MacOSHostPackageComposition,
) -> None:
    """Validate the final package signature, not pkgbuild's candidate output."""

    signing = composition.macos_installer_package_signing
    if signing.mode not in {"unsigned", "signed"}:
        raise MacOSHostPackageCompositionError(
            "macOS Installer package signing mode must be unsigned or signed"
        )
    if signing.mode == "signed":
        require_macos_installer_package_signing_identity(signing.signing_identity)
        productsign_executable = signing.productsign_executable
        if (
            productsign_executable is None
            or not productsign_executable.is_absolute()
            or not productsign_executable.is_file()
        ):
            raise MacOSHostPackageCompositionError(
                "signed macOS Installer package productsign executable is missing or not a file"
            )
        if composition.macos_virtual_machine_supervisor_code_signing.mode != "signed":
            raise MacOSHostPackageCompositionError(
                "a signed macOS package requires a signed macOS virtual machine supervisor"
            )
        return
    if signing.signing_identity is not None or signing.productsign_executable is not None:
        raise MacOSHostPackageCompositionError(
            "unsigned macOS Installer package signing must not supply signing inputs"
        )


def validate_macos_virtual_machine_supervisor_code_signing(
    code_signing: MacOSVirtualMachineSupervisorCodeSigning,
) -> None:
    if code_signing.mode not in {"unsigned", "signed"}:
        raise MacOSHostPackageCompositionError(
            "macOS virtual machine supervisor code signing mode must be unsigned or signed"
        )
    signing_inputs = (
        code_signing.signing_identity,
        code_signing.codesign_executable,
        code_signing.virtualization_entitlements,
    )
    if code_signing.mode == "unsigned":
        if any(value is not None for value in signing_inputs):
            raise MacOSHostPackageCompositionError(
                "unsigned macOS virtual machine supervisor code signing must not supply signing inputs"
            )
        return
    require_macos_virtual_machine_supervisor_signing_identity(code_signing.signing_identity)
    for input_name, path in (
        ("macOS virtual machine supervisor codesign executable", code_signing.codesign_executable),
        ("macOS virtual machine supervisor virtualization entitlements", code_signing.virtualization_entitlements),
    ):
        if path is None or not path.is_absolute() or not path.is_file():
            raise MacOSHostPackageCompositionError(input_name + " is missing or not a file")


def sign_staged_macos_virtual_machine_supervisor(
    code_signing: MacOSVirtualMachineSupervisorCodeSigning,
    staged_virtual_machine_supervisor: Path,
) -> None:
    """Sign and verify the staged VM owner without mutating the supplied build artifact."""

    if code_signing.mode == "unsigned":
        return
    codesign_executable = code_signing.codesign_executable
    virtualization_entitlements = code_signing.virtualization_entitlements
    if codesign_executable is None or virtualization_entitlements is None:
        raise MacOSHostPackageCompositionError(
            "signed macOS virtual machine supervisor code signing inputs were not validated"
        )
    execute_macos_virtual_machine_supervisor_codesign(
        codesign_executable,
        [
            "--force",
            "--sign",
            require_macos_virtual_machine_supervisor_signing_identity(code_signing.signing_identity),
            "--entitlements",
            str(virtualization_entitlements),
            "--options",
            "runtime",
            "--timestamp",
            str(staged_virtual_machine_supervisor),
        ],
        "sign",
    )
    execute_macos_virtual_machine_supervisor_codesign(
        codesign_executable,
        ["--verify", "--strict", "--verbose=4", str(staged_virtual_machine_supervisor)],
        "verify",
    )
    verify_macos_virtual_machine_supervisor_virtualization_entitlement(
        codesign_executable,
        staged_virtual_machine_supervisor,
    )


def execute_macos_virtual_machine_supervisor_codesign(
    codesign_executable: Path,
    arguments: list[str],
    operation: str,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        [str(codesign_executable), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic output"
        raise MacOSHostPackageCompositionError(
            "macOS virtual machine supervisor code signing " + operation + " failed: " + detail
        )
    return completed


def verify_macos_virtual_machine_supervisor_virtualization_entitlement(
    codesign_executable: Path,
    staged_virtual_machine_supervisor: Path,
) -> None:
    completed = execute_macos_virtual_machine_supervisor_codesign(
        codesign_executable,
        ["--display", "--entitlements", ":-", str(staged_virtual_machine_supervisor)],
        "entitlement display",
    )
    entitlement_output = completed.stdout + "\n" + completed.stderr
    entitlement_document = parse_displayed_macos_virtual_machine_supervisor_entitlement_plist(
        entitlement_output
    )
    if not isinstance(entitlement_document, dict) or entitlement_document.get("com.apple.security.virtualization") is not True:
        raise MacOSHostPackageCompositionError(
            "macOS virtual machine supervisor signature lacks com.apple.security.virtualization=true"
        )


def parse_displayed_macos_virtual_machine_supervisor_entitlement_plist(
    codesign_display_output: str,
) -> Mapping[str, Any]:
    """Extract only the entitlement plist from mixed codesign diagnostics.

    `codesign --display --entitlements :-` writes an XML plist, but macOS may
    place executable/signature diagnostics before or after it (and can use
    either stdout or stderr).  The external command output is evidence, not a
    plist document as a whole.  Parsing from `<?xml` through the matching
    closing plist tag preserves the entitlement boundary without discarding a
    missing or malformed entitlement claim.
    """

    xml_start = codesign_display_output.find("<?xml")
    xml_end = codesign_display_output.find("</plist>", xml_start)
    if xml_start < 0 or xml_end < 0:
        raise MacOSHostPackageCompositionError(
            "macOS virtual machine supervisor code signing did not display an entitlement plist"
        )
    try:
        entitlement_document = plistlib.loads(
            codesign_display_output[xml_start : xml_end + len("</plist>")].encode("utf-8")
        )
    except (plistlib.InvalidFileException, ValueError) as error:
        raise MacOSHostPackageCompositionError(
            "macOS virtual machine supervisor displayed entitlement plist is invalid"
        ) from error
    if not isinstance(entitlement_document, dict):
        raise MacOSHostPackageCompositionError(
            "macOS virtual machine supervisor displayed entitlement plist must be a dictionary"
        )
    return entitlement_document


def load_json_document(path: Path, document_name: str) -> Mapping[str, Any]:
    if not path.is_file():
        raise MacOSHostPackageCompositionError(document_name + " is missing or not a file")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MacOSHostPackageCompositionError(document_name + " cannot be read as JSON") from error
    if not isinstance(document, dict):
        raise MacOSHostPackageCompositionError(document_name + " must be a JSON object")
    return document


def required_object(document: Mapping[str, Any], name: str, document_name: str) -> Mapping[str, Any]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise MacOSHostPackageCompositionError(document_name + " requires object " + name)
    return value


def required_string(document: Mapping[str, Any], name: str, document_name: str) -> str:
    value = document.get(name)
    if not isinstance(value, str) or not value:
        raise MacOSHostPackageCompositionError(document_name + " requires non-empty " + name)
    return value


def require_positive_integer(value: Any, field_name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise MacOSHostPackageCompositionError(field_name + " must be a positive integer")


def require_port(value: Any, field_name: str) -> None:
    require_positive_integer(value, field_name)
    if value > 65535:
        raise MacOSHostPackageCompositionError(field_name + " must not exceed 65535")


def require_request_path_prefix(value: str, field_name: str) -> None:
    if not value.startswith("/") or "?" in value or "#" in value or ".." in PurePosixPath(value).parts:
        raise MacOSHostPackageCompositionError(field_name + " must be an absolute request path prefix without query, fragment, or traversal")


def require_payload_path(payload_base_path: PurePosixPath, value: Any, field_name: str) -> None:
    require_safe_absolute_path(value, field_name)
    path = PurePosixPath(value)
    try:
        path.relative_to(payload_base_path)
    except ValueError as error:
        raise MacOSHostPackageCompositionError(field_name + " must be below the explicit package payload base path") from error


def require_safe_absolute_path(value: Any, field_name: str) -> None:
    if not isinstance(value, str) or not value.startswith("/") or "\\" in value or ".." in PurePosixPath(value).parts:
        raise MacOSHostPackageCompositionError(field_name + " must be an absolute path without traversal")


def require_path_within_directory(path: str, directory: str, field_name: str) -> None:
    candidate = PurePosixPath(path)
    parent = PurePosixPath(directory)
    try:
        relative_path = candidate.relative_to(parent)
    except ValueError as error:
        raise MacOSHostPackageCompositionError(
            field_name + " must be within C33 installation.dataDirectory"
        ) from error
    if relative_path == PurePosixPath("."):
        raise MacOSHostPackageCompositionError(
            field_name + " must name a file below C33 installation.dataDirectory"
        )


def require_macos_installer_package_signing_identity(signing_identity: str | None) -> str:
    if signing_identity is None or not signing_identity.strip():
        raise MacOSHostPackageCompositionError(
            "signed macOS Installer package signing requires a signing identity"
        )
    return signing_identity


def require_macos_virtual_machine_supervisor_signing_identity(signing_identity: str | None) -> str:
    if signing_identity is None or not signing_identity.strip():
        raise MacOSHostPackageCompositionError(
            "signed macOS virtual machine supervisor code signing requires a signing identity"
        )
    return signing_identity


def copy_declared_regular_file_to_package_payload(
    source: Path, destination: Path, executable: bool = False
) -> None:
    """Copy declared product bytes with the package-owned mode and no source metadata.

    C23/C47 select payload *bytes*, not a build workstation's timestamps,
    Finder metadata, resource forks, quarantine state, or extended attributes.
    `copy2` would preserve those unowned facts and lets pkgbuild emit
    AppleDouble `._*` entries.  The package adapter therefore copies only file
    contents and sets the one package-owned mode explicitly.
    """

    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    destination.chmod(0o755 if executable else 0o644)


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_storage_sources(values: Iterable[str]) -> dict[str, Path]:
    sources: dict[str, Path] = {}
    for value in values:
        storage_id, separator, source_path = value.partition("=")
        if not separator or not storage_id or not source_path or storage_id in sources:
            raise MacOSHostPackageCompositionError("storage source must be unique and formatted as storage-id=/absolute/source/path")
        sources[storage_id] = Path(source_path)
    return sources


def parse_arguments(arguments: list[str]) -> MacOSHostPackageComposition:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-delivery-plans-document", required=True)
    parser.add_argument("--release-delivery-plan-id", required=True)
    parser.add_argument("--payload-base-path", required=True)
    parser.add_argument("--host-agent-binary", required=True)
    parser.add_argument("--host-edge-proxy-binary", required=True)
    parser.add_argument("--macos-virtual-machine-supervisor-binary", required=True)
    parser.add_argument("--host-agent-deployment-configuration", required=True)
    parser.add_argument("--host-edge-proxy-deployment-configuration", required=True)
    parser.add_argument("--macos-virtual-machine-configuration", required=True)
    parser.add_argument("--guest-artifact-manifest", required=True)
    parser.add_argument("--guest-artifact-compilation-receipt", required=True)
    parser.add_argument("--guest-product-process-supervisor-artifact", required=True)
    parser.add_argument("--guest-product-process-deployment-configuration", required=True)
    parser.add_argument("--guest-product-service-manager-deployment-configuration", required=True)
    parser.add_argument("--guest-product-bootstrap-configuration", required=True)
    parser.add_argument("--guest-product-vitalserver-topology-deployment", required=True)
    parser.add_argument("--external-vitalserver-delivery-configuration")
    parser.add_argument("--guest-kernel-source", required=True)
    parser.add_argument("--guest-initial-ramdisk-source")
    parser.add_argument("--guest-storage-source", action="append", default=[])
    parser.add_argument("--output-package", required=True)
    parser.add_argument("--pkgbuild-executable", required=True)
    parser.add_argument(
        "--macos-installer-package-signing-mode",
        required=True,
        choices=("unsigned", "signed"),
    )
    parser.add_argument("--macos-installer-package-signing-identity")
    parser.add_argument("--macos-installer-package-productsign-executable")
    parser.add_argument("--macos-virtual-machine-supervisor-code-signing-mode", required=True, choices=("unsigned", "signed"))
    parser.add_argument("--macos-virtual-machine-supervisor-signing-identity")
    parser.add_argument("--macos-virtual-machine-supervisor-codesign-executable")
    parser.add_argument("--macos-virtual-machine-supervisor-virtualization-entitlements")
    parser.add_argument("--replace-output", action="store_true")
    parsed = parser.parse_args(arguments)
    return MacOSHostPackageComposition(
        release_delivery_plans_document=Path(parsed.release_delivery_plans_document),
        release_delivery_plan_id=parsed.release_delivery_plan_id,
        payload_base_path=PurePosixPath(parsed.payload_base_path),
        host_agent_binary=Path(parsed.host_agent_binary),
        host_edge_proxy_binary=Path(parsed.host_edge_proxy_binary),
        macos_virtual_machine_supervisor_binary=Path(parsed.macos_virtual_machine_supervisor_binary),
        host_agent_deployment_configuration=Path(parsed.host_agent_deployment_configuration),
        host_edge_proxy_deployment_configuration=Path(parsed.host_edge_proxy_deployment_configuration),
        macos_virtual_machine_configuration=Path(parsed.macos_virtual_machine_configuration),
        guest_artifact_manifest=Path(parsed.guest_artifact_manifest),
        guest_artifact_compilation_receipt=Path(parsed.guest_artifact_compilation_receipt),
        guest_product_process_supervisor_artifact=Path(parsed.guest_product_process_supervisor_artifact),
        guest_product_process_deployment_configuration=Path(parsed.guest_product_process_deployment_configuration),
        guest_product_service_manager_deployment_configuration=Path(parsed.guest_product_service_manager_deployment_configuration),
        guest_product_bootstrap_configuration=Path(parsed.guest_product_bootstrap_configuration),
        guest_product_vitalserver_topology_deployment=Path(parsed.guest_product_vitalserver_topology_deployment),
        external_vitalserver_delivery_configuration=Path(parsed.external_vitalserver_delivery_configuration)
        if parsed.external_vitalserver_delivery_configuration
        else None,
        guest_kernel_source=Path(parsed.guest_kernel_source),
        guest_initial_ramdisk_source=Path(parsed.guest_initial_ramdisk_source) if parsed.guest_initial_ramdisk_source else None,
        guest_storage_sources=parse_storage_sources(parsed.guest_storage_source),
        output_package=Path(parsed.output_package),
        pkgbuild_executable=Path(parsed.pkgbuild_executable),
        macos_installer_package_signing=MacOSInstallerPackageSigning(
            mode=parsed.macos_installer_package_signing_mode,
            signing_identity=parsed.macos_installer_package_signing_identity,
            productsign_executable=Path(parsed.macos_installer_package_productsign_executable)
            if parsed.macos_installer_package_productsign_executable
            else None,
        ),
        macos_virtual_machine_supervisor_code_signing=MacOSVirtualMachineSupervisorCodeSigning(
            mode=parsed.macos_virtual_machine_supervisor_code_signing_mode,
            signing_identity=parsed.macos_virtual_machine_supervisor_signing_identity,
            codesign_executable=Path(parsed.macos_virtual_machine_supervisor_codesign_executable)
            if parsed.macos_virtual_machine_supervisor_codesign_executable
            else None,
            virtualization_entitlements=Path(parsed.macos_virtual_machine_supervisor_virtualization_entitlements)
            if parsed.macos_virtual_machine_supervisor_virtualization_entitlements
            else None,
        ),
        replace_output=parsed.replace_output,
    )


def main(arguments: list[str]) -> int:
    try:
        result = compose_macos_host_package(parse_arguments(arguments))
    except MacOSHostPackageCompositionError as error:
        print("macOS Host package composition failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
