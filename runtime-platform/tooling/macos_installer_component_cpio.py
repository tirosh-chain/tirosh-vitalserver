"""Recompose macOS Installer component CPIO archives from an explicit file inventory.

``pkgbuild`` currently serializes macOS extended attributes as AppleDouble
``._*`` entries inside a component package's ``Payload`` and ``Scripts`` CPIO
archives.  Those entries are transport metadata created by the build Host, not
declared product files.  This module keeps the macOS Installer archive format
boundary explicit: it preserves every declared CPIO record byte-for-byte while
removing only AppleDouble carrier records and reporting the resulting archive
inventory.

It does not choose a package payload, inspect product contracts, invoke
``pkgbuild``, or sign a package.  Those responsibilities remain with the
macOS Host package composer.
"""

from __future__ import annotations

from dataclasses import dataclass
import gzip
from pathlib import Path, PurePosixPath
import stat
from typing import BinaryIO


class MacOSInstallerComponentCpioArchiveError(RuntimeError):
    """A macOS Installer component CPIO archive is unreadable or unsafe."""


OLD_ASCII_CPIO_MAGIC = b"070707"
OLD_ASCII_CPIO_HEADER_BYTES = 76
CPIO_COPY_CHUNK_BYTES = 1024 * 1024


@dataclass(frozen=True)
class ReconstitutedMacOSInstallerComponentCpioArchive:
    """The explicit inventory retained after AppleDouble carrier removal."""

    retained_entry_count: int
    retained_regular_file_bytes: int
    removed_appledouble_paths: tuple[str, ...]


def recompose_macos_installer_component_cpio_archive_without_appledouble_carriers(
    source_compressed_archive: Path,
    destination_compressed_archive: Path,
    component_archive_role: str,
) -> ReconstitutedMacOSInstallerComponentCpioArchive:
    """Copy one Installer CPIO archive while removing only ``._*`` carriers.

    macOS component packages use old-ASCII CPIO inside gzip-compressed
    ``Payload`` and ``Scripts`` members.  The package composer treats the
    records produced by ``pkgbuild`` as a candidate archive, not as a declared
    product inventory.  Retained records keep their original CPIO header,
    pathname, bytes, mode, ownership, and timestamp.  This avoids recreating
    Installer-specific CPIO metadata while making the only policy decision
    explicit: AppleDouble carrier paths have no product payload role.
    """

    if not component_archive_role:
        raise MacOSInstallerComponentCpioArchiveError(
            "macOS Installer component archive role is required"
        )
    if not source_compressed_archive.is_file():
        raise MacOSInstallerComponentCpioArchiveError(
            component_archive_role + " source archive is missing or not a file"
        )
    if destination_compressed_archive.exists():
        raise MacOSInstallerComponentCpioArchiveError(
            component_archive_role + " destination archive already exists"
        )
    if not destination_compressed_archive.parent.is_dir():
        raise MacOSInstallerComponentCpioArchiveError(
            component_archive_role + " destination archive parent directory is missing"
        )

    retained_entry_count = 0
    retained_regular_file_bytes = 0
    removed_appledouble_paths: list[str] = []

    try:
        with gzip.open(source_compressed_archive, "rb") as source_archive:
            with destination_compressed_archive.open("xb") as destination_file:
                with gzip.GzipFile(
                    filename="",
                    mode="wb",
                    fileobj=destination_file,
                    mtime=0,
                ) as destination_archive:
                    while True:
                        header = read_exactly(
                            source_archive,
                            OLD_ASCII_CPIO_HEADER_BYTES,
                            component_archive_role + " CPIO header",
                        )
                        if header[: len(OLD_ASCII_CPIO_MAGIC)] != OLD_ASCII_CPIO_MAGIC:
                            raise MacOSInstallerComponentCpioArchiveError(
                                component_archive_role
                                + " must use the macOS Installer old-ASCII CPIO format"
                            )
                        mode = parse_old_ascii_cpio_octal_field(
                            header[18:24],
                            component_archive_role + " CPIO mode",
                        )
                        name_size = parse_old_ascii_cpio_octal_field(
                            header[59:65],
                            component_archive_role + " CPIO pathname size",
                        )
                        file_size = parse_old_ascii_cpio_octal_field(
                            header[65:76],
                            component_archive_role + " CPIO file size",
                        )
                        if name_size < 1:
                            raise MacOSInstallerComponentCpioArchiveError(
                                component_archive_role + " CPIO pathname size must be positive"
                            )
                        pathname_bytes = read_exactly(
                            source_archive,
                            name_size,
                            component_archive_role + " CPIO pathname",
                        )
                        pathname = parse_old_ascii_cpio_pathname(
                            pathname_bytes,
                            component_archive_role,
                        )
                        if pathname == "TRAILER!!!":
                            if file_size != 0:
                                raise MacOSInstallerComponentCpioArchiveError(
                                    component_archive_role
                                    + " CPIO trailer must not carry file bytes"
                                )
                            destination_archive.write(header)
                            destination_archive.write(pathname_bytes)
                            copy_and_validate_zero_trailer_padding(
                                source_archive,
                                destination_archive,
                                component_archive_role,
                            )
                            return ReconstitutedMacOSInstallerComponentCpioArchive(
                                retained_entry_count=retained_entry_count,
                                retained_regular_file_bytes=retained_regular_file_bytes,
                                removed_appledouble_paths=tuple(
                                    removed_appledouble_paths
                                ),
                            )

                        if is_appledouble_carrier_path(pathname):
                            discard_exactly(
                                source_archive,
                                file_size,
                                component_archive_role + " AppleDouble carrier bytes",
                            )
                            removed_appledouble_paths.append(pathname)
                            continue

                        destination_archive.write(header)
                        destination_archive.write(pathname_bytes)
                        copy_exactly(
                            source_archive,
                            destination_archive,
                            file_size,
                            component_archive_role + " declared CPIO file bytes",
                        )
                        retained_entry_count += 1
                        if stat.S_ISREG(mode):
                            retained_regular_file_bytes += file_size
    except (OSError, EOFError, gzip.BadGzipFile) as error:
        raise MacOSInstallerComponentCpioArchiveError(
            component_archive_role + " CPIO archive cannot be recomposed"
        ) from error


