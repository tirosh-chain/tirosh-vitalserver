"""C43 Guest root-storage partition assembly without source or state inference."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence


SCHEMA_VERSION = "v1"
ARCHITECTURE = "arm64"
WHOLE_DISK_EXT4_LAYOUT = "whole-disk-ext4"
MBR_PARTITION_TABLE_TYPE = "mbr"
ROOT_PARTITION_START_SECTOR = 2048
LOGICAL_SECTOR_SIZE_BYTES = 512
LINUX_EXT4_MBR_PARTITION_TYPE = 0x83
SHA256_LENGTH = 64
COPY_BUFFER_BYTES = 1024 * 1024


class GuestRootStoragePartitionAssemblyError(RuntimeError):
    """One typed C43 failure; it never means an empty assembled storage image."""

    def __init__(self, assembly_id: str, stage: str, reason: str) -> None:
        self.assembly_id = assembly_id or "unknown"
        self.stage = stage
        self.reason = reason
        super().__init__(
            "Guest root storage partition assembly failed "
            "assemblyId={0} stage={1} reason={2}".format(
                self.assembly_id, self.stage, self.reason
            )
        )


@dataclass(frozen=True)
class ImmutableArtifactIdentity:
    """An immutable artifact identity without a build-machine source path."""

    artifact_id: str
    size_bytes: int
    sha256: str


@dataclass(frozen=True)
class C42ReceiptReference:
    """The exact C42 receipt accepted by a C43 invocation."""

    receipt_absolute_path: Path
    receipt_sha256: str
    extraction_id: str


@dataclass(frozen=True)
class DeclaredWholeDiskRootStorage:
    """One C42 root-storage output presented to the partition assembler."""

    identity: ImmutableArtifactIdentity
    source_absolute_path: Path


@dataclass(frozen=True)
class DeclaredPartitionedRootStorage:
    """One C39-compatible raw-disk output and its complete MBR root partition."""

    artifact_id: str
    output_relative_path: str
    guest_disk_device_path: str
    root_partition_device_path: str
    root_partition_index: int
    partition_table_type: str
    first_partition_start_sector: int
    partition_type_mbr_hex: str
    filesystem_type: str
    logical_sector_size_bytes: int


@dataclass(frozen=True)
class GuestRootStoragePartitionAssemblyDeclaration:
    """C43 desired input; paths exist only while this release-build effect runs."""

    assembly_id: str
    architecture: str
    source_c42_receipt: C42ReceiptReference
    source_root_storage: DeclaredWholeDiskRootStorage
    target_root_storage: DeclaredPartitionedRootStorage


@dataclass(frozen=True)
class GuestRootStoragePartitionAssemblyExecution:
    """Caller-owned C43 effect paths; the assembler owns receipt completion."""

    declaration_absolute_path: Path
    output_directory: Path


def execute_guest_root_storage_partition_assembly(
    execution: GuestRootStoragePartitionAssemblyExecution,
) -> Mapping[str, Any]:
    """Verify C42 evidence and atomically publish one C39-compatible raw disk."""

    try:
        _require_absolute_regular_non_symlink(execution.declaration_absolute_path, "C43 declaration")
        declaration_bytes = execution.declaration_absolute_path.read_bytes()
        declaration = _decode_guest_root_storage_partition_assembly_declaration(
            _decode_json_object(declaration_bytes, "C43 declaration")
        )
    except GuestRootStoragePartitionAssemblyError:
        raise
    except (OSError, ValueError) as error:
        raise GuestRootStoragePartitionAssemblyError("", "C43-decode", str(error)) from error

    _require_absent_output_directory(declaration.assembly_id, execution.output_directory)
    _verify_c42_evidence(declaration)
    _verify_declared_source_root_storage(declaration)

    temporary_output_directory = Path(
        tempfile.mkdtemp(
            prefix=".{0}.C43.".format(execution.output_directory.name),
            dir=str(execution.output_directory.parent),
        )
    )
    try:
        target_storage_path = temporary_output_directory / declaration.target_root_storage.output_relative_path
        target_identity = _write_declared_mbr_partitioned_root_storage(
            declaration,
            target_storage_path,
        )
        receipt = _compose_guest_root_storage_partition_assembly_receipt(
            declaration,
            declaration_bytes,
            target_identity,
            _record_utc_root_storage_partition_assembly_completion_time(),
        )
        _write_new_json_document(
            temporary_output_directory / "guest-root-storage-partition-assembly-receipt.json",
            receipt,
        )
        os.replace(temporary_output_directory, execution.output_directory)
        return receipt
    except GuestRootStoragePartitionAssemblyError:
        raise
    except (OSError, ValueError) as error:
        raise GuestRootStoragePartitionAssemblyError(
            declaration.assembly_id, "output-publish", str(error)
        ) from error
    finally:
        shutil.rmtree(temporary_output_directory, ignore_errors=True)


def _decode_guest_root_storage_partition_assembly_declaration(
    document: Mapping[str, Any],
) -> GuestRootStoragePartitionAssemblyDeclaration:
    _require_exact_keys(
        document,
        {
            "schemaVersion",
            "assemblyId",
            "architecture",
            "sourceC42Receipt",
            "sourceRootStorage",
            "targetRootStorage",
        },
        "C43 declaration",
    )
    if document["schemaVersion"] != SCHEMA_VERSION:
        raise ValueError("C43 declaration schemaVersion must be v1")
    assembly_id = _require_identifier(document["assemblyId"], "C43 declaration assemblyId")
    if document["architecture"] != ARCHITECTURE:
        raise ValueError("C43 declaration architecture must be arm64")

    source_c42_receipt = _decode_c42_receipt_reference(document["sourceC42Receipt"])
    source_root_storage = _decode_declared_whole_disk_root_storage(document["sourceRootStorage"])
    target_root_storage = _decode_declared_partitioned_root_storage(document["targetRootStorage"])
    return GuestRootStoragePartitionAssemblyDeclaration(
        assembly_id=assembly_id,
        architecture=ARCHITECTURE,
        source_c42_receipt=source_c42_receipt,
        source_root_storage=source_root_storage,
        target_root_storage=target_root_storage,
    )


def _decode_c42_receipt_reference(value: Any) -> C42ReceiptReference:
    document = _require_mapping(value, "C43 sourceC42Receipt")
    _require_exact_keys(
        document,
        {
            "receiptAbsolutePath",
            "receiptSHA256",
            "extractionId",
        },
        "C43 sourceC42Receipt",
    )
    return C42ReceiptReference(
        receipt_absolute_path=_require_absolute_path(
            document["receiptAbsolutePath"], "C43 sourceC42Receipt receiptAbsolutePath"
        ),
        receipt_sha256=_require_sha256(
            document["receiptSHA256"], "C43 sourceC42Receipt receiptSHA256"
        ),
        extraction_id=_require_identifier(
            document["extractionId"], "C43 sourceC42Receipt extractionId"
        ),
    )


def _decode_declared_whole_disk_root_storage(value: Any) -> DeclaredWholeDiskRootStorage:
    document = _require_mapping(value, "C43 sourceRootStorage")
    _require_exact_keys(
        document,
        {"id", "sourceAbsolutePath", "sizeBytes", "sha256", "storageLayout", "filesystemType"},
        "C43 sourceRootStorage",
    )
    if document["storageLayout"] != WHOLE_DISK_EXT4_LAYOUT or document["filesystemType"] != "ext4":
        raise ValueError("C43 sourceRootStorage must be whole-disk-ext4")
    size_bytes = _require_positive_integer(document["sizeBytes"], "C43 sourceRootStorage sizeBytes")
    if size_bytes < LOGICAL_SECTOR_SIZE_BYTES or size_bytes % LOGICAL_SECTOR_SIZE_BYTES != 0:
        raise ValueError("C43 sourceRootStorage sizeBytes must be a positive 512-byte multiple")
    return DeclaredWholeDiskRootStorage(
        identity=ImmutableArtifactIdentity(
            artifact_id=_require_identifier(document["id"], "C43 sourceRootStorage id"),
            size_bytes=size_bytes,
            sha256=_require_sha256(document["sha256"], "C43 sourceRootStorage sha256"),
        ),
        source_absolute_path=_require_absolute_path(
            document["sourceAbsolutePath"], "C43 sourceRootStorage sourceAbsolutePath"
        ),
    )


def _decode_declared_partitioned_root_storage(value: Any) -> DeclaredPartitionedRootStorage:
    document = _require_mapping(value, "C43 targetRootStorage")
    _require_exact_keys(
        document,
        {
            "id",
            "outputRelativePath",
            "guestDiskDevicePath",
            "rootPartitionDevicePath",
            "rootPartitionIndex",
            "partitionTableType",
            "firstPartitionStartSector",
            "partitionTypeMbrHex",
            "filesystemType",
            "logicalSectorSizeBytes",
        },
        "C43 targetRootStorage",
    )
    output_relative_path = _require_storage_output_relative_path(
        document["outputRelativePath"], "C43 targetRootStorage outputRelativePath"
    )
    required_values = {
        "guestDiskDevicePath": "/dev/vda",
        "rootPartitionDevicePath": "/dev/vda1",
        "rootPartitionIndex": 1,
        "partitionTableType": MBR_PARTITION_TABLE_TYPE,
        "firstPartitionStartSector": ROOT_PARTITION_START_SECTOR,
        "partitionTypeMbrHex": "83",
        "filesystemType": "ext4",
        "logicalSectorSizeBytes": LOGICAL_SECTOR_SIZE_BYTES,
    }
    for field, expected_value in required_values.items():
        if document[field] != expected_value:
            raise ValueError("C43 targetRootStorage {0} must be {1!r}".format(field, expected_value))
    return DeclaredPartitionedRootStorage(
        artifact_id=_require_identifier(document["id"], "C43 targetRootStorage id"),
        output_relative_path=output_relative_path,
        guest_disk_device_path="/dev/vda",
        root_partition_device_path="/dev/vda1",
        root_partition_index=1,
        partition_table_type=MBR_PARTITION_TABLE_TYPE,
        first_partition_start_sector=ROOT_PARTITION_START_SECTOR,
        partition_type_mbr_hex="83",
        filesystem_type="ext4",
        logical_sector_size_bytes=LOGICAL_SECTOR_SIZE_BYTES,
    )


def _verify_c42_evidence(declaration: GuestRootStoragePartitionAssemblyDeclaration) -> None:
    reference = declaration.source_c42_receipt
    try:
        _require_absolute_regular_non_symlink(reference.receipt_absolute_path, "C42 receipt")
        receipt_bytes = reference.receipt_absolute_path.read_bytes()
        receipt_sha256 = _sha256_hex(receipt_bytes)
        if receipt_sha256 != reference.receipt_sha256:
            raise ValueError("C42 receipt SHA-256 does not match C43 declaration")
        receipt = _decode_c42_extraction_receipt(_decode_json_object(receipt_bytes, "C42 receipt"))
        if receipt["extractionId"] != reference.extraction_id:
            raise ValueError("C42 receipt extractionId does not match C43 declaration")
        receipt_root_storage = receipt["rootStorage"]
        if (
            receipt_root_storage["id"] != declaration.source_root_storage.identity.artifact_id
            or receipt_root_storage["sizeBytes"] != declaration.source_root_storage.identity.size_bytes
            or receipt_root_storage["sha256"] != declaration.source_root_storage.identity.sha256
        ):
            raise ValueError("C42 receipt rootStorage identity does not match C43 sourceRootStorage")
    except GuestRootStoragePartitionAssemblyError:
        raise
    except (OSError, ValueError) as error:
        raise GuestRootStoragePartitionAssemblyError(
            declaration.assembly_id, "C42-evidence-verify", str(error)
        ) from error


def _verify_declared_source_root_storage(
    declaration: GuestRootStoragePartitionAssemblyDeclaration,
) -> None:
    source = declaration.source_root_storage
    try:
        _require_absolute_regular_non_symlink(source.source_absolute_path, "C43 sourceRootStorage")
        actual_identity = _identify_regular_file(source.identity.artifact_id, source.source_absolute_path)
        if actual_identity != source.identity:
            raise ValueError("C43 sourceRootStorage immutable identity does not match declaration")
        _require_ext4_superblock_signature(source.source_absolute_path)
    except GuestRootStoragePartitionAssemblyError:
        raise
    except (OSError, ValueError) as error:
        raise GuestRootStoragePartitionAssemblyError(
            declaration.assembly_id, "source-root-storage-verify", str(error)
        ) from error


def _write_declared_mbr_partitioned_root_storage(
    declaration: GuestRootStoragePartitionAssemblyDeclaration,
    target_storage_path: Path,
) -> ImmutableArtifactIdentity:
    source = declaration.source_root_storage
    target = declaration.target_root_storage
    try:
        target_storage_path.parent.mkdir(parents=True, exist_ok=False)
        partition_sector_count = source.identity.size_bytes // LOGICAL_SECTOR_SIZE_BYTES
        if partition_sector_count > 0xFFFFFFFF:
            raise ValueError("C43 sourceRootStorage is too large for declared MBR partition")
        mbr = _compose_declared_mbr_partition_table(partition_sector_count)
        hasher = hashlib.sha256()
        written = 0
        with source.source_absolute_path.open("rb") as source_file, target_storage_path.open("xb") as target_file:
            written += _write_and_hash(target_file, hasher, mbr)
            padding_size = target.first_partition_start_sector * LOGICAL_SECTOR_SIZE_BYTES - len(mbr)
            written += _write_zero_padding_and_hash(target_file, hasher, padding_size)
            while True:
                chunk = source_file.read(COPY_BUFFER_BYTES)
                if not chunk:
                    break
                written += _write_and_hash(target_file, hasher, chunk)
            target_file.flush()
            os.fsync(target_file.fileno())
        expected_size = (
            target.first_partition_start_sector * LOGICAL_SECTOR_SIZE_BYTES
            + source.identity.size_bytes
        )
        if written != expected_size:
            raise ValueError("C43 targetRootStorage written byte count is invalid")
        _verify_assembled_mbr_partitioned_root_storage(
            target_storage_path,
            source.identity,
            target,
        )
        return ImmutableArtifactIdentity(
            artifact_id=target.artifact_id,
            size_bytes=written,
            sha256=hasher.hexdigest(),
        )
    except GuestRootStoragePartitionAssemblyError:
        raise
    except (OSError, ValueError) as error:
        raise GuestRootStoragePartitionAssemblyError(
            declaration.assembly_id, "root-storage-partition-write", str(error)
        ) from error


def _compose_declared_mbr_partition_table(partition_sector_count: int) -> bytes:
    mbr = bytearray(LOGICAL_SECTOR_SIZE_BYTES)
    partition_entry_offset = 446
    mbr[partition_entry_offset + 1 : partition_entry_offset + 4] = b"\xff\xff\xff"
    mbr[partition_entry_offset + 4] = LINUX_EXT4_MBR_PARTITION_TYPE
    mbr[partition_entry_offset + 5 : partition_entry_offset + 8] = b"\xff\xff\xff"
    struct.pack_into("<I", mbr, partition_entry_offset + 8, ROOT_PARTITION_START_SECTOR)
    struct.pack_into("<I", mbr, partition_entry_offset + 12, partition_sector_count)
    mbr[510:512] = b"\x55\xaa"
    return bytes(mbr)


def _verify_assembled_mbr_partitioned_root_storage(
    target_storage_path: Path,
    source_identity: ImmutableArtifactIdentity,
    target_storage: DeclaredPartitionedRootStorage,
) -> None:
    with target_storage_path.open("rb") as target_file:
        mbr = target_file.read(LOGICAL_SECTOR_SIZE_BYTES)
        partition_entry_offset = 446
        if mbr[510:512] != b"\x55\xaa":
            raise ValueError("C43 targetRootStorage MBR signature is absent")
        if mbr[partition_entry_offset + 4] != LINUX_EXT4_MBR_PARTITION_TYPE:
            raise ValueError("C43 targetRootStorage MBR root partition type is invalid")
        start_sector = struct.unpack_from("<I", mbr, partition_entry_offset + 8)[0]
        sector_count = struct.unpack_from("<I", mbr, partition_entry_offset + 12)[0]
        if start_sector != target_storage.first_partition_start_sector:
            raise ValueError("C43 targetRootStorage MBR partition start is invalid")
        if sector_count != source_identity.size_bytes // LOGICAL_SECTOR_SIZE_BYTES:
            raise ValueError("C43 targetRootStorage MBR partition size is invalid")
        target_file.seek(start_sector * LOGICAL_SECTOR_SIZE_BYTES)
        copied_source_identity = _identify_open_regular_file(
            source_identity.artifact_id,
            target_file,
            source_identity.size_bytes,
        )
        if copied_source_identity != source_identity:
            raise ValueError("C43 targetRootStorage partition bytes do not match sourceRootStorage")


def _compose_guest_root_storage_partition_assembly_receipt(
    declaration: GuestRootStoragePartitionAssemblyDeclaration,
    declaration_bytes: bytes,
    target_identity: ImmutableArtifactIdentity,
    completed_at: str,
) -> Mapping[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "assemblyId": declaration.assembly_id,
        "architecture": declaration.architecture,
        "assemblyDeclarationSHA256": _sha256_hex(declaration_bytes),
        "sourceC42Receipt": {
            "extractionId": declaration.source_c42_receipt.extraction_id,
            "sha256": declaration.source_c42_receipt.receipt_sha256,
        },
        "sourceRootStorage": _identity_document(declaration.source_root_storage.identity),
        "targetRootStorage": {
            "id": target_identity.artifact_id,
            "relativePath": declaration.target_root_storage.output_relative_path,
            "sizeBytes": target_identity.size_bytes,
            "sha256": target_identity.sha256,
        },
        "rootPartition": {
            "guestDiskDevicePath": declaration.target_root_storage.guest_disk_device_path,
            "rootPartitionDevicePath": declaration.target_root_storage.root_partition_device_path,
            "rootPartitionIndex": declaration.target_root_storage.root_partition_index,
            "partitionTableType": declaration.target_root_storage.partition_table_type,
            "firstPartitionStartSector": declaration.target_root_storage.first_partition_start_sector,
            "partitionTypeMbrHex": declaration.target_root_storage.partition_type_mbr_hex,
            "filesystemType": declaration.target_root_storage.filesystem_type,
            "logicalSectorSizeBytes": declaration.target_root_storage.logical_sector_size_bytes,
        },
        "completedAt": completed_at,
    }


def _record_utc_root_storage_partition_assembly_completion_time() -> str:
    """Record C43 completion after the declared storage image was verified."""

    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _decode_c42_extraction_receipt(document: Mapping[str, Any]) -> Mapping[str, Any]:
    _require_exact_keys(
        document,
        {
            "schemaVersion",
            "extractionId",
            "architecture",
            "extractionDeclarationSHA256",
            "sourceImage",
            "bootResources",
            "rootStorage",
            "completedAt",
        },
        "C42 receipt",
    )
    if document["schemaVersion"] != SCHEMA_VERSION or document["architecture"] != ARCHITECTURE:
        raise ValueError("C42 receipt schemaVersion or architecture is invalid")
    _require_identifier(document["extractionId"], "C42 receipt extractionId")
    _require_sha256(document["extractionDeclarationSHA256"], "C42 receipt extractionDeclarationSHA256")
    _decode_identity_without_relative_path(document["sourceImage"], "C42 receipt sourceImage")
    boot_resources = document["bootResources"]
    if not isinstance(boot_resources, list) or len(boot_resources) != 2:
        raise ValueError("C42 receipt bootResources must name kernel and initial ramdisk")
    for index, boot_resource in enumerate(boot_resources):
        _decode_identity_with_relative_path(boot_resource, "C42 receipt bootResources[{0}]".format(index))
    _decode_identity_with_relative_path(document["rootStorage"], "C42 receipt rootStorage")
    _validate_completed_at(document["completedAt"])
    return document


def _decode_identity_without_relative_path(value: Any, label: str) -> ImmutableArtifactIdentity:
    document = _require_mapping(value, label)
    _require_exact_keys(document, {"id", "sizeBytes", "sha256"}, label)
    return ImmutableArtifactIdentity(
        artifact_id=_require_identifier(document["id"], label + " id"),
        size_bytes=_require_positive_integer(document["sizeBytes"], label + " sizeBytes"),
        sha256=_require_sha256(document["sha256"], label + " sha256"),
    )


def _decode_identity_with_relative_path(value: Any, label: str) -> ImmutableArtifactIdentity:
    document = _require_mapping(value, label)
    _require_exact_keys(document, {"id", "relativePath", "sizeBytes", "sha256"}, label)
    _require_nonempty_string(document["relativePath"], label + " relativePath")
    return ImmutableArtifactIdentity(
        artifact_id=_require_identifier(document["id"], label + " id"),
        size_bytes=_require_positive_integer(document["sizeBytes"], label + " sizeBytes"),
        sha256=_require_sha256(document["sha256"], label + " sha256"),
    )


def _require_ext4_superblock_signature(source_path: Path) -> None:
    with source_path.open("rb") as source_file:
        source_file.seek(1024 + 56)
        magic = source_file.read(2)
    if magic != b"\x53\xef":
        raise ValueError("C43 sourceRootStorage does not have an ext4 superblock signature")


def _identify_regular_file(artifact_id: str, source_path: Path) -> ImmutableArtifactIdentity:
    with source_path.open("rb") as source_file:
        return _identify_open_regular_file(artifact_id, source_file)


def _identify_open_regular_file(
    artifact_id: str,
    source_file: Any,
    exact_size_bytes: int | None = None,
) -> ImmutableArtifactIdentity:
    hasher = hashlib.sha256()
    size_bytes = 0
    while exact_size_bytes is None or size_bytes < exact_size_bytes:
        remaining = COPY_BUFFER_BYTES if exact_size_bytes is None else min(COPY_BUFFER_BYTES, exact_size_bytes - size_bytes)
        chunk = source_file.read(remaining)
        if not chunk:
            break
        hasher.update(chunk)
        size_bytes += len(chunk)
    if exact_size_bytes is not None and size_bytes != exact_size_bytes:
        raise ValueError("C43 root partition is shorter than declared sourceRootStorage")
    if size_bytes < 1:
        raise ValueError("C43 regular file is empty")
    return ImmutableArtifactIdentity(artifact_id, size_bytes, hasher.hexdigest())


def _write_and_hash(target_file: Any, hasher: Any, contents: bytes) -> int:
    target_file.write(contents)
    hasher.update(contents)
    return len(contents)


def _write_zero_padding_and_hash(target_file: Any, hasher: Any, size_bytes: int) -> int:
    zero_chunk = b"\0" * min(COPY_BUFFER_BYTES, size_bytes)
    written = 0
    while written < size_bytes:
        chunk = zero_chunk[: min(len(zero_chunk), size_bytes - written)]
        written += _write_and_hash(target_file, hasher, chunk)
    return written


def _identity_document(identity: ImmutableArtifactIdentity) -> Mapping[str, Any]:
    return {"id": identity.artifact_id, "sizeBytes": identity.size_bytes, "sha256": identity.sha256}


def _require_absent_output_directory(assembly_id: str, output_directory: Path) -> None:
    if not output_directory.is_absolute():
        raise GuestRootStoragePartitionAssemblyError(assembly_id, "output-validate", "C43 output directory must be absolute")
    parent = output_directory.parent
    try:
        parent_info = os.lstat(parent)
    except OSError as error:
        raise GuestRootStoragePartitionAssemblyError(
            assembly_id, "output-validate", "C43 output parent cannot be stated: {0}".format(error)
        ) from error
    if os.path.islink(parent) or not os.path.isdir(parent):
        raise GuestRootStoragePartitionAssemblyError(
            assembly_id, "output-validate", "C43 output parent must be a directory non-symlink"
        )
    if output_directory.exists() or output_directory.is_symlink():
        raise GuestRootStoragePartitionAssemblyError(
            assembly_id, "output-validate", "C43 output directory already exists"
        )
    del parent_info


def _write_new_json_document(destination: Path, document: Mapping[str, Any]) -> None:
    contents = json.dumps(document, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    with destination.open("xb") as output_file:
        output_file.write(contents)
        output_file.flush()
        os.fsync(output_file.fileno())


def _decode_json_object(contents: bytes, label: str) -> Mapping[str, Any]:
    try:
        document = json.loads(contents.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("{0} JSON cannot be decoded: {1}".format(label, error)) from error
    return _require_mapping(document, label)


def _require_absolute_regular_non_symlink(path: Path, label: str) -> None:
    if not path.is_absolute():
        raise ValueError("{0} path must be absolute".format(label))
    info = os.lstat(path)
    if os.path.islink(path) or not os.path.isfile(path):
        raise ValueError("{0} must be a regular non-symlink file".format(label))
    del info


def _require_mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("{0} must be an object".format(label))
    return value


def _require_exact_keys(document: Mapping[str, Any], expected_keys: set[str], label: str) -> None:
    actual_keys = set(document.keys())
    if actual_keys != expected_keys:
        raise ValueError(
            "{0} keys are invalid missing={1} unexpected={2}".format(
                label,
                sorted(expected_keys - actual_keys),
                sorted(actual_keys - expected_keys),
            )
        )


def _require_identifier(value: Any, label: str) -> str:
    text = _require_nonempty_string(value, label)
    if len(text) > 128 or not text[0].isalnum() or any(
        not (character.isalnum() or character in "._-") for character in text
    ):
        raise ValueError("{0} is invalid".format(label))
    return text


def _require_sha256(value: Any, label: str) -> str:
    text = _require_nonempty_string(value, label)
    if len(text) != SHA256_LENGTH or any(character not in "0123456789abcdef" for character in text):
        raise ValueError("{0} must be a lowercase SHA-256".format(label))
    return text


def _require_positive_integer(value: Any, label: str) -> int:
    if type(value) is not int or value < 1:
        raise ValueError("{0} must be a positive integer".format(label))
    return value


def _require_nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError("{0} must be a non-empty string".format(label))
    return value


def _require_absolute_path(value: Any, label: str) -> Path:
    path = Path(_require_nonempty_string(value, label))
    if not path.is_absolute():
        raise ValueError("{0} must be absolute".format(label))
    return path


def _require_storage_output_relative_path(value: Any, label: str) -> str:
    text = _require_nonempty_string(value, label)
    path = Path(text)
    if path.is_absolute() or path.as_posix() != text or len(path.parts) != 2 or path.parts[0] != "storage" or not text.endswith(".raw"):
        raise ValueError("{0} must be one direct storage/*.raw output path".format(label))
    return text


def _validate_completed_at(value: Any) -> None:
    text = _require_nonempty_string(value, "completedAt")
    parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("completedAt must include a timezone")


def _sha256_hex(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def _parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Assemble C42 whole-disk ext4 root storage into one declared MBR partition.")
    parser.add_argument("--guest-root-storage-partition-assembly-declaration", required=True)
    parser.add_argument("--output-directory", required=True)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    parsed_arguments = _parse_arguments(sys.argv[1:] if arguments is None else arguments)
    try:
        execute_guest_root_storage_partition_assembly(
            GuestRootStoragePartitionAssemblyExecution(
                declaration_absolute_path=Path(
                    parsed_arguments.guest_root_storage_partition_assembly_declaration
                ),
                output_directory=Path(parsed_arguments.output_directory),
            )
        )
    except GuestRootStoragePartitionAssemblyError as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
