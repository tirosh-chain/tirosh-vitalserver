"""Prepare one explicit Linux Host release input for the DEB composer.

The Linux Host installer is a product boundary, not a convenient collection
of build outputs.  This adapter selects exactly one C23 delivery plan, five
Linux Host executables, and the C33/C36/C53/C56/C58 deployment documents.  It
publishes a single C48 release source, its three systemd unit definitions, and
the composition document consumed by :mod:`linux_host_package_composer`.

It neither compiles those executables, runs dpkg/systemd, nor observes a
machine.  Those effects have their own owners.  In particular, producing a
DEB here is not clean-Host installation evidence.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
from typing import Any, Mapping

from tooling.contracts import ContractRepository, ContractToolError


class LinuxHostReleaseInputPreparationError(RuntimeError):
    """Raised when selected Linux inputs cannot make one C48 release."""


PRODUCT_ROOT = "/opt/vitalserver-runtime-platform"
DATA_ROOT = "/var/lib/vitalserver-runtime-platform/data"
CONTROL_ROOT = PRODUCT_ROOT + "/control"
SYSTEMD_ROOT = "/etc/systemd/system"
RELEASE_INPUT_DIRECTORY_NAME = "linux-host-release-input"
RELEASE_DIRECTORY_NAME = "release"
PACKAGE_IDENTIFIER = "com.tirosh.vitalserver.runtime-platform"


@dataclass(frozen=True)
class LinuxHostReleaseInputPreparation:
    """Caller-selected immutable bytes for one Linux DEB release input."""

    release_root: Path
    release_slot_id: str
    release_delivery_plans_document: Path
    release_delivery_plan_id: str
    package_maintainer: str
    package_description: str
    host_agent_binary: Path
    host_edge_proxy_binary: Path
    host_installation_manager_binary: Path
    host_update_handoff_supervisor_binary: Path
    platformctl_binary: Path
    linux_kvm_libvirt_systemd_bridge_binary: Path
    host_agent_deployment_configuration: Path
    host_edge_proxy_deployment_configuration: Path
    host_update_handoff_supervisor_configuration: Path
    operator_interface_bootstrap_configuration: Path
    host_update_trust_store: Path


@dataclass(frozen=True)
class LinuxReleasePlan:
    product_version: str
    expected_package_file_name: str
    service_names: Mapping[str, str]


def prepare_linux_host_release_input(
    preparation: LinuxHostReleaseInputPreparation,
) -> Mapping[str, Any]:
    """Publish one immutable C48 source and a DEB composition document."""

    plan = _load_linux_release_plan(preparation)
    _validate_preparation_identity(preparation)
    _load_and_validate_documents(preparation, plan)
    _validate_selected_binaries(preparation)
    destination = preparation.release_root / RELEASE_INPUT_DIRECTORY_NAME
    if destination.exists() or destination.is_symlink():
        raise LinuxHostReleaseInputPreparationError(
            "Linux release input directory already exists: " + str(destination)
        )
    temporary = Path(
        tempfile.mkdtemp(
            prefix="." + RELEASE_INPUT_DIRECTORY_NAME + ".", dir=preparation.release_root
        )
    )
    try:
        release = temporary / RELEASE_DIRECTORY_NAME
        _copy_release_files(preparation, release)
        services = _write_systemd_units(temporary / "services", preparation, plan)
        control = temporary / "control"
        control.mkdir(parents=True, exist_ok=True)
        _copy_regular_file(
            preparation.operator_interface_bootstrap_configuration,
            control / "runtime-console-bootstrap.json",
        )
        manifest = _compose_installation_manifest(release, services, preparation, plan)
        _validate_contract("host-product-installation-manifest.schema.json", manifest, "C48")
        _write_json(release / "installation-manifest.json", manifest)
        _write_json(
            temporary / "linux-host-package-composition.json",
            _compose_package_composition(destination, preparation, plan),
        )
        os.replace(temporary, destination)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    manifest_path = destination / RELEASE_DIRECTORY_NAME / "installation-manifest.json"
    composition_path = destination / "linux-host-package-composition.json"
    return {
        "releaseInputDirectory": str(destination),
        "installationManifestPath": str(manifest_path),
        "installationManifestSha256": _sha256_file(manifest_path),
        "linuxHostPackageCompositionPath": str(composition_path),
        "expectedInstallerArtifact": plan.expected_package_file_name,
    }


def _load_linux_release_plan(preparation: LinuxHostReleaseInputPreparation) -> LinuxReleasePlan:
    _require_absolute_file(preparation.release_delivery_plans_document, "C23 release delivery plans document")
    if not preparation.release_delivery_plan_id:
        raise LinuxHostReleaseInputPreparationError("C23 release delivery plan id is required")
    document = _read_json(preparation.release_delivery_plans_document, "C23 release delivery plans document")
    plans = document.get("plans")
    if document.get("schemaVersion") != "v1" or not isinstance(plans, list):
        raise LinuxHostReleaseInputPreparationError("C23 release delivery plans document requires schemaVersion v1 and plans")
    selected = [item for item in plans if isinstance(item, dict) and item.get("id") == preparation.release_delivery_plan_id]
    if len(selected) != 1:
        raise LinuxHostReleaseInputPreparationError("C23 must select exactly one Linux release delivery plan")
    plan = selected[0]
    _validate_contract("release-delivery-plan.schema.json", plan, "C23")
    if plan.get("platform") != "linux" or plan.get("providerKind") != "linux-kvm-libvirt-systemd":
        raise LinuxHostReleaseInputPreparationError("C23 release delivery plan must target Linux KVM/libvirt/systemd")
    installer = _required_object(plan, "intendedInstallerArtifact", "C23")
    if installer.get("kind") != "deb":
        raise LinuxHostReleaseInputPreparationError("C23 Linux intended installer artifact must be deb")
    expected_name = _required_string(installer, "expectedName", "C23 intended installer artifact")
    if "/" in expected_name or "\\" in expected_name or Path(expected_name).name != expected_name or not expected_name.endswith(".deb"):
        raise LinuxHostReleaseInputPreparationError("C23 Linux DEB expectedName must be one .deb file name")
    names: dict[str, str] = {}
    registrations = _required_list(plan, "requiredHostServiceRegistrations", "C23")
    for role in _required_service_roles():
        matches = [entry for entry in registrations if entry.get("role") == role]
        if len(matches) != 1 or matches[0].get("manager") != "systemd":
            raise LinuxHostReleaseInputPreparationError("C23 must declare exactly one systemd " + role + " registration")
        name = _required_string(matches[0], "name", "C23 " + role + " service registration")
        if not name.endswith(".service"):
            raise LinuxHostReleaseInputPreparationError("C23 Linux systemd registration must name one .service unit")
        names[role] = name
    return LinuxReleasePlan(_required_string(plan, "productVersion", "C23"), expected_name, names)


def _validate_preparation_identity(preparation: LinuxHostReleaseInputPreparation) -> None:
    if not preparation.release_root.is_absolute() or not preparation.release_root.is_dir() or preparation.release_root.is_symlink():
        raise LinuxHostReleaseInputPreparationError("release root must be one existing absolute non-symbolic directory")
    if not preparation.release_slot_id or "/" in preparation.release_slot_id or "\\" in preparation.release_slot_id:
        raise LinuxHostReleaseInputPreparationError("release slot id must be one non-empty identifier-like value")
    if not preparation.package_maintainer.strip() or not preparation.package_description.strip():
        raise LinuxHostReleaseInputPreparationError("DEB package maintainer and description are required")


def _load_and_validate_documents(preparation: LinuxHostReleaseInputPreparation, plan: LinuxReleasePlan) -> None:
    sources = {
        "host_agent": (preparation.host_agent_deployment_configuration, "host-agent-deployment-configuration.schema.json", "C33"),
        "host_edge_proxy": (preparation.host_edge_proxy_deployment_configuration, "host-edge-proxy-deployment-configuration.schema.json", "C36"),
        "handoff": (preparation.host_update_handoff_supervisor_configuration, "host-update-handoff-supervisor-configuration.schema.json", "C56"),
        "operator": (preparation.operator_interface_bootstrap_configuration, "operator-interface-bootstrap-configuration.schema.json", "C53"),
        "trust": (preparation.host_update_trust_store, "host-update-trust-store.schema.json", "C58"),
    }
    documents: dict[str, Mapping[str, Any]] = {}
    for key, (path, schema, label) in sources.items():
        _require_absolute_file(path, label + " source")
        value = _read_json(path, label + " source")
        _validate_contract(schema, value, label)
        documents[key] = value
    agent = documents["host_agent"]
    installation = _required_object(agent, "installation", "C33")
    if installation.get("productVersion") != plan.product_version:
        raise LinuxHostReleaseInputPreparationError("C33 installation productVersion must equal C23 Linux productVersion")
    if installation.get("dataDirectory") != DATA_ROOT:
        raise LinuxHostReleaseInputPreparationError("C33 dataDirectory must name the Linux package mutable data root")
    control = _required_object(agent, "control", "C33")
    local = _required_object(control, "localAdministration", "C33 control")
    if local.get("transport") != "unix-domain-socket":
        raise LinuxHostReleaseInputPreparationError("C33 Linux package requires a unix-domain-socket local administration transport")
    if local.get("endpointAddress") != "/run/vitalserver-runtime-platform/host-agent.sock":
        raise LinuxHostReleaseInputPreparationError("C33 local socket path must use the systemd RuntimeDirectory")
    if local.get("descriptorPath") != CONTROL_ROOT + "/host-agent.local.json":
        raise LinuxHostReleaseInputPreparationError("C33 local descriptor path must name the Linux packaged control path")
    if control.get("stateDatabasePath") != DATA_ROOT + "/host-agent/host-agent.sqlite":
        raise LinuxHostReleaseInputPreparationError("C33 state database path must name the Host-owned Linux mutable store")
    provider = _required_object(agent, "provider", "C33")
    if provider.get("kind") != "linux-kvm-libvirt-systemd":
        raise LinuxHostReleaseInputPreparationError("C33 provider kind must be linux-kvm-libvirt-systemd")
    if provider.get("nativeProviderBridgeExecutablePath") != _current_release_path() + "/bin/linux-kvm-libvirt-systemd-bridge":
        raise LinuxHostReleaseInputPreparationError("C33 must name the packaged Linux provider bridge path")
    if provider.get("hostServiceName") != plan.service_names["host-agent"]:
        raise LinuxHostReleaseInputPreparationError("C33 provider hostServiceName must equal C23 host-agent service name")
    update = _required_object(agent, "updateBootstrap", "C33")
    if update.get("mode") != "staged" or update.get("trustStorePath") != _current_release_path() + "/config/update-trust-store.json":
        raise LinuxHostReleaseInputPreparationError("C33 update bootstrap must select the packaged staged Linux trust store")
    operator = documents["operator"]
    if operator.get("bootstrapConfigurationPath") != CONTROL_ROOT + "/runtime-console-bootstrap.json":
        raise LinuxHostReleaseInputPreparationError("C53 bootstrapConfigurationPath must name the Linux packaged control path")
    if operator.get("localAdministrationDescriptorPath") != local.get("descriptorPath"):
        raise LinuxHostReleaseInputPreparationError("C53 descriptor path must equal C33 local administration descriptor path")
    handoff = documents["handoff"]
    if handoff.get("stagingDirectory") != update.get("stagingDirectory"):
        raise LinuxHostReleaseInputPreparationError("C56 stagingDirectory must equal C33 updateBootstrap stagingDirectory")
    if handoff.get("handoffQueueDirectory") != str(update["stagingDirectory"]) + "/handoff-queue":
        raise LinuxHostReleaseInputPreparationError("C56 handoffQueueDirectory must be C33 stagingDirectory/handoff-queue")
    if handoff.get("hostLocalAdministrationDescriptorPath") != local.get("descriptorPath"):
        raise LinuxHostReleaseInputPreparationError("C56 descriptor path must equal C33 local administration descriptor path")


def _validate_selected_binaries(preparation: LinuxHostReleaseInputPreparation) -> None:
    for label, path in (
        ("Host Agent", preparation.host_agent_binary),
        ("Host Edge Proxy", preparation.host_edge_proxy_binary),
        ("Host Installation Manager", preparation.host_installation_manager_binary),
        ("Host Update Handoff Supervisor", preparation.host_update_handoff_supervisor_binary),
        ("platformctl", preparation.platformctl_binary),
        ("Linux KVM/libvirt/systemd Bridge", preparation.linux_kvm_libvirt_systemd_bridge_binary),
    ):
        _require_absolute_file(path, label + " binary")


def _copy_release_files(preparation: LinuxHostReleaseInputPreparation, destination: Path) -> None:
    entries = {
        "bin/host-agent": preparation.host_agent_binary,
        "bin/host-edge-proxy": preparation.host_edge_proxy_binary,
        "bin/host-installation-manager": preparation.host_installation_manager_binary,
        "bin/host-update-handoff-supervisor": preparation.host_update_handoff_supervisor_binary,
        "bin/platformctl": preparation.platformctl_binary,
        "bin/linux-kvm-libvirt-systemd-bridge": preparation.linux_kvm_libvirt_systemd_bridge_binary,
        "config/host-agent-deployment.json": preparation.host_agent_deployment_configuration,
        "config/host-edge-proxy-deployment.json": preparation.host_edge_proxy_deployment_configuration,
        "config/host-update-handoff-supervisor-configuration.json": preparation.host_update_handoff_supervisor_configuration,
        "config/update-trust-store.json": preparation.host_update_trust_store,
    }
    for relative, source in entries.items():
        target = destination / relative
        _copy_regular_file(source, target)
        if relative.startswith("bin/"):
            target.chmod(0o755)


def _write_systemd_units(directory: Path, preparation: LinuxHostReleaseInputPreparation, plan: LinuxReleasePlan) -> Mapping[str, Path]:
    commands = {
        "host-agent": ["--deployment-configuration", _current_release_path() + "/config/host-agent-deployment.json"],
        "host-edge-proxy": ["--deployment-configuration", _current_release_path() + "/config/host-edge-proxy-deployment.json"],
        "host-update-handoff-supervisor": ["--configuration", _current_release_path() + "/config/host-update-handoff-supervisor-configuration.json", "--mode", "service"],
    }
    result: dict[str, Path] = {}
    for role in _required_service_roles():
        unit = directory / plan.service_names[role]
        command = " ".join([_current_release_path() + "/bin/" + role, *commands[role]])
        runtime = "RuntimeDirectory=vitalserver-runtime-platform\nRuntimeDirectoryMode=0750\n" if role == "host-agent" else ""
        unit.parent.mkdir(parents=True, exist_ok=True)
        unit.write_text(
            "[Unit]\n"
            + "Description=VitalServer Runtime Platform " + role + "\n"
            + "After=network-online.target\nWants=network-online.target\n\n"
            + "[Service]\nType=simple\n"
            + runtime
            + "ExecStart=" + command + "\nRestart=on-failure\nRestartSec=5\n\n"
            + "[Install]\nWantedBy=multi-user.target\n",
            encoding="utf-8",
        )
        result[role] = unit
    return result


def _compose_installation_manifest(release: Path, services: Mapping[str, Path], preparation: LinuxHostReleaseInputPreparation, plan: LinuxReleasePlan) -> Mapping[str, Any]:
    release_root = PRODUCT_ROOT + "/releases/" + preparation.release_slot_id
    entries = [
        {"relativePath": path.relative_to(release).as_posix(), "sha256": _sha256_file(path), "executable": path.relative_to(release).as_posix().startswith("bin/")}
        for path in sorted(release.rglob("*")) if path.is_file()
    ]
    required_services = [
        {
            "role": role,
            "manager": "systemd",
            "name": plan.service_names[role],
            "definitionPath": SYSTEMD_ROOT + "/" + plan.service_names[role],
            "definitionSha256": _sha256_file(services[role]),
        }
        for role in _required_service_roles()
    ]
    return {
        "schemaVersion": "v1",
        "installationId": "vitalserver-runtime-platform",
        "platform": "linux",
        "release": {"id": preparation.release_slot_id, "productVersion": plan.product_version, "runtimeVersion": plan.product_version},
        "package": {"identifier": PACKAGE_IDENTIFIER, "productVersion": plan.product_version},
        "immutablePayload": {"releaseCatalogPath": PRODUCT_ROOT + "/releases", "releaseRootPath": release_root, "manifestPath": release_root + "/installation-manifest.json", "entries": entries},
        "activation": {"currentReleaseLinkPath": _current_release_path(), "referenceKind": "symbolic-link", "expectedReleaseRootPath": release_root},
        "operatorInterface": {"bootstrapConfigurationPath": CONTROL_ROOT + "/runtime-console-bootstrap.json", "bootstrapConfigurationSha256": _sha256_file(preparation.operator_interface_bootstrap_configuration)},
        "requiredServices": required_services,
        "mutableStores": [
            {"id": "installation-data-root", "path": DATA_ROOT, "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
            {"id": "installation-manager-journal", "path": DATA_ROOT + "/installation-manager", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
            {"id": "native-machine-runtime", "path": DATA_ROOT + "/virtual-machine", "kind": "directory", "owner": "native-platform-provider", "retention": "preserve-by-default"},
        ],
    }


def _compose_package_composition(destination: Path, preparation: LinuxHostReleaseInputPreparation, plan: LinuxReleasePlan) -> Mapping[str, Any]:
    data = DATA_ROOT + "/installation-manager"
    return {
        "manifestPath": str(destination / RELEASE_DIRECTORY_NAME / "installation-manifest.json"),
        "releaseSourceDirectory": str(destination / RELEASE_DIRECTORY_NAME),
        "serviceDefinitionSources": {role: str(destination / "services" / plan.service_names[role]) for role in _required_service_roles()},
        "operatorInterfaceBootstrapSource": str(destination / "control" / "runtime-console-bootstrap.json"),
        "installationJournalPath": data + "/current-transaction.json",
        "installationReceiptPath": data + "/latest-installation-receipt.json",
        "removalJournalPath": data + "/current-removal-transaction.json",
        "removalReceiptPath": data + "/latest-removal-receipt.json",
        "packageManagerCompletionManagerPath": data + "/package-manager-removal-completion",
        "packageManagerCompletionManifestPath": data + "/package-manager-removal-manifest.json",
        "outputPackage": str(preparation.release_root / plan.expected_package_file_name),
        "packageName": PACKAGE_IDENTIFIER,
        "architecture": "amd64",
        "maintainer": preparation.package_maintainer,
        "description": preparation.package_description,
    }


def _required_service_roles() -> tuple[str, str, str]:
    return ("host-agent", "host-edge-proxy", "host-update-handoff-supervisor")


def _current_release_path() -> str:
    return PRODUCT_ROOT + "/current"


def _validate_contract(schema: str, document: Mapping[str, Any], label: str) -> None:
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        findings = repository.validate_instance(schema, document)
    except ContractToolError as error:
        raise LinuxHostReleaseInputPreparationError(label + " contract source is unavailable: " + str(error)) from error
    if findings:
        raise LinuxHostReleaseInputPreparationError(label + " is invalid: " + "; ".join(findings))


def _require_absolute_file(path: Path, label: str) -> None:
    if not path.is_absolute():
        raise LinuxHostReleaseInputPreparationError(label + " path must be absolute")
    if not path.is_file() or path.is_symlink():
        raise LinuxHostReleaseInputPreparationError(label + " must be one regular non-symbolic file")


def _copy_regular_file(source: Path, destination: Path) -> None:
    _require_absolute_file(source, "selected source")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def _read_json(path: Path, label: str) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LinuxHostReleaseInputPreparationError("could not read " + label + ": " + str(error)) from error
    if not isinstance(value, dict):
        raise LinuxHostReleaseInputPreparationError(label + " must be one JSON object")
    return value


def _write_json(path: Path, document: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _required_object(document: Mapping[str, Any], key: str, label: str) -> Mapping[str, Any]:
    value = document.get(key)
    if not isinstance(value, dict):
        raise LinuxHostReleaseInputPreparationError(label + " requires object " + key)
    return value


def _required_string(document: Mapping[str, Any], key: str, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise LinuxHostReleaseInputPreparationError(label + " requires non-empty string " + key)
    return value


def _required_list(document: Mapping[str, Any], key: str, label: str) -> list[Mapping[str, Any]]:
    value = document.get(key)
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise LinuxHostReleaseInputPreparationError(label + " requires object array " + key)
    return value


def _parse_arguments(arguments: list[str] | None = None) -> LinuxHostReleaseInputPreparation:
    parser = argparse.ArgumentParser(description="prepare one Linux C48 release input and DEB composition")
    parser.add_argument("--preparation", type=Path, required=True, help="absolute JSON LinuxHostReleaseInputPreparation document")
    values = parser.parse_args(arguments)
    document = _read_json(values.preparation, "Linux Host release input preparation")
    try:
        return LinuxHostReleaseInputPreparation(
            release_root=Path(document["releaseRoot"]), release_slot_id=str(document["releaseSlotId"]),
            release_delivery_plans_document=Path(document["releaseDeliveryPlansDocument"]), release_delivery_plan_id=str(document["releaseDeliveryPlanId"]),
            package_maintainer=str(document["packageMaintainer"]), package_description=str(document["packageDescription"]),
            host_agent_binary=Path(document["hostAgentBinary"]), host_edge_proxy_binary=Path(document["hostEdgeProxyBinary"]),
            host_installation_manager_binary=Path(document["hostInstallationManagerBinary"]), host_update_handoff_supervisor_binary=Path(document["hostUpdateHandoffSupervisorBinary"]),
            platformctl_binary=Path(document["platformctlBinary"]),
            linux_kvm_libvirt_systemd_bridge_binary=Path(document["linuxKVMlibvirtSystemdBridgeBinary"]),
            host_agent_deployment_configuration=Path(document["hostAgentDeploymentConfiguration"]),
            host_edge_proxy_deployment_configuration=Path(document["hostEdgeProxyDeploymentConfiguration"]),
            host_update_handoff_supervisor_configuration=Path(document["hostUpdateHandoffSupervisorConfiguration"]),
            operator_interface_bootstrap_configuration=Path(document["operatorInterfaceBootstrapConfiguration"]),
            host_update_trust_store=Path(document["hostUpdateTrustStore"]),
        )
    except (KeyError, TypeError) as error:
        raise LinuxHostReleaseInputPreparationError("Linux Host release input preparation is missing a required field: " + str(error)) from error


def main(arguments: list[str] | None = None) -> int:
    try:
        print(json.dumps(prepare_linux_host_release_input(_parse_arguments(arguments)), sort_keys=True))
    except LinuxHostReleaseInputPreparationError as error:
        print("Linux Host release input preparation failed: " + str(error))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
