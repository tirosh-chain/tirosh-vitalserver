"""Shared versioned Vital File adapter contracts."""

from __future__ import annotations

from tirosh_vitalserver.vitalfile.reader import (
    VitalDbVitalFileReader,
    VitalFileReadError,
    VitalFileSource,
    read_vital_file_header,
)
from tirosh_vitalserver.vitalfile.stream import (
    STREAM_CHUNK_BYTES,
    VitalFilePacketScanner,
    VitalFilePacketSink,
)
from tirosh_vitalserver.vitalfile.writer import (
    VitalDbVitalFileWriter,
    VitalFileWriteReceipt,
)

__all__ = [
    "STREAM_CHUNK_BYTES",
    "VitalDbVitalFileReader",
    "VitalDbVitalFileWriter",
    "VitalFilePacketScanner",
    "VitalFilePacketSink",
    "VitalFileReadError",
    "VitalFileSource",
    "VitalFileWriteReceipt",
    "read_vital_file_header",
]
