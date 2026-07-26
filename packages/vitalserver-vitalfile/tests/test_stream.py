from __future__ import annotations

import gzip
import struct
from dataclasses import dataclass, field
from pathlib import Path

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    VitalDeviceDefinition,
    VitalFileFormatVersion,
    VitalFileHeader,
    VitalTrackDefinition,
    VitalTrackKind,
)
from tirosh_vitalserver.vitalfile import (
    STREAM_CHUNK_BYTES,
    VitalFilePacketScanner,
    VitalFileReadError,
)


@dataclass
class RecordingSink:
    header: VitalFileHeader | None = None
    devices: list[tuple[int, VitalDeviceDefinition]] = field(default_factory=list)
    tracks: list[tuple[int, VitalTrackDefinition]] = field(default_factory=list)
    waveform_chunks: list[tuple[int, float, int, int, bytes]] = field(
        default_factory=list
    )
    numeric_records: list[tuple[int, float, float]] = field(default_factory=list)
    string_records: list[tuple[int, float, str]] = field(default_factory=list)

    def on_header(self, header: VitalFileHeader) -> None:
        self.header = header

    def on_device(
        self,
        *,
        device_id: int,
        device: VitalDeviceDefinition,
    ) -> None:
        self.devices.append((device_id, device))

    def on_track(self, *, track_id: int, track: VitalTrackDefinition) -> None:
        self.tracks.append((track_id, track))

    def on_waveform_chunk(
        self,
        *,
        track_id: int,
        recorded_at: float,
        sample_offset: int,
        sample_count: int,
        raw_values: bytes,
    ) -> None:
        self.waveform_chunks.append(
            (track_id, recorded_at, sample_offset, sample_count, raw_values)
        )

    def on_numeric_record(
        self,
        *,
        track_id: int,
        recorded_at: float,
        value: float,
    ) -> None:
        self.numeric_records.append((track_id, recorded_at, value))

    def on_string_record(
        self,
        *,
        track_id: int,
        recorded_at: float,
        value: str,
    ) -> None:
        self.string_records.append((track_id, recorded_at, value))


@pytest.mark.parametrize(
    "version",
    (
        VitalFileFormatVersion.V1,
        VitalFileFormatVersion.V2,
        VitalFileFormatVersion.V3,
    ),
)
def test_scanner_streams_supported_versions_to_explicit_events(
    tmp_path: Path,
    version: VitalFileFormatVersion,
) -> None:
    path = tmp_path / f"Source_260721_12000{int(version)}.vital"
    path.write_bytes(gzip.compress(vital_payload(version)))
    sink = RecordingSink()

    header = VitalFilePacketScanner().scan(path, sink)

    assert header.format_version is version
    assert sink.header == header
    assert [(item[0], item[1].name) for item in sink.devices] == [(1, "Source")]
    assert {
        item[1].dtname: (item[1].kind, item[1].sample_rate) for item in sink.tracks
    } == {
        "Source/WAVE": (VitalTrackKind.WAVEFORM, 2.0),
        "Source/HR": (VitalTrackKind.NUMERIC, 0.0),
        "Source/LABEL": (VitalTrackKind.STRING, 0.0),
    }
    assert sink.waveform_chunks == [(1, 100.0, 0, 2, struct.pack("<ff", 1.25, 2.5))]
    assert sink.numeric_records == [(2, 100.0, 72.0)]
    assert sink.string_records == [(3, 100.0, "ready")]


def test_scanner_splits_packed_waveform_record_into_bounded_chunks(
    tmp_path: Path,
) -> None:
    sample_count = STREAM_CHUNK_BYTES // 4 * 3 + 7
    samples = struct.pack(f"<{sample_count}f", *([1.25] * sample_count))
    path = tmp_path / "Source_260721_120003.vital"
    path.write_bytes(
        gzip.compress(
            vital_payload(
                VitalFileFormatVersion.V3,
                waveform_value=struct.pack("<I", sample_count) + samples,
            )
        )
    )
    sink = RecordingSink()

    VitalFilePacketScanner().scan(path, sink)

    assert len(sink.waveform_chunks) == 4
    assert max(len(item[4]) for item in sink.waveform_chunks) <= STREAM_CHUNK_BYTES
    assert sum(item[3] for item in sink.waveform_chunks) == sample_count
    assert [item[2] for item in sink.waveform_chunks] == [
        0,
        STREAM_CHUNK_BYTES // 4,
        STREAM_CHUNK_BYTES // 2,
        STREAM_CHUNK_BYTES // 4 * 3,
    ]


@pytest.mark.parametrize("company", ("", "Draeger"))
def test_scanner_accepts_legacy_device_company(
    tmp_path: Path,
    company: str,
) -> None:
    path = tmp_path / "Source_260721_120003.vital"
    path.write_bytes(
        gzip.compress(
            vital_payload(
                VitalFileFormatVersion.V3,
                device_suffix=text(company),
            )
        )
    )
    sink = RecordingSink()

    VitalFilePacketScanner().scan(path, sink)

    assert [(device_id, device.port) for device_id, device in sink.devices] == [
        (1, "test-port")
    ]


