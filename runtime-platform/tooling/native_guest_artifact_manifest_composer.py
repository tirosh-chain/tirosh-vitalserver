"""Compose C65 from explicit amd64 Guest compiler outputs.

This adapter does not build, mount, or boot a Guest image.  It records the
immutable identities of the UEFI-bootable raw disk and its separate NoCloud
bootstrap volume after the selected C35 builder has produced them.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import tempfile
from typing import Mapping, Sequence


class NativeGuestArtifactManifestCompositionError(RuntimeError):
    """An explicit amd64 Guest output cannot truthfully compose C65."""


@dataclass(frozen=True)
class NativeGuestStorageArtifactSource:
    """One immutable C65 storage artifact and its explicit Guest role."""

    storage_id: str
    storage_role: str
    storage_image_format: str
    guest_volume_file_system: str | None
    source: Path


@dataclass(frozen=True)
class NativeGuestArtifactManifestComposition:
    """All caller-selected C65 composition inputs; there are no defaults."""

    artifact_set_id: str
    storage_sources: Sequence[NativeGuestStorageArtifactSource]
    output_manifest: Path


def compose_native_guest_artifact_manifest(
    composition: NativeGuestArtifactManifestComposition,
) -> dict[str, object]:
    """Write one C65 document from complete, regular amd64 Guest outputs."""

    validate_native_guest_artifact_manifest_composition(composition)
    document: dict[str, object] = {
        "schemaVersion": "v1",
        "artifactSetId": composition.artifact_set_id,
        "architecture": "amd64",
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
                **artifact_identity(storage_source.source),
            }
            for storage_source in composition.storage_sources
        ],
    }
    write_json_document(composition.output_manifest, document)
    return document


def validate_native_guest_artifact_manifest_composition(
    composition: NativeGuestArtifactManifestComposition,
) -> None:
    if not is_contract_identifier(composition.artifact_set_id):
        raise NativeGuestArtifactManifestCompositionError("artifact set ID must be a contract identifier")
    if not composition.output_manifest.is_absolute():
        raise NativeGuestArtifactManifestCompositionError("output manifest path must be absolute")
    if not composition.output_manifest.parent.is_dir() or composition.output_manifest.parent.is_symlink():
        raise NativeGuestArtifactManifestCompositionError("output manifest parent must be a non-symlink directory")
    if composition.output_manifest.exists():
        raise NativeGuestArtifactManifestCompositionError("output manifest already exists")
    if len(composition.storage_sources) != 2:
        raise NativeGuestArtifactManifestCompositionError("exactly two Guest storage sources are required")
    declared_storage = {
        (
            source.storage_id,
            source.storage_role,
            source.storage_image_format,
            source.guest_volume_file_system,
        )
        for source in composition.storage_sources
    }
    expected_storage = {
        ("guest-root", "guest-root-storage", "raw", None),
        ("guest-product-bootstrap", "guest-product-bootstrap-volume", "raw", "iso9660"),
    }
    if declared_storage != expected_storage:
        raise NativeGuestArtifactManifestCompositionError(
            "storage sources must declare guest-root/raw and guest-product-bootstrap/raw ISO9660 roles"
        )
    for source in composition.storage_sources:
        require_existing_regular_artifact(source.source, "Guest storage source " + source.storage_id)


def require_existing_regular_artifact(path: Path, role: str) -> None:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise NativeGuestArtifactManifestCompositionError(role + " is missing, not regular, or symbolic")
    if path.stat().st_size < 1:
        raise NativeGuestArtifactManifestCompositionError(role + " must not be empty")


def artifact_identity(path: Path) -> dict[str, object]:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"sizeBytes": path.stat().st_size, "sha256": digest.hexdigest()}


def write_json_document(destination: Path, document: Mapping[str, object]) -> None:
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
        raise NativeGuestArtifactManifestCompositionError("could not write output manifest") from error


_IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def is_contract_identifier(value: str) -> bool:
    return bool(_IDENTIFIER_PATTERN.fullmatch(value))
