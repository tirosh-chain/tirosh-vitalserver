"""Tests for the macOS Installer component CPIO inventory boundary."""

from __future__ import annotations

import gzip
from pathlib import Path
import stat
import tempfile
import unittest

from tooling import macos_installer_component_cpio as component_cpio


class MacOSInstallerComponentCpioTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_recomposition_removes_only_appledouble_carriers_and_preserves_declared_entries(self) -> None:
        source = self.write_compressed_archive(
            "candidate-payload.gz",
            [
                (".", stat.S_IFDIR | 0o755, b""),
                ("./Library", stat.S_IFDIR | 0o755, b""),
                ("./Library/host-agent", stat.S_IFREG | 0o755, b"host-agent"),
                ("./Library/._host-agent", stat.S_IFREG | 0o644, b"appledouble"),
                ("./._Library", stat.S_IFREG | 0o644, b"directory-metadata"),
            ],
        )
        destination = self.root / "declared-payload.gz"

        inventory = (
            component_cpio.recompose_macos_installer_component_cpio_archive_without_appledouble_carriers(
                source,
                destination,
                "Payload",
            )
        )

        self.assertEqual(3, inventory.retained_entry_count)
        self.assertEqual(len(b"host-agent"), inventory.retained_regular_file_bytes)
        self.assertEqual(
            ("./Library/._host-agent", "./._Library"),
            inventory.removed_appledouble_paths,
        )
        self.assertEqual(
            [".", "./Library", "./Library/host-agent", "TRAILER!!!"],
            archive_pathnames(destination),
        )

    def test_recomposition_rejects_nonzero_data_after_the_cpio_trailer(self) -> None:
        source = self.write_compressed_archive(
            "candidate-payload.gz",
            [(".", stat.S_IFDIR | 0o755, b"")],
            trailer_padding=b"unexpected-record",
        )

        with self.assertRaisesRegex(
            component_cpio.MacOSInstallerComponentCpioArchiveError,
            "contains nonzero data after trailer",
        ):
            component_cpio.recompose_macos_installer_component_cpio_archive_without_appledouble_carriers(
                source,
                self.root / "declared-payload.gz",
                "Payload",
            )

    def test_recomposition_rejects_path_traversal_before_it_can_become_a_package_inventory(self) -> None:
        source = self.write_compressed_archive(
            "candidate-payload.gz",
            [("../outside", stat.S_IFREG | 0o644, b"invalid")],
        )

        with self.assertRaisesRegex(
            component_cpio.MacOSInstallerComponentCpioArchiveError,
            "safe relative Installer path",
        ):
            component_cpio.recompose_macos_installer_component_cpio_archive_without_appledouble_carriers(
                source,
                self.root / "declared-payload.gz",
                "Payload",
            )

    def write_compressed_archive(
        self,
        name: str,
        entries: list[tuple[str, int, bytes]],
        trailer_padding: bytes = b"\0" * 512,
    ) -> Path:
        archive = b"".join(
            old_ascii_cpio_record(pathname, mode, content)
            for pathname, mode, content in [
                *entries,
                ("TRAILER!!!", 0, b""),
            ]
        ) + trailer_padding
        path = self.root / name
        path.write_bytes(gzip.compress(archive, mtime=0))
        return path


def old_ascii_cpio_record(pathname: str, mode: int, content: bytes) -> bytes:
    pathname_bytes = pathname.encode("utf-8") + b"\0"
    header = (
        "070707"
        + f"{0:06o}"  # device
        + f"{0:06o}"  # inode
        + f"{mode:06o}"
        + f"{0:06o}"  # uid
        + f"{0:06o}"  # gid
        + f"{1:06o}"  # links
        + f"{0:06o}"  # rdev
        + f"{0:011o}"  # mtime
        + f"{len(pathname_bytes):06o}"
        + f"{len(content):011o}"
    ).encode("ascii")
    assert len(header) == component_cpio.OLD_ASCII_CPIO_HEADER_BYTES
    return header + pathname_bytes + content


def archive_pathnames(path: Path) -> list[str]:
    raw = gzip.decompress(path.read_bytes())
    offset = 0
    names: list[str] = []
    while True:
        header = raw[offset : offset + component_cpio.OLD_ASCII_CPIO_HEADER_BYTES]
        assert header[:6] == component_cpio.OLD_ASCII_CPIO_MAGIC
        name_size = int(header[59:65], 8)
        file_size = int(header[65:76], 8)
        name_end = offset + component_cpio.OLD_ASCII_CPIO_HEADER_BYTES + name_size
        pathname = raw[
            offset + component_cpio.OLD_ASCII_CPIO_HEADER_BYTES : name_end - 1
        ].decode("utf-8")
        names.append(pathname)
        if pathname == "TRAILER!!!":
            return names
        offset = name_end + file_size


if __name__ == "__main__":
    unittest.main()
