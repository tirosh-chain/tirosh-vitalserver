from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tooling import guest_linux_source_disk_materializer as materializer


class GuestLinuxSourceDiskMaterializerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "ubuntu-arm64.qcow2"
        self.source.write_bytes(b"declared qcow2 bytes")
        self.qemu_img = self.root / "qemu-img"
        self.qemu_img.write_text("fixture", encoding="utf-8")
        self.qemu_img.chmod(0o700)
        self.declaration_path = self.root / "declaration.json"
        self.write_declaration()
        self.output_directory = self.root / "output"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_declaration(self) -> None:
        self.declaration_path.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "documentKind": "guest-linux-source-disk-materialization-declaration",
                    "materializationId": "ubuntu-arm64-qcow2-to-raw",
                    "architecture": "arm64",
                    "sourceImage": {
                        "id": "ubuntu-arm64-qcow2",
                        "sourceAbsolutePath": str(self.source),
                        "sourceOriginUri": "https://images.example.test/ubuntu-arm64.qcow2",
                        "sourceRelease": "ubuntu-24.04-release-20250516",
                        "sizeBytes": self.source.stat().st_size,
                        "sha256": hashlib.sha256(self.source.read_bytes()).hexdigest(),
                    },
                    "sourceImageFormat": "qcow2",
                    "rawImage": {
                        "id": "ubuntu-arm64-raw",
                        "outputRelativePath": "storage/ubuntu-arm64.raw",
                        "imageFormat": "raw",
                    },
                }
            ),
            encoding="utf-8",
        )

    def command_result(self, arguments: list[str]) -> mock.Mock:
        if arguments[1:3] == ["info", "--output=json"]:
            image_path = Path(arguments[3])
            image_format = "qcow2" if image_path == self.source else "raw"
            return mock.Mock(
                returncode=0,
                stdout=json.dumps(
                    {"format": image_format, "virtual-size": 4096}
                ),
                stderr="",
            )
        if arguments[1:3] == ["convert", "-O"]:
            self.assertEqual("raw", arguments[3])
            raw_output = Path(arguments[5])
            raw_output.write_bytes(b"R" * 4096)
            return mock.Mock(returncode=0, stdout="", stderr="")
        self.fail("unexpected qemu-img invocation: " + str(arguments))

    def execute(self) -> dict:
        with mock.patch.object(
            materializer.subprocess,
            "run",
            side_effect=lambda arguments, **_: self.command_result(arguments),
        ):
            return dict(
                materializer.execute_guest_linux_source_disk_materialization(
                    materializer.GuestLinuxSourceDiskMaterialization(
                        declaration_path=self.declaration_path,
                        output_directory=self.output_directory,
                        qemu_img_executable=self.qemu_img,
                    )
                )
            )

    def test_materializes_one_identified_qcow2_as_a_new_raw_image_and_receipt(self) -> None:
        result = self.execute()

        raw_image_path = self.output_directory / "storage" / "ubuntu-arm64.raw"
        receipt_path = self.output_directory / "guest-linux-source-disk-materialization-receipt.json"
        self.assertEqual(str(raw_image_path), result["rawImage"]["path"])
        self.assertEqual(b"R" * 4096, raw_image_path.read_bytes())
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertEqual("guest-linux-source-disk-materialization-receipt", receipt["documentKind"])
        self.assertEqual("qcow2", receipt["sourceImageFormat"])
        self.assertEqual("raw", receipt["rawImage"]["imageFormat"])
        self.assertNotIn(str(self.root), receipt_path.read_text(encoding="utf-8"))

    def test_rejects_image_tool_that_reports_a_non_qcow2_source_before_output_exists(self) -> None:
        def wrong_source_format(arguments: list[str], **_: object) -> mock.Mock:
            return mock.Mock(
                returncode=0,
                stdout=json.dumps({"format": "raw", "virtual-size": 4096}),
                stderr="",
            )

        with mock.patch.object(materializer.subprocess, "run", side_effect=wrong_source_format):
            with self.assertRaisesRegex(
                materializer.GuestLinuxSourceDiskMaterializationError,
                "not declared qcow2",
            ):
                materializer.execute_guest_linux_source_disk_materialization(
                    materializer.GuestLinuxSourceDiskMaterialization(
                        declaration_path=self.declaration_path,
                        output_directory=self.output_directory,
                        qemu_img_executable=self.qemu_img,
                    )
                )
        self.assertFalse(self.output_directory.exists())

    def test_rejects_existing_output_directory_without_replacing_it(self) -> None:
        self.output_directory.mkdir()
        with self.assertRaisesRegex(
            materializer.GuestLinuxSourceDiskMaterializationError,
            "must be new",
        ):
            materializer.execute_guest_linux_source_disk_materialization(
                materializer.GuestLinuxSourceDiskMaterialization(
                    declaration_path=self.declaration_path,
                    output_directory=self.output_directory,
                    qemu_img_executable=self.qemu_img,
                )
            )


if __name__ == "__main__":
    unittest.main()
