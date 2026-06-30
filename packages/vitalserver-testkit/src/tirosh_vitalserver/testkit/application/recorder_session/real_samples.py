"""Packaged real recorder sample catalog for TestKit sessions."""

from __future__ import annotations

from tirosh_vitalserver.testkit.schemas.recorder_dataset import (
    RecorderDatasetManifestDocument,
)
from tirosh_vitalserver.testkit.types.json import JsonObject

PACKAGED_REAL_SAMPLE_DATASET = "not-distributed"
PACKAGED_REAL_SAMPLE_REASON = (
    "real recorder sample data is not distributed with TestKit; "
    "provide an explicit dataset manifest or local payload path"
)


def load_packaged_real_sample_manifest() -> RecorderDatasetManifestDocument:
    """Report that packaged recorder sample data is not distributed."""

    raise RuntimeError(PACKAGED_REAL_SAMPLE_REASON)


def packaged_real_sample_catalog_document() -> JsonObject:
    """Return explicit API state for non-distributed recorder samples."""

    return {
        "dataset": PACKAGED_REAL_SAMPLE_DATASET,
        "schemaVersion": "recorder-dataset.v1",
        "state": "unavailable",
        "reason": PACKAGED_REAL_SAMPLE_REASON,
        "scenarios": [],
    }


def load_packaged_real_sample_payload(key: str) -> JsonObject:
    """Report that packaged recorder sample payloads are not distributed."""

    raise RuntimeError(f"{PACKAGED_REAL_SAMPLE_REASON}: {key}")


class PackagedRecordedFrameSourceProvider:
    """Recorded frame source provider for non-distributed packaged samples."""

    def load_recorded_frame_source(self, key: str) -> JsonObject:
        """Report that packaged recorder sample payloads are not distributed."""

        return load_packaged_real_sample_payload(key)
