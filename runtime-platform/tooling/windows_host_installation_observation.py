"""Observe Windows installer and SCM facts through explicit command contracts.

This adapter owns subprocess execution and decoding of Windows-owned output.
It does not decide whether an observation proves a clean Host or a successful
release stage.  Those are C24 workflow decisions made by the evidence runner.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
from typing import Any, Callable, Mapping, Sequence


class WindowsHostInstallationObservationError(RuntimeError):
    """A Windows command result cannot be used as an explicit observation."""


@dataclass(frozen=True)
class WindowsHostInstallationCommandObservation:
    executable: Path
    arguments: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class WindowsMSIArtifactIdentityObservation:
    state: str
    product_version: str | None
    signature_state: str | None
    metadata_command: WindowsHostInstallationCommandObservation
    signature_command: WindowsHostInstallationCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class WindowsMSIRegistrationObservation:
    product_code: str
    state: str
    product_version: str | None
    command: WindowsHostInstallationCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class WindowsSCMServiceRegistrationObservation:
    role: str
    service_name: str
    state: str
    command: WindowsHostInstallationCommandObservation


@dataclass(frozen=True)
class WindowsHostBootSessionObservation:
    boot_session_identifier: str
    command: WindowsHostInstallationCommandObservation


CommandExecutor = Callable[
    [Path, Sequence[str]], WindowsHostInstallationCommandObservation
]


WINDOWS_MSI_PRODUCT_VERSION_SCRIPT = (
    "$installer=New-Object -ComObject WindowsInstaller.Installer;"
    "$database=$installer.OpenDatabase($args[0],0);"
    "$view=$database.OpenView(\"SELECT `Value` FROM `Property` "
    "WHERE `Property` = 'ProductVersion'\");"
    "$view.Execute();$record=$view.Fetch();"
    "if($null -eq $record){exit 3};"
    "[Console]::Out.Write($record.StringData(1))"
)
WINDOWS_MSI_SIGNATURE_SCRIPT = (
    "$signature=Get-AuthenticodeSignature -LiteralPath $args[0];"
    "[PSCustomObject]@{status=[string]$signature.Status;"
    "statusMessage=[string]$signature.StatusMessage}|ConvertTo-Json -Compress"
)
WINDOWS_BOOT_SESSION_SCRIPT = (
    "$boot=(Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime;"
    "if($null -eq $boot){exit 3};"
    "[Console]::Out.Write($boot.ToUniversalTime().ToString('o'))"
)
EXPLICITLY_ABSENT_MSI_REGISTRATION_MARKER = (
    "unable to find the specified registry key or value"
)
EXPLICITLY_ABSENT_SCM_SERVICE_MARKER = "does not exist as an installed service"


def execute_windows_host_installation_command(
    executable: Path, arguments: Sequence[str]
) -> WindowsHostInstallationCommandObservation:
    """Run one caller-declared Windows command and preserve raw output."""

    try:
        completed = subprocess.run(
            [str(executable), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise WindowsHostInstallationObservationError(
            "Windows Host installation command execution failed for "
            + str(executable)
            + ": "
            + str(error)
        ) from error
    return WindowsHostInstallationCommandObservation(
        executable=executable,
        arguments=tuple(arguments),
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def observe_windows_msi_artifact_identity(
    powershell_executable: Path,
    installer_artifact_path: Path,
    execute_command: CommandExecutor = execute_windows_host_installation_command,
) -> WindowsMSIArtifactIdentityObservation:
    """Observe MSI ProductVersion and Authenticode status from MSI bytes."""

    metadata_command = execute_command(
        powershell_executable,
        ["-NoProfile", "-NonInteractive", "-Command", WINDOWS_MSI_PRODUCT_VERSION_SCRIPT, str(installer_artifact_path)],
    )
    signature_command = execute_command(
        powershell_executable,
        ["-NoProfile", "-NonInteractive", "-Command", WINDOWS_MSI_SIGNATURE_SCRIPT, str(installer_artifact_path)],
    )
    if metadata_command.returncode != 0:
        return WindowsMSIArtifactIdentityObservation(
            state="unavailable",
            product_version=None,
            signature_state=None,
            metadata_command=metadata_command,
            signature_command=signature_command,
            reason="PowerShell could not read MSI ProductVersion",
        )
    product_version = metadata_command.stdout.strip()
    if not product_version:
        return WindowsMSIArtifactIdentityObservation(
            state="invalid",
            product_version=None,
            signature_state=None,
            metadata_command=metadata_command,
            signature_command=signature_command,
            reason="MSI ProductVersion observation is empty",
        )
    if signature_command.returncode != 0:
        return WindowsMSIArtifactIdentityObservation(
            state="unavailable",
            product_version=product_version,
            signature_state=None,
            metadata_command=metadata_command,
            signature_command=signature_command,
            reason="PowerShell could not read MSI Authenticode status",
        )
    try:
        signature_document = json.loads(signature_command.stdout)
    except json.JSONDecodeError as error:
        return WindowsMSIArtifactIdentityObservation(
            state="invalid",
            product_version=product_version,
            signature_state=None,
            metadata_command=metadata_command,
            signature_command=signature_command,
            reason="Windows MSI Authenticode observation is not JSON: " + str(error),
        )
    signature_state = signature_document.get("status") if isinstance(signature_document, dict) else None
    if not isinstance(signature_state, str) or not signature_state:
        return WindowsMSIArtifactIdentityObservation(
            state="invalid",
            product_version=product_version,
            signature_state=None,
            metadata_command=metadata_command,
            signature_command=signature_command,
            reason="Windows MSI Authenticode observation requires status",
        )
    return WindowsMSIArtifactIdentityObservation(
        state="available",
        product_version=product_version,
        signature_state=signature_state,
        metadata_command=metadata_command,
        signature_command=signature_command,
    )


def observe_windows_msi_registration(
    registry_executable: Path,
    product_code: str,
    execute_command: CommandExecutor = execute_windows_host_installation_command,
) -> WindowsMSIRegistrationObservation:
    """Observe a ProductCode receipt without treating a generic error as absent."""

    key = "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + product_code
    command = execute_command(registry_executable, ["query", key, "/v", "DisplayVersion"])
    if command.returncode == 0:
        product_version = parse_windows_registry_display_version(command.stdout)
        if product_version is None:
            return WindowsMSIRegistrationObservation(
                product_code=product_code,
                state="invalid",
                product_version=None,
                command=command,
                reason="Windows MSI registration does not contain one DisplayVersion value",
            )
        return WindowsMSIRegistrationObservation(
            product_code=product_code,
            state="installed",
            product_version=product_version,
            command=command,
        )
    output = (command.stdout + "\n" + command.stderr).lower()
    if EXPLICITLY_ABSENT_MSI_REGISTRATION_MARKER in output:
        return WindowsMSIRegistrationObservation(
            product_code=product_code,
            state="absent",
            product_version=None,
            command=command,
        )
    return WindowsMSIRegistrationObservation(
        product_code=product_code,
        state="unavailable",
        product_version=None,
        command=command,
        reason="reg.exe did not explicitly report the MSI registration as absent",
    )


def observe_windows_scm_service_registration(
    sc_executable: Path,
    role: str,
    service_name: str,
    execute_command: CommandExecutor = execute_windows_host_installation_command,
) -> WindowsSCMServiceRegistrationObservation:
    """Observe one C23 SCM service without inferring registration from failure."""

    command = execute_command(sc_executable, ["query", service_name])
    if command.returncode == 0:
        state = "registered"
    elif EXPLICITLY_ABSENT_SCM_SERVICE_MARKER in (command.stdout + "\n" + command.stderr).lower():
        state = "absent"
    else:
        state = "unavailable"
    return WindowsSCMServiceRegistrationObservation(
        role=role,
        service_name=service_name,
        state=state,
        command=command,
    )


def observe_windows_host_boot_session(
    powershell_executable: Path,
    execute_command: CommandExecutor = execute_windows_host_installation_command,
) -> WindowsHostBootSessionObservation:
    """Observe one Windows boot session from the OS-owned CIM timestamp."""

    command = execute_command(
        powershell_executable,
        ["-NoProfile", "-NonInteractive", "-Command", WINDOWS_BOOT_SESSION_SCRIPT],
    )
    boot_session_identifier = command.stdout.strip()
    if command.returncode != 0 or not boot_session_identifier:
        raise WindowsHostInstallationObservationError(
            "Windows Host boot-session identifier is unavailable"
        )
    return WindowsHostBootSessionObservation(
        boot_session_identifier=boot_session_identifier,
        command=command,
    )


def parse_windows_registry_display_version(output: str) -> str | None:
    """Decode the one ``reg query`` DisplayVersion line required by this adapter."""

    values = [
        match.group("value").strip()
        for line in output.splitlines()
        if (match := re.match(r"^\s*DisplayVersion\s+REG_\w+\s+(?P<value>.+?)\s*$", line))
    ]
    if len(values) != 1 or not values[0]:
        return None
    return values[0]


def command_document(
    observation: WindowsHostInstallationCommandObservation,
) -> Mapping[str, Any]:
    return {
        "executable": str(observation.executable),
        "arguments": list(observation.arguments),
        "returncode": observation.returncode,
        "stdout": observation.stdout,
        "stderr": observation.stderr,
    }


def msi_artifact_identity_document(
    observation: WindowsMSIArtifactIdentityObservation,
) -> Mapping[str, Any]:
    document: dict[str, Any] = {
        "state": observation.state,
        "metadataCommand": command_document(observation.metadata_command),
        "signatureCommand": command_document(observation.signature_command),
    }
    if observation.product_version is not None:
        document["productVersion"] = observation.product_version
    if observation.signature_state is not None:
        document["signatureState"] = observation.signature_state
    if observation.reason is not None:
        document["reason"] = observation.reason
    return document


def msi_registration_document(
    observation: WindowsMSIRegistrationObservation,
) -> Mapping[str, Any]:
    document: dict[str, Any] = {
        "productCode": observation.product_code,
        "state": observation.state,
        "command": command_document(observation.command),
    }
    if observation.product_version is not None:
        document["productVersion"] = observation.product_version
    if observation.reason is not None:
        document["reason"] = observation.reason
    return document


def scm_service_registration_document(
    observation: WindowsSCMServiceRegistrationObservation,
) -> Mapping[str, Any]:
    return {
        "role": observation.role,
        "serviceName": observation.service_name,
        "state": observation.state,
        "command": command_document(observation.command),
    }


def boot_session_document(
    observation: WindowsHostBootSessionObservation,
) -> Mapping[str, Any]:
    return {
        "bootSessionIdentifier": observation.boot_session_identifier,
        "command": command_document(observation.command),
    }
