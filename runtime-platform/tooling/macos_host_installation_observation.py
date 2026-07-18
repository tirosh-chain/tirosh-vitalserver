"""Observe macOS Installer and code-signing facts without owning their meaning.

This adapter has no release, development, Host Agent, Guest Runtime, or
launchd state machine.  A caller supplies every executable and every target;
the adapter returns raw command evidence plus a narrowly decoded observation.
Release evidence and development-installation evidence apply their own guards
to these facts instead of sharing or inferring each other's state.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import plistlib
import subprocess
import tempfile
from typing import Any, Callable, Mapping, Sequence
import xml.etree.ElementTree as ElementTree


class MacOSHostInstallationObservationError(RuntimeError):
    """A declared macOS command could not be executed or decoded."""


EXPLICITLY_ABSENT_PACKAGE_RECEIPT_MARKERS = (
    "no receipt for",
    "no receipt found",
)
EXPLICITLY_ABSENT_LAUNCHD_SERVICE_MARKERS = (
    "could not find service",
    "service not found",
)


@dataclass(frozen=True)
class MacOSHostInstallationCommandObservation:
    """One exact external command result; no return-code meaning is hidden."""

    executable: Path
    arguments: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class MacOSInstallerArtifactIdentityObservation:
    """The flat-PKG identity observed from expanded PackageInfo."""

    state: str
    package_identifier: str | None
    product_version: str | None
    package_expansion_command: MacOSHostInstallationCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class MacOSPackageReceiptObservation:
    """The installed package receipt fact reported by pkgutil."""

    state: str
    package_identifier: str | None
    product_version: str | None
    command: MacOSHostInstallationCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class MacOSLaunchdServiceRegistrationObservation:
    """The current registration fact reported for one launchd service."""

    role: str
    service_label: str
    state: str
    command: MacOSHostInstallationCommandObservation


@dataclass(frozen=True)
class MacOSHostBootSessionObservation:
    """The macOS boot-session identifier observed through sysctl."""

    boot_session_identifier: str
    command: MacOSHostInstallationCommandObservation


@dataclass(frozen=True)
class MacOSVirtualMachineSupervisorCodeSignatureObservation:
    """A direct observation of one installed VM supervisor's code signature."""

    signature_state: str
    virtualization_entitlement_state: str
    signature_verification_command: MacOSHostInstallationCommandObservation
    signature_display_command: MacOSHostInstallationCommandObservation
    entitlement_display_command: MacOSHostInstallationCommandObservation
    reason: str | None = None


CommandExecutor = Callable[
    [Path, Sequence[str]], MacOSHostInstallationCommandObservation
]


