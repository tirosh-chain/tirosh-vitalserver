from __future__ import annotations

import gzip
import struct
from pathlib import Path

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    VitalFileFormatVersion,
    VitalTrackKind,
)
from tirosh_vitalserver.vitalfile import VitalDbVitalFileReader


@pytest.mark.parametrize(
    "version",
    (
        VitalFileFormatVersion.V1,
        VitalFileFormatVersion.V2,
        VitalFileFormatVersion.V3,
    ),
)
def test_wire_compatibility_corpus_normalizes_to_one_manifest(
    tmp_path: Path,
    version: VitalFileFormatVersion,
) -> None:
    path = tmp_path / f"Source_260721_12000{int(version)}.vital"
    path.write_bytes(gzip.compress(_vital_payload(version)))

    source = VitalDbVitalFileReader().open(path)

    assert source.manifest.header.format_version is version
    assert source.manifest.started_at == 100.0
    assert source.manifest.ended_at == 101.0
    devices = [
        (device.name, device.device_type, device.port)
        for device in source.manifest.devices
    ]
    assert devices == [("Source", "monitor", "test-port")]
    assert {
        track.dtname: (track.kind, track.sample_rate)
        for track in source.manifest.tracks
    } == {
        "Source/WAVE": (VitalTrackKind.WAVEFORM, 2.0),
        "Source/HR": (VitalTrackKind.NUMERIC, 0.0),
        "Source/LABEL": (VitalTrackKind.STRING, 0.0),
    }
    waveform = source.track_samples("Source/WAVE", interval_seconds=0.5)
    numeric = source.track_samples("Source/HR", interval_seconds=1.0)
    assert list(waveform) == pytest.approx([1.25, 2.5])
    assert list(numeric) == pytest.approx([72.0])


def _vital_payload(version: VitalFileFormatVersion) -> bytes:
    header_body = struct.pack("<hI4B", -540, 7, 1, 2, 3, 4)
    if version is VitalFileFormatVersion.V3:
        header_body += struct.pack("<ddB", 100.0, 101.0, 0)

    return b"".join(
        (
            b"VITA",
            struct.pack("<I", int(version)),
            struct.pack("<H", len(header_body)),
            header_body,
            _packet(
                9,
                struct.pack("<I", 1)
                + _text("monitor")
                + _text("Source")
                + _text("test-port"),
            ),
            _track_packet(
                1,
                kind=VitalTrackKind.WAVEFORM,
                name="WAVE",
                sample_rate=2.0,
            ),
            _track_packet(2, kind=VitalTrackKind.NUMERIC, name="HR", sample_rate=0.0),
            _track_packet(3, kind=VitalTrackKind.STRING, name="LABEL", sample_rate=0.0),
            _record_packet(1, struct.pack("<Iff", 2, 1.25, 2.5)),
            _record_packet(2, struct.pack("<f", 72.0)),
            _record_packet(3, struct.pack("<I", 0) + _text("ready")),
        )
    )


def _track_packet(
    track_id: int,
    *,
    kind: VitalTrackKind,
    name: str,
    sample_rate: float,
) -> bytes:
    body = b"".join(
        (
            struct.pack("<HBB", track_id, int(kind), 1),
            _text(name),
            _text(""),
            struct.pack("<ffIfddBI", 0.0, 200.0, 0, sample_rate, 1.0, 0.0, 0, 1),
        )
    )
    return _packet(0, body)


def _record_packet(track_id: int, value: bytes) -> bytes:
    return _packet(1, struct.pack("<HdH", 10, 100.0, track_id) + value)


def _packet(packet_type: int, body: bytes) -> bytes:
    return struct.pack("<BI", packet_type, len(body)) + body


def _text(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<I", len(encoded)) + encoded
