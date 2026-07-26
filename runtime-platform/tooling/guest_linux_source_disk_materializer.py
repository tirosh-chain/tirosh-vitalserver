#!/usr/bin/env python3
"""Materialize one declared QCOW2 Guest Linux source disk as a raw disk.

This C73 release-build adapter is deliberately narrower than a Guest image
builder.  It verifies caller-selected QCOW2 bytes, invokes one caller-selected
``qemu-img`` executable with fixed conversion arguments, and publishes a new
raw image with a receipt.  It does not download an image, discover a release,
choose an ext4 partition, or claim C42 extraction, Guest boot, or installation.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
from typing import Any, Mapping, Sequence
from urllib.parse import urlparse


class GuestLinuxSourceDiskMaterializationError(RuntimeError):
    """A C73 input, image-tool observation, or output is not trustworthy."""


@dataclass(frozen=True)
class GuestLinuxSourceDiskMaterialization:
    """Release-process-owned C73 execution inputs for one new output directory."""

    declaration_path: Path
    output_directory: Path
    qemu_img_executable: Path


def execute_guest_linux_source_disk_materialization(
    materialization: GuestLinuxSourceDiskMaterialization,
) -> Mapping[str, Any]:
    """Verify and convert one declared QCOW2 input before atomic publication."""

    validate_execution(materialization)
    declaration_bytes = read_regular_file(
        materialization.declaration_path, "C73 declaration"
    )
    declaration = decode_declaration(declaration_bytes)
    source = required_object(declaration.get("sourceImage"), "C73 sourceImage")
    source_path = Path(required_absolute_path(source.get("sourceAbsolutePath"), "C73 sourceImage sourceAbsolutePath"))
    source_identity = identify_regular_file(source_path, required_identifier(source.get("id"), "C73 sourceImage ID"))
    if (
        source_identity["sizeBytes"] != source.get("sizeBytes")
        or source_identity["sha256"] != source.get("sha256")
    ):
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 sourceImage immutable identity does not match declaration"
        )

    source_info = inspect_image(materialization.qemu_img_executable, source_path)
    if source_info["format"] != "qcow2":
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 source image format is not declared qcow2: " + source_info["format"]
        )
    raw_image = required_object(declaration.get("rawImage"), "C73 rawImage")
    raw_relative_path = required_storage_relative_path(
        raw_image.get("outputRelativePath"), "C73 rawImage outputRelativePath"
    )
    raw_image_id = required_identifier(raw_image.get("id"), "C73 rawImage ID")
    temporary_directory = Path(
        tempfile.mkdtemp(
            prefix="." + materialization.output_directory.name + ".C73.",
            dir=materialization.output_directory.parent,
        )
    )
    try:
        raw_output_path = temporary_directory / Path(raw_relative_path)
        raw_output_path.parent.mkdir(mode=0o700, parents=True, exist_ok=False)
        convert_image(materialization.qemu_img_executable, source_path, raw_output_path)
        raw_info = inspect_image(materialization.qemu_img_executable, raw_output_path)
        if raw_info["format"] != "raw":
            raise GuestLinuxSourceDiskMaterializationError(
                "C73 qemu-img conversion did not produce raw output: " + raw_info["format"]
            )
        raw_identity = identify_regular_file(raw_output_path, raw_image_id)
        if raw_identity["sizeBytes"] % 512 != 0:
            raise GuestLinuxSourceDiskMaterializationError(
                "C73 raw image size is not a 512-byte multiple"
            )
        if raw_info["virtualSize"] != raw_identity["sizeBytes"]:
            raise GuestLinuxSourceDiskMaterializationError(
                "C73 qemu-img raw virtual size does not match materialized file size"
            )
        receipt = {
            "schemaVersion": "v1",
            "documentKind": "guest-linux-source-disk-materialization-receipt",
            "materializationId": declaration["materializationId"],
            "architecture": "arm64",
            "materializationDeclarationSha256": sha256_bytes(declaration_bytes),
            "sourceImage": {
                "id": source["id"],
                "sourceOriginUri": source["sourceOriginUri"],
                "sourceRelease": source["sourceRelease"],
                "sizeBytes": source_identity["sizeBytes"],
                "sha256": source_identity["sha256"],
            },
            "sourceImageFormat": "qcow2",
            "rawImage": {
                "id": raw_identity["id"],
                "relativePath": raw_relative_path,
                "imageFormat": "raw",
                "sizeBytes": raw_identity["sizeBytes"],
                "sha256": raw_identity["sha256"],
            },
            "completedAt": utc_timestamp(),
        }
        write_new_json(
            temporary_directory
            / "guest-linux-source-disk-materialization-receipt.json",
            receipt,
        )
        publish_new_directory(temporary_directory, materialization.output_directory)
    except Exception:
        remove_tree(temporary_directory)
        raise
    return {
        "materializationId": declaration["materializationId"],
        "outputDirectory": str(materialization.output_directory),
        "rawImage": {
            "path": str(materialization.output_directory / Path(raw_relative_path)),
            **identify_regular_file(
                materialization.output_directory / Path(raw_relative_path), raw_image_id
            ),
        },
        "receipt": {
            "path": str(
                materialization.output_directory
                / "guest-linux-source-disk-materialization-receipt.json"
            ),
            **identify_regular_file(
                materialization.output_directory
                / "guest-linux-source-disk-materialization-receipt.json",
                "guest-linux-source-disk-materialization-receipt",
            ),
        },
    }


def validate_execution(materialization: GuestLinuxSourceDiskMaterialization) -> None:
    require_regular_file(materialization.declaration_path, "C73 declaration")
    require_regular_file(materialization.qemu_img_executable, "C73 qemu-img executable")
    if not os.access(materialization.qemu_img_executable, os.X_OK):
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 qemu-img executable is not executable: "
            + str(materialization.qemu_img_executable)
        )
    if not materialization.output_directory.is_absolute():
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 output directory must be absolute"
        )
    parent = materialization.output_directory.parent
    if parent.is_symlink() or not parent.is_dir():
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 output parent must be an existing non-symlink directory"
        )
    if materialization.output_directory.exists() or materialization.output_directory.is_symlink():
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 output directory must be new: " + str(materialization.output_directory)
        )


def decode_declaration(payload: bytes) -> Mapping[str, Any]:
    try:
        declaration = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 declaration is unreadable: " + str(error)
        ) from error
    if not isinstance(declaration, dict):
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 declaration must contain one JSON object"
        )
    expected_keys = {
        "schemaVersion",
        "documentKind",
        "materializationId",
        "architecture",
        "sourceImage",
        "sourceImageFormat",
        "rawImage",
    }
    if set(declaration) != expected_keys:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 declaration fields are not exact"
        )
    if declaration.get("schemaVersion") != "v1":
        raise GuestLinuxSourceDiskMaterializationError("C73 schemaVersion must be v1")
    if declaration.get("documentKind") != "guest-linux-source-disk-materialization-declaration":
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 declaration documentKind is invalid"
        )
    required_identifier(declaration.get("materializationId"), "C73 materializationId")
    if declaration.get("architecture") != "arm64":
        raise GuestLinuxSourceDiskMaterializationError("C73 architecture must be arm64")
    if declaration.get("sourceImageFormat") != "qcow2":
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 sourceImageFormat must be qcow2"
        )
    source = required_object(declaration.get("sourceImage"), "C73 sourceImage")
    if set(source) != {
        "id",
        "sourceAbsolutePath",
        "sourceOriginUri",
        "sourceRelease",
        "sizeBytes",
        "sha256",
    }:
        raise GuestLinuxSourceDiskMaterializationError("C73 sourceImage fields are not exact")
    required_identifier(source.get("id"), "C73 sourceImage ID")
    required_absolute_path(source.get("sourceAbsolutePath"), "C73 sourceImage sourceAbsolutePath")
    parsed_origin = urlparse(required_string(source.get("sourceOriginUri"), "C73 sourceImage sourceOriginUri"))
    if parsed_origin.scheme != "https" or not parsed_origin.netloc:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 sourceImage sourceOriginUri must be an absolute HTTPS URI"
        )
    required_string(source.get("sourceRelease"), "C73 sourceImage sourceRelease")
    required_positive_integer(source.get("sizeBytes"), "C73 sourceImage sizeBytes")
    required_sha256(source.get("sha256"), "C73 sourceImage sha256")
    raw_image = required_object(declaration.get("rawImage"), "C73 rawImage")
    if set(raw_image) != {"id", "outputRelativePath", "imageFormat"}:
        raise GuestLinuxSourceDiskMaterializationError("C73 rawImage fields are not exact")
    required_identifier(raw_image.get("id"), "C73 rawImage ID")
    required_storage_relative_path(
        raw_image.get("outputRelativePath"), "C73 rawImage outputRelativePath"
    )
    if raw_image.get("imageFormat") != "raw":
        raise GuestLinuxSourceDiskMaterializationError("C73 rawImage imageFormat must be raw")
    return declaration


def inspect_image(qemu_img_executable: Path, image_path: Path) -> Mapping[str, int | str]:
    completed = subprocess.run(
        [str(qemu_img_executable), "info", "--output=json", str(image_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 qemu-img info failed exitCode={0} reason={1}".format(
                completed.returncode,
                (completed.stderr or completed.stdout).strip() or "no diagnostic output",
            )
        )
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 qemu-img info response is not JSON"
        ) from error
    if not isinstance(document, dict):
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 qemu-img info response must be an object"
        )
    image_format = document.get("format")
    virtual_size = document.get("virtual-size")
    if not isinstance(image_format, str) or not image_format:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 qemu-img info response has no image format"
        )
    if not isinstance(virtual_size, int) or virtual_size <= 0:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 qemu-img info response has no positive virtual size"
        )
    return {"format": image_format, "virtualSize": virtual_size}


def convert_image(qemu_img_executable: Path, source_path: Path, output_path: Path) -> None:
    completed = subprocess.run(
        [
            str(qemu_img_executable),
            "convert",
            "-O",
            "raw",
            str(source_path),
            str(output_path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 qemu-img convert failed exitCode={0} reason={1}".format(
                completed.returncode,
                (completed.stderr or completed.stdout).strip() or "no diagnostic output",
            )
        )
    require_regular_file(output_path, "C73 converted raw image")


def identify_regular_file(path: Path, identifier: str) -> Mapping[str, Any]:
    require_regular_file(path, "C73 regular file")
    hasher = hashlib.sha256()
    size = 0
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                hasher.update(chunk)
                size += len(chunk)
    except OSError as error:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 cannot read regular file: " + str(error)
        ) from error
    if size <= 0:
        raise GuestLinuxSourceDiskMaterializationError("C73 regular file is empty")
    return {"id": identifier, "sizeBytes": size, "sha256": hasher.hexdigest()}


def write_new_json(path: Path, document: Mapping[str, Any]) -> None:
    payload = canonical_json(document).encode("utf-8")
    descriptor, temporary_path = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, path)
    except OSError as error:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 receipt write failed: " + str(error)
        ) from error


def publish_new_directory(temporary_directory: Path, output_directory: Path) -> None:
    try:
        os.replace(temporary_directory, output_directory)
    except OSError as error:
        raise GuestLinuxSourceDiskMaterializationError(
            "C73 output publication failed: " + str(error)
        ) from error


def read_regular_file(path: Path, label: str) -> bytes:
    require_regular_file(path, label)
    try:
        return path.read_bytes()
    except OSError as error:
        raise GuestLinuxSourceDiskMaterializationError(
            label + " read failed: " + str(error)
        ) from error


def require_regular_file(path: Path, label: str) -> None:
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise GuestLinuxSourceDiskMaterializationError(
            label + " must be one absolute regular non-symlink file: " + str(path)
        )


def required_object(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise GuestLinuxSourceDiskMaterializationError(label + " must be an object")
    return value


def required_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise GuestLinuxSourceDiskMaterializationError(label + " is required")
    return value


def required_identifier(value: Any, label: str) -> str:
    result = required_string(value, label)
    if len(result) > 128 or not result.replace("-", "").replace("_", "").replace(".", "").isalnum():
        raise GuestLinuxSourceDiskMaterializationError(label + " is invalid")
    return result


def required_absolute_path(value: Any, label: str) -> str:
    result = required_string(value, label)
    if not Path(result).is_absolute():
        raise GuestLinuxSourceDiskMaterializationError(label + " must be absolute")
    return result


def required_positive_integer(value: Any, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise GuestLinuxSourceDiskMaterializationError(label + " must be positive")
    return value


def required_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise GuestLinuxSourceDiskMaterializationError(label + " must be a lowercase SHA-256")
    return value


def required_storage_relative_path(value: Any, label: str) -> str:
    result = required_string(value, label)
    path = PurePosixPath(result)
    if (
        path.is_absolute()
        or ".." in path.parts
        or len(path.parts) != 2
        or path.parts[0] != "storage"
        or path.suffix != ".raw"
    ):
        raise GuestLinuxSourceDiskMaterializationError(
            label + " must be one safe storage/*.raw path"
        )
    return result


def canonical_json(document: Mapping[str, Any]) -> str:
    return json.dumps(document, sort_keys=True, indent=2) + "\n"


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def remove_tree(path: Path) -> None:
    if not path.exists():
        return
    for child in sorted(path.rglob("*"), reverse=True):
        if child.is_dir() and not child.is_symlink():
            child.rmdir()
        else:
            child.unlink()
    path.rmdir()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--declaration", required=True, type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--qemu-img-executable", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        result = execute_guest_linux_source_disk_materialization(
            GuestLinuxSourceDiskMaterialization(
                declaration_path=arguments.declaration,
                output_directory=arguments.output_directory,
                qemu_img_executable=arguments.qemu_img_executable,
            )
        )
    except GuestLinuxSourceDiskMaterializationError as error:
        parser.exit(2, "guest Linux source disk materialization failed: " + str(error) + "\n")
    print(canonical_json(result), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
