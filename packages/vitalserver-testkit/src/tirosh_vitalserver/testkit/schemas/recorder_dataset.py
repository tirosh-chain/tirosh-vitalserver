"""External recorder dataset manifest schemas."""

from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Self

from pydantic import Field, field_validator

from tirosh_vitalserver.testkit.schemas.base import ExternalSchema
from tirosh_vitalserver.testkit.types.json import JsonObject


class RecorderDatasetItemDocument(ExternalSchema):
    """One recorder payload entry in a dataset manifest."""

    source: str = Field(min_length=1)
    payload: str = Field(min_length=1)
    title: str | None = None
    purpose: str | None = None
    metadata: str | None = None
    group: str | None = None
    headerTrackCount: int | None = None
    payloadTrackCount: int | None = None
    headerPayloadTrackDelta: int | None = None
    sizeBytes: int | None = None
    recordCount: int | None = None
    sampleCount: int | None = None
    devices: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    tracks: list[str] = Field(default_factory=list)

    @field_validator("devices", "tags", "tracks", mode="before")
    @classmethod
    def validate_string_list(cls, value: object) -> list[str]:
        if value is None:
            return []
        if not isinstance(value, list) or not all(
            isinstance(item, str) for item in value
        ):
            raise ValueError("dataset item list fields must contain strings")

        return value


class RecorderDatasetManifestDocument(ExternalSchema):
    """Manifest for explicit real-recorder payload datasets."""

    schemaVersion: int
    dataset: str = Field(min_length=1)
    sourceGlob: str | None = None
    outputDir: str | None = None
    scenario: str | None = None
    startOffsetSeconds: float | None = None
    durationSeconds: int | float | None = None
    totalFiles: int | None = None
    usageNotes: list[str] = Field(default_factory=list)
    recommendedSets: dict[str, RecorderDatasetItemDocument] = Field(
        default_factory=dict
    )
    payloads: list[RecorderDatasetItemDocument] = Field(default_factory=list)

    @classmethod
    def from_json_file(cls, path: str | Path) -> Self:
        return cls.model_validate(json.loads(Path(path).read_text()))

    @field_validator("usageNotes", mode="before")
    @classmethod
    def validate_usage_notes(cls, value: object) -> list[str]:
        if value is None:
            return []
        if not isinstance(value, list) or not all(
            isinstance(item, str) for item in value
        ):
            raise ValueError("usageNotes must contain strings")

        return value

    def require_recommended_payload(self, key: str, *, manifest_path: Path) -> Path:
        """Return the payload path for an explicit recommended dataset key."""

        if not key:
            raise ValueError("dataset key must not be empty")

        item = self.recommendedSets.get(key)
        if item is None:
            available = ", ".join(sorted(self.recommendedSets))
            raise ValueError(
                f"unknown dataset key: {key}. available: {available or '<none>'}"
            )

        return resolve_manifest_path(item.payload, manifest_path=manifest_path)

    def recommended_sets_document(self) -> JsonObject:
        """Return a stable JSON document of recommended dataset entries."""

        return {
            "dataset": self.dataset,
            "schemaVersion": self.schemaVersion,
            "recommendedSets": {
                key: deepcopy(item.model_dump())
                for key, item in sorted(self.recommendedSets.items())
            },
        }


def load_recorder_dataset_manifest(
    path: str | Path,
) -> RecorderDatasetManifestDocument:
    """Load and validate a recorder dataset manifest from disk."""

    return RecorderDatasetManifestDocument.from_json_file(path)


def resolve_manifest_path(value: str, *, manifest_path: Path) -> Path:
    """Resolve a manifest path while preserving explicit path meaning."""

    path = Path(value)
    if path.is_absolute() or path.exists():
        return path

    manifest_relative = manifest_path.parent / path
    if manifest_relative.exists():
        return manifest_relative

    return path
