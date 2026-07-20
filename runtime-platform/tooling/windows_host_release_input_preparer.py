"""Prepare one explicit Windows Host release input for the WiX MSI composer.

This release-process adapter turns selected build outputs and deployment
documents into the *one* C48 source tree consumed by
``windows_host_msi_composer``.  It does not compile Go, invoke WiX, install
an MSI, create an SCM service, or infer deployment values from the build
machine.  Those effects remain separate owners.

The prepared tree deliberately contains C48's immutable release bytes only.
C70 service definitions and C53 console bootstrap configuration are copied as
separate MSI inputs because C48 declares them at their Host-owned stable
paths rather than inside its immutable release slot.
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
import uuid
from typing import Any, Mapping

from tooling.contracts import ContractRepository, ContractToolError


class WindowsHostReleaseInputPreparationError(RuntimeError):
    """Raised when selected Windows release inputs cannot form one C48."""


PRODUCT_ROOT = r"C:\ProgramData\VitalServerRuntimePlatform"
RELEASE_INPUT_DIRECTORY_NAME = "windows-host-release-input"
RELEASE_DIRECTORY_NAME = "release"


@dataclass(frozen=True)
class WindowsHostReleaseInputPreparation:
    """Caller-owned bytes and release identity for one Windows MSI input set."""

    release_root: Path
    release_slot_id: str
    release_delivery_plans_document: Path
    release_delivery_plan_id: str
    package_product_code: str
    manufacturer: str
    upgrade_code: str
    host_agent_binary: Path
    host_edge_proxy_binary: Path
    host_installation_manager_binary: Path
    host_service_runner_binary: Path
    host_update_handoff_supervisor_binary: Path
    platformctl_binary: Path
    windows_hyperv_scm_bridge_binary: Path
    host_agent_deployment_configuration: Path
    host_edge_proxy_deployment_configuration: Path
    host_update_handoff_supervisor_configuration: Path
    operator_interface_bootstrap_configuration: Path
    host_update_trust_store: Path


@dataclass(frozen=True)
class WindowsReleasePlan:
    product_version: str
    expected_package_file_name: str
    service_names: Mapping[str, str]


def prepare_windows_host_release_input(
    preparation: WindowsHostReleaseInputPreparation,
) -> Mapping[str, Any]:
    """Publish a new C48 release source and MSI composition document.

    The output directory is created once and atomically.  A second request
    must name a new release workspace; replacing an earlier selected input
    could silently make its hashes describe different bytes.
    """

    plan = _load_windows_release_plan(preparation)
    _validate_preparation_identity(preparation)
    documents = _load_and_validate_documents(preparation, plan)
    _validate_selected_binaries(preparation)
    destination = preparation.release_root / RELEASE_INPUT_DIRECTORY_NAME
    if destination.exists():
        raise WindowsHostReleaseInputPreparationError(
            "Windows release input directory already exists: " + str(destination)
        )
    temporary = Path(tempfile.mkdtemp(prefix="." + RELEASE_INPUT_DIRECTORY_NAME + ".", dir=preparation.release_root))
    try:
        release_directory = temporary / RELEASE_DIRECTORY_NAME
        _copy_release_files(preparation, release_directory)
        services_directory = temporary / "services"
        service_definitions = _write_service_definitions(
            services_directory, preparation, plan
        )
        control_directory = temporary / "control"
        control_directory.mkdir(parents=True, exist_ok=True)
        _copy_regular_file(
            preparation.operator_interface_bootstrap_configuration,
            control_directory / "runtime-console-bootstrap.json",
        )
        manifest = _compose_installation_manifest(
            release_directory, service_definitions, preparation, plan
        )
        _validate_contract(
            "host-product-installation-manifest.schema.json", manifest, "C48"
        )
        _write_json(release_directory / "installation-manifest.json", manifest)
        composition = _compose_msi_composition(
            destination,
            destination / RELEASE_DIRECTORY_NAME,
            destination / "services",
            destination / "control",
            preparation,
        )
        _write_json(temporary / "windows-host-msi-composition.json", composition)
        os.replace(temporary, destination)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    manifest_path = destination / RELEASE_DIRECTORY_NAME / "installation-manifest.json"
    composition_path = destination / "windows-host-msi-composition.json"
    return {
        "releaseInputDirectory": str(destination),
        "installationManifestPath": str(manifest_path),
        "installationManifestSha256": _sha256_file(manifest_path),
        "windowsHostMSICompositionPath": str(composition_path),
        "expectedInstallerArtifact": plan.expected_package_file_name,
    }


def _load_windows_release_plan(preparation: WindowsHostReleaseInputPreparation) -> WindowsReleasePlan:
    _require_absolute_file(preparation.release_delivery_plans_document, "C23 release delivery plans document")
    if not preparation.release_delivery_plan_id:
        raise WindowsHostReleaseInputPreparationError("C23 release delivery plan id is required")
    document = _read_json(preparation.release_delivery_plans_document, "C23 release delivery plans document")
    plans = document.get("plans")
    if document.get("schemaVersion") != "v1" or not isinstance(plans, list):
        raise WindowsHostReleaseInputPreparationError("C23 release delivery plans document requires schemaVersion v1 and plans")
    selected = [plan for plan in plans if isinstance(plan, dict) and plan.get("id") == preparation.release_delivery_plan_id]
    if len(selected) != 1:
        raise WindowsHostReleaseInputPreparationError("C23 must select exactly one Windows release delivery plan")
    plan = selected[0]
    _validate_contract("release-delivery-plan.schema.json", plan, "C23")
    if plan.get("platform") != "windows" or plan.get("providerKind") != "windows-hyperv-scm":
        raise WindowsHostReleaseInputPreparationError("C23 release delivery plan must target Windows Hyper-V/SCM")
    installer = _required_object(plan, "intendedInstallerArtifact", "C23")
    if installer.get("kind") != "msi":
        raise WindowsHostReleaseInputPreparationError("C23 Windows intended installer artifact must be msi")
    expected_name = _required_string(installer, "expectedName", "C23 intended installer artifact")
    if "/" in expected_name or "\\" in expected_name or Path(expected_name).name != expected_name or not expected_name.lower().endswith(".msi"):
        raise WindowsHostReleaseInputPreparationError("C23 Windows MSI expectedName must be one .msi file name")
    registrations = _required_list(plan, "requiredHostServiceRegistrations", "C23")
    names: dict[str, str] = {}
    for role in _required_service_roles():
        matches = [entry for entry in registrations if isinstance(entry, dict) and entry.get("role") == role]
        if len(matches) != 1 or matches[0].get("manager") != "windows-scm":
            raise WindowsHostReleaseInputPreparationError("C23 must declare exactly one Windows SCM " + role + " registration")
        names[role] = _required_string(matches[0], "name", "C23 " + role + " service registration")
    return WindowsReleasePlan(
        product_version=_required_string(plan, "productVersion", "C23"),
        expected_package_file_name=expected_name,
        service_names=names,
    )


def _validate_preparation_identity(preparation: WindowsHostReleaseInputPreparation) -> None:
    if not preparation.release_root.is_absolute() or not preparation.release_root.is_dir() or preparation.release_root.is_symlink():
        raise WindowsHostReleaseInputPreparationError("release root must be one existing absolute non-symbolic directory")
    if not preparation.release_slot_id or "/" in preparation.release_slot_id or "\\" in preparation.release_slot_id:
        raise WindowsHostReleaseInputPreparationError("release slot id must be one non-empty identifier-like value")
    if not preparation.manufacturer.strip():
        raise WindowsHostReleaseInputPreparationError("MSI manufacturer is required")
    for label, value in (("MSI ProductCode", preparation.package_product_code), ("MSI UpgradeCode", preparation.upgrade_code)):
        if not _is_braced_guid(value):
            raise WindowsHostReleaseInputPreparationError(label + " must be one braced GUID")


def _is_braced_guid(value: str) -> bool:
    if len(value) != 38 or not value.startswith("{") or not value.endswith("}"):
        return False
    try:
        uuid.UUID(value[1:-1])
    except (ValueError, AttributeError):
        return False
    return True


def _load_and_validate_documents(
    preparation: WindowsHostReleaseInputPreparation, plan: WindowsReleasePlan
) -> Mapping[str, Mapping[str, Any]]:
    sources = {
        "host_agent": (preparation.host_agent_deployment_configuration, "host-agent-deployment-configuration.schema.json", "C33"),
        "host_edge_proxy": (preparation.host_edge_proxy_deployment_configuration, "host-edge-proxy-deployment-configuration.schema.json", "C36"),
        "handoff": (preparation.host_update_handoff_supervisor_configuration, "host-update-handoff-supervisor-configuration.schema.json", "C56"),
        "operator": (preparation.operator_interface_bootstrap_configuration, "operator-interface-bootstrap-configuration.schema.json", "C53"),
        "trust": (preparation.host_update_trust_store, "host-update-trust-store.schema.json", "C58"),
    }
    documents: dict[str, Mapping[str, Any]] = {}
    for name, (path, schema, label) in sources.items():
        _require_absolute_file(path, label + " source")
        document = _read_json(path, label + " source")
        _validate_contract(schema, document, label)
        documents[name] = document
    agent = documents["host_agent"]
    installation = _required_object(agent, "installation", "C33")
    if installation.get("productVersion") != plan.product_version:
        raise WindowsHostReleaseInputPreparationError("C33 installation productVersion must equal C23 Windows productVersion")
    provider = _required_object(agent, "provider", "C33")
    current = _current_release_path()
    if provider.get("kind") != "windows-hyperv-scm":
        raise WindowsHostReleaseInputPreparationError("C33 provider kind must be windows-hyperv-scm")
    if provider.get("nativeProviderBridgeExecutablePath") != current + r"\bin\windows-hyperv-scm-bridge.exe":
        raise WindowsHostReleaseInputPreparationError("C33 must name the packaged Windows provider bridge path")
    if provider.get("hostServiceName") != plan.service_names["host-agent"]:
        raise WindowsHostReleaseInputPreparationError("C33 provider hostServiceName must equal C23 host-agent service name")
    local = _required_object(_required_object(agent, "control", "C33"), "localAdministration", "C33 control")
    if local.get("transport") != "windows-named-pipe":
        raise WindowsHostReleaseInputPreparationError("C33 Windows package requires a windows-named-pipe local administration transport")
    operator = documents["operator"]
    if operator.get("bootstrapConfigurationPath") != PRODUCT_ROOT + r"\control\runtime-console-bootstrap.json":
        raise WindowsHostReleaseInputPreparationError("C53 bootstrapConfigurationPath must name the Windows packaged control path")
    if operator.get("localAdministrationDescriptorPath") != local.get("descriptorPath"):
        raise WindowsHostReleaseInputPreparationError("C53 descriptor path must equal C33 local administration descriptor path")
    update = _required_object(agent, "updateBootstrap", "C33")
    if update.get("mode") != "staged":
        raise WindowsHostReleaseInputPreparationError("C33 updateBootstrap must be staged for the packaged C56 supervisor")
    if update.get("trustStorePath") != current + r"\config\update-trust-store.json":
        raise WindowsHostReleaseInputPreparationError("C33 update trust store must name the packaged C58 path")
    handoff = documents["handoff"]
    if handoff.get("stagingDirectory") != update.get("stagingDirectory"):
        raise WindowsHostReleaseInputPreparationError("C56 stagingDirectory must equal C33 updateBootstrap stagingDirectory")
    if handoff.get("handoffQueueDirectory") != str(update["stagingDirectory"]) + r"\handoff-queue":
        raise WindowsHostReleaseInputPreparationError("C56 handoffQueueDirectory must be C33 stagingDirectory\\handoff-queue")
    if handoff.get("hostLocalAdministrationDescriptorPath") != local.get("descriptorPath"):
        raise WindowsHostReleaseInputPreparationError("C56 descriptor path must equal C33 local administration descriptor path")
    return documents


def _validate_selected_binaries(preparation: WindowsHostReleaseInputPreparation) -> None:
    for label, path in (
        ("Host Agent", preparation.host_agent_binary),
        ("Host Edge Proxy", preparation.host_edge_proxy_binary),
        ("Host Installation Manager", preparation.host_installation_manager_binary),
        ("Host Service Runner", preparation.host_service_runner_binary),
        ("Host Update Handoff Supervisor", preparation.host_update_handoff_supervisor_binary),
        ("platformctl", preparation.platformctl_binary),
        ("Windows Hyper-V SCM Bridge", preparation.windows_hyperv_scm_bridge_binary),
    ):
        _require_absolute_file(path, label + " binary")


def _copy_release_files(preparation: WindowsHostReleaseInputPreparation, destination: Path) -> None:
    entries = {
        "bin/host-agent.exe": preparation.host_agent_binary,
        "bin/host-edge-proxy.exe": preparation.host_edge_proxy_binary,
        "bin/host-installation-manager.exe": preparation.host_installation_manager_binary,
        "bin/host-service-runner.exe": preparation.host_service_runner_binary,
        "bin/host-update-handoff-supervisor.exe": preparation.host_update_handoff_supervisor_binary,
        "bin/platformctl.exe": preparation.platformctl_binary,
        "bin/windows-hyperv-scm-bridge.exe": preparation.windows_hyperv_scm_bridge_binary,
        "config/host-agent-deployment.json": preparation.host_agent_deployment_configuration,
        "config/host-edge-proxy-deployment.json": preparation.host_edge_proxy_deployment_configuration,
        "config/host-update-handoff-supervisor-configuration.json": preparation.host_update_handoff_supervisor_configuration,
        "config/update-trust-store.json": preparation.host_update_trust_store,
    }
    for relative, source in entries.items():
        _copy_regular_file(source, destination / relative)


def _write_service_definitions(
    services_directory: Path, preparation: WindowsHostReleaseInputPreparation, plan: WindowsReleasePlan
) -> Mapping[str, Path]:
    current = _current_release_path()
    arguments = {
        "host-agent": ["--deployment-configuration", current + r"\config\host-agent-deployment.json"],
        "host-edge-proxy": ["--deployment-configuration", current + r"\config\host-edge-proxy-deployment.json"],
        "host-update-handoff-supervisor": ["--configuration", current + r"\config\host-update-handoff-supervisor-configuration.json", "--mode", "service"],
    }
    result: dict[str, Path] = {}
    for role in _required_service_roles():
        path = services_directory / (role + ".json")
        document = {
            "schemaVersion": "v1",
            "documentKind": "host-service-execution-definition",
            "serviceName": plan.service_names[role],
            "role": role,
            "command": {
                "executablePath": current + "\\bin\\" + role + ".exe",
                "arguments": arguments[role],
            },
        }
        _validate_contract("host-service-execution-definition.schema.json", document, "C70")
        _write_json(path, document)
        result[role] = path
    return result


def _compose_installation_manifest(
    release_directory: Path, service_definitions: Mapping[str, Path], preparation: WindowsHostReleaseInputPreparation, plan: WindowsReleasePlan
) -> Mapping[str, Any]:
    release_root = PRODUCT_ROOT + r"\releases" + "\\" + preparation.release_slot_id
    entries = []
    for path in sorted(release_directory.rglob("*")):
        if path.is_dir():
            continue
        relative = path.relative_to(release_directory).as_posix()
        entries.append({"relativePath": relative, "sha256": _sha256_file(path), "executable": relative.startswith("bin/")})
    required_services = []
    for role in _required_service_roles():
        definition_path = PRODUCT_ROOT + "\\services\\" + role + ".json"
        required_services.append({
            "role": role,
            "manager": "windows-scm",
            "name": plan.service_names[role],
            "definitionPath": definition_path,
            "definitionSha256": _sha256_file(service_definitions[role]),
            "windowsScmRegistration": {
                "executablePath": _current_release_path() + r"\bin\host-service-runner.exe",
                "arguments": ["--service-definition", definition_path],
                "startMode": "automatic",
                "account": "LocalSystem",
            },
        })
    return {
        "schemaVersion": "v1",
        "installationId": "vitalserver-runtime-platform",
        "platform": "windows",
        "release": {"id": preparation.release_slot_id, "productVersion": plan.product_version, "runtimeVersion": plan.product_version},
        "package": {"identifier": "com.tirosh.vitalserver.runtime-platform", "productVersion": plan.product_version, "packageManagerIdentifier": preparation.package_product_code},
        "immutablePayload": {
            "releaseCatalogPath": PRODUCT_ROOT + r"\releases",
            "releaseRootPath": release_root,
            "manifestPath": release_root + r"\installation-manifest.json",
            "entries": entries,
        },
        "activation": {"currentReleaseLinkPath": _current_release_path(), "referenceKind": "directory-junction", "expectedReleaseRootPath": release_root},
        "operatorInterface": {
            "bootstrapConfigurationPath": PRODUCT_ROOT + r"\control\runtime-console-bootstrap.json",
            "bootstrapConfigurationSha256": _sha256_file(preparation.operator_interface_bootstrap_configuration),
        },
        "requiredServices": required_services,
        "mutableStores": [
            {"id": "installation-data-root", "path": PRODUCT_ROOT + r"\data", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
            {"id": "installation-manager-journal", "path": PRODUCT_ROOT + r"\data\installation-manager", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
            {"id": "native-machine-runtime", "path": PRODUCT_ROOT + r"\data\virtual-machine", "kind": "directory", "owner": "native-platform-provider", "retention": "preserve-by-default"},
        ],
    }


def _compose_msi_composition(
    destination: Path, release_directory: Path, services_directory: Path, control_directory: Path, preparation: WindowsHostReleaseInputPreparation
) -> Mapping[str, Any]:
    data = PRODUCT_ROOT + r"\data\installation-manager"
    return {
        "manifestPath": str(release_directory / "installation-manifest.json"),
        "releaseSourceDirectory": str(release_directory),
        "serviceDefinitionSources": {role: str(services_directory / (role + ".json")) for role in _required_service_roles()},
        "operatorInterfaceBootstrapSource": str(control_directory / "runtime-console-bootstrap.json"),
        "installationJournalPath": data + r"\current-transaction.json",
        "installationReceiptPath": data + r"\latest-installation-receipt.json",
        "removalJournalPath": data + r"\current-removal-transaction.json",
        "removalReceiptPath": data + r"\latest-removal-receipt.json",
        "packageManagerCompletionManagerPath": data + r"\package-manager-removal-completion.exe",
        "packageManagerCompletionManifestPath": data + r"\package-manager-removal-manifest.json",
        "wixSourcePath": str(destination / "VitalServerRuntimePlatform.wxs"),
        "manufacturer": preparation.manufacturer,
        "upgradeCode": preparation.upgrade_code,
    }


def _required_service_roles() -> tuple[str, str, str]:
    return ("host-agent", "host-edge-proxy", "host-update-handoff-supervisor")


def _current_release_path() -> str:
    return PRODUCT_ROOT + r"\current"


def _validate_contract(schema: str, document: Mapping[str, Any], label: str) -> None:
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        findings = repository.validate_instance(schema, document)
    except ContractToolError as error:
        raise WindowsHostReleaseInputPreparationError(label + " contract source is unavailable: " + str(error)) from error
    if findings:
        raise WindowsHostReleaseInputPreparationError(label + " is invalid: " + "; ".join(findings))


def _require_absolute_file(path: Path, label: str) -> None:
    if not path.is_absolute():
        raise WindowsHostReleaseInputPreparationError(label + " path must be absolute")
    if not path.is_file() or path.is_symlink():
        raise WindowsHostReleaseInputPreparationError(label + " must be one regular non-symbolic file")


def _copy_regular_file(source: Path, destination: Path) -> None:
    _require_absolute_file(source, "selected source")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def _read_json(path: Path, label: str) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise WindowsHostReleaseInputPreparationError("could not read " + label + ": " + str(error)) from error
    if not isinstance(value, dict):
        raise WindowsHostReleaseInputPreparationError(label + " must be one JSON object")
    return value


def _write_json(path: Path, document: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _required_object(document: Mapping[str, Any], key: str, label: str) -> Mapping[str, Any]:
    value = document.get(key)
    if not isinstance(value, dict):
        raise WindowsHostReleaseInputPreparationError(label + " requires object " + key)
    return value


def _required_string(document: Mapping[str, Any], key: str, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise WindowsHostReleaseInputPreparationError(label + " requires non-empty string " + key)
    return value


def _required_list(document: Mapping[str, Any], key: str, label: str) -> list[Any]:
    value = document.get(key)
    if not isinstance(value, list):
        raise WindowsHostReleaseInputPreparationError(label + " requires array " + key)
    return value


def _parse_arguments(arguments: list[str] | None = None) -> WindowsHostReleaseInputPreparation:
    parser = argparse.ArgumentParser(description="prepare one Windows C48 release input and WiX composition")
    parser.add_argument("--preparation", type=Path, required=True, help="absolute JSON WindowsHostReleaseInputPreparation document")
    values = parser.parse_args(arguments)
    document = _read_json(values.preparation, "Windows Host release input preparation")
    try:
        return WindowsHostReleaseInputPreparation(
            release_root=Path(document["releaseRoot"]),
            release_slot_id=str(document["releaseSlotId"]),
            release_delivery_plans_document=Path(document["releaseDeliveryPlansDocument"]),
            release_delivery_plan_id=str(document["releaseDeliveryPlanId"]),
            package_product_code=str(document["packageProductCode"]),
            manufacturer=str(document["manufacturer"]),
            upgrade_code=str(document["upgradeCode"]),
            host_agent_binary=Path(document["hostAgentBinary"]),
            host_edge_proxy_binary=Path(document["hostEdgeProxyBinary"]),
            host_installation_manager_binary=Path(document["hostInstallationManagerBinary"]),
            host_service_runner_binary=Path(document["hostServiceRunnerBinary"]),
            host_update_handoff_supervisor_binary=Path(document["hostUpdateHandoffSupervisorBinary"]),
            platformctl_binary=Path(document["platformctlBinary"]),
            windows_hyperv_scm_bridge_binary=Path(document["windowsHyperVSCMBridgeBinary"]),
            host_agent_deployment_configuration=Path(document["hostAgentDeploymentConfiguration"]),
            host_edge_proxy_deployment_configuration=Path(document["hostEdgeProxyDeploymentConfiguration"]),
            host_update_handoff_supervisor_configuration=Path(document["hostUpdateHandoffSupervisorConfiguration"]),
            operator_interface_bootstrap_configuration=Path(document["operatorInterfaceBootstrapConfiguration"]),
            host_update_trust_store=Path(document["hostUpdateTrustStore"]),
        )
    except (KeyError, TypeError) as error:
        raise WindowsHostReleaseInputPreparationError("Windows Host release input preparation is missing a required field: " + str(error)) from error


def main(arguments: list[str] | None = None) -> int:
    try:
        preparation = _parse_arguments(arguments)
        print(json.dumps(prepare_windows_host_release_input(preparation), sort_keys=True))
    except WindowsHostReleaseInputPreparationError as error:
        print("Windows Host release input preparation failed: " + str(error))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
