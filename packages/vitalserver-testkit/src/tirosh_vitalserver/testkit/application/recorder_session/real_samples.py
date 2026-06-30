"""Packaged real recorder sample catalog for TestKit sessions."""

from __future__ import annotations

import gzip
import json
from importlib import resources

from tirosh_vitalserver.testkit.schemas.payloads import RecorderPayloadDocument
from tirosh_vitalserver.testkit.schemas.recorder_dataset import (
    RecorderDatasetManifestDocument,
)
from tirosh_vitalserver.testkit.types.json import JsonObject

FIXTURE_PACKAGE = "tirosh_vitalserver.testkit.fixtures.real_recorder_samples"
MANIFEST_NAME = "manifest.json"


def load_packaged_real_sample_manifest() -> RecorderDatasetManifestDocument:
    """Load the explicit manifest shipped inside the TestKit package."""

    payload = resources.files(FIXTURE_PACKAGE).joinpath(MANIFEST_NAME).read_text()
    return RecorderDatasetManifestDocument.model_validate_json(payload)


def packaged_real_sample_catalog_document() -> JsonObject:
    """Return public scenario data for packaged recorder fixtures."""

    manifest = load_packaged_real_sample_manifest()
    return {
        "dataset": manifest.dataset,
        "schemaVersion": manifest.schemaVersion,
        "scenarios": [
            {
                "key": key,
                "title": item.title or key.replace("_", " ").title(),
                "purpose": item.purpose or "",
                "durationSeconds": manifest.durationSeconds,
                "tracks": list(item.tracks),
                "payloadTrackCount": item.payloadTrackCount,
                "recordCount": item.recordCount,
                "sampleCount": item.sampleCount,
            }
            for key, item in sorted(manifest.recommendedSets.items())
        ],
    }


def load_packaged_real_sample_payload(key: str) -> JsonObject:
    """Load one packaged real recorder sample payload by manifest key."""

    manifest = load_packaged_real_sample_manifest()
    item = manifest.recommendedSets.get(key)
    if item is None:
        available = ", ".join(sorted(manifest.recommendedSets))
        raise ValueError(
            f"unknown packaged scenario key: {key}. available: {available or '<none>'}"
        )

    raw = resources.files(FIXTURE_PACKAGE).joinpath(item.payload).read_bytes()
    data = gzip.decompress(raw) if item.payload.endswith(".gz") else raw
    decoded = json.loads(data)
    return RecorderPayloadDocument.from_external(decoded).to_internal()


class PackagedRecordedFrameSourceProvider:
    """Recorded frame source provider backed by packaged fixtures."""

    def load_recorded_frame_source(self, key: str) -> JsonObject:
        """Load one packaged recorded frame source payload."""

        return load_packaged_real_sample_payload(key)
