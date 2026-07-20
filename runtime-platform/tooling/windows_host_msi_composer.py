"""Compose a WiX v4 source document for one explicit Windows C48 release.

This module deliberately separates an MSI *authoring source* from an MSI
artifact.  WiX is an external Windows build tool; without an explicit WiX v4
executable and its Util extension, this composer publishes only the reviewable
source and never claims an installable MSI exists.

The source carries the explicit Windows package-manager lifecycle:

* C50 runs after ``InstallFiles`` while MSI registration is not observable;
  the request therefore declares ``windows-msi-installing`` explicitly.
* C54 runs before ``RemoveFiles`` from the installed release, stops/deletes
  only declared SCM services and removes the activation junction, then returns
  control to MSI.  It leaves the exact immutable release for MSI because a
  running Windows executable cannot delete itself.
* a commit custom action invokes C54's durable completion transport after the
  MSI transaction commits, when the ProductCode receipt is observably absent.

No custom action infers package-manager state, recursively runs ``msiexec``,
or embeds a second Host Installation Manager executable.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path, PureWindowsPath
import shutil
import subprocess
from typing import Any, Mapping
import uuid
import xml.etree.ElementTree as ElementTree

from tooling.contracts import ContractRepository, ContractToolError


class WindowsHostMSICompositionError(RuntimeError):
    """Raised when one release cannot be represented as the declared MSI."""


_WINDOWS_PRODUCT_ROOT = r"C:\ProgramData\VitalServerRuntimePlatform"
_WIX_NAMESPACE = "http://wixtoolset.org/schemas/v4/wxs"
_WIX_UTIL_EXTENSION = "WixToolset.Util.wixext"
_WIX_ARCHITECTURE = "x64"
_COMMAND_LINE_UNSAFE = set('"&|<>^\r\n')


@dataclass(frozen=True)
class WindowsHostMSIComposition:
    """All explicit inputs for one WiX v4 MSI authoring document.

    ``wix_executable_path`` and ``output_package`` are an all-or-nothing pair.
    Supplying neither produces only ``wix_source_path``; supplying both asks the
    configured external WiX toolchain to compile that source.  This keeps
    source generation useful on macOS/Linux release workstations without
    mislabeling generated XML as an MSI artifact.
    """

    manifest_path: Path
    release_source_directory: Path
    service_definition_sources: Mapping[str, Path]
    operator_interface_bootstrap_source: Path
    installation_journal_path: str
    installation_receipt_path: str
    removal_journal_path: str
    removal_receipt_path: str
    package_manager_completion_manager_path: str
    package_manager_completion_manifest_path: str
    wix_source_path: Path
    manufacturer: str
    upgrade_code: str
    wix_executable_path: Path | None = None
    output_package: Path | None = None
    replace_output: bool = False


def compose_windows_host_msi(composition: WindowsHostMSIComposition) -> dict[str, str]:
    """Validate one Windows C48 and publish WiX source or an explicit MSI.

    The function never probes an installed Host.  Every installed file and
    every custom-action argument comes from C48 plus explicit composition
    input, so a source review has the same lifecycle meaning as the artifact.
    """

    manifest = _read_manifest(composition.manifest_path)
    _validate_composition(composition, manifest)
    if composition.wix_source_path.exists() and not composition.replace_output:
        raise WindowsHostMSICompositionError("WiX source output already exists: " + str(composition.wix_source_path))
    if composition.output_package is not None and composition.output_package.exists() and not composition.replace_output:
        raise WindowsHostMSICompositionError("MSI output already exists: " + str(composition.output_package))

    source = _render_wix_source(composition, manifest)
    composition.wix_source_path.parent.mkdir(parents=True, exist_ok=True)
    composition.wix_source_path.write_text(source, encoding="utf-8")

    result = {
        "artifactKind": "wix-source",
        "artifactPath": str(composition.wix_source_path),
        "wixSourcePath": str(composition.wix_source_path),
        "sha256": _sha256_file(composition.wix_source_path),
        "productCode": _required_string(_required_object(manifest, "package", "C48"), "packageManagerIdentifier", "Windows C48 package"),
        "productVersion": _required_string(_required_object(manifest, "package", "C48"), "productVersion", "Windows C48 package"),
    }
    if composition.wix_executable_path is None:
        return result

    assert composition.output_package is not None
    _compile_msi(composition)
    result.update(
        {
            "artifactKind": "msi",
            "artifactPath": str(composition.output_package),
            "sha256": _sha256_file(composition.output_package),
            "sizeBytes": str(composition.output_package.stat().st_size),
        }
    )
    return result


def _read_manifest(path: Path) -> Mapping[str, Any]:
    document = _read_json(path, "C48 HostProductInstallationManifest")
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        findings = repository.validate_instance("host-product-installation-manifest.schema.json", document)
    except ContractToolError as error:
        raise WindowsHostMSICompositionError("C48 contract source is unavailable: " + str(error)) from error
    if findings:
        raise WindowsHostMSICompositionError("C48 is invalid: " + "; ".join(findings))
    if document.get("platform") != "windows":
        raise WindowsHostMSICompositionError("Windows MSI composer requires C48 platform windows")
    return document


def _validate_composition(composition: WindowsHostMSIComposition, manifest: Mapping[str, Any]) -> None:
    if not composition.manufacturer.strip():
        raise WindowsHostMSICompositionError("MSI manufacturer is required")
    if not _is_guid(composition.upgrade_code):
        raise WindowsHostMSICompositionError("MSI UpgradeCode must be one braced GUID")
    if (composition.wix_executable_path is None) != (composition.output_package is None):
        raise WindowsHostMSICompositionError("WiX executable and MSI output must be supplied together")
    if composition.wix_executable_path is not None and (not composition.wix_executable_path.is_file() or composition.wix_executable_path.is_symlink()):
        raise WindowsHostMSICompositionError("configured WiX executable is unavailable or symbolic")
    if not composition.release_source_directory.is_dir() or composition.release_source_directory.is_symlink():
        raise WindowsHostMSICompositionError("C48 release source directory is unavailable or symbolic")
    expected_manifest = composition.release_source_directory / "installation-manifest.json"
    if expected_manifest.resolve() != composition.manifest_path.resolve():
        raise WindowsHostMSICompositionError("C48 manifest must be the installation-manifest.json in the selected release source")

    package = _required_object(manifest, "package", "C48")
    product_code = _required_string(package, "packageManagerIdentifier", "Windows C48 package")
    if not _is_guid(product_code):
        raise WindowsHostMSICompositionError("Windows C48 packageManagerIdentifier must be an MSI ProductCode")
    product_version = _required_string(package, "productVersion", "Windows C48 package")
    if not _is_msi_version(product_version):
        raise WindowsHostMSICompositionError("Windows C48 package productVersion must be an MSI numeric version (major.minor.build)")

    release = _required_object(manifest, "release", "C48")
    immutable = _required_object(manifest, "immutablePayload", "C48")
    release_root = _required_string(immutable, "releaseRootPath", "C48 immutablePayload")
    _require_product_path(release_root, "C48 immutable release root")
    if _normalized_windows_path(release_root) != _normalized_windows_path(_WINDOWS_PRODUCT_ROOT + "\\releases\\" + _required_string(release, "id", "C48 release")):
        raise WindowsHostMSICompositionError("Windows C48 immutable release root must be the declared ProgramData release slot")
    _require_product_path(_required_string(immutable, "releaseCatalogPath", "C48 immutablePayload"), "C48 immutable release catalog")
    _require_product_path(_required_string(immutable, "manifestPath", "C48 immutablePayload"), "C48 immutable manifest")
    _validate_declared_release_files(composition.release_source_directory, immutable)
    manager_source = composition.release_source_directory / "bin" / "host-installation-manager.exe"
    if not manager_source.is_file() or manager_source.is_symlink():
        raise WindowsHostMSICompositionError("C48 release source must contain a regular bin/host-installation-manager.exe")
    service_runner_source = composition.release_source_directory / "bin" / "host-service-runner.exe"
    if not service_runner_source.is_file() or service_runner_source.is_symlink():
        raise WindowsHostMSICompositionError("C48 release source must contain a regular bin/host-service-runner.exe")

    activation = _required_object(manifest, "activation", "C48")
    if activation.get("referenceKind") != "directory-junction":
        raise WindowsHostMSICompositionError("Windows C48 activation must use a directory-junction")
    _require_product_path(_required_string(activation, "currentReleaseLinkPath", "C48 activation"), "C48 activation path")
    if _normalized_windows_path(_required_string(activation, "currentReleaseLinkPath", "C48 activation")) != _normalized_windows_path(_WINDOWS_PRODUCT_ROOT + r"\current"):
        raise WindowsHostMSICompositionError("Windows C48 activation path must be the declared ProgramData current junction")

    operator = _required_object(manifest, "operatorInterface", "C48")
    _verify_file_hash(composition.operator_interface_bootstrap_source, _required_string(operator, "bootstrapConfigurationSha256", "C48 operatorInterface"), "C53 bootstrap source")
    _require_product_path(_required_string(operator, "bootstrapConfigurationPath", "C48 operatorInterface"), "C48 bootstrap path")

    services = _required_list(manifest, "requiredServices", "C48")
    if set(composition.service_definition_sources) != {str(service["role"]) for service in services}:
        raise WindowsHostMSICompositionError("every and only C48 service role must have one service-definition source")
    for service in services:
        if service.get("manager") != "windows-scm":
            raise WindowsHostMSICompositionError("Windows C48 service manager must be windows-scm")
        registration = _required_object(service, "windowsScmRegistration", "Windows C48 requiredService")
        definition_path = _required_string(service, "definitionPath", "C48 requiredService")
        _require_product_path(definition_path, "C48 service definition path")
        _require_product_path(_required_string(registration, "executablePath", "C48 SCM registration"), "C48 SCM executable path")
        if registration.get("startMode") != "automatic" or registration.get("account") != "LocalSystem":
            raise WindowsHostMSICompositionError("Windows C48 SCM registration must declare automatic LocalSystem")
        definition_source = composition.service_definition_sources[str(service["role"])]
        _verify_file_hash(definition_source, _required_string(service, "definitionSha256", "C48 requiredService"), "C48 SCM definition " + str(service["role"]))
        _validate_windows_service_execution_definition(service, registration, _read_json(definition_source, "C48 Host service execution definition"), _required_string(activation, "currentReleaseLinkPath", "C48 activation"), definition_path)

    for path, context in (
        (composition.installation_journal_path, "installation journal path"),
        (composition.installation_receipt_path, "installation receipt path"),
        (composition.removal_journal_path, "removal journal path"),
        (composition.removal_receipt_path, "removal receipt path"),
        (composition.package_manager_completion_manager_path, "package-manager completion manager path"),
        (composition.package_manager_completion_manifest_path, "package-manager completion manifest path"),
    ):
        _require_product_path(path, context)
    if not composition.package_manager_completion_manager_path.lower().endswith(r"\package-manager-removal-completion.exe") or not composition.package_manager_completion_manifest_path.lower().endswith(r"\package-manager-removal-manifest.json"):
        raise WindowsHostMSICompositionError("Windows C54 completion transport paths are invalid")
    _require_manager_owned_transport(composition, manifest)


def _render_wix_source(composition: WindowsHostMSIComposition, manifest: Mapping[str, Any]) -> str:
    ElementTree.register_namespace("", _WIX_NAMESPACE)
    wix = ElementTree.Element(_tag("Wix"))
    package = _required_object(manifest, "package", "C48")
    release = _required_object(manifest, "release", "C48")
    package_element = ElementTree.SubElement(
        wix,
        _tag("Package"),
        {
            "Name": _required_string(package, "identifier", "C48 package"),
            "Manufacturer": composition.manufacturer,
            "Version": _required_string(package, "productVersion", "C48 package"),
            "ProductCode": _required_string(package, "packageManagerIdentifier", "C48 package"),
            "UpgradeCode": composition.upgrade_code,
            "Language": "1033",
            "Scope": "perMachine",
            "InstallerVersion": "500",
        },
    )
    ElementTree.SubElement(package_element, _tag("MediaTemplate"), {"EmbedCab": "yes"})
    # C68, not Windows Installer major-upgrade, owns a version-changing Host
    # release. MSI detects a related ProductCode before files are written and
    # rejects that direct invocation; it must not schedule
    # RemoveExistingProducts as an implicit update workflow.
    upgrade = ElementTree.SubElement(package_element, _tag("Upgrade"), {"Id": composition.upgrade_code})
    ElementTree.SubElement(upgrade, _tag("UpgradeVersion"), {"OnlyDetect": "yes", "Property": "VITALSERVER_RUNTIME_PLATFORM_DIRECT_UPDATE"})
    ElementTree.SubElement(
        package_element,
        _tag("Launch"),
        {
            "Condition": "Installed OR NOT VITALSERVER_RUNTIME_PLATFORM_DIRECT_UPDATE",
            "Message": "Direct Windows MSI version upgrades are unsupported; use the staged Host Updater.",
        },
    )
    standard_root = ElementTree.SubElement(package_element, _tag("StandardDirectory"), {"Id": "CommonAppDataFolder"})
    product_root = ElementTree.SubElement(standard_root, _tag("Directory"), {"Id": "VitalServerRuntimePlatformDirectory", "Name": "VitalServerRuntimePlatform"})

    files = _declared_payload_files(composition, manifest)
    file_ids, component_ids = _write_directory_tree(product_root, files, _required_string(release, "id", "C48 release"))
    manager_file_id = file_ids.get("releases\\" + _required_string(release, "id", "C48 release") + "\\bin\\host-installation-manager.exe")
    if manager_file_id is None:
        raise WindowsHostMSICompositionError("C48 payload file mapping lost host-installation-manager.exe")

    # Windows Installer installs Components through Features. Keep every C48
    # payload component explicit here instead of relying on a linker default:
    # a missing reference would otherwise make a file present in the WiX
    # source but absent from the installed product and C50/C54 lifecycle.
    feature = ElementTree.SubElement(
        package_element,
        _tag("Feature"),
        {
            "Id": "VitalServerRuntimePlatformFeature",
            "Title": "VitalServer Runtime Platform",
            "Level": "1",
            "InstallDefault": "local",
            "AllowAdvertise": "no",
        },
    )
    for component_id in component_ids:
        ElementTree.SubElement(feature, _tag("ComponentRef"), {"Id": component_id})

    _write_lifecycle_custom_actions(package_element, composition, manifest, manager_file_id)
    tree = ElementTree.ElementTree(wix)
    ElementTree.indent(tree, space="  ")
    return "<?xml version='1.0' encoding='utf-8'?>\n" + ElementTree.tostring(wix, encoding="unicode") + "\n"


def _declared_payload_files(composition: WindowsHostMSIComposition, manifest: Mapping[str, Any]) -> list[tuple[str, Path]]:
    immutable = _required_object(manifest, "immutablePayload", "C48")
    payload: list[tuple[str, Path]] = []
    for entry in _required_list(immutable, "entries", "C48 immutablePayload"):
        relative = _safe_relative_path(_required_string(entry, "relativePath", "C48 immutable entry"))
        payload.append((_target_relative_path(_required_string(immutable, "releaseRootPath", "C48 immutablePayload"), str(relative).replace("/", "\\")), composition.release_source_directory / relative))
    payload.append((_target_relative_path(_required_string(immutable, "manifestPath", "C48 immutablePayload")), composition.manifest_path))
    for service in _required_list(manifest, "requiredServices", "C48"):
        payload.append((_target_relative_path(_required_string(service, "definitionPath", "C48 requiredService")), composition.service_definition_sources[str(service["role"])]))
    operator = _required_object(manifest, "operatorInterface", "C48")
    payload.append((_target_relative_path(_required_string(operator, "bootstrapConfigurationPath", "C48 operatorInterface")), composition.operator_interface_bootstrap_source))
    if len({target.lower() for target, _ in payload}) != len(payload):
        raise WindowsHostMSICompositionError("C48 payload maps more than one source to one MSI target")
    return sorted(payload, key=lambda entry: entry[0].lower())


def _write_directory_tree(root: ElementTree.Element, files: list[tuple[str, Path]], release_id: str) -> tuple[dict[str, str], list[str]]:
    directories: dict[str, ElementTree.Element] = {"": root}
    file_ids: dict[str, str] = {}
    component_ids: list[str] = []
    for target, source in files:
        path = PureWindowsPath(target)
        parent_key = ""
        parent = root
        for part in path.parts[:-1]:
            parent_key = part if not parent_key else parent_key + "\\" + part
            if parent_key not in directories:
                directories[parent_key] = ElementTree.SubElement(parent, _tag("Directory"), {"Id": _identifier("Directory", parent_key), "Name": part})
            parent = directories[parent_key]
        component_id = _identifier("Component", target)
        component = ElementTree.SubElement(parent, _tag("Component"), {"Id": component_id, "Guid": _stable_guid("component:" + release_id + ":" + target)})
        file_id = _identifier("File", target)
        ElementTree.SubElement(component, _tag("File"), {"Id": file_id, "Source": str(source), "KeyPath": "yes"})
        file_ids[target] = file_id
        component_ids.append(component_id)
    return file_ids, component_ids


def _write_lifecycle_custom_actions(package: ElementTree.Element, composition: WindowsHostMSIComposition, manifest: Mapping[str, Any], manager_file_id: str) -> None:
    immutable = _required_object(manifest, "immutablePayload", "C48")
    manager = '"[#' + manager_file_id + ']"'
    manifest_path = _quoted(_required_string(immutable, "manifestPath", "C48 immutablePayload"))
    common = " --manifest {manifest} --journal {journal} --receipt {receipt}".format(
        manifest=manifest_path,
        journal=_quoted(composition.installation_journal_path),
        receipt=_quoted(composition.installation_receipt_path),
    )
    request = " --request-id {request} --installation-id {installation} --release-id {release}".format(
        request=_quoted(_required_string(_required_object(manifest, "package", "C48"), "identifier", "C48 package") + "-msi-install"),
        installation=_quoted(_required_string(manifest, "installationId", "C48")),
        release=_quoted(_required_string(_required_object(manifest, "release", "C48"), "id", "C48 release")),
    )
    commands = {
        "C50PreflightFresh": manager + " --mode preflight --package-manager-operation windows-msi-installing" + common + request,
        "C50PreflightRepair": manager + " --mode preflight" + common + request,
        "C50Quiesce": manager + " --mode quiesce" + common,
        "C50Activate": manager + " --mode activate" + common,
        "C50Finalize": manager + " --mode finalize" + common,
        "C54Remove": manager + " --mode remove" + common + " --request-id " + _quoted(_required_string(_required_object(manifest, "package", "C48"), "identifier", "C48 package") + "-msi-remove") + " --installation-id " + _quoted(_required_string(manifest, "installationId", "C48")) + " --release-id " + _quoted(_required_string(_required_object(manifest, "release", "C48"), "id", "C48 release")) + " --data-disposition preserve-mutable-data --removal-journal " + _quoted(composition.removal_journal_path) + " --removal-receipt " + _quoted(composition.removal_receipt_path) + " --package-manager-completion-manager " + _quoted(composition.package_manager_completion_manager_path) + " --package-manager-completion-manifest " + _quoted(composition.package_manager_completion_manifest_path),
        "C54PackageManagerCompletion": _quoted(composition.package_manager_completion_manager_path) + " --mode complete-removal-after-package-manager --manifest " + _quoted(composition.package_manager_completion_manifest_path) + " --journal " + _quoted(composition.installation_journal_path) + " --receipt " + _quoted(composition.installation_receipt_path) + " --removal-journal " + _quoted(composition.removal_journal_path) + " --removal-receipt " + _quoted(composition.removal_receipt_path),
    }
    for action_id, command in commands.items():
        ElementTree.SubElement(package, _tag("SetProperty"), {"Id": action_id, "Value": command, "Before": action_id, "Sequence": "execute"})
        attributes = {"Id": action_id, "BinaryRef": "Wix4UtilCA_$(sys.BUILDARCHSHORT)", "DllEntry": "WixQuietExec64", "Return": "check", "Impersonate": "no"}
        attributes["Execute"] = "commit" if action_id == "C54PackageManagerCompletion" else "deferred"
        ElementTree.SubElement(package, _tag("CustomAction"), attributes)
    sequence = ElementTree.SubElement(package, _tag("InstallExecuteSequence"))
    non_removal = 'NOT REMOVE="ALL"'
    ElementTree.SubElement(sequence, _tag("Custom"), {"Action": "C50PreflightFresh", "After": "InstallFiles", "Condition": "NOT Installed AND " + non_removal})
    ElementTree.SubElement(sequence, _tag("Custom"), {"Action": "C50PreflightRepair", "After": "C50PreflightFresh", "Condition": "Installed AND " + non_removal})
    ElementTree.SubElement(sequence, _tag("Custom"), {"Action": "C50Quiesce", "After": "C50PreflightRepair", "Condition": non_removal})
    ElementTree.SubElement(sequence, _tag("Custom"), {"Action": "C50Activate", "After": "C50Quiesce", "Condition": non_removal})
    ElementTree.SubElement(sequence, _tag("Custom"), {"Action": "C50Finalize", "After": "C50Activate", "Condition": non_removal})
    ElementTree.SubElement(sequence, _tag("Custom"), {"Action": "C54Remove", "Before": "RemoveFiles", "Condition": 'REMOVE="ALL"'})
    ElementTree.SubElement(sequence, _tag("Custom"), {"Action": "C54PackageManagerCompletion", "Before": "InstallFinalize", "Condition": 'REMOVE="ALL"'})


def _compile_msi(composition: WindowsHostMSIComposition) -> None:
    assert composition.wix_executable_path is not None
    assert composition.output_package is not None
    composition.output_package.parent.mkdir(parents=True, exist_ok=True)
    command = [str(composition.wix_executable_path), "build", str(composition.wix_source_path), "-arch", _WIX_ARCHITECTURE, "-ext", _WIX_UTIL_EXTENSION, "-o", str(composition.output_package)]
    try:
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
    except OSError as error:
        raise WindowsHostMSICompositionError("run configured WiX executable: " + str(error)) from error
    if completed.returncode != 0:
        detail = (completed.stdout + "\n" + completed.stderr).strip()
        raise WindowsHostMSICompositionError("WiX build failed: " + detail)
    if not composition.output_package.is_file() or composition.output_package.is_symlink() or composition.output_package.stat().st_size == 0:
        raise WindowsHostMSICompositionError("WiX reported success but did not publish one regular MSI")


def _validate_declared_release_files(root: Path, immutable: Mapping[str, Any]) -> None:
    declared = {"installation-manifest.json"}
    for entry in _required_list(immutable, "entries", "C48 immutablePayload"):
        relative = _safe_relative_path(_required_string(entry, "relativePath", "C48 immutable entry"))
        declared.add(relative.as_posix())
        _verify_file_hash(root / relative, _required_string(entry, "sha256", "C48 immutable entry"), "C48 immutable source " + relative.as_posix())
    actual = set()
    for source in root.rglob("*"):
        if source.is_dir():
            continue
        if source.is_symlink() or not source.is_file():
            raise WindowsHostMSICompositionError("C48 release source contains an unsupported filesystem entry")
        actual.add(source.relative_to(root).as_posix())
    if actual != declared:
        raise WindowsHostMSICompositionError("C48 release source does not contain exactly its immutable manifest and declared entries")


def _require_manager_owned_transport(composition: WindowsHostMSIComposition, manifest: Mapping[str, Any]) -> None:
    manager_paths = {
        _normalized_windows_path(str(store["path"]))
        for store in _required_list(manifest, "mutableStores", "C48")
        if store.get("owner") == "host-installation-manager" and store.get("retention") == "purge-only-by-explicit-command"
    }
    manager = _normalized_windows_path(composition.package_manager_completion_manager_path)
    manifest_path = _normalized_windows_path(composition.package_manager_completion_manifest_path)
    if not any(manager.startswith(path + "\\") and manifest_path.startswith(path + "\\") for path in manager_paths):
        raise WindowsHostMSICompositionError("Windows C54 completion transport must be below one declared manager-owned mutable store")


def _target_relative_path(value: str, suffix: str = "") -> str:
    path = _normalized_windows_path(value)
    root = _normalized_windows_path(_WINDOWS_PRODUCT_ROOT)
    if not path.startswith(root + "\\"):
        raise WindowsHostMSICompositionError("C48 payload path is outside the declared ProgramData product root")
    relative = path[len(root) + 1 :]
    if suffix:
        relative = relative.rstrip("\\") + "\\" + suffix
    return relative


def _require_product_path(value: str, context: str) -> None:
    normalized = _normalized_windows_path(value)
    root = _normalized_windows_path(_WINDOWS_PRODUCT_ROOT)
    if normalized != root and not normalized.startswith(root + "\\"):
        raise WindowsHostMSICompositionError(context + " must be a safe path below " + _WINDOWS_PRODUCT_ROOT)
    if any(character in _COMMAND_LINE_UNSAFE for character in value):
        raise WindowsHostMSICompositionError(context + " contains a character unsafe for explicit MSI command transport")


def _normalized_windows_path(value: str) -> str:
    if not isinstance(value, str) or not value or any(character in "\x00\r\n" for character in value):
        raise WindowsHostMSICompositionError("Windows path is missing or invalid")
    path = PureWindowsPath(value)
    if path.drive.lower() != "c:" or not path.is_absolute() or any(part in {".", ".."} for part in path.parts):
        raise WindowsHostMSICompositionError("Windows path must be an absolute C: path without traversal")
    return str(path).rstrip("\\").lower()


def _is_guid(value: str) -> bool:
    if not isinstance(value, str) or len(value) != 38 or not value.startswith("{") or not value.endswith("}"):
        return False
    try:
        uuid.UUID(value[1:-1])
    except ValueError:
        return False
    return True


def _is_msi_version(value: str) -> bool:
    parts = value.split(".")
    if len(parts) != 3:
        return False
    maximums = (255, 255, 65535)
    for part, maximum in zip(parts, maximums):
        if not part or (len(part) > 1 and part[0] == "0"):
            return False
        try:
            number = int(part)
        except ValueError:
            return False
        if number < 0 or number > maximum:
            return False
    return True


def _safe_relative_path(value: str) -> Path:
    path = Path(value)
    if path.is_absolute() or value in {"", "."} or "\\" in value or any(part in {"", ".", ".."} for part in path.parts):
        raise WindowsHostMSICompositionError("C48 immutable relative path is unsafe")
    return path


def _validate_windows_service_execution_definition(service: Mapping[str, Any], registration: Mapping[str, Any], definition: Mapping[str, Any], current_release_link_path: str, definition_path: str) -> None:
    expected_definition_keys = {"schemaVersion", "documentKind", "serviceName", "role", "command"}
    if set(definition) != expected_definition_keys:
        raise WindowsHostMSICompositionError("C48 Host service execution definition fields are invalid")
    role = _required_string(service, "role", "C48 requiredService")
    service_name = _required_string(service, "name", "C48 requiredService")
    if definition.get("schemaVersion") != "v1" or definition.get("documentKind") != "host-service-execution-definition" or definition.get("role") != role or definition.get("serviceName") != service_name:
        raise WindowsHostMSICompositionError("C48 Host service execution definition identity does not match its required service")
    command = _required_object(definition, "command", "C48 Host service execution definition")
    if set(command) != {"executablePath", "arguments"}:
        raise WindowsHostMSICompositionError("C48 Host service execution definition command fields are invalid")
    expected_child_path = current_release_link_path + "\\bin\\" + role + ".exe"
    if _normalized_windows_path(_required_string(command, "executablePath", "C48 Host service execution definition command")) != _normalized_windows_path(expected_child_path):
        raise WindowsHostMSICompositionError("C48 Host service execution definition command must name its current-release role executable")
    _required_string_list(command, "arguments", "C48 Host service execution definition command")
    expected_runner_path = current_release_link_path + r"\bin\host-service-runner.exe"
    if _normalized_windows_path(_required_string(registration, "executablePath", "C48 SCM registration")) != _normalized_windows_path(expected_runner_path) or _required_string_list(registration, "arguments", "C48 SCM registration") != ["--service-definition", definition_path]:
        raise WindowsHostMSICompositionError("C48 SCM registration must use the declared Host service runner and definition path")


def _required_object(value: Mapping[str, Any], key: str, context: str) -> Mapping[str, Any]:
    child = value.get(key)
    if not isinstance(child, dict):
        raise WindowsHostMSICompositionError(context + " requires object " + key)
    return child


def _required_list(value: Mapping[str, Any], key: str, context: str) -> list[Mapping[str, Any]]:
    child = value.get(key)
    if not isinstance(child, list) or not all(isinstance(item, dict) for item in child):
        raise WindowsHostMSICompositionError(context + " requires object array " + key)
    return child


def _required_string_list(value: Mapping[str, Any], key: str, context: str) -> list[str]:
    child = value.get(key)
    if not isinstance(child, list) or len(child) > 64 or not all(isinstance(item, str) and 0 < len(item) <= 4096 and "\x00" not in item for item in child):
        raise WindowsHostMSICompositionError(context + " requires a bounded string array " + key)
    return child


def _required_string(value: Mapping[str, Any], key: str, context: str) -> str:
    child = value.get(key)
    if not isinstance(child, str) or not child:
        raise WindowsHostMSICompositionError(context + " requires string " + key)
    return child


def _verify_file_hash(path: Path, expected: str, context: str) -> None:
    if not path.is_file() or path.is_symlink():
        raise WindowsHostMSICompositionError(context + " is missing or symbolic")
    if _sha256_file(path) != expected:
        raise WindowsHostMSICompositionError(context + " SHA-256 does not match C48")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _identifier(prefix: str, value: str) -> str:
    return prefix + hashlib.sha256(value.encode("utf-8")).hexdigest()[:24]


def _stable_guid(value: str) -> str:
    return "{" + str(uuid.uuid5(uuid.NAMESPACE_URL, "https://tirosh.example/vitalserver-runtime-platform/" + value)).upper() + "}"


def _quoted(value: str) -> str:
    return '"' + value + '"'


def _tag(name: str) -> str:
    return "{" + _WIX_NAMESPACE + "}" + name


def _read_json(path: Path, description: str) -> Mapping[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise WindowsHostMSICompositionError(description + " is missing or symbolic")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise WindowsHostMSICompositionError("read " + description + ": " + str(error)) from error
    if not isinstance(value, dict):
        raise WindowsHostMSICompositionError(description + " must be one JSON object")
    return value


def _parse_arguments(arguments: list[str] | None = None) -> WindowsHostMSIComposition:
    parser = argparse.ArgumentParser(description="compose Windows WiX v4 source or an MSI for VitalServer Runtime Platform")
    parser.add_argument("--composition", required=True, type=Path, help="JSON WindowsHostMSIComposition document")
    values = parser.parse_args(arguments)
    document = _read_json(values.composition, "Windows Host MSI composition")
    try:
        return WindowsHostMSIComposition(
            manifest_path=Path(document["manifestPath"]),
            release_source_directory=Path(document["releaseSourceDirectory"]),
            service_definition_sources={str(key): Path(value) for key, value in document["serviceDefinitionSources"].items()},
            operator_interface_bootstrap_source=Path(document["operatorInterfaceBootstrapSource"]),
            installation_journal_path=str(document["installationJournalPath"]),
            installation_receipt_path=str(document["installationReceiptPath"]),
            removal_journal_path=str(document["removalJournalPath"]),
            removal_receipt_path=str(document["removalReceiptPath"]),
            package_manager_completion_manager_path=str(document["packageManagerCompletionManagerPath"]),
            package_manager_completion_manifest_path=str(document["packageManagerCompletionManifestPath"]),
            wix_source_path=Path(document["wixSourcePath"]),
            manufacturer=str(document["manufacturer"]),
            upgrade_code=str(document["upgradeCode"]),
            wix_executable_path=Path(document["wixExecutablePath"]) if document.get("wixExecutablePath") is not None else None,
            output_package=Path(document["outputPackage"]) if document.get("outputPackage") is not None else None,
            replace_output=bool(document.get("replaceOutput", False)),
        )
    except (KeyError, TypeError) as error:
        raise WindowsHostMSICompositionError("Windows Host MSI composition is missing one required field: " + str(error)) from error


def main(arguments: list[str] | None = None) -> int:
    try:
        composition = _parse_arguments(arguments)
        print(json.dumps(compose_windows_host_msi(composition), sort_keys=True))
    except WindowsHostMSICompositionError as error:
        print("Windows Host MSI composition failed: " + str(error))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