def read_exactly(source: BinaryIO, byte_count: int, context: str) -> bytes:
    """Read one complete archive field or keep the truncation state explicit."""

    value = source.read(byte_count)
    if len(value) != byte_count:
        raise MacOSInstallerComponentCpioArchiveError(context + " is truncated")
    return value


def parse_old_ascii_cpio_octal_field(value: bytes, context: str) -> int:
    try:
        return int(value, 8)
    except ValueError as error:
        raise MacOSInstallerComponentCpioArchiveError(
            context + " is not an old-ASCII CPIO octal value"
        ) from error


def parse_old_ascii_cpio_pathname(
    value: bytes,
    component_archive_role: str,
) -> str:
    if not value.endswith(b"\0"):
        raise MacOSInstallerComponentCpioArchiveError(
            component_archive_role + " CPIO pathname is not NUL-terminated"
        )
    try:
        pathname = value[:-1].decode("utf-8")
    except UnicodeDecodeError as error:
        raise MacOSInstallerComponentCpioArchiveError(
            component_archive_role + " CPIO pathname is not UTF-8"
        ) from error
    if pathname in {".", "TRAILER!!!"}:
        return pathname
    path = PurePosixPath(pathname)
    if (
        not pathname.startswith("./")
        or path.is_absolute()
        or any(part in {"", ".", ".."} for part in path.parts[1:])
    ):
        raise MacOSInstallerComponentCpioArchiveError(
            component_archive_role
            + " CPIO pathname must remain a safe relative Installer path"
        )
    return pathname


def is_appledouble_carrier_path(pathname: str) -> bool:
    """Return whether the CPIO path is macOS metadata, never a product file."""

    return pathname not in {".", "TRAILER!!!"} and PurePosixPath(pathname).name.startswith(
        "._"
    )


def copy_exactly(
    source: BinaryIO,
    destination: BinaryIO,
    byte_count: int,
    context: str,
) -> None:
    remaining = byte_count
    while remaining:
        chunk = source.read(min(CPIO_COPY_CHUNK_BYTES, remaining))
        if not chunk:
            raise MacOSInstallerComponentCpioArchiveError(context + " is truncated")
        destination.write(chunk)
        remaining -= len(chunk)


def discard_exactly(source: BinaryIO, byte_count: int, context: str) -> None:
    remaining = byte_count
    while remaining:
        chunk = source.read(min(CPIO_COPY_CHUNK_BYTES, remaining))
        if not chunk:
            raise MacOSInstallerComponentCpioArchiveError(context + " is truncated")
        remaining -= len(chunk)


def copy_and_validate_zero_trailer_padding(
    source: BinaryIO,
    destination: BinaryIO,
    component_archive_role: str,
) -> None:
    """Preserve CPIO block padding while refusing hidden records after trailer."""

    while True:
        chunk = source.read(CPIO_COPY_CHUNK_BYTES)
        if not chunk:
            return
        if any(byte != 0 for byte in chunk):
            raise MacOSInstallerComponentCpioArchiveError(
                component_archive_role + " CPIO archive contains nonzero data after trailer"
            )
        destination.write(chunk)
