"""Focused proof for the explicit C35/C39 Guest Node Services bundle input."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from tooling import guest_node_services_bundle_composer as composer


class GuestNodeServicesBundleComposerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.node_root = self.root / "node-linux-arm64"
        self.gateway_root = self.root / "recorder-gateway"
        self.runner_root = self.root / "lab-recorder-runner"
        self.catalog = self.root / "lab-scenario-catalog.json"
        self.output = self.root / "output" / "guest-node-services.tar.gz"
        self.write_file(
            self.node_root / "bin/node",
            b"\x7fELF\x02\x01" + (b"\x00" * 12) + b"\xb7\x00" + b"linux-arm64-node",
            0o755,
        )
        self.write_file(
            self.gateway_root / "package.json",
            b'{"dependencies":{"socket.io":"4.8.3"},"devDependencies":{"typescript":"5.9.3","ws":"8.21.1"}}',
        )
        self.write_lock(
            self.gateway_root,
            {
                "node_modules/socket.io": {"version": "4.8.3"},
                # The real Gateway declares ws for development but Socket.IO
                # also requires it at runtime.  Its lock entry is therefore
                # not development-only and it is valid in the bundle.
                "node_modules/ws": {"version": "8.21.1"},
                "node_modules/typescript": {"version": "5.9.3", "dev": True},
            },
        )
        self.write_file(
            self.gateway_root / "dist/cmd/recorder-gateway.js",
            b"gateway-program",
            0o755,
        )
        self.write_file(
            self.gateway_root / "node_modules/socket.io/index.js",
            b"gateway-runtime-dependency",
        )
        self.write_file(
            self.gateway_root / "node_modules/ws/index.js",
            b"gateway-transitive-runtime-dependency",
        )
        self.write_file(
            self.runner_root / "package.json",
            b'{"dependencies":{"socket.io-client":"4.8.3"},"devDependencies":{"typescript":"5.9.3"}}',
        )
        self.write_lock(
            self.runner_root,
            {
                "node_modules/socket.io-client": {"version": "4.8.3"},
                "node_modules/typescript": {"version": "5.9.3", "dev": True},
            },
        )
        self.write_file(
            self.runner_root / "dist/cmd/lab-recorder-runner.js",
            b"runner-program",
            0o755,
        )
        self.write_file(
            self.runner_root / "node_modules/socket.io-client/index.js",
            b"runner-runtime-dependency",
        )
        self.write_file(
            self.catalog,
            b'{"schemaVersion":"v1","catalogId":"test-lab-scenarios","scenarios":[]}',
        )
        self.output.parent.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_composes_deterministic_bundle_with_all_required_product_paths(self) -> None:
        first = composer.compose_guest_node_services_bundle(self.composition())

        self.assertEqual("guest-node-services-linux-arm64", first["artifactId"])
        self.assertEqual(self.output.stat().st_size, first["sizeBytes"])
        self.assertEqual(self.sha256(self.output), first["sha256"])
        with tarfile.open(self.output, "r:gz") as archive:
            names = set(archive.getnames())
            self.assertTrue(
                {
                    "node/bin/node",
                    "recorder-gateway/dist/cmd/recorder-gateway.js",
                    "recorder-gateway/node_modules/socket.io/index.js",
                    "lab-recorder-runner/dist/cmd/lab-recorder-runner.js",
                    "lab-recorder-runner/node_modules/socket.io-client/index.js",
                    "lab-recorder-runner/lab-scenario-catalog.json",
                }.issubset(names)
            )
            self.assertEqual(
                b'{"schemaVersion":"v1","catalogId":"test-lab-scenarios","scenarios":[]}',
                archive.extractfile("lab-recorder-runner/lab-scenario-catalog.json").read(),
            )
        self.assertFalse(any(path.name.startswith(".") for path in self.output.parent.iterdir()))

    def test_composes_amd64_bundle_only_from_linux_amd64_node(self) -> None:
        amd64_node_root = self.root / "node-linux-amd64"
        self.write_file(
            amd64_node_root / "bin/node",
            b"\x7fELF\x02\x01" + (b"\x00" * 12) + b"\x3e\x00" + b"linux-amd64-node",
            0o755,
        )
        output = self.root / "output" / "guest-node-services-amd64.tar.gz"
        composition = composer.GuestNodeServicesBundleComposition(
            node_distribution_root=amd64_node_root,
            guest_architecture="amd64",
            recorder_gateway_root=self.gateway_root,
            lab_recorder_runner_root=self.runner_root,
            lab_scenario_catalog=self.catalog,
            output_archive=output,
        )

        result = composer.compose_guest_node_services_bundle(composition)

        self.assertEqual("guest-node-services-linux-amd64", result["artifactId"])
        self.assertTrue(output.is_file())

    def test_rejects_runner_dependency_symlink_that_escapes_its_declared_tree(self) -> None:
        escaped = self.root / "escaped-dependency.js"
        self.write_file(escaped, b"outside")
        (self.runner_root / "node_modules/socket.io-client/escaped.js").symlink_to(
            "../../../escaped-dependency.js"
        )

        with self.assertRaisesRegex(
            composer.GuestNodeServicesBundleCompositionError,
            "symbolic link escapes",
        ):
            composer.compose_guest_node_services_bundle(self.composition())

        self.assertFalse(self.output.exists())

    def test_preserves_a_relative_node_distribution_symlink_inside_its_declared_tree(self) -> None:
        self.write_file(self.node_root / "bin/node-helper", b"node-helper", 0o755)
        (self.node_root / "bin/corepack").symlink_to("node-helper")

        composer.compose_guest_node_services_bundle(self.composition())

        with tarfile.open(self.output, "r:gz") as archive:
            corepack = archive.getmember("node/bin/corepack")
            self.assertTrue(corepack.issym())
            self.assertEqual("node-helper", corepack.linkname)

    def test_does_not_overwrite_an_existing_declared_output(self) -> None:
        self.output.write_bytes(b"existing-release-artifact")

        with self.assertRaisesRegex(
            composer.GuestNodeServicesBundleCompositionError,
            "output already exists",
        ):
            composer.compose_guest_node_services_bundle(self.composition())

        self.assertEqual(b"existing-release-artifact", self.output.read_bytes())

    def test_rejects_host_or_wrong_architecture_node_before_packaging(self) -> None:
        self.write_file(self.node_root / "bin/node", b"not-linux-node", 0o755)

        with self.assertRaisesRegex(
            composer.GuestNodeServicesBundleCompositionError,
            "Linux ELF64",
        ):
            composer.compose_guest_node_services_bundle(self.composition())

        self.assertFalse(self.output.exists())

    def test_rejects_arm64_node_when_amd64_guest_was_selected(self) -> None:
        composition = composer.GuestNodeServicesBundleComposition(
            node_distribution_root=self.node_root,
            guest_architecture="amd64",
            recorder_gateway_root=self.gateway_root,
            lab_recorder_runner_root=self.runner_root,
            lab_scenario_catalog=self.catalog,
            output_archive=self.output,
        )

        with self.assertRaisesRegex(
            composer.GuestNodeServicesBundleCompositionError,
            "Linux amd64",
        ):
            composer.compose_guest_node_services_bundle(composition)

        self.assertFalse(self.output.exists())

    def test_rejects_development_dependency_in_runtime_payload(self) -> None:
        self.write_file(
            self.runner_root / "node_modules/typescript/bin/tsc",
            b"development-compiler",
        )

        with self.assertRaisesRegex(
            composer.GuestNodeServicesBundleCompositionError,
            "development-only package: node_modules/typescript",
        ):
            composer.compose_guest_node_services_bundle(self.composition())

        self.assertFalse(self.output.exists())

    def composition(self) -> composer.GuestNodeServicesBundleComposition:
        return composer.GuestNodeServicesBundleComposition(
            node_distribution_root=self.node_root,
            guest_architecture="arm64",
            recorder_gateway_root=self.gateway_root,
            lab_recorder_runner_root=self.runner_root,
            lab_scenario_catalog=self.catalog,
            output_archive=self.output,
        )

    def write_file(self, path: Path, contents: bytes, mode: int = 0o644) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        path.chmod(mode)

    def write_lock(self, service_root: Path, packages: dict[str, dict[str, object]]) -> None:
        self.write_file(
            service_root / "package-lock.json",
            json.dumps(
                {
                    "lockfileVersion": 3,
                    "packages": {
                        "": {"name": service_root.name},
                        **packages,
                    },
                },
                sort_keys=True,
            ).encode("utf-8"),
        )

    def sha256(self, path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
