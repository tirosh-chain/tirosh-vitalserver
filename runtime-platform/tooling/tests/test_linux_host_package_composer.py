from __future__ import annotations

import gzip
import hashlib
import io
import json
from dataclasses import replace
from pathlib import Path
import tarfile
import tempfile
import unittest

from tooling import linux_host_package_composer as composer


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def ar_members(value: bytes) -> dict[str, bytes]:
    if not value.startswith(b"!<arch>\n"):
        raise AssertionError("not an ar archive")
    offset = 8
    result: dict[str, bytes] = {}
    while offset < len(value):
        header = value[offset : offset + 60]
        offset += 60
        name = header[:16].decode("ascii").strip().removesuffix("/")
        size = int(header[48:58].decode("ascii").strip())
        result[name] = value[offset : offset + size]
        offset += size + (size % 2)
    return result


def tar_members(value: bytes) -> dict[str, bytes]:
    with gzip.GzipFile(fileobj=io.BytesIO(value), mode="rb") as compressed:
        with tarfile.open(fileobj=compressed, mode="r:") as archive:
            return {
                member.name: archive.extractfile(member).read()
                for member in archive.getmembers()
                if member.isfile()
            }


class LinuxHostPackageComposerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.release = self.root / "release"
        self.release.mkdir()
        self.release_id = "runtime-platform-0.2.0-dev-build-001"
        self.release_root = "/opt/vitalserver-runtime-platform/releases/" + self.release_id
        self.entries = {
            "bin/host-agent": b"host-agent",
            "bin/host-edge-proxy": b"host-edge-proxy",
            "bin/host-installation-manager": b"host-installation-manager",
            "bin/host-update-handoff-supervisor": b"host-update-handoff-supervisor",
            "config/host-agent.json": b"{\"schemaVersion\":\"v1\"}",
        }
        for relative, content in self.entries.items():
            path = self.release / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            if relative.startswith("bin/"):
                path.chmod(0o755)
        self.bootstrap = self.root / "runtime-console-bootstrap.json"
        self.bootstrap.write_bytes(b"{\"schemaVersion\":\"v1\"}")
        self.services: dict[str, Path] = {}
        service_names = {
            "host-agent": "vitalserver-host-agent.service",
            "host-edge-proxy": "vitalserver-host-edge-proxy.service",
            "host-update-handoff-supervisor": "vitalserver-host-update-handoff-supervisor.service",
        }
        required_services = []
        for role, name in service_names.items():
            source = self.root / (role + ".service")
            source.write_bytes(("[Unit]\nDescription=" + role + "\n").encode())
            self.services[role] = source
            required_services.append({
                "role": role, "manager": "systemd", "name": name,
                "definitionPath": "/etc/systemd/system/" + name,
                "definitionSha256": sha(source.read_bytes()),
            })
        self.manifest = {
            "schemaVersion": "v1", "installationId": "vitalserver-runtime-platform", "platform": "linux",
            "release": {"id": self.release_id, "productVersion": "0.2.0-dev", "runtimeVersion": "0.2.0"},
            "package": {"identifier": "com.tirosh.vitalserver.runtime-platform", "productVersion": "0.2.0-dev"},
            "immutablePayload": {
                "releaseCatalogPath": "/opt/vitalserver-runtime-platform/releases", "releaseRootPath": self.release_root,
                "manifestPath": self.release_root + "/installation-manifest.json",
                "entries": [{"relativePath": relative, "sha256": sha(content), "executable": relative.startswith("bin/")} for relative, content in self.entries.items()],
            },
            "activation": {"currentReleaseLinkPath": "/opt/vitalserver-runtime-platform/current", "referenceKind": "symbolic-link", "expectedReleaseRootPath": self.release_root},
            "operatorInterface": {"bootstrapConfigurationPath": "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json", "bootstrapConfigurationSha256": sha(self.bootstrap.read_bytes())},
            "requiredServices": required_services,
            "mutableStores": [
                {"id": "installation-data-root", "path": "/var/lib/vitalserver-runtime-platform/data", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
                {"id": "installation-manager-journal", "path": "/var/lib/vitalserver-runtime-platform/data/installation-manager", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
                {"id": "native-machine-runtime", "path": "/var/lib/vitalserver-runtime-platform/data/virtual-machine", "kind": "directory", "owner": "native-platform-provider", "retention": "preserve-by-default"},
            ],
        }
        self.manifest_path = self.release / "installation-manifest.json"
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def composition(self) -> composer.LinuxHostPackageComposition:
        return composer.LinuxHostPackageComposition(
            manifest_path=self.manifest_path, release_source_directory=self.release,
            service_definition_sources=self.services, operator_interface_bootstrap_source=self.bootstrap,
            installation_journal_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/current-transaction.json",
            installation_receipt_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/latest-installation-receipt.json",
            removal_journal_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/current-removal-transaction.json",
            removal_receipt_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/latest-removal-receipt.json",
            package_manager_completion_manager_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/package-manager-removal-completion",
            package_manager_completion_manifest_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/package-manager-removal-manifest.json",
            output_package=self.root / "com.tirosh.vitalserver.runtime-platform_0.2.0-dev_amd64.deb",
            package_name="com.tirosh.vitalserver.runtime-platform", architecture="amd64", maintainer="Tirosh <support@tirosh.example>", description="VitalServer Runtime Platform",
        )

    def test_composes_declared_release_and_c54_dpkg_handoff_script(self) -> None:
        result = composer.compose_linux_host_package(self.composition())
        package = Path(result["artifactPath"])
        self.assertTrue(package.is_file())
        members = ar_members(package.read_bytes())
        self.assertEqual(b"2.0\n", members["debian-binary"])
        control = tar_members(members["control.tar.gz"])
        data = tar_members(members["data.tar.gz"])
        self.assertNotIn("com.tirosh.vitalserver.runtime-platform.host-installation-manager", control)
        self.assertNotIn("com.tirosh.vitalserver.runtime-platform.installation-manifest.json", control)
        self.assertNotIn("--mode preflight", control["preinst"].decode())
        self.assertIn("direct Debian package upgrades are unsupported", control["preinst"].decode())
        self.assertIn("--mode preflight", control["postinst"].decode())
        self.assertIn("--mode quiesce", control["postinst"].decode())
        prerm = control["prerm"].decode()
        self.assertIn("--data-disposition preserve-mutable-data", prerm)
        self.assertIn("direct Debian package upgrades are unsupported", prerm)
        postrm = control["postrm"].decode()
        self.assertIn("--mode complete-removal-after-package-manager", postrm)
        self.assertIn("/var/lib/vitalserver-runtime-platform/data/installation-manager/package-manager-removal-completion", postrm)
        self.assertIn("opt/vitalserver-runtime-platform/releases/" + self.release_id + "/bin/host-installation-manager", data)
        self.assertIn("etc/systemd/system/vitalserver-host-agent.service", data)
        self.assertIn("opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json", data)

    def test_transports_one_declared_systemctl_executable_to_every_manager_phase(self) -> None:
        result = composer.compose_linux_host_package(replace(self.composition(), systemctl_executable_path="/usr/local/lib/vitalserver-test-systemctl"))
        control = tar_members(ar_members(Path(result["artifactPath"]).read_bytes())["control.tar.gz"])
        for script_name in ("postinst", "prerm", "postrm"):
            self.assertIn('--systemctl "/usr/local/lib/vitalserver-test-systemctl"', control[script_name].decode())

    def test_rejects_a_service_definition_that_does_not_match_c48(self) -> None:
        self.services["host-agent"].write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(composer.LinuxHostPackageCompositionError, "SHA-256"):
            composer.compose_linux_host_package(self.composition())

    def test_rejects_a_debian_package_name_that_does_not_match_c48_dpkg_receipt_identifier(self) -> None:
        with self.assertRaisesRegex(composer.LinuxHostPackageCompositionError, "must equal the C48 package identifier"):
            composer.compose_linux_host_package(replace(self.composition(), package_name="vitalserver-runtime-platform"))
