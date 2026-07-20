"""Assemble explicit C42/C43 inputs for one macOS development release.

This development-only workflow turns one caller-selected raw ARM64 Linux
source disk into the three immutable files that C41 later consumes: the
uncompressed kernel, initial RAM disk, and MBR-partitioned root storage. The
declared ext4 filesystem can be either the entire source disk or one explicit
source-disk partition. A QCOW2 source reaches this workflow only through the
C73 materialization receipt for its raw output.

The caller owns source acquisition and supplies its identity, origin, release,
Guest paths, and every operation identifier.  The workflow owns only its new
``guest-boot-inputs`` directory.  It calls the selected C42 executable and the
C43 assembler using private staging, and publishes the complete directory only
when both effects have succeeded.  It never downloads an image, infers boot
paths, bootstraps a Guest, or writes C41/C47/package state.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Mapping, Sequence
from urllib.parse import urlparse

from tooling import guest_root_storage_partition_assembler


class MacOSDevelopmentGuestBootInputAssemblyError(RuntimeError):
    """One explicit C42/C43 development input workflow could not complete."""


@dataclass(frozen=True)
class MacOSDevelopmentGuestBootResourceSource:
    """One explicit C42 boot-resource source selected by the release caller."""

    kind: str
    guest_absolute_path: PurePosixPath | None = None
    external_artifact: Path | None = None
    external_origin_uri: str | None = None
    external_release: str | None = None


@dataclass(frozen=True)
class MacOSDevelopmentGuestBootInputAssembly:
    """All caller-owned source identity and C42/C43 effect inputs for one output set."""

    release_root: Path
    assembly_id: str
    c42_extraction_id: str
    c43_assembly_id: str
    source_image: Path
    source_image_id: str
    source_origin_uri: str
    source_release: str
    source_filesystem_layout: str
    source_filesystem_partition_index: int | None
    source_root_storage_id: str
    target_root_storage_id: str
    target_root_storage_output_relative_path: PurePosixPath
    kernel_source: MacOSDevelopmentGuestBootResourceSource
    initial_ramdisk_source: MacOSDevelopmentGuestBootResourceSource
    c42_extractor_executable: Path
    source_materialization_receipt: Path | None = None
    source_materialization_id: str | None = None


OUTPUT_DIRECTORY_NAME = "guest-boot-inputs"
C42_OUTPUT_DIRECTORY_NAME = "c42-artifacts"
C43_OUTPUT_DIRECTORY_NAME = "c43-artifacts"
C42_DECLARATION_NAME = "guest-linux-boot-artifact-extraction-declaration.json"
C43_DECLARATION_NAME = "guest-root-storage-partition-assembly-declaration.json"
ASSEMBLY_RECEIPT_NAME = "macos-development-guest-boot-input-assembly-receipt.json"
KERNEL_RELATIVE_PATH = PurePosixPath("boot/Image")
INITIAL_RAMDISK_RELATIVE_PATH = PurePosixPath("boot/initrd.img")


def assemble_macos_development_guest_boot_inputs(
    assembly: MacOSDevelopmentGuestBootInputAssembly,
) -> Mapping[str, Any]:
    """Publish one complete C42/C43 output set in a new release workspace."""

    validate_assembly(assembly)
    output_directory = assembly.release_root / OUTPUT_DIRECTORY_NAME
    temporary_directory = Path(
        tempfile.mkdtemp(
            prefix="." + OUTPUT_DIRECTORY_NAME + ".",
            dir=assembly.release_root,
        )
    )
    try:
        c42_declaration_path = temporary_directory / C42_DECLARATION_NAME
        c42_declaration = compose_c42_declaration(assembly)
        write_new_json(c42_declaration_path, c42_declaration)
        c42_output_directory = temporary_directory / C42_OUTPUT_DIRECTORY_NAME
        run_c42_extractor(assembly, c42_declaration_path, c42_output_directory)
        c42_receipt_path = c42_output_directory / "guest-linux-boot-artifact-extraction-receipt.json"
        require_regular_file(c42_receipt_path, "C42 receipt")
        kernel_path = c42_output_directory / Path(KERNEL_RELATIVE_PATH)
        initial_ramdisk_path = c42_output_directory / Path(INITIAL_RAMDISK_RELATIVE_PATH)
        source_root_storage_path = c42_output_directory / "storage" / "source-root-storage.raw"
        require_regular_file(kernel_path, "C42 extracted kernel")
        require_regular_file(initial_ramdisk_path, "C42 extracted initial RAM disk")
        require_regular_file(source_root_storage_path, "C42 extracted root storage")

        c43_declaration_path = temporary_directory / C43_DECLARATION_NAME
        c43_declaration = compose_c43_declaration(
            assembly,
            c42_receipt_path,
            source_root_storage_path,
        )
        write_new_json(c43_declaration_path, c43_declaration)
        c43_output_directory = temporary_directory / C43_OUTPUT_DIRECTORY_NAME
        guest_root_storage_partition_assembler.execute_guest_root_storage_partition_assembly(
            guest_root_storage_partition_assembler.GuestRootStoragePartitionAssemblyExecution(
                declaration_absolute_path=c43_declaration_path,
                output_directory=c43_output_directory,
            )
        )
        target_root_storage_path = c43_output_directory / Path(
            assembly.target_root_storage_output_relative_path
        )
        c43_receipt_path = c43_output_directory / "guest-root-storage-partition-assembly-receipt.json"
        require_regular_file(target_root_storage_path, "C43 target root storage")
        require_regular_file(c43_receipt_path, "C43 receipt")

        # C42/C43 declarations contain build-machine input paths.  They are
        # execution input only and must not leak into the retained output set.
        c42_declaration_path.unlink()
        c43_declaration_path.unlink()
        receipt = compose_assembly_receipt(
            assembly,
            c42_receipt_path,
            kernel_path,
            initial_ramdisk_path,
            target_root_storage_path,
            c43_receipt_path,
        )
        write_new_json(temporary_directory / ASSEMBLY_RECEIPT_NAME, receipt)
        publish_new_directory(temporary_directory, output_directory)
    except Exception:
        shutil.rmtree(temporary_directory, ignore_errors=True)
        raise

    return {
        "releaseRoot": str(assembly.release_root),
        "guestBootInputsDirectory": str(output_directory),
        "kernel": identity_result(output_directory / C42_OUTPUT_DIRECTORY_NAME / Path(KERNEL_RELATIVE_PATH)),
        "initialRamdisk": identity_result(output_directory / C42_OUTPUT_DIRECTORY_NAME / Path(INITIAL_RAMDISK_RELATIVE_PATH)),
        "rootStorage": identity_result(
            output_directory
            / C43_OUTPUT_DIRECTORY_NAME
            / Path(assembly.target_root_storage_output_relative_path)
        ),
        "receipt": identity_result(output_directory / ASSEMBLY_RECEIPT_NAME),
    }


def validate_assembly(assembly: MacOSDevelopmentGuestBootInputAssembly) -> None:
    """Reject ambiguity before any C42/C43 effect or output directory exists."""

    require_directory(assembly.release_root, "release root")
    output_directory = assembly.release_root / OUTPUT_DIRECTORY_NAME
    if output_directory.exists() or output_directory.is_symlink():
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "guest boot inputs directory already exists: " + str(output_directory)
        )
    for label, identifier in (
        ("assembly id", assembly.assembly_id),
        ("C42 extraction id", assembly.c42_extraction_id),
        ("C43 assembly id", assembly.c43_assembly_id),
        ("source image id", assembly.source_image_id),
        ("source root storage id", assembly.source_root_storage_id),
        ("target root storage id", assembly.target_root_storage_id),
    ):
        require_identifier(identifier, label)
    if assembly.c42_extraction_id == assembly.c43_assembly_id:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "C42 extraction id and C43 assembly id must be different"
        )
    require_regular_file(assembly.source_image, "source image")
    if assembly.source_image.stat().st_size % 512 != 0:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "source image size must be a 512-byte multiple for C43"
        )
    parsed_origin = urlparse(assembly.source_origin_uri)
    if parsed_origin.scheme != "https" or not parsed_origin.netloc:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "source origin URI must be an explicit HTTPS URI"
        )
    if not assembly.source_release.strip():
        raise MacOSDevelopmentGuestBootInputAssemblyError("source release is required")
    if assembly.source_filesystem_layout == "whole-disk-ext4":
        if assembly.source_filesystem_partition_index is not None:
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                "whole-disk source filesystem must not declare a partition index"
            )
    elif assembly.source_filesystem_layout == "partitioned-disk-ext4":
        if (
            assembly.source_filesystem_partition_index is None
            or assembly.source_filesystem_partition_index < 1
            or assembly.source_filesystem_partition_index > 128
        ):
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                "partitioned source filesystem requires partition index 1 through 128"
            )
    else:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "source filesystem layout must be whole-disk-ext4 or partitioned-disk-ext4"
        )
    if (assembly.source_materialization_receipt is None) != (
        assembly.source_materialization_id is None
    ):
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "source materialization receipt and ID must be supplied together"
        )
    if assembly.source_materialization_receipt is not None:
        require_regular_file(
            assembly.source_materialization_receipt,
            "C73 source materialization receipt",
        )
        require_identifier(
            assembly.source_materialization_id or "",
            "C73 source materialization ID",
        )
    validate_boot_resource_source(assembly.kernel_source, "kernel")
    validate_boot_resource_source(assembly.initial_ramdisk_source, "initial RAM disk")
    relative_path = assembly.target_root_storage_output_relative_path
    if (
        relative_path.is_absolute()
        or ".." in relative_path.parts
        or len(relative_path.parts) != 2
        or relative_path.parts[0] != "storage"
        or relative_path.suffix != ".raw"
    ):
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "target root storage output path must be one relative storage/*.raw path"
        )
    require_regular_file(assembly.c42_extractor_executable, "C42 extractor executable")
    if not os.access(assembly.c42_extractor_executable, os.X_OK):
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "C42 extractor executable is not executable: "
            + str(assembly.c42_extractor_executable)
        )


def compose_c42_declaration(
    assembly: MacOSDevelopmentGuestBootInputAssembly,
) -> Mapping[str, Any]:
    """Project caller-owned source facts into the C42 declaration exactly."""

    source_identity = file_identity(assembly.source_image)
    source_image: dict[str, Any] = {
        "id": assembly.source_image_id,
        "sourceAbsolutePath": str(assembly.source_image),
        "sourceOriginUri": assembly.source_origin_uri,
        "sourceRelease": assembly.source_release,
        **source_identity,
    }
    if assembly.source_materialization_receipt is not None:
        source_image["sourceMaterialization"] = {
            "receiptAbsolutePath": str(assembly.source_materialization_receipt),
            "receiptSHA256": sha256_file(assembly.source_materialization_receipt),
            "materializationId": assembly.source_materialization_id,
        }
    return {
        "schemaVersion": "v1",
        "extractionId": assembly.c42_extraction_id,
        "architecture": "arm64",
        "sourceImage": source_image,
        "sourceFilesystem": {
            "layout": assembly.source_filesystem_layout,
            "filesystemType": "ext4",
            **(
                {"partitionIndex": assembly.source_filesystem_partition_index}
                if assembly.source_filesystem_partition_index is not None
                else {}
            ),
        },
        "bootResources": {
            "kernel": {
                "id": "linux-arm64-kernel",
                "source": compose_boot_resource_source(assembly.kernel_source),
                "sourceCompression": "gzip",
                "outputRelativePath": KERNEL_RELATIVE_PATH.as_posix(),
                "outputFormat": "uncompressed-linux-arm64-image",
            },
            "initialRamdisk": {
                "id": "linux-arm64-initial-ramdisk",
                "source": compose_boot_resource_source(assembly.initial_ramdisk_source),
                "sourceCompression": "none",
                "outputRelativePath": INITIAL_RAMDISK_RELATIVE_PATH.as_posix(),
                "outputFormat": "cpio",
            },
        },
        "rootStorage": {
            "id": assembly.source_root_storage_id,
            "guestDevicePath": "/dev/vda",
            "outputRelativePath": "storage/source-root-storage.raw",
            "filesystemType": "ext4",
            "storageLayout": "whole-disk-ext4",
        },
    }


def validate_boot_resource_source(
    source: MacOSDevelopmentGuestBootResourceSource,
    label: str,
) -> None:
    """Keep C42 boot-source choice explicit before any extractor effect."""

    if source.kind == "source-image-filesystem":
        guest_path = source.guest_absolute_path
        if (
            guest_path is None
            or not guest_path.is_absolute()
            or ".." in guest_path.parts
        ):
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                label + " source-image-filesystem source requires an absolute non-traversing Guest path"
            )
        if (
            source.external_artifact is not None
            or source.external_origin_uri is not None
            or source.external_release is not None
        ):
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                label + " source-image-filesystem source must not declare an external artifact"
            )
        return
    if source.kind == "external-artifact":
        if source.guest_absolute_path is not None:
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                label + " external-artifact source must not declare a Guest path"
            )
        if source.external_artifact is None:
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                label + " external-artifact source requires an artifact file"
            )
        require_regular_file(source.external_artifact, label + " external artifact")
        parsed_origin = urlparse(source.external_origin_uri or "")
        if parsed_origin.scheme != "https" or not parsed_origin.netloc:
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                label + " external-artifact source requires an explicit HTTPS origin URI"
            )
        if not (source.external_release or "").strip():
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                label + " external-artifact source requires a release"
            )
        return
    raise MacOSDevelopmentGuestBootInputAssemblyError(
        label + " source kind must be source-image-filesystem or external-artifact"
    )


def compose_boot_resource_source(
    source: MacOSDevelopmentGuestBootResourceSource,
) -> Mapping[str, Any]:
    """Project an already-validated source choice without deriving identity."""

    if source.kind == "source-image-filesystem":
        guest_path = source.guest_absolute_path
        if guest_path is None:
            raise MacOSDevelopmentGuestBootInputAssemblyError(
                "validated source-image-filesystem boot resource lost its Guest path"
            )
        return {
            "kind": source.kind,
            "guestAbsolutePath": guest_path.as_posix(),
        }
    external_artifact = source.external_artifact
    if external_artifact is None:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "validated external boot resource source lost its artifact"
        )
    return {
        "kind": source.kind,
        "sourceAbsolutePath": str(external_artifact),
        "sourceOriginUri": source.external_origin_uri,
        "sourceRelease": source.external_release,
        **file_identity(external_artifact),
    }


def compose_c43_declaration(
    assembly: MacOSDevelopmentGuestBootInputAssembly,
    c42_receipt_path: Path,
    source_root_storage_path: Path,
) -> Mapping[str, Any]:
    """Bind C43 to the C42 receipt and root copy just produced in staging."""

    return {
        "schemaVersion": "v1",
        "assemblyId": assembly.c43_assembly_id,
        "architecture": "arm64",
        "sourceC42Receipt": {
            "receiptAbsolutePath": str(c42_receipt_path),
            "receiptSHA256": sha256_file(c42_receipt_path),
            "extractionId": assembly.c42_extraction_id,
        },
        "sourceRootStorage": {
            "id": assembly.source_root_storage_id,
            "sourceAbsolutePath": str(source_root_storage_path),
            **file_identity(source_root_storage_path),
            "storageLayout": "whole-disk-ext4",
            "filesystemType": "ext4",
        },
        "targetRootStorage": {
            "id": assembly.target_root_storage_id,
            "outputRelativePath": assembly.target_root_storage_output_relative_path.as_posix(),
            "guestDiskDevicePath": "/dev/vda",
            "rootPartitionDevicePath": "/dev/vda1",
            "rootPartitionIndex": 1,
            "partitionTableType": "mbr",
            "firstPartitionStartSector": 2048,
            "partitionTypeMbrHex": "83",
            "filesystemType": "ext4",
            "logicalSectorSizeBytes": 512,
        },
    }


def run_c42_extractor(
    assembly: MacOSDevelopmentGuestBootInputAssembly,
    declaration_path: Path,
    output_directory: Path,
) -> None:
    """Run only the caller-selected C42 executable with explicit paths."""

    completed = subprocess.run(
        [
            str(assembly.c42_extractor_executable),
            "--guest-linux-boot-artifact-extraction-declaration",
            str(declaration_path),
            "--output-directory",
            str(output_directory),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        details = (completed.stderr or completed.stdout).strip()
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "C42 extractor failed exitCode={0} reason={1}".format(
                completed.returncode,
                details or "no diagnostic output",
            )
        )


def compose_assembly_receipt(
    assembly: MacOSDevelopmentGuestBootInputAssembly,
    c42_receipt_path: Path,
    kernel_path: Path,
    initial_ramdisk_path: Path,
    root_storage_path: Path,
    c43_receipt_path: Path,
) -> Mapping[str, Any]:
    """Record only output-relative identities, never source-machine paths."""

    return {
        "schemaVersion": "v1",
        "assemblyId": assembly.assembly_id,
        "architecture": "arm64",
        "c42": {
            "extractionId": assembly.c42_extraction_id,
            "receipt": {"relativePath": C42_OUTPUT_DIRECTORY_NAME + "/guest-linux-boot-artifact-extraction-receipt.json", **file_identity(c42_receipt_path)},
            "kernel": {"relativePath": C42_OUTPUT_DIRECTORY_NAME + "/" + KERNEL_RELATIVE_PATH.as_posix(), **file_identity(kernel_path)},
            "initialRamdisk": {"relativePath": C42_OUTPUT_DIRECTORY_NAME + "/" + INITIAL_RAMDISK_RELATIVE_PATH.as_posix(), **file_identity(initial_ramdisk_path)},
        },
        "c43": {
            "assemblyId": assembly.c43_assembly_id,
            "receipt": {"relativePath": C43_OUTPUT_DIRECTORY_NAME + "/guest-root-storage-partition-assembly-receipt.json", **file_identity(c43_receipt_path)},
            "rootStorage": {"id": assembly.target_root_storage_id, "relativePath": C43_OUTPUT_DIRECTORY_NAME + "/" + assembly.target_root_storage_output_relative_path.as_posix(), **file_identity(root_storage_path)},
        },
    }


def publish_new_directory(temporary_directory: Path, output_directory: Path) -> None:
    """Publish only if no concurrent caller claimed the declared output."""

    try:
        os.rename(temporary_directory, output_directory)
    except FileExistsError as error:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "guest boot inputs directory already exists: " + str(output_directory)
        ) from error
    except OSError as error:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "publish guest boot inputs: " + str(error)
        ) from error


def require_directory(path: Path, label: str) -> None:
    if not path.is_absolute() or ".." in path.parts or not path.is_dir() or path.is_symlink():
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            label + " must be an existing absolute non-symlink directory: " + str(path)
        )


def require_regular_file(path: Path, label: str) -> None:
    if not path.is_absolute() or ".." in path.parts or not path.is_file() or path.is_symlink():
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            label + " must be an absolute regular non-symlink file: " + str(path)
        )


def require_identifier(value: str, label: str) -> None:
    if (
        not value
        or len(value) > 128
        or not value[0].isalnum()
        or any(not (character.isalnum() or character in "._-") for character in value)
    ):
        raise MacOSDevelopmentGuestBootInputAssemblyError(label + " is invalid")


def file_identity(path: Path) -> Mapping[str, Any]:
    return {"sizeBytes": path.stat().st_size, "sha256": sha256_file(path)}


def identity_result(path: Path) -> Mapping[str, Any]:
    return {"path": str(path), **file_identity(path)}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_new_json(path: Path, document: Mapping[str, Any]) -> None:
    try:
        with path.open("xb") as output:
            output.write((json.dumps(document, sort_keys=True, indent=2) + "\n").encode("utf-8"))
            output.flush()
            os.fsync(output.fileno())
    except OSError as error:
        raise MacOSDevelopmentGuestBootInputAssemblyError(
            "write development guest boot input document: " + str(error)
        ) from error


def parse_arguments(arguments: Sequence[str]) -> MacOSDevelopmentGuestBootInputAssembly:
    parser = argparse.ArgumentParser(
        description="assemble explicit C42/C43 Guest boot inputs for one macOS development release"
    )
    parser.add_argument("--release-root", required=True)
    parser.add_argument("--assembly-id", required=True)
    parser.add_argument("--c42-extraction-id", required=True)
    parser.add_argument("--c43-assembly-id", required=True)
    parser.add_argument("--source-image", required=True)
    parser.add_argument("--source-image-id", required=True)
    parser.add_argument("--source-origin-uri", required=True)
    parser.add_argument("--source-release", required=True)
    parser.add_argument("--source-filesystem-layout", required=True)
    parser.add_argument("--source-filesystem-partition-index", type=int)
    parser.add_argument("--source-materialization-receipt")
    parser.add_argument("--source-materialization-id")
    parser.add_argument("--source-root-storage-id", required=True)
    parser.add_argument("--target-root-storage-id", required=True)
    parser.add_argument("--target-root-storage-output-relative-path", required=True)
    parser.add_argument("--kernel-source-kind", required=True)
    parser.add_argument("--kernel-guest-absolute-path")
    parser.add_argument("--kernel-external-artifact")
    parser.add_argument("--kernel-external-origin-uri")
    parser.add_argument("--kernel-external-release")
    parser.add_argument("--initial-ramdisk-source-kind", required=True)
    parser.add_argument("--initial-ramdisk-guest-absolute-path")
    parser.add_argument("--initial-ramdisk-external-artifact")
    parser.add_argument("--initial-ramdisk-external-origin-uri")
    parser.add_argument("--initial-ramdisk-external-release")
    parser.add_argument("--c42-extractor-executable", required=True)
    options = parser.parse_args(arguments)
    return MacOSDevelopmentGuestBootInputAssembly(
        release_root=Path(options.release_root),
        assembly_id=options.assembly_id,
        c42_extraction_id=options.c42_extraction_id,
        c43_assembly_id=options.c43_assembly_id,
        source_image=Path(options.source_image),
        source_image_id=options.source_image_id,
        source_origin_uri=options.source_origin_uri,
        source_release=options.source_release,
        source_filesystem_layout=options.source_filesystem_layout,
        source_filesystem_partition_index=options.source_filesystem_partition_index,
        source_root_storage_id=options.source_root_storage_id,
        target_root_storage_id=options.target_root_storage_id,
        target_root_storage_output_relative_path=PurePosixPath(options.target_root_storage_output_relative_path),
        kernel_source=MacOSDevelopmentGuestBootResourceSource(
            kind=options.kernel_source_kind,
            guest_absolute_path=(
                PurePosixPath(options.kernel_guest_absolute_path)
                if options.kernel_guest_absolute_path is not None
                else None
            ),
            external_artifact=(
                Path(options.kernel_external_artifact)
                if options.kernel_external_artifact is not None
                else None
            ),
            external_origin_uri=options.kernel_external_origin_uri,
            external_release=options.kernel_external_release,
        ),
        initial_ramdisk_source=MacOSDevelopmentGuestBootResourceSource(
            kind=options.initial_ramdisk_source_kind,
            guest_absolute_path=(
                PurePosixPath(options.initial_ramdisk_guest_absolute_path)
                if options.initial_ramdisk_guest_absolute_path is not None
                else None
            ),
            external_artifact=(
                Path(options.initial_ramdisk_external_artifact)
                if options.initial_ramdisk_external_artifact is not None
                else None
            ),
            external_origin_uri=options.initial_ramdisk_external_origin_uri,
            external_release=options.initial_ramdisk_external_release,
        ),
        c42_extractor_executable=Path(options.c42_extractor_executable),
        source_materialization_receipt=(
            Path(options.source_materialization_receipt)
            if options.source_materialization_receipt is not None
            else None
        ),
        source_materialization_id=options.source_materialization_id,
    )


def main(arguments: Sequence[str] | None = None) -> int:
    try:
        result = assemble_macos_development_guest_boot_inputs(
            parse_arguments(sys.argv[1:] if arguments is None else arguments)
        )
    except MacOSDevelopmentGuestBootInputAssemblyError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
