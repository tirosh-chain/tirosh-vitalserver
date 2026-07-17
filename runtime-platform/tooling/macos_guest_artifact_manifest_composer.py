"""Compose C34 from explicit macOS Guest image compiler outputs.

This release-tool adapter does not compile a Linux Guest image and does not
claim that any Guest can boot. A Guest image compiler owns that operation. This
adapter reads only the compiler outputs named on its command line, calculates
their immutable identity, and writes C34 MacOSGuestArtifactManifest for the
macOS Host package composer.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
from typing import Iterable, Mapping, Sequence


class MacOSGuestArtifactManifestCompositionError(RuntimeError):
    """An explicit Guest artifact input cannot compose a truthful C34."""


@dataclass(frozen=True)
class MacOSGuestStorageArtifactSource:
    """One compiled Guest storage artifact with its intended Host attachment."""

    storage_id: str
    storage_role: str
    storage_image_format: str
    guest_volume_file_system: str | None
    source: Path


@dataclass(frozen=True)
class MacOSGuestArtifactManifestComposition:
    artifact_set_id: str
    kernel_source: Path
    initial_ramdisk_source: Path | None
    storage_sources: Sequence[MacOSGuestStorageArtifactSource]
    output_manifest: Path
    replace_output: bool


def compose_macos_guest_artifact_manifest(
    composition: MacOSGuestArtifactManifestComposition,
) -> dict[str, object]:
    """Write one C34 document from the complete explicit compiler output set."""

    validate_macos_guest_artifact_manifest_composition(composition)
    document: dict[str, object] = {
        "schemaVersion": "v1",
        "artifactSetId": composition.artifact_set_id,
        "architecture": "arm64",
        "kernel": build_artifact_digest(composition.kernel_source),
        "storageDevices": [
            {
                "id": storage_source.storage_id,
                "role": storage_source.storage_role,
                "storageImageFormat": storage_source.storage_image_format,
                **(
                    {"guestVolumeFileSystem": storage_source.guest_volume_file_system}
                    if storage_source.guest_volume_file_system is not None
                    else {}
                ),
                **build_artifact_digest(storage_source.source),
            }
            for storage_source in composition.storage_sources
        ],
    }
    if composition.initial_ramdisk_source is not None:
        document["initialRamdisk"] = build_artifact_digest(composition.initial_ramdisk_source)
    write_json_document(composition.output_manifest, document)
    return document


def validate_macos_guest_artifact_manifest_composition(
    composition: MacOSGuestArtifactManifestComposition,
) -> None:
    if not is_contract_identifier(composition.artifact_set_id):
        raise MacOSGuestArtifactManifestCompositionError("artifact set ID must be a contract identifier")
    require_existing_artifact(composition.kernel_source, "Guest kernel source")
    if composition.initial_ramdisk_source is not None:
        require_existing_artifact(composition.initial_ramdisk_source, "Guest initial RAM disk source")
    if len(composition.storage_sources) != 2:
        raise MacOSGuestArtifactManifestCompositionError("exactly two Guest storage sources are required")
    storage_ids: set[str] = set()
    for storage_artifact_source in composition.storage_sources:
        if not is_contract_identifier(storage_artifact_source.storage_id):
            raise MacOSGuestArtifactManifestCompositionError("Guest storage ID must be a contract identifier")
        if storage_artifact_source.storage_id in storage_ids:
            raise MacOSGuestArtifactManifestCompositionError("Guest storage IDs must be unique")
        storage_ids.add(storage_artifact_source.storage_id)
        if storage_artifact_source.storage_image_format != "raw":
            raise MacOSGuestArtifactManifestCompositionError("Guest storage image format must be raw")
        require_existing_artifact(storage_artifact_source.source, "Guest storage source " + storage_artifact_source.storage_id)
    expected_storage = {
        ("guest-root", "guest-root-storage", "raw", None),
        ("guest-product-bootstrap", "guest-product-bootstrap-volume", "raw", "iso9660"),
    }
    declared_storage = {
        (storage_source.storage_id, storage_source.storage_role, storage_source.storage_image_format, storage_source.guest_volume_file_system)
        for storage_source in composition.storage_sources
    }
    if declared_storage != expected_storage:
        raise MacOSGuestArtifactManifestCompositionError(
            "Guest storage sources must declare guest-root/raw and guest-product-bootstrap/raw storage image with ISO9660 Guest volume roles"
        )
    if not composition.output_manifest.is_absolute():
        raise MacOSGuestArtifactManifestCompositionError("output manifest path must be absolute")
    if not composition.output_manifest.parent.is_dir():
        raise MacOSGuestArtifactManifestCompositionError("output manifest parent directory is missing")
    if composition.output_manifest.exists() and not composition.replace_output:
        raise MacOSGuestArtifactManifestCompositionError("output manifest already exists; pass --replace-output explicitly")


def build_artifact_digest(source: Path) -> dict[str, object]:
    return {"sizeBytes": source.stat().st_size, "sha256": sha256_file(source)}


def write_json_document(destination: Path, document: Mapping[str, object]) -> None:
    """Atomically replace only the explicitly selected C34 output document."""

    serialized = json.dumps(document, indent=2, sort_keys=True) + "\n"
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=destination.name + ".",
        suffix=".tmp",
        dir=destination.parent,
        delete=False,
    ) as temporary_file:
        temporary_path = Path(temporary_file.name)
        temporary_file.write(serialized)
    try:
        temporary_path.replace(destination)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise MacOSGuestArtifactManifestCompositionError("could not write output manifest") from error


def require_existing_artifact(source: Path, artifact_name: str) -> None:
    if not source.is_absolute() or not source.is_file():
        raise MacOSGuestArtifactManifestCompositionError(artifact_name + " is missing or not a file")
    if source.stat().st_size < 1:
        raise MacOSGuestArtifactManifestCompositionError(artifact_name + " must not be empty")


def sha256_file(source: Path) -> str:
    digest = hashlib.sha256()
    with source.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_storage_sources(values: Iterable[str]) -> tuple[MacOSGuestStorageArtifactSource, ...]:
    sources: list[MacOSGuestStorageArtifactSource] = []
    source_ids: set[str] = set()
    for value in values:
        storage_id, separator, storage_role_format_and_path = value.partition("=")
        storage_role, role_separator, storage_image_format_and_rest = storage_role_format_and_path.partition(",")
        storage_image_format, image_format_separator, guest_volume_file_system_and_path = storage_image_format_and_rest.partition(",")
        guest_volume_file_system, file_system_separator, source_path = guest_volume_file_system_and_path.partition(":")
        if (
            not separator
            or not role_separator
            or not image_format_separator
            or not file_system_separator
            or not storage_id
            or not storage_role
            or not storage_image_format
            or not guest_volume_file_system
            or not source_path
            or storage_id in source_ids
        ):
            raise MacOSGuestArtifactManifestCompositionError(
                "Guest storage source must be unique and formatted as storage-id=storage-role,raw,none|iso9660:/absolute/source/path"
            )
        source_ids.add(storage_id)
        sources.append(
            MacOSGuestStorageArtifactSource(
                storage_id=storage_id,
                storage_role=storage_role,
                storage_image_format=storage_image_format,
                guest_volume_file_system=None if guest_volume_file_system == "none" else guest_volume_file_system,
                source=Path(source_path),
            )
        )
    return tuple(sources)


contract_identifier_pattern = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def is_contract_identifier(value: str) -> bool:
    return bool(contract_identifier_pattern.fullmatch(value))


def parse_arguments(arguments: list[str]) -> MacOSGuestArtifactManifestComposition:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact-set-id", required=True)
    parser.add_argument("--guest-kernel-source", required=True)
    parser.add_argument("--guest-initial-ramdisk-source")
    parser.add_argument("--guest-storage-source", action="append", default=[])
    parser.add_argument("--output-manifest", required=True)
    parser.add_argument("--replace-output", action="store_true")
    parsed = parser.parse_args(arguments)
    return MacOSGuestArtifactManifestComposition(
        artifact_set_id=parsed.artifact_set_id,
        kernel_source=Path(parsed.guest_kernel_source),
        initial_ramdisk_source=Path(parsed.guest_initial_ramdisk_source) if parsed.guest_initial_ramdisk_source else None,
        storage_sources=parse_storage_sources(parsed.guest_storage_source),
        output_manifest=Path(parsed.output_manifest),
        replace_output=parsed.replace_output,
    )


def main(arguments: list[str]) -> int:
    try:
        document = compose_macos_guest_artifact_manifest(parse_arguments(arguments))
    except MacOSGuestArtifactManifestCompositionError as error:
        print("macOS Guest artifact manifest composition failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(document, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
