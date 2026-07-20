"""Observe Linux DEB, systemd, filesystem, and boot facts explicitly.

This adapter owns command execution and parsing of Linux-owned output. C24
stage policy belongs to the Linux clean-Host release evidence workflow, not to
these observation functions.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
from typing import Any, Callable, Mapping, Sequence


class LinuxHostInstallationObservationError(RuntimeError):
    """A Linux command result cannot form an explicit observation."""


@dataclass(frozen=True)
class LinuxHostInstallationCommandObservation:
    executable: Path
    arguments: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class LinuxDEBArtifactIdentityObservation:
    state: str
    package_identifier: str | None
    product_version: str | None
    command: LinuxHostInstallationCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class LinuxDEBPackageRegistrationObservation:
    package_identifier: str
    state: str
    product_version: str | None
    command: LinuxHostInstallationCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class LinuxSystemdServiceRegistrationObservation:
    role: str
    service_name: str
    state: str
    command: LinuxHostInstallationCommandObservation


@dataclass(frozen=True)
class LinuxPathObservation:
    path: Path
    state: str
    command: LinuxHostInstallationCommandObservation


@dataclass(frozen=True)
class LinuxHostBootSessionObservation:
    boot_session_identifier: str
    command: LinuxHostInstallationCommandObservation


CommandExecutor = Callable[[Path, Sequence[str]], LinuxHostInstallationCommandObservation]
EXPLICITLY_ABSENT_DPKG_PACKAGE_MARKER = "no packages found matching"


def execute_linux_host_installation_command(
    executable: Path, arguments: Sequence[str]
) -> LinuxHostInstallationCommandObservation:
    """Execute one declared command and retain stdout/stderr for evidence."""

    try:
        completed = subprocess.run(
            [str(executable), *arguments], capture_output=True, text=True, check=False
        )
    except OSError as error:
        raise LinuxHostInstallationObservationError(
            "Linux Host installation command execution failed for "
            + str(executable)
            + ": "
            + str(error)
        ) from error
    return LinuxHostInstallationCommandObservation(
        executable=executable,
        arguments=tuple(arguments),
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def observe_linux_deb_artifact_identity(
    dpkg_deb_executable: Path,
    installer_artifact_path: Path,
    execute_command: CommandExecutor = execute_linux_host_installation_command,
) -> LinuxDEBArtifactIdentityObservation:
    """Read DEB package/version metadata from the selected artifact bytes."""

    command = execute_command(
        dpkg_deb_executable,
        ["--field", str(installer_artifact_path), "Package", "Version"],
    )
    if command.returncode != 0:
        return LinuxDEBArtifactIdentityObservation(
            state="unavailable",
            package_identifier=None,
            product_version=None,
            command=command,
            reason="dpkg-deb could not read DEB Package and Version metadata",
        )
    lines = [line.strip() for line in command.stdout.splitlines() if line.strip()]
    if len(lines) != 2:
        return LinuxDEBArtifactIdentityObservation(
            state="invalid",
            package_identifier=None,
            product_version=None,
            command=command,
            reason="dpkg-deb metadata output must contain Package and Version lines",
        )
    return LinuxDEBArtifactIdentityObservation(
        state="available",
        package_identifier=lines[0],
        product_version=lines[1],
        command=command,
    )


def observe_linux_deb_package_registration(
    dpkg_query_executable: Path,
    package_identifier: str,
    execute_command: CommandExecutor = execute_linux_host_installation_command,
) -> LinuxDEBPackageRegistrationObservation:
    """Observe dpkg state; residual config is not an absent clean-Host state."""

    command = execute_command(
        dpkg_query_executable,
        ["--show", "--showformat=${db:Status-Abbrev}|${Version}\\n", package_identifier],
    )
    if command.returncode == 0:
        output = command.stdout.strip()
        if "|" not in output:
            return LinuxDEBPackageRegistrationObservation(
                package_identifier=package_identifier,
                state="invalid",
                product_version=None,
                command=command,
                reason="dpkg-query output must contain status and version",
            )
        status, product_version = output.split("|", 1)
        if status == "ii " and product_version:
            return LinuxDEBPackageRegistrationObservation(
                package_identifier=package_identifier,
                state="installed",
                product_version=product_version,
                command=command,
            )
        return LinuxDEBPackageRegistrationObservation(
            package_identifier=package_identifier,
            state="residual",
            product_version=product_version or None,
            command=command,
            reason="dpkg-query did not report install ok installed",
        )
    output = (command.stdout + "\n" + command.stderr).lower()
    if EXPLICITLY_ABSENT_DPKG_PACKAGE_MARKER in output:
        return LinuxDEBPackageRegistrationObservation(
            package_identifier=package_identifier,
            state="absent",
            product_version=None,
            command=command,
        )
    return LinuxDEBPackageRegistrationObservation(
        package_identifier=package_identifier,
        state="unavailable",
        product_version=None,
        command=command,
        reason="dpkg-query did not explicitly report the package as absent",
    )


def observe_linux_systemd_service_registration(
    systemctl_executable: Path,
    role: str,
    service_name: str,
    execute_command: CommandExecutor = execute_linux_host_installation_command,
) -> LinuxSystemdServiceRegistrationObservation:
    """Observe one C23 systemd registration without parsing a status screen."""

    command = execute_command(
        systemctl_executable, ["show", "--property=LoadState", "--value", service_name]
    )
    state = command.stdout.strip()
    if command.returncode == 0 and state == "loaded":
        registration_state = "registered"
    elif command.returncode == 0 and state == "not-found":
        registration_state = "absent"
    else:
        registration_state = "unavailable"
    return LinuxSystemdServiceRegistrationObservation(
        role=role,
        service_name=service_name,
        state=registration_state,
        command=command,
    )


def observe_linux_path(
    test_executable: Path,
    path: Path,
    execute_command: CommandExecutor = execute_linux_host_installation_command,
) -> LinuxPathObservation:
    """Observe an explicit root path; generic execution failure is not absence."""

    command = execute_command(test_executable, ["-e", str(path)])
    if command.returncode == 0:
        state = "present"
    elif command.returncode == 1:
        state = "absent"
    else:
        state = "unavailable"
    return LinuxPathObservation(path=path, state=state, command=command)


def observe_linux_host_boot_session(
    cat_executable: Path,
    boot_id_path: Path,
    execute_command: CommandExecutor = execute_linux_host_installation_command,
) -> LinuxHostBootSessionObservation:
    """Observe the Linux kernel boot ID through a declared immutable path."""

    command = execute_command(cat_executable, [str(boot_id_path)])
    boot_session_identifier = command.stdout.strip()
    if command.returncode != 0 or not boot_session_identifier:
        raise LinuxHostInstallationObservationError(
            "Linux Host boot-session identifier is unavailable"
        )
    return LinuxHostBootSessionObservation(
        boot_session_identifier=boot_session_identifier, command=command
    )


def command_document(
    observation: LinuxHostInstallationCommandObservation,
) -> Mapping[str, Any]:
    return {
        "executable": str(observation.executable),
        "arguments": list(observation.arguments),
        "returncode": observation.returncode,
        "stdout": observation.stdout,
        "stderr": observation.stderr,
    }


def deb_artifact_identity_document(
    observation: LinuxDEBArtifactIdentityObservation,
) -> Mapping[str, Any]:
    document: dict[str, Any] = {
        "state": observation.state,
        "command": command_document(observation.command),
    }
    if observation.package_identifier is not None:
        document["packageIdentifier"] = observation.package_identifier
    if observation.product_version is not None:
        document["productVersion"] = observation.product_version
    if observation.reason is not None:
        document["reason"] = observation.reason
    return document


def deb_package_registration_document(
    observation: LinuxDEBPackageRegistrationObservation,
) -> Mapping[str, Any]:
    document: dict[str, Any] = {
        "packageIdentifier": observation.package_identifier,
        "state": observation.state,
        "command": command_document(observation.command),
    }
    if observation.product_version is not None:
        document["productVersion"] = observation.product_version
    if observation.reason is not None:
        document["reason"] = observation.reason
    return document


def systemd_service_registration_document(
    observation: LinuxSystemdServiceRegistrationObservation,
) -> Mapping[str, Any]:
    return {
        "role": observation.role,
        "serviceName": observation.service_name,
        "state": observation.state,
        "command": command_document(observation.command),
    }


def path_document(observation: LinuxPathObservation) -> Mapping[str, Any]:
    return {
        "path": str(observation.path),
        "state": observation.state,
        "command": command_document(observation.command),
    }


def boot_session_document(observation: LinuxHostBootSessionObservation) -> Mapping[str, Any]:
    return {
        "bootSessionIdentifier": observation.boot_session_identifier,
        "command": command_document(observation.command),
    }
