"""Focused C43 assembly tests: C42 evidence, MBR bytes, and no partial output."""

from __future__ import annotations

import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tooling.guest_root_storage_partition_assembler import (
    GuestRootStoragePartitionAssemblyError,
    GuestRootStoragePartitionAssemblyExecution,
    execute_guest_root_storage_partition_assembly,
    main,
)


class GuestRootStoragePartitionAssemblerTests(unittest.TestCase):
    def test_assembles_c42_whole_disk_ext4_into_declared_mbr_root_partition(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path, _, c42_receipt_path = _write_c42_source_evidence(root)
            c43_declaration_path = _write_c43_declaration(
                root,
                source_path,
                c42_receipt_path,
            )
            output_directory = root / "assembled-root-storage"

            with patch(
                "tooling.guest_root_storage_partition_assembler._record_utc_root_storage_partition_assembly_completion_time",
                return_value="2026-07-17T12:12:00Z",
            ):
                receipt = execute_guest_root_storage_partition_assembly(
                    GuestRootStoragePartitionAssemblyExecution(
                        declaration_absolute_path=c43_declaration_path,
                        output_directory=output_directory,
                    )
                )

            target_path = output_directory / "storage" / "vitalserver-guest-root.raw"
            self.assertTrue(target_path.is_file())
            self.assertEqual("vitalserver-guest-root-storage", receipt["targetRootStorage"]["id"])
            self.assertEqual(target_path.stat().st_size, receipt["targetRootStorage"]["sizeBytes"])
            self.assertEqual("2026-07-17T12:12:00Z", receipt["completedAt"])
            self.assertNotIn(str(root), (output_directory / "guest-root-storage-partition-assembly-receipt.json").read_text())
            with target_path.open("rb") as target_file:
                mbr = target_file.read(512)
                self.assertEqual(b"\x55\xaa", mbr[510:512])
                self.assertEqual(0x83, mbr[450])
                self.assertEqual(2048, struct.unpack_from("<I", mbr, 454)[0])
                self.assertEqual(source_path.stat().st_size // 512, struct.unpack_from("<I", mbr, 458)[0])
                target_file.seek(2048 * 512)
                self.assertEqual(source_path.read_bytes(), target_file.read())

    def test_rejects_tampered_c42_receipt_without_publishing_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path, _, c42_receipt_path = _write_c42_source_evidence(root)
            c42_receipt_path.write_text("{}\n", encoding="utf-8")
            c43_declaration_path = _write_c43_declaration(
                root,
                source_path,
                c42_receipt_path,
                declared_receipt_sha256="0" * 64,
            )
            output_directory = root / "assembled-root-storage"

            with self.assertRaisesRegex(GuestRootStoragePartitionAssemblyError, "C42-evidence-verify"):
                execute_guest_root_storage_partition_assembly(
                    GuestRootStoragePartitionAssemblyExecution(
                        declaration_absolute_path=c43_declaration_path,
                        output_directory=output_directory,
                    )
                )

            self.assertFalse(output_directory.exists())

    def test_rejects_source_without_ext4_signature_without_publishing_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_path, c42_declaration_path, c42_receipt_path = _write_c42_source_evidence(root)
            source_path.write_bytes(b"\0" * 4096)
            _rewrite_c42_receipt_for_source(c42_receipt_path, source_path, c42_declaration_path)
            c43_declaration_path = _write_c43_declaration(
                root,
                source_path,
                c42_receipt_path,
            )
            output_directory = root / "assembled-root-storage"

            with self.assertRaisesRegex(GuestRootStoragePartitionAssemblyError, "source-root-storage-verify"):
                execute_guest_root_storage_partition_assembly(
                    GuestRootStoragePartitionAssemblyExecution(
                        declaration_absolute_path=c43_declaration_path,
                        output_directory=output_directory,
                    )
                )

            self.assertFalse(output_directory.exists())

    def test_execution_rejects_a_caller_supplied_completion_time(self) -> None:
        with self.assertRaises(TypeError):
            GuestRootStoragePartitionAssemblyExecution(
                declaration_absolute_path=Path("/declaration.json"),
                output_directory=Path("/output"),
                completed_at="2026-07-17T21:12:00+09:00",
            )

    def test_cli_rejects_a_caller_supplied_completion_time(self) -> None:
        with self.assertRaises(SystemExit):
            main(
                [
                    "--guest-root-storage-partition-assembly-declaration",
                    "/declaration.json",
                    "--output-directory",
                    "/output",
                    "--completed-at",
                    "2026-07-17T21:12:00+09:00",
                ]
            )


def _write_c42_source_evidence(root: Path) -> tuple[Path, Path, Path]:
    source_path = root / "ubuntu-noble-root.raw"
    source_bytes = bytearray(4096)
    source_bytes[1024 + 56 : 1024 + 58] = b"\x53\xef"
    source_path.write_bytes(source_bytes)
    identity = _identity(source_path)
    c42_declaration_path = root / "guest-linux-boot-artifact-extraction-declaration.json"
    c42_declaration = {
        "schemaVersion": "v1",
        "extractionId": "ubuntu-noble-arm64-boot-artifacts",
        "architecture": "arm64",
        "sourceImage": {
            "id": "ubuntu-noble-arm64-cloud-image",
            "sourceAbsolutePath": str(source_path),
            "sourceOriginUri": "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-noble.tar.gz",
            "sourceRelease": "Ubuntu Noble",
            **identity,
        },
        "sourceFilesystem": {"layout": "whole-disk-ext4", "filesystemType": "ext4"},
        "bootResources": {
            "kernel": {"id": "kernel", "guestAbsolutePath": "/boot/vmlinuz", "sourceCompression": "gzip", "outputRelativePath": "boot/Image", "outputFormat": "uncompressed-linux-arm64-image"},
            "initialRamdisk": {"id": "initrd", "guestAbsolutePath": "/boot/initrd.img", "sourceCompression": "none", "outputRelativePath": "boot/initrd.img", "outputFormat": "cpio"},
        },
        "rootStorage": {
            "id": "ubuntu-noble-arm64-root-storage",
            "guestDevicePath": "/dev/vda",
            "outputRelativePath": "storage/ubuntu-noble-root.raw",
            "filesystemType": "ext4",
            "storageLayout": "whole-disk-ext4",
        },
    }
    _write_json(c42_declaration_path, c42_declaration)
    c42_receipt_path = root / "guest-linux-boot-artifact-extraction-receipt.json"
    _rewrite_c42_receipt_for_source(c42_receipt_path, source_path, c42_declaration_path)
    return source_path, c42_declaration_path, c42_receipt_path


def _rewrite_c42_receipt_for_source(
    c42_receipt_path: Path,
    source_path: Path,
    c42_declaration_path: Path | None = None,
) -> None:
    identity = _identity(source_path)
    declaration_sha256 = "1" * 64 if c42_declaration_path is None else _sha256(c42_declaration_path)
    _write_json(
        c42_receipt_path,
        {
            "schemaVersion": "v1",
            "extractionId": "ubuntu-noble-arm64-boot-artifacts",
            "architecture": "arm64",
            "extractionDeclarationSHA256": declaration_sha256,
            "sourceImage": {"id": "ubuntu-noble-arm64-cloud-image", **identity},
            "bootResources": [
                {"id": "kernel", "relativePath": "boot/Image", "sizeBytes": 1, "sha256": "2" * 64},
                {"id": "initrd", "relativePath": "boot/initrd.img", "sizeBytes": 1, "sha256": "3" * 64},
            ],
            "rootStorage": {"id": "ubuntu-noble-arm64-root-storage", "relativePath": "storage/ubuntu-noble-root.raw", **identity},
            "completedAt": "2026-07-17T21:12:00+09:00",
        },
    )


def _write_c43_declaration(
    root: Path,
    source_path: Path,
    c42_receipt_path: Path,
    declared_receipt_sha256: str | None = None,
) -> Path:
    identity = _identity(source_path)
    declaration_path = root / "guest-root-storage-partition-assembly-declaration.json"
    _write_json(
        declaration_path,
        {
            "schemaVersion": "v1",
            "assemblyId": "ubuntu-noble-arm64-root-partition",
            "architecture": "arm64",
            "sourceC42Receipt": {
                "receiptAbsolutePath": str(c42_receipt_path),
                "receiptSHA256": declared_receipt_sha256 or _sha256(c42_receipt_path),
                "extractionId": "ubuntu-noble-arm64-boot-artifacts",
            },
            "sourceRootStorage": {
                "id": "ubuntu-noble-arm64-root-storage",
                "sourceAbsolutePath": str(source_path),
                **identity,
                "storageLayout": "whole-disk-ext4",
                "filesystemType": "ext4",
            },
            "targetRootStorage": {
                "id": "vitalserver-guest-root-storage",
                "outputRelativePath": "storage/vitalserver-guest-root.raw",
                "guestDiskDevicePath": "/dev/vda",
                "rootPartitionDevicePath": "/dev/vda1",
                "rootPartitionIndex": 1,
                "partitionTableType": "mbr",
                "firstPartitionStartSector": 2048,
                "partitionTypeMbrHex": "83",
                "filesystemType": "ext4",
                "logicalSectorSizeBytes": 512,
            },
        },
    )
    return declaration_path


def _identity(path: Path) -> dict[str, object]:
    return {"sizeBytes": path.stat().st_size, "sha256": _sha256(path)}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_json(path: Path, document: object) -> None:
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