def test_scanner_rejects_truncated_legacy_device_company(tmp_path: Path) -> None:
    path = tmp_path / "Source_260721_120003.vital"
    path.write_bytes(
        gzip.compress(
            vital_payload(
                VitalFileFormatVersion.V3,
                device_suffix=struct.pack("<I", 1),
            )
        )
    )

    with pytest.raises(VitalFileReadError) as error:
        VitalFilePacketScanner().scan(path, RecordingSink())

    assert error.value.code == "invalidDeviceMetadata"


def test_scanner_uses_latest_repeated_device_definition(tmp_path: Path) -> None:
    path = tmp_path / "Source_260721_120003.vital"
    path.write_bytes(
        gzip.compress(
            vital_payload(
                VitalFileFormatVersion.V3,
                replacement_device_name="Replacement",
            )
        )
    )
    sink = RecordingSink()

    VitalFilePacketScanner().scan(path, sink)

    assert [(device_id, device.name) for device_id, device in sink.devices] == [
        (1, "Source"),
        (1, "Replacement"),
    ]
    assert {track.dtname for _, track in sink.tracks} == {
        "Replacement/WAVE",
        "Replacement/HR",
        "Replacement/LABEL",
    }


def test_scanner_ignores_record_for_unknown_track_id(tmp_path: Path) -> None:
    path = tmp_path / "Source_260721_120003.vital"
    path.write_bytes(
        gzip.compress(
            vital_payload(
                VitalFileFormatVersion.V3,
                record_prefix=record_packet(999, struct.pack("<f", 10.0)),
            )
        )
    )
    sink = RecordingSink()

    VitalFilePacketScanner().scan(path, sink)

    assert sink.numeric_records == [(2, 100.0, 72.0)]


def test_scanner_reports_truncated_large_record_without_partial_success(
    tmp_path: Path,
) -> None:
    payload = vital_payload(VitalFileFormatVersion.V3)
    path = tmp_path / "Source_260721_120003.vital"
    path.write_bytes(gzip.compress(payload[:-2]))

    with pytest.raises(VitalFileReadError) as error:
        VitalFilePacketScanner().scan(path, RecordingSink())

    assert error.value.code == "truncatedPacket"


def vital_payload(
    version: VitalFileFormatVersion,
    *,
    waveform_value: bytes | None = None,
    device_suffix: bytes = b"",
    replacement_device_name: str | None = None,
    record_prefix: bytes = b"",
) -> bytes:
    header_body = struct.pack("<hI4B", -540, 7, 1, 2, 3, 4)
    if version is VitalFileFormatVersion.V3:
        header_body += struct.pack("<ddB", 100.0, 101.0, 1)
    device_packets = [
        packet(
            9,
            struct.pack("<I", 1)
            + text("monitor")
            + text("Source")
            + text("test-port")
            + device_suffix,
        )
    ]
    if replacement_device_name is not None:
        device_packets.append(
            packet(
                9,
                struct.pack("<I", 1)
                + text("monitor")
                + text(replacement_device_name)
                + text("replacement-port"),
            )
        )
    return b"".join(
        (
            b"VITA",
            struct.pack("<I", int(version)),
            struct.pack("<H", len(header_body)),
            header_body,
            *device_packets,
            track_packet(
                1,
                kind=VitalTrackKind.WAVEFORM,
                name="WAVE",
                sample_rate=2.0,
            ),
            track_packet(
                2,
                kind=VitalTrackKind.NUMERIC,
                name="HR",
                sample_rate=0.0,
            ),
            track_packet(
                3,
                kind=VitalTrackKind.STRING,
                name="LABEL",
                sample_rate=0.0,
            ),
            record_prefix,
            record_packet(
                1,
                waveform_value or struct.pack("<Iff", 2, 1.25, 2.5),
            ),
            record_packet(2, struct.pack("<f", 72.0)),
            record_packet(3, struct.pack("<I", 0) + text("ready")),
        )
    )


def track_packet(
    track_id: int,
    *,
    kind: VitalTrackKind,
    name: str,
    sample_rate: float,
) -> bytes:
    body = b"".join(
        (
            struct.pack("<HBB", track_id, int(kind), 1),
            text(name),
            text(""),
            struct.pack(
                "<ffIfddBI",
                0.0,
                200.0,
                0,
                sample_rate,
                1.0,
                0.0,
                0,
                1,
            ),
        )
    )
    return packet(0, body)


def record_packet(track_id: int, value: bytes) -> bytes:
    return packet(1, struct.pack("<HdH", 10, 100.0, track_id) + value)


def packet(packet_type: int, body: bytes) -> bytes:
    return struct.pack("<BI", packet_type, len(body)) + body


def text(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<I", len(encoded)) + encoded
