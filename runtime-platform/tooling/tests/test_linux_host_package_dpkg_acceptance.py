"""Opt-in real dpkg proof for the Linux Host package lifecycle."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from dataclasses import replace

from tooling import linux_host_package_composer as composer


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


@unittest.skipUnless(
    os.environ.get("RUNTIME_PLATFORM_LINUX_DPKG_ACCEPTANCE") == "1",
    "set RUNTIME_PLATFORM_LINUX_DPKG_ACCEPTANCE=1 to run the Docker dpkg lifecycle proof",
)
class LinuxHostPackageDpkgAcceptanceTests(unittest.TestCase):
    def test_dpkg_remove_runs_c54_handoff_then_postrm_completion(self) -> None:
        manager_source = Path(os.environ.get("RUNTIME_PLATFORM_LINUX_HOST_INSTALLATION_MANAGER", ""))
        docker_executable = os.environ.get("RUNTIME_PLATFORM_DOCKER", "docker")
        if not manager_source.is_file() or manager_source.is_symlink():
            self.fail("RUNTIME_PLATFORM_LINUX_HOST_INSTALLATION_MANAGER must name a regular Linux manager binary")
        if shutil.which(docker_executable) is None:
            self.fail("selected Docker executable is unavailable: " + docker_executable)
        repository_root = Path(__file__).resolve().parents[2]
        temporary_root = repository_root / ".tmp"
        temporary_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="linux-dpkg-acceptance-", dir=temporary_root) as temporary:
            root = Path(temporary)
            self.build_ownership_fixture(
                repository_root=repository_root,
                destination=root / "host-update-ownership-fixture",
            )
            package = self.compose_package(root, manager_source)
            result = subprocess.run(
                [docker_executable, "run", "--rm", "--platform", "linux/amd64", "--mount", "type=bind,source=" + str(root) + ",target=/work,readonly", "debian:bookworm-slim", "sh", "-ceu", self.removal_command(package.name)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if result.returncode != 0:
                self.fail("Docker dpkg lifecycle proof failed:\nstdout:\n" + result.stdout + "\nstderr:\n" + result.stderr)
            self.assertIn('"state":"completed"', result.stdout)
            self.assertIn('"packageReceiptRemoval":"removed-by-os-package-manager"', result.stdout)
            self.assertTrue(package.is_file())

    @unittest.skipUnless(
        os.environ.get("RUNTIME_PLATFORM_LINUX_PRODUCT_PACKAGE_COMPOSITION"),
        "set RUNTIME_PLATFORM_LINUX_PRODUCT_PACKAGE_COMPOSITION to prove one selected product C48 through real dpkg",
    )
    def test_selected_product_release_runs_through_real_dpkg_lifecycle(self) -> None:
        """Exercise selected product bytes without pretending systemd runs in Docker.

        The package is composed from the same C48 source selected by the
        release preparer. The only test substitution is a declared executable
        for the package's systemctl port: a Docker container has no systemd
        process, so `/usr/bin/systemctl` cannot provide a lifecycle result.
        This proves dpkg/C50/C54 ownership, package payload correlation, and
        removal completion; C24 remains the owner of real-systemd evidence.
        """

        composition_path = Path(os.environ["RUNTIME_PLATFORM_LINUX_PRODUCT_PACKAGE_COMPOSITION"])
        if not composition_path.is_absolute() or not composition_path.is_file() or composition_path.is_symlink():
            self.fail("RUNTIME_PLATFORM_LINUX_PRODUCT_PACKAGE_COMPOSITION must name one absolute regular composition document")
        docker_executable = os.environ.get("RUNTIME_PLATFORM_DOCKER", "docker")
        if shutil.which(docker_executable) is None:
            self.fail("selected Docker executable is unavailable: " + docker_executable)
        selected = composer._parse_arguments(["--composition", str(composition_path)])
        if selected.output_package.name != "vitalserver-runtime-platform_0.2.0-dev_amd64.deb":
            self.fail("selected product C23 artifact name is not the expected Linux release package")
        repository_root = Path(__file__).resolve().parents[2]
        temporary_root = repository_root / ".tmp"
        temporary_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="linux-product-dpkg-acceptance-", dir=temporary_root) as temporary:
            root = Path(temporary)
            ownership_fixture = self.build_ownership_fixture(
                repository_root=repository_root,
                destination=root / "host-update-ownership-fixture",
            )
            fake_systemctl = root / "vitalserver-test-systemctl"
            fake_systemctl.write_text("#!/bin/sh\nif [ \"${1:-}\" = show ]; then printf '%s\\n' not-found; fi\nexit 0\n", encoding="utf-8")
            fake_systemctl.chmod(0o755)
            package = root / selected.output_package.name
            result_package = composer.compose_linux_host_package(replace(
                selected,
                output_package=package,
                systemctl_executable_path="/work/vitalserver-test-systemctl",
            ))
            self.assertEqual(str(package), result_package["artifactPath"])
            manifest = json.loads(selected.manifest_path.read_text(encoding="utf-8"))
            installation_id = manifest["installationId"]
            result = subprocess.run(
                [docker_executable, "run", "--rm", "--platform", "linux/amd64", "--mount", "type=bind,source=" + str(root) + ",target=/work,readonly", "debian:bookworm-slim", "sh", "-ceu", self.removal_command(package.name, installation_id=installation_id, ownership_fixture=ownership_fixture.name)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if result.returncode != 0:
                self.fail("selected product Docker dpkg lifecycle proof failed:\nstdout:\n" + result.stdout + "\nstderr:\n" + result.stderr)
            self.assertIn('"state":"completed"', result.stdout)
            self.assertIn('"packageReceiptRemoval":"removed-by-os-package-manager"', result.stdout)

    @staticmethod
    def removal_command(
        package_file_name: str = "com.tirosh.vitalserver.runtime-platform_0.2.0-dev_amd64.deb",
        *,
        installation_id: str = "vitalserver-runtime-platform",
        ownership_fixture: str = "host-update-ownership-fixture",
    ) -> str:
        return "\n".join((
            "dpkg --install /work/" + package_file_name,
            "for path in /opt/vitalserver-runtime-platform/current /etc/systemd/system/vitalserver-host-agent.service /opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json; do if ! test -e \"$path\"; then echo \"missing installed package payload: $path\" >&2; exit 1; fi; done",
            "/work/" + ownership_fixture + " --socket /run/vitalserver-runtime-platform/host-agent.sock --descriptor /opt/vitalserver-runtime-platform/control/host-agent.local.json --installation-id " + installation_id + " --installation-revision 1 &",
            "fixture_pid=$!",
            "for attempt in 1 2 3 4 5; do test -f /opt/vitalserver-runtime-platform/control/host-agent.local.json && break; sleep 1; done",
            "if ! test -f /opt/vitalserver-runtime-platform/control/host-agent.local.json; then echo 'explicit Host update ownership fixture did not publish its descriptor' >&2; kill \"$fixture_pid\" || true; exit 1; fi",
            "dpkg --remove com.tirosh.vitalserver.runtime-platform",
            "for path in /opt/vitalserver-runtime-platform/releases /opt/vitalserver-runtime-platform/current /etc/systemd/system/vitalserver-host-agent.service /opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json; do if test -e \"$path\"; then echo \"unexpected remaining package payload: $path\" >&2; exit 1; fi; done",
            "receipt=/var/lib/vitalserver-runtime-platform/data/installation-manager/latest-removal-receipt.json; if ! test -f \"$receipt\"; then echo \"missing C54 terminal receipt: $receipt\" >&2; exit 1; fi",
            "if ! grep -Eq '\"state\"[[:space:]]*:[[:space:]]*\"completed\"' \"$receipt\"; then echo 'C54 receipt is not completed' >&2; exit 1; fi",
            "if ! grep -Eq '\"packageReceiptRemoval\"[[:space:]]*:[[:space:]]*\"removed-by-os-package-manager\"' \"$receipt\"; then echo 'C54 receipt does not name OS package-manager removal' >&2; exit 1; fi",
            "status=$(dpkg-query -W -f='${Status}' com.tirosh.vitalserver.runtime-platform); if test \"$status\" != 'deinstall ok config-files'; then echo \"unexpected final dpkg status: $status\" >&2; exit 1; fi",
        ))

    @staticmethod
    def build_ownership_fixture(*, repository_root: Path, destination: Path) -> Path:
        environment = dict(os.environ)
        environment.update({"GOOS": "linux", "GOARCH": "amd64", "CGO_ENABLED": "0"})
        result = subprocess.run(
            [
                environment.get("GO", "go"),
                "build",
                "-trimpath",
                "-o",
                str(destination),
                ".",
            ],
            cwd=repository_root / "tooling" / "host-update-ownership-fixture",
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                "failed to build explicit Host update ownership fixture:\n"
                + result.stdout
                + result.stderr
            )
        return destination

    def compose_package(self, root: Path, manager_source: Path) -> Path:
        release_id = "runtime-platform-0.2.0-dev-build-001"
        release_root = "/opt/vitalserver-runtime-platform/releases/" + release_id
        release = root / "release"
        manager = release / "bin" / "host-installation-manager"
        manager.parent.mkdir(parents=True)
        shutil.copyfile(manager_source, manager)
        manager.chmod(0o755)
        bootstrap = root / "runtime-console-bootstrap.json"
        bootstrap_bytes = b'{"schemaVersion":"v1"}\n'
        bootstrap.write_bytes(bootstrap_bytes)
        services: dict[str, Path] = {}
        required_services = []
        for role, name in (("host-agent", "vitalserver-host-agent.service"), ("host-edge-proxy", "vitalserver-host-edge-proxy.service"), ("host-update-handoff-supervisor", "vitalserver-host-update-handoff-supervisor.service")):
            definition = root / (role + ".service")
            definition.write_text("[Unit]\nDescription=" + role + "\n[Service]\nExecStart=/bin/true\n", encoding="utf-8")
            services[role] = definition
            required_services.append({"role": role, "manager": "systemd", "name": name, "definitionPath": "/etc/systemd/system/" + name, "definitionSha256": sha256_file(definition)})
        manifest = {
            "schemaVersion": "v1", "installationId": "vitalserver-runtime-platform", "platform": "linux",
            "release": {"id": release_id, "productVersion": "0.2.0-dev", "runtimeVersion": "0.2.0"},
            "package": {"identifier": "com.tirosh.vitalserver.runtime-platform", "productVersion": "0.2.0-dev"},
            "immutablePayload": {"releaseCatalogPath": "/opt/vitalserver-runtime-platform/releases", "releaseRootPath": release_root, "manifestPath": release_root + "/installation-manifest.json", "entries": [{"relativePath": "bin/host-installation-manager", "sha256": sha256_file(manager), "executable": True}]},
            "activation": {"currentReleaseLinkPath": "/opt/vitalserver-runtime-platform/current", "referenceKind": "symbolic-link", "expectedReleaseRootPath": release_root},
            "operatorInterface": {"bootstrapConfigurationPath": "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json", "bootstrapConfigurationSha256": sha256_bytes(bootstrap_bytes)},
            "requiredServices": required_services,
            "mutableStores": [
                {"id": "installation-data-root", "path": "/var/lib/vitalserver-runtime-platform/data", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
                {"id": "installation-manager-journal", "path": "/var/lib/vitalserver-runtime-platform/data/installation-manager", "kind": "directory", "owner": "host-installation-manager", "retention": "purge-only-by-explicit-command"},
            ],
        }
        manifest_path = release / "installation-manifest.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        fake_systemctl = root / "vitalserver-test-systemctl"
        fake_systemctl.write_text("#!/bin/sh\nif [ \"${1:-}\" = show ]; then printf '%s\\n' not-found; fi\nexit 0\n", encoding="utf-8")
        fake_systemctl.chmod(0o755)
        package = root / "com.tirosh.vitalserver.runtime-platform_0.2.0-dev_amd64.deb"
        composer.compose_linux_host_package(composer.LinuxHostPackageComposition(
            manifest_path=manifest_path, release_source_directory=release, service_definition_sources=services, operator_interface_bootstrap_source=bootstrap,
            installation_journal_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/current-transaction.json",
            installation_receipt_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/latest-installation-receipt.json",
            removal_journal_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/current-removal-transaction.json",
            removal_receipt_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/latest-removal-receipt.json",
            package_manager_completion_manager_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/package-manager-removal-completion",
            package_manager_completion_manifest_path="/var/lib/vitalserver-runtime-platform/data/installation-manager/package-manager-removal-manifest.json",
            output_package=package, package_name="com.tirosh.vitalserver.runtime-platform", architecture="amd64", maintainer="Tirosh <support@tirosh.example>", description="VitalServer Runtime Platform", systemctl_executable_path="/work/vitalserver-test-systemctl",
        ))
        return package
