"""Executable C21/C10 checks for the macOS virtual machine command CLI."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "providers" / "macos-virtualization"


def lifecycle_invocation() -> dict:
    return {
        "schemaVersion": "v1",
        "providerKind": "macos-virtualization",
        "requestId": "macos-provider-cli-start",
        "expectedGuestRuntimeControlEndpointRevision": 1,
        "lifecycle": {
            "schemaVersion": "v1",
            "requestId": "macos-provider-cli-start",
            "providerId": "vitalserver-guest",
            "action": "start",
        },
    }


class MacOSVirtualMachineCommandCliContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        build = subprocess.run(["swift", "build"], cwd=PACKAGE, capture_output=True, text=True, check=False)
        if build.returncode != 0:
            raise AssertionError("build macOS virtual machine command CLI failed:\n{0}\n{1}".format(build.stdout, build.stderr))
        cls.command_cli = PACKAGE / ".build" / "debug" / "macos-virtual-machine-command-cli"
        if not cls.command_cli.is_file():
            raise AssertionError("macOS virtual machine command CLI binary is missing: {0}".format(cls.command_cli))

    def invoke(self, *arguments: str) -> dict:
        completed = subprocess.run(
            [str(self.command_cli), *arguments],
            input=json.dumps(lifecycle_invocation(), separators=(",", ":")),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        return json.loads(completed.stdout)

    def test_missing_explicit_configuration_is_unavailable_not_an_unconfigured_success(self) -> None:
        result = self.invoke("--virtual-machine-configuration", "/Library/Application Support/VitalServerRuntimePlatform/missing-vm.json")
        self.assertEqual("unavailable", result["observedState"])
        self.assertEqual("macos-vm-configuration-unavailable", result["issue"]["code"])

    def test_invalid_explicit_configuration_is_failed_not_silently_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            configuration = Path(temporary_directory) / "invalid-vm.json"
            configuration.write_text("{not-json", encoding="utf-8")
            result = self.invoke("--virtual-machine-configuration", str(configuration))
        self.assertEqual("failed", result["observedState"])
        self.assertEqual("macos-vm-configuration-failed", result["issue"]["code"])

    def test_absent_configuration_remains_explicitly_unconfigured(self) -> None:
        result = self.invoke()
        self.assertEqual("unavailable", result["observedState"])
        self.assertEqual("macos-vm-not-configured", result["issue"]["code"])


if __name__ == "__main__":
    unittest.main()
