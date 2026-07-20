"""Focused proof for the explicit macOS C42/C43 development input workflow."""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
import tempfile
import textwrap
import unittest

from tooling import macos_development_guest_boot_input_assembly as assembly_module


class MacOSDevelopmentGuestBootInputAssemblyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.release_root = self.root / "release"
        self.release_root.mkdir()
        self.source_image = self.root / "ubuntu-arm64-whole-disk-ext4.raw"
        image = bytearray(4096)
        image[1024 + 56 : 1024 + 58] = b"\x53\xef"
        self.source_image.write_bytes(image)
        self.c42_extractor = self.root / "fake-c42-extractor.py"
        self.write_fake_c42_extractor(self.c42_extractor)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_assembles_c42_and_c43_outputs_without_retaining_source_paths(self) -> None:
        result = assembly_module.assemble_macos_development_guest_boot_inputs(
            self.assembly()
        )

        output = self.release_root / "guest-boot-inputs"
        self.assertEqual(str(output), result["guestBootInputsDirectory"])
        self.assertTrue((output / "c42-artifacts" / "boot/Image").is_file())
        self.assertTrue((output / "c42-artifacts" / "boot/initrd.img").is_file())
        root_storage = output / "c43-artifacts" / "storage/guest-root.raw"
        self.assertTrue(root_storage.is_file())
        self.assertEqual(2048 * 512 + self.source_image.stat().st_size, root_storage.stat().st_size)
        self.assertFalse((output / "guest-linux-boot-artifact-extraction-declaration.json").exists())
        self.assertFalse((output / "guest-root-storage-partition-assembly-declaration.json").exists())
        receipt = output / "macos-development-guest-boot-input-assembly-receipt.json"
        encoded = receipt.read_text(encoding="utf-8")
        self.assertNotIn(str(self.source_image), encoded)
        document = json.loads(encoded)
        self.assertEqual("development-guest-boot-inputs-001", document["assemblyId"])
        self.assertEqual("storage/guest-root.raw", document["c43"]["rootStorage"]["relativePath"].split("/", 1)[1])
        self.assertFalse(any(path.name.startswith(".guest-boot-inputs.") for path in self.release_root.iterdir()))

    def test_c42_failure_does_not_publish_partial_guest_boot_inputs(self) -> None:
        failing = self.root / "failing-c42-extractor.py"
        failing.write_text("#!/bin/sh\nprintf '%s\\n' intentional-c42-failure >&2\nexit 19\n", encoding="utf-8")
        failing.chmod(0o755)
        candidate = assembly_module.MacOSDevelopmentGuestBootInputAssembly(
            **{**self.assembly().__dict__, "c42_extractor_executable": failing}
        )

        with self.assertRaisesRegex(
            assembly_module.MacOSDevelopmentGuestBootInputAssemblyError,
            "C42 extractor failed exitCode=19",
        ):
            assembly_module.assemble_macos_development_guest_boot_inputs(candidate)

        self.assertFalse((self.release_root / "guest-boot-inputs").exists())
        self.assertFalse(any(path.name.startswith(".guest-boot-inputs.") for path in self.release_root.iterdir()))

    def test_existing_guest_boot_input_directory_is_preserved(self) -> None:
        output = self.release_root / "guest-boot-inputs"
        output.mkdir()
        sentinel = output / "sentinel"
        sentinel.write_text("preserve", encoding="utf-8")

        with self.assertRaisesRegex(
            assembly_module.MacOSDevelopmentGuestBootInputAssemblyError,
            "already exists",
        ):
            assembly_module.assemble_macos_development_guest_boot_inputs(self.assembly())

        self.assertEqual("preserve", sentinel.read_text(encoding="utf-8"))

    def test_composes_identity_verified_external_boot_sources_without_guest_path_fallback(self) -> None:
        kernel = self.root / "ubuntu-arm64-vmlinuz-generic"
        initrd = self.root / "ubuntu-arm64-initrd-generic"
        kernel.write_bytes(b"gzip-kernel")
        initrd.write_bytes(b"cpio-initrd")
        candidate = assembly_module.MacOSDevelopmentGuestBootInputAssembly(
            **{
                **self.assembly().__dict__,
                "kernel_source": assembly_module.MacOSDevelopmentGuestBootResourceSource(
                    kind="external-artifact",
                    external_artifact=kernel,
                    external_origin_uri="https://cloud-images.example.test/noble/vmlinuz-generic",
                    external_release="ubuntu-24.04-noble-release-20250516",
                ),
                "initial_ramdisk_source": assembly_module.MacOSDevelopmentGuestBootResourceSource(
                    kind="external-artifact",
                    external_artifact=initrd,
                    external_origin_uri="https://cloud-images.example.test/noble/initrd-generic",
                    external_release="ubuntu-24.04-noble-release-20250516",
                ),
            }
        )

        assembly_module.validate_assembly(candidate)
        declaration = assembly_module.compose_c42_declaration(candidate)

        kernel_source = declaration["bootResources"]["kernel"]["source"]
        initrd_source = declaration["bootResources"]["initialRamdisk"]["source"]
        self.assertEqual("external-artifact", kernel_source["kind"])
        self.assertEqual(str(kernel), kernel_source["sourceAbsolutePath"])
        self.assertEqual(kernel.stat().st_size, kernel_source["sizeBytes"])
        self.assertNotIn("guestAbsolutePath", kernel_source)
        self.assertEqual("external-artifact", initrd_source["kind"])
        self.assertEqual(str(initrd), initrd_source["sourceAbsolutePath"])
        self.assertNotIn("guestAbsolutePath", initrd_source)

    def assembly(self) -> assembly_module.MacOSDevelopmentGuestBootInputAssembly:
        return assembly_module.MacOSDevelopmentGuestBootInputAssembly(
            release_root=self.release_root,
            assembly_id="development-guest-boot-inputs-001",
            c42_extraction_id="development-c42-extraction-001",
            c43_assembly_id="development-c43-assembly-001",
            source_image=self.source_image,
            source_image_id="ubuntu-arm64-source-image",
            source_origin_uri="https://images.example.test/ubuntu-arm64-source-image.raw",
            source_release="Ubuntu test ARM64",
            source_filesystem_layout="whole-disk-ext4",
            source_filesystem_partition_index=None,
            source_root_storage_id="ubuntu-arm64-root-storage",
            target_root_storage_id="vitalserver-guest-root-storage",
            target_root_storage_output_relative_path=PurePosixPath("storage/guest-root.raw"),
            kernel_source=assembly_module.MacOSDevelopmentGuestBootResourceSource(
                kind="source-image-filesystem",
                guest_absolute_path=PurePosixPath("/boot/vmlinuz"),
            ),
            initial_ramdisk_source=assembly_module.MacOSDevelopmentGuestBootResourceSource(
                kind="source-image-filesystem",
                guest_absolute_path=PurePosixPath("/boot/initrd.img"),
            ),
            c42_extractor_executable=self.c42_extractor,
        )

    def write_fake_c42_extractor(self, destination: Path) -> None:
        destination.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import hashlib
                import json
                from pathlib import Path
                import sys

                arguments = sys.argv[1:]
                declaration_path = Path(arguments[1])
                output = Path(arguments[3])
                declaration_bytes = declaration_path.read_bytes()
                declaration = json.loads(declaration_bytes)
                source = Path(declaration["sourceImage"]["sourceAbsolutePath"])
                source_bytes = source.read_bytes()
                output.mkdir()
                (output / "boot").mkdir()
                (output / "storage").mkdir()
                kernel = output / "boot/Image"
                initrd = output / "boot/initrd.img"
                root = output / "storage/source-root-storage.raw"
                kernel.write_bytes(b"uncompressed-linux-arm64-kernel")
                initrd.write_bytes(b"cpio-initrd")
                root.write_bytes(source_bytes)
                identity = lambda path: {"sizeBytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                receipt = {
                    "schemaVersion": "v1",
                    "extractionId": declaration["extractionId"],
                    "architecture": "arm64",
                    "extractionDeclarationSHA256": hashlib.sha256(declaration_bytes).hexdigest(),
                    "sourceImage": {"id": declaration["sourceImage"]["id"], **identity(source)},
                    "bootResources": [
                        {"id": declaration["bootResources"]["kernel"]["id"], "relativePath": "boot/Image", **identity(kernel)},
                        {"id": declaration["bootResources"]["initialRamdisk"]["id"], "relativePath": "boot/initrd.img", **identity(initrd)},
                    ],
                    "rootStorage": {"id": declaration["rootStorage"]["id"], "relativePath": "storage/source-root-storage.raw", **identity(root)},
                    "completedAt": "2026-07-19T00:00:00Z",
                }
                (output / "guest-linux-boot-artifact-extraction-receipt.json").write_text(json.dumps(receipt), encoding="utf-8")
                """
            ),
            encoding="utf-8",
        )
        destination.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
