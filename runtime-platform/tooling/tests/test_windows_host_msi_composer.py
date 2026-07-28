from __future__ import annotations

from dataclasses import replace
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree

from tooling import windows_host_msi_composer as composer


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class WindowsHostMSIComposerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.release = self.root / "release"
        self.release.mkdir()
        self.release_id = "runtime-platform-0.2.0-build-001"
        self.product_root = r"C:\ProgramData\VitalServerRuntimePlatform"
        self.release_root = self.product_root + "\\releases\\" + self.release_id
        self.entries = {
            "bin/host-agent.exe": b"host-agent",
            "bin/host-edge-proxy.exe": b"host-edge-proxy",
            "bin/host-installation-manager.exe": b"host-installation-manager",
            "bin/host-service-runner.exe": b"host-service-runner",
            "bin/host-update-handoff-supervisor.exe": b"host-update-handoff-supervisor",
            "config/host-agent.json": b"{\"schemaVersion\":\"v1\"}",
        }
        for relative, content in self.entries.items():
            path = self.release / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self.bootstrap = self.root / "runtime-console-bootstrap.json"
        self.bootstrap.write_bytes(b"{\"schemaVersion\":\"v1\"}")
        service_names = {
            "host-agent": "VitalServerRuntimePlatformHostAgent",
            "host-edge-proxy": "VitalServerRuntimePlatformHostEdgeProxy",
            "host-update-handoff-supervisor": "VitalServerRuntimePlatformHostUpdateHandoffSupervisor",
        }
        self.services: dict[str, Path] = {}
        required_services = []
        for role, name in service_names.items():
            source = self.root / (role + ".json")
            source.write_text(json.dumps({
                "schemaVersion": "v1",
                "documentKind": "host-service-execution-definition",
                "serviceName": name,
                "role": role,
                "command": {
                    "executablePath": self.product_root + "\\current\\bin\\" + role + ".exe",
                    "arguments": [],
                },
            }), encoding="utf-8")
            self.services[role] = source
            required_services.append(
                {
                    "role": role,
                    "manager": "windows-scm",
                    "name": name,
                    "definitionPath": self.product_root + "\\services\\" + role + ".json",
                    "definitionSha256": sha(source.read_bytes()),
                    "windowsScmRegistration": {
                        "executablePath": self.product_root + r"\current\bin\host-service-runner.exe",
                        "arguments": ["--service-definition", self.product_root + "\\services\\" + role + ".json"],
                        "startMode": "automatic",
                        "account": "LocalSystem",
                    },
                }
            )
        self.manifest = {
            "schemaVersion": "v1",
            "installationId": "vitalserver-runtime-platform",
            "platform": "windows",
            "release": {"id": self.release_id, "productVersion": "0.2.0", "runtimeVersion": "0.2.0"},
            "package": {
                "identifier": "com.tirosh.vitalserver.runtime-platform",
                "productVersion": "0.2.0",
                "packageManagerIdentifier": "{12345678-1234-1234-1234-1234567890AB}",
            },
            "immutablePayload": {
                "releaseCatalogPath": self.product_root + r"\releases",
                "releaseRootPath": self.release_root,
                "manifestPath": self.release_root + r"\installation-manifest.json",
                "entries": [{"relativePath": relative, "sha256": sha(content), "executable": relative.startswith("bin/")} for relative, content in self.entries.items()],
            },
            "activation": {"currentReleaseLinkPath": self.product_root + r"\current", "referenceKind": "directory-junction", "expectedReleaseRootPath": self.release_root},
            "operatorInterface": {"bootstrapConfigurationPath": self.product_root + r"\control\runtime-console-bootstrap.json", "bootstrapConfigurationSha256": sha(self.bootstrap.read_bytes())},
            "requiredServices": required_services,
            "mutableStores": [
                {"id": "installation-data-root", "path": self.product_root + r"\data", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
                {"id": "installation-manager-journal", "path": self.product_root + r"\data\installation-manager", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
                {"id": "native-machine-runtime", "path": self.product_root + r"\data\virtual-machine", "kind": "directory", "owner": "native-platform-provider", "retention": "preserve-by-default"},
            ],
        }
        self.manifest_path = self.release / "installation-manifest.json"
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def composition(self) -> composer.WindowsHostMSIComposition:
        data = self.product_root + r"\data\installation-manager"
        return composer.WindowsHostMSIComposition(
            manifest_path=self.manifest_path,
            release_source_directory=self.release,
            service_definition_sources=self.services,
            operator_interface_bootstrap_source=self.bootstrap,
            installation_journal_path=data + r"\current-transaction.json",
            installation_receipt_path=data + r"\latest-installation-receipt.json",
            removal_journal_path=data + r"\current-removal-transaction.json",
            removal_receipt_path=data + r"\latest-removal-receipt.json",
            package_manager_completion_manager_path=data + r"\package-manager-removal-completion.exe",
            package_manager_completion_manifest_path=data + r"\package-manager-removal-manifest.json",
            wix_source_path=self.root / "VitalServerRuntimePlatform.wxs",
            manufacturer="Tirosh",
            upgrade_code="{87654321-4321-4321-4321-BA0987654321}",
        )

    def test_writes_wix_source_with_explicit_msi_install_and_removal_boundaries(self) -> None:
        result = composer.compose_windows_host_msi(self.composition())
        self.assertEqual("wix-source", result["artifactKind"])
        source = Path(result["wixSourcePath"])
        self.assertTrue(source.is_file())
        content = source.read_text(encoding="utf-8")
        document = ElementTree.fromstring(content)
        namespace = {"wix": "http://wixtoolset.org/schemas/v4/wxs"}
        self.assertIn('Action="C50PreflightFresh" After="InstallFiles" Condition="NOT Installed AND NOT REMOVE=&quot;ALL&quot;"', content)
        self.assertIn('Action="C50PreflightRepair" After="C50PreflightFresh" Condition="Installed AND NOT REMOVE=&quot;ALL&quot;"', content)
        self.assertIn("--package-manager-operation windows-msi-installing", content)
        self.assertIn('<Upgrade Id="{87654321-4321-4321-4321-BA0987654321}">', content)
        upgrade_version = document.find(".//wix:UpgradeVersion", namespace)
        self.assertIsNotNone(upgrade_version)
        assert upgrade_version is not None
        self.assertEqual(
            {
                "Minimum": "0.0.0",
                "IncludeMinimum": "yes",
                "Maximum": "255.255.65535",
                "IncludeMaximum": "yes",
                "OnlyDetect": "yes",
                "Property": "VITALSERVER_RUNTIME_PLATFORM_DIRECT_UPDATE",
            },
            upgrade_version.attrib,
        )
        self.assertIn('Condition="Installed OR NOT VITALSERVER_RUNTIME_PLATFORM_DIRECT_UPDATE"', content)
        self.assertIn("Direct Windows MSI upgrades and downgrades are unsupported", content)
        self.assertNotIn("MajorUpgrade", content)
        self.assertIn('Id="VitalServerRuntimePlatformFeature" Title="VitalServer Runtime Platform" Level="1" InstallDefault="local" AllowAdvertise="no"', content)
        component_ids = {element.attrib["Id"] for element in document.findall(".//wix:Component", namespace)}
        feature_component_ids = {element.attrib["Id"] for element in document.findall(".//wix:Feature/wix:ComponentRef", namespace)}
        self.assertEqual(component_ids, feature_component_ids)
        self.assertEqual(len(self.manifest["immutablePayload"]["entries"]) + 1 + len(self.manifest["requiredServices"]) + 1, len(component_ids))
        self.assertIn('Action="C54Remove" Before="RemoveFiles" Condition="REMOVE=&quot;ALL&quot;"', content)
        self.assertIn('Action="C54PackageManagerCompletion" Before="InstallFinalize" Condition="REMOVE=&quot;ALL&quot;"', content)
        self.assertIn('Id="C54PackageManagerCompletion" BinaryRef="Wix4UtilCA_$(sys.BUILDARCHSHORT)" DllEntry="WixQuietExec64" Return="check" Impersonate="no" Execute="commit"', content)
        self.assertIn(r'package-manager-removal-completion.exe', content)
        self.assertIn("--host-administration-descriptor", content)
        self.assertIn("host-agent.local.json&quot;", content)
        self.assertIn("--host-administration-timeout-milliseconds 5000", content)
        self.assertEqual(1, content.count('Source="' + str(self.release / "bin" / "host-installation-manager.exe") + '"'))

    def test_rejects_non_numeric_msi_receipt_version(self) -> None:
        self.manifest["package"]["productVersion"] = "0.2.0-dev"
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        with self.assertRaisesRegex(composer.WindowsHostMSICompositionError, "MSI numeric version"):
            composer.compose_windows_host_msi(self.composition())

    def test_rejects_an_msi_version_outside_windows_installer_range(self) -> None:
        self.manifest["release"]["productVersion"] = "256.0.0"
        self.manifest["package"]["productVersion"] = "256.0.0"
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        with self.assertRaisesRegex(composer.WindowsHostMSICompositionError, "MSI numeric version"):
            composer.compose_windows_host_msi(self.composition())

    def test_rejects_a_completion_transport_that_is_not_executable_on_windows(self) -> None:
        with self.assertRaisesRegex(composer.WindowsHostMSICompositionError, "completion transport paths are invalid"):
            composer.compose_windows_host_msi(replace(self.composition(), package_manager_completion_manager_path=self.product_root + r"\data\installation-manager\package-manager-removal-completion"))

    def test_rejects_a_direct_host_executable_scm_registration(self) -> None:
        self.manifest["requiredServices"][0]["windowsScmRegistration"]["executablePath"] = self.product_root + r"\current\bin\host-agent.exe"
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        with self.assertRaisesRegex(composer.WindowsHostMSICompositionError, "declared Host service runner"):
            composer.compose_windows_host_msi(self.composition())

    def test_rejects_a_service_definition_that_names_another_role(self) -> None:
        source = self.services["host-agent"]
        definition = json.loads(source.read_text(encoding="utf-8"))
        definition["command"]["executablePath"] = self.product_root + r"\current\bin\host-edge-proxy.exe"
        source.write_text(json.dumps(definition), encoding="utf-8")
        self.manifest["requiredServices"][0]["definitionSha256"] = sha(source.read_bytes())
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        with self.assertRaisesRegex(composer.WindowsHostMSICompositionError, "current-release role executable"):
            composer.compose_windows_host_msi(self.composition())

    def test_refuses_to_claim_an_msi_without_an_explicit_wix_toolchain(self) -> None:
        with self.assertRaisesRegex(composer.WindowsHostMSICompositionError, "WiX executable and MSI output"):
            composer.compose_windows_host_msi(replace(self.composition(), output_package=self.root / "VitalServerRuntimePlatform.msi"))

    def test_compiles_the_declared_source_only_when_a_pinned_wix_toolchain_is_explicitly_supplied(self) -> None:
        wix = os.environ.get("RUNTIME_PLATFORM_WINDOWS_WIX")
        if wix is None:
            self.skipTest("set RUNTIME_PLATFORM_WINDOWS_WIX only in a Windows WiX v4 compile runner")
        result = composer.compose_windows_host_msi(
            replace(
                self.composition(),
                wix_executable_path=Path(wix),
                output_package=self.root / "VitalServerRuntimePlatform.msi",
            )
        )
        package = Path(result["artifactPath"])
        self.assertEqual("msi", result["artifactKind"])
        self.assertTrue(package.is_file())
        self.assertGreater(package.stat().st_size, 0)
