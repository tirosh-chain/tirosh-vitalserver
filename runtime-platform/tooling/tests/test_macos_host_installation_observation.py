"""Tests for explicit macOS external-installation observations."""

from __future__ import annotations

from pathlib import Path
import unittest

from tooling import macos_host_installation_observation as observation


class MacOSHostInstallationObservationTests(unittest.TestCase):
    def command(
        self,
        returncode: int,
        stdout: str = "",
        stderr: str = "",
    ) -> observation.MacOSHostInstallationCommandObservation:
        return observation.MacOSHostInstallationCommandObservation(
            executable=Path("/bin/launchctl"),
            arguments=("print", "system/com.tirosh.vitalserver.host-agent"),
            returncode=returncode,
            stdout=stdout,
            stderr=stderr,
        )

    def test_observes_legacy_and_macos26_explicit_absence(self) -> None:
        legacy = observation.observe_macos_launchd_service_registration(
            Path("/bin/launchctl"),
            "host-agent",
            "com.tirosh.vitalserver.host-agent",
            execute_command=lambda _executable, _arguments: self.command(3),
        )
        macos26 = observation.observe_macos_launchd_service_registration(
            Path("/bin/launchctl"),
            "host-agent",
            "com.tirosh.vitalserver.host-agent",
            execute_command=lambda _executable, _arguments: self.command(
                113,
                stderr='Bad request.\nCould not find service "com.tirosh.vitalserver.host-agent" in domain for system\n',
            ),
        )

        self.assertEqual("absent", legacy.state)
        self.assertEqual("absent", macos26.state)

    def test_does_not_turn_ambiguous_macos26_failure_into_absence(self) -> None:
        result = observation.observe_macos_launchd_service_registration(
            Path("/bin/launchctl"),
            "host-agent",
            "com.tirosh.vitalserver.host-agent",
            execute_command=lambda _executable, _arguments: self.command(
                113,
                stderr='Bad request.\nCould not find service "another.service" in domain for system\n',
            ),
        )

        self.assertEqual("unavailable", result.state)
