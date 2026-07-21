"""Shared `.vital` file domain contracts."""

from __future__ import annotations

from tirosh_vitalserver.core.domain.vital_file.canonical import (
    VitalDeviceDefinition,
    VitalFileManifest,
    VitalTrackDefinition,
)
from tirosh_vitalserver.core.domain.vital_file.discovery import (
    iter_vital_files,
)
from tirosh_vitalserver.core.domain.vital_file.format import (
    VITAL_BASE_HEADER_LENGTH,
    VITAL_HEADER_PREFIX_LENGTH,
    VITAL_MAGIC,
    VITAL_PACKED_HEADER_LENGTH,
    VITAL_TIMED_HEADER_LENGTH,
    VitalFileFormatVersion,
    VitalFileHeader,
    VitalTrackKind,
    probe_vital_header,
)
from tirosh_vitalserver.core.domain.vital_file.models import PayloadFile
from tirosh_vitalserver.core.domain.vital_file.policy import (
    VITAL_FILENAME_RE,
    assert_vital_filenames,
)
from tirosh_vitalserver.core.domain.vital_file.raw_archive import (
    RawArchivePayload,
    RawArchiveVitalGroup,
    iter_raw_archive_payloads_from_jsonl_lines,
    raw_archive_payload_from_record,
    raw_archive_payloads_from_jsonl_lines,
    vital_groups_from_raw_archive,
    vital_tracks_by_vrcode_from_raw_archive,
)
from tirosh_vitalserver.core.domain.vital_file.session_recording import (
    VitalSessionMetadata,
    VitalTrack,
    VitalTrackRecord,
    collect_frame_tracks,
    metadata_track,
)
from tirosh_vitalserver.core.errors import (
    RawArchiveDecodeError,
    VitalFileFormatError,
)

__all__ = [
    "VITAL_BASE_HEADER_LENGTH",
    "VITAL_FILENAME_RE",
    "VITAL_HEADER_PREFIX_LENGTH",
    "VITAL_MAGIC",
    "VITAL_PACKED_HEADER_LENGTH",
    "VITAL_TIMED_HEADER_LENGTH",
    "PayloadFile",
    "RawArchiveDecodeError",
    "RawArchivePayload",
    "RawArchiveVitalGroup",
    "VitalDeviceDefinition",
    "VitalFileFormatError",
    "VitalFileFormatVersion",
    "VitalFileHeader",
    "VitalFileManifest",
    "VitalSessionMetadata",
    "VitalTrack",
    "VitalTrackDefinition",
    "VitalTrackKind",
    "VitalTrackRecord",
    "assert_vital_filenames",
    "collect_frame_tracks",
    "iter_raw_archive_payloads_from_jsonl_lines",
    "iter_vital_files",
    "metadata_track",
    "probe_vital_header",
    "raw_archive_payload_from_record",
    "raw_archive_payloads_from_jsonl_lines",
    "vital_groups_from_raw_archive",
    "vital_tracks_by_vrcode_from_raw_archive",
]
