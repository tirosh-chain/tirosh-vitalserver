"""Behavior checks for C34 composition from explicit Guest compiler outputs."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from tooling import macos_guest_artifact_manifest_composer as composer


class MacOSGuestArtifactManifestComposerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.kernel = self.write_artifact("compiler-output/Image", b"kernel")
        self.initial_ramdisk = self.write_artifact("compiler-output/initrd.img", b"initial ramdisk")
        self.root_storage = self.write_artifact("compiler-output/guest-root.raw", b"guest storage")
        self.bootstrap_volume = self.write_artifact("compiler-output/guest-product-bootstrap.raw", b"bootstrap volume")
        self.output_directory = self.root / "release"
        self.output_directory.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_artifact(self, relative_path: str, content: bytes) -> Path:
        artifact = self.root / relative_path
        artifact.parent.mkdir(parents=True, exist_ok=True)
        artifact.write_bytes(content)
        return artifact

    def composition(self, output_name: str = "macos-guest-artifact-manifest.json") -> composer.MacOSGuestArtifactManifestComposition:
        return composer.MacOSGuestArtifactManifestComposition(
            artifact_set_id="vitalserver-guest-arm64-dev",
            kernel_source=self.kernel,
            initial_ramdisk_source=self.initial_ramdisk,
            storage_sources=(
                composer.MacOSGuestStorageArtifactSource(
                    storage_id="guest-root",
                    storage_role="guest-root-storage",
                    storage_image_format="raw",
                    guest_volume_file_system=None,
                    source=self.root_storage,
                ),
                composer.MacOSGuestStorageArtifactSource(
                    storage_id="guest-product-bootstrap",
                    storage_role="guest-product-bootstrap-volume",
                    storage_image_format="raw",
                    guest_volume_file_system="iso9660",
                    source=self.bootstrap_volume,
                ),
            ),
            output_manifest=self.output_directory / output_name,
            replace_output=False,
        )

    def test_composes_c34_without_leaking_build_machine_source_paths(self) -> None:
        composition = self.composition()
        document = composer.compose_macos_guest_artifact_manifest(composition)
        persisted = json.loads(composition.output_manifest.read_text(encoding="utf-8"))

        self.assertEqual(document, persisted)
        self.assertEqual("v1", document["schemaVersion"])
        self.assertEqual("arm64", document["architecture"])
        self.assertEqual({"id", "role", "storageImageFormat", "sizeBytes", "sha256"}, set(document["storageDevices"][0]))
        self.assertNotIn(str(self.root), composition.output_manifest.read_text(encoding="utf-8"))

    def test_refuses_to_overwrite_existing_manifest_without_explicit_replacement(self) -> None:
        composition = self.composition()
        composer.compose_macos_guest_artifact_manifest(composition)

        with self.assertRaisesRegex(composer.MacOSGuestArtifactManifestCompositionError, "already exists"):
            composer.compose_macos_guest_artifact_manifest(composition)

    def test_rejects_missing_or_empty_compiler_output(self) -> None:
        missing = self.composition()
        missing = composer.MacOSGuestArtifactManifestComposition(
            artifact_set_id=missing.artifact_set_id,
            kernel_source=self.root / "compiler-output" / "missing-kernel",
            initial_ramdisk_source=missing.initial_ramdisk_source,
            storage_sources=missing.storage_sources,
            output_manifest=missing.output_manifest,
            replace_output=missing.replace_output,
        )
        with self.assertRaisesRegex(composer.MacOSGuestArtifactManifestCompositionError, "Guest kernel source"):
            composer.compose_macos_guest_artifact_manifest(missing)

        empty_storage = self.write_artifact("compiler-output/empty.raw", b"")
        empty = composer.MacOSGuestArtifactManifestComposition(
            artifact_set_id="vitalserver-guest-arm64-empty",
            kernel_source=self.kernel,
            initial_ramdisk_source=None,
            storage_sources=(
                composer.MacOSGuestStorageArtifactSource(
                    storage_id="guest-root",
                    storage_role="guest-root-storage",
                    storage_image_format="raw",
                    guest_volume_file_system=None,
                    source=empty_storage,
                ),
                composer.MacOSGuestStorageArtifactSource(
                    storage_id="guest-product-bootstrap",
                    storage_role="guest-product-bootstrap-volume",
                    storage_image_format="raw",
                    guest_volume_file_system="iso9660",
                    source=self.bootstrap_volume,
                ),
            ),
            output_manifest=self.output_directory / "empty.json",
            replace_output=False,
        )
        with self.assertRaisesRegex(composer.MacOSGuestArtifactManifestCompositionError, "must not be empty"):
            composer.compose_macos_guest_artifact_manifest(empty)

    def test_storage_source_parser_requires_unique_explicit_identity(self) -> None:
        with self.assertRaisesRegex(composer.MacOSGuestArtifactManifestCompositionError, "unique"):
            composer.parse_storage_sources(["guest-root=guest-root-storage,raw,none:/tmp/one.raw", "guest-root=guest-root-storage,raw,none:/tmp/two.raw"])
        with self.assertRaisesRegex(composer.MacOSGuestArtifactManifestCompositionError, "formatted"):
            composer.parse_storage_sources(["guest-root"])


if __name__ == "__main__":
    unittest.main()
