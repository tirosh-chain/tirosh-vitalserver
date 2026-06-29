"""Shared `.vital` file domain contracts."""

from __future__ import annotations

from tirosh_vitalserver.core.domain.vital_file.discovery import (
    iter_vital_files,
)
from tirosh_vitalserver.core.domain.vital_file.models import PayloadFile
from tirosh_vitalserver.core.domain.vital_file.policy import (
    VITAL_FILENAME_RE,
    assert_vital_filenames,
)
from tirosh_vitalserver.core.domain.vital_file.raw_archive import (
    RawArchivePayload,
    raw_archive_payload_from_record,
    raw_archive_payloads_from_jsonl_lines,
    vital_tracks_by_vrcode_from_raw_archive,
)
from tirosh_vitalserver.core.domain.vital_file.session_recording import (
    VitalSessionMetadata,
    VitalTrack,
    VitalTrackRecord,
    collect_frame_tracks,
    metadata_track,
)

__all__ = [
    "VITAL_FILENAME_RE",
    "PayloadFile",
    "RawArchivePayload",
    "VitalSessionMetadata",
    "VitalTrack",
    "VitalTrackRecord",
    "assert_vital_filenames",
    "collect_frame_tracks",
    "iter_vital_files",
    "metadata_track",
    "raw_archive_payload_from_record",
    "raw_archive_payloads_from_jsonl_lines",
    "vital_tracks_by_vrcode_from_raw_archive",
]