def execute_macos_host_installation_command(
    executable: Path,
    arguments: Sequence[str],
) -> MacOSHostInstallationCommandObservation:
    """Execute one caller-declared macOS command and preserve raw evidence."""

    try:
        completed = subprocess.run(
            [str(executable), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise MacOSHostInstallationObservationError(
            "macOS Host installation command execution failed for "
            + str(executable)
            + ": "
            + str(error)
        ) from error
    return MacOSHostInstallationCommandObservation(
        executable=executable,
        arguments=tuple(arguments),
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def observe_macos_installer_artifact_identity(
    pkgutil_executable: Path,
    installer_artifact_path: Path,
    execute_command: CommandExecutor = execute_macos_host_installation_command,
) -> MacOSInstallerArtifactIdentityObservation:
    """Observe an uninstalled flat PKG identity through ``pkgutil --expand``."""

    with tempfile.TemporaryDirectory(
        prefix="vitalserver-macos-installer-artifact-metadata-"
    ) as temporary_directory:
        expanded_package_directory = Path(temporary_directory) / "expanded-package"
        package_expansion_command = execute_command(
            pkgutil_executable,
            ["--expand", str(installer_artifact_path), str(expanded_package_directory)],
        )
        if package_expansion_command.returncode != 0:
            return MacOSInstallerArtifactIdentityObservation(
                state="unavailable",
                package_identifier=None,
                product_version=None,
                package_expansion_command=package_expansion_command,
                reason="pkgutil package expansion returned a non-zero result",
            )
        package_info_path = expanded_package_directory / "PackageInfo"
        try:
            package_info = ElementTree.parse(package_info_path).getroot()
        except (OSError, ElementTree.ParseError) as error:
            return MacOSInstallerArtifactIdentityObservation(
                state="invalid",
                package_identifier=None,
                product_version=None,
                package_expansion_command=package_expansion_command,
                reason="expanded macOS PackageInfo cannot be decoded: " + str(error),
            )
        package_identifier = package_info.get("identifier")
        product_version = package_info.get("version")
        if not package_identifier or not product_version:
            return MacOSInstallerArtifactIdentityObservation(
                state="invalid",
                package_identifier=package_identifier,
                product_version=product_version,
                package_expansion_command=package_expansion_command,
                reason="expanded macOS PackageInfo requires identifier and version",
            )
        return MacOSInstallerArtifactIdentityObservation(
            state="available",
            package_identifier=package_identifier,
            product_version=product_version,
            package_expansion_command=package_expansion_command,
        )


def observe_macos_package_receipt(
    pkgutil_executable: Path,
    package_identifier: str,
    execute_command: CommandExecutor = execute_macos_host_installation_command,
) -> MacOSPackageReceiptObservation:
    """Observe an installed receipt without treating ambiguous failure as absence."""

    command = execute_command(pkgutil_executable, ["--pkg-info", package_identifier])
    if command.returncode == 0:
        try:
            metadata = parse_macos_installed_package_receipt_output(command.stdout)
        except MacOSHostInstallationObservationError as error:
            return MacOSPackageReceiptObservation(
                state="invalid",
                package_identifier=None,
                product_version=None,
                command=command,
                reason=str(error),
            )
        return MacOSPackageReceiptObservation(
            state="installed",
            package_identifier=metadata.get("package-id"),
            product_version=metadata.get("version"),
            command=command,
        )
    output = (command.stdout + "\n" + command.stderr).lower()
    if any(marker in output for marker in EXPLICITLY_ABSENT_PACKAGE_RECEIPT_MARKERS):
        return MacOSPackageReceiptObservation(
            state="absent",
            package_identifier=None,
            product_version=None,
            command=command,
        )
    return MacOSPackageReceiptObservation(
        state="unavailable",
        package_identifier=None,
        product_version=None,
        command=command,
        reason="pkgutil did not explicitly report the installer receipt as absent",
    )


def observe_macos_launchd_service_registration(
    launchctl_executable: Path,
    role: str,
    service_label: str,
    execute_command: CommandExecutor = execute_macos_host_installation_command,
) -> MacOSLaunchdServiceRegistrationObservation:
    """Observe one declared launchd label without inferring service absence."""

    command = execute_command(launchctl_executable, ["print", "system/" + service_label])
    if command.returncode == 0:
        state = "registered"
    else:
        output = (command.stdout + "\n" + command.stderr).lower()
        state = (
            "absent"
            if any(
                marker in output
                for marker in EXPLICITLY_ABSENT_LAUNCHD_SERVICE_MARKERS
            )
            else "unavailable"
        )
    return MacOSLaunchdServiceRegistrationObservation(
        role=role,
        service_label=service_label,
        state=state,
        command=command,
    )


def observe_macos_host_boot_session(
    sysctl_executable: Path,
    execute_command: CommandExecutor = execute_macos_host_installation_command,
) -> MacOSHostBootSessionObservation:
    """Observe one boot session; missing output remains unavailable."""

    command = execute_command(sysctl_executable, ["-n", "kern.bootsessionuuid"])
    boot_session_identifier = command.stdout.strip()
    if command.returncode != 0 or not boot_session_identifier:
        raise MacOSHostInstallationObservationError(
            "macOS Host boot-session identifier is unavailable"
        )
    return MacOSHostBootSessionObservation(
        boot_session_identifier=boot_session_identifier,
        command=command,
    )


def observe_macos_virtual_machine_supervisor_code_signature(
    codesign_executable: Path,
    supervisor_path: Path,
    execute_command: CommandExecutor = execute_macos_host_installation_command,
) -> MacOSVirtualMachineSupervisorCodeSignatureObservation:
    """Observe signature kind and virtualization entitlement without trusting labels.

    ``codesign`` diagnostics are raw evidence.  A verified signature with an
    unrecognised issuer is reported as ``unknown-signed`` rather than treated
    as ad-hoc or Developer ID.  The development workflow accepts only the
    explicit ``ad-hoc`` result.
    """

    verification_command = execute_command(
        codesign_executable,
        ["--verify", "--strict", "--verbose=4", str(supervisor_path)],
    )
    signature_display_command = execute_command(
        codesign_executable,
        ["--display", "--verbose=4", str(supervisor_path)],
    )
    entitlement_display_command = execute_command(
        codesign_executable,
        ["--display", "--entitlements", ":-", str(supervisor_path)],
    )
    if verification_command.returncode != 0:
        return MacOSVirtualMachineSupervisorCodeSignatureObservation(
            signature_state="invalid",
            virtualization_entitlement_state="not-observed",
            signature_verification_command=verification_command,
            signature_display_command=signature_display_command,
            entitlement_display_command=entitlement_display_command,
            reason="codesign strict verification returned a non-zero result",
        )
    signature_output = (
        signature_display_command.stdout + "\n" + signature_display_command.stderr
    ).lower()
    if signature_display_command.returncode != 0:
        signature_state = "unavailable"
    elif "signature=adhoc" in signature_output or "authority=adhoc" in signature_output:
        signature_state = "ad-hoc"
    elif "authority=developer id application" in signature_output:
        signature_state = "developer-id"
    elif "code object is not signed at all" in signature_output:
        signature_state = "unsigned"
    else:
        signature_state = "unknown-signed"
    if entitlement_display_command.returncode != 0:
        return MacOSVirtualMachineSupervisorCodeSignatureObservation(
            signature_state=signature_state,
            virtualization_entitlement_state="unavailable",
            signature_verification_command=verification_command,
            signature_display_command=signature_display_command,
            entitlement_display_command=entitlement_display_command,
            reason="codesign entitlement display returned a non-zero result",
        )
    try:
        entitlements = parse_displayed_macos_entitlement_plist(
            entitlement_display_command.stdout + "\n" + entitlement_display_command.stderr
        )
    except MacOSHostInstallationObservationError as error:
        return MacOSVirtualMachineSupervisorCodeSignatureObservation(
            signature_state=signature_state,
            virtualization_entitlement_state="invalid",
            signature_verification_command=verification_command,
            signature_display_command=signature_display_command,
            entitlement_display_command=entitlement_display_command,
            reason=str(error),
        )
    return MacOSVirtualMachineSupervisorCodeSignatureObservation(
        signature_state=signature_state,
        virtualization_entitlement_state=(
            "present"
            if entitlements.get("com.apple.security.virtualization") is True
            else "missing"
        ),
        signature_verification_command=verification_command,
        signature_display_command=signature_display_command,
        entitlement_display_command=entitlement_display_command,
    )


def parse_macos_installed_package_receipt_output(output: str) -> Mapping[str, str]:
    """Decode only the required installed receipt fields from pkgutil output."""

    metadata: dict[str, str] = {}
    for line in output.splitlines():
        key, separator, value = line.partition(":")
        if separator and key and value.strip():
            metadata[key.strip()] = value.strip()
    if not metadata.get("package-id") or not metadata.get("version"):
        raise MacOSHostInstallationObservationError(
            "pkgutil output does not contain package-id and version"
        )
    return metadata


def parse_displayed_macos_entitlement_plist(
    codesign_display_output: str,
) -> Mapping[str, Any]:
    """Extract an entitlement plist from mixed codesign diagnostics."""

    xml_start = codesign_display_output.find("<?xml")
    xml_end = codesign_display_output.find("</plist>", xml_start)
    if xml_start < 0 or xml_end < 0:
        raise MacOSHostInstallationObservationError(
            "macOS code-signature observation did not display an entitlement plist"
        )
    try:
        entitlement_document = plistlib.loads(
            codesign_display_output[xml_start : xml_end + len("</plist>")].encode(
                "utf-8"
            )
        )
    except (plistlib.InvalidFileException, ValueError) as error:
        raise MacOSHostInstallationObservationError(
            "macOS code-signature observation displayed entitlement plist is invalid"
        ) from error
    if not isinstance(entitlement_document, dict):
        raise MacOSHostInstallationObservationError(
            "macOS code-signature observation entitlement plist must be a dictionary"
        )
    return entitlement_document


def command_document(
    command: MacOSHostInstallationCommandObservation,
) -> Mapping[str, Any]:
    return {
        "executable": str(command.executable),
        "arguments": list(command.arguments),
        "returnCode": command.returncode,
        "stdout": command.stdout,
        "stderr": command.stderr,
    }


def installer_artifact_identity_document(
    observation: MacOSInstallerArtifactIdentityObservation,
) -> Mapping[str, Any]:
    return {
        "state": observation.state,
        "packageIdentifier": observation.package_identifier,
        "productVersion": observation.product_version,
        "reason": observation.reason,
        "packageExpansionCommand": command_document(
            observation.package_expansion_command
        ),
    }


def package_receipt_document(
    observation: MacOSPackageReceiptObservation,
) -> Mapping[str, Any]:
    return {
        "state": observation.state,
        "packageIdentifier": observation.package_identifier,
        "productVersion": observation.product_version,
        "reason": observation.reason,
        "command": command_document(observation.command),
    }


def launchd_service_registration_document(
    observation: MacOSLaunchdServiceRegistrationObservation,
) -> Mapping[str, Any]:
    return {
        "role": observation.role,
        "serviceLabel": observation.service_label,
        "state": observation.state,
        "command": command_document(observation.command),
    }


def boot_session_document(
    observation: MacOSHostBootSessionObservation,
) -> Mapping[str, Any]:
    return {
        "bootSessionIdentifier": observation.boot_session_identifier,
        "command": command_document(observation.command),
    }


def virtual_machine_supervisor_code_signature_document(
    observation: MacOSVirtualMachineSupervisorCodeSignatureObservation,
) -> Mapping[str, Any]:
    return {
        "signatureState": observation.signature_state,
        "virtualizationEntitlementState": observation.virtualization_entitlement_state,
        "reason": observation.reason,
        "signatureVerificationCommand": command_document(
            observation.signature_verification_command
        ),
        "signatureDisplayCommand": command_document(
            observation.signature_display_command
        ),
        "entitlementDisplayCommand": command_document(
            observation.entitlement_display_command
        ),
    }
