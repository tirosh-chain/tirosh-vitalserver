from __future__ import annotations

import gzip
import sqlite3
import struct
from pathlib import Path

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    VitalFileFormatVersion,
    VitalTrack,
    VitalTrackKind,
    VitalTrackRecord,
)
from tirosh_vitalserver.vitalfile import VitalDbVitalFileWriter
from vitalserver_lab.vital_replay import (
    LabReplayGapPolicy,
    LabReplayStringTrackPolicy,
    VitalReplaySourceError,
)
from vitalserver_lab.vital_replay_spool import StreamingVitalReplaySourceFactory


@pytest.mark.parametrize(
    "version",
    (
        VitalFileFormatVersion.V1,
        VitalFileFormatVersion.V2,
        VitalFileFormatVersion.V3,
    ),
)
def test_streaming_replay_spool_preserves_v1_v2_v3_track_meaning(
    tmp_path: Path,
    version: VitalFileFormatVersion,
) -> None:
    path = write_vital(tmp_path, version=version)
    spool_root = tmp_path / "spool"
    spool_root.mkdir()
    replay = replay_factory(spool_root=spool_root).open(path)

    first = replay.frame(offset_seconds=0, output_time=200.0)
    second = replay.frame(offset_seconds=1, output_time=201.0)

    assert replay.format_version is version
    assert replay.duration_seconds == 2
    assert [track["type"] for track in first.tracks] == ["wav", "num"]
    assert first.tracks[0]["recs"] == [{"dt": 200.0, "val": [1.25, 2.5]}]
    assert second.tracks[0]["recs"] == [{"dt": 201.0, "val": [3.75, 5.0]}]
    assert first.tracks[1]["recs"] == [{"dt": 200.0, "val": 72.0}]
    assert second.tracks[1]["recs"] == [{"dt": 201.0, "val": 73.0}]
    spool_directory = replay.spool_path.parent
    assert replay.spool_path.is_file()

    replay.close()

    assert not spool_directory.exists()


def test_streaming_replay_spool_stores_large_waveform_in_bounded_rows(
    tmp_path: Path,
) -> None:
    sample_rate = 20_000.0
    samples = [1.25] * 40_000
    path = write_vital(
        tmp_path,
        version=VitalFileFormatVersion.V3,
        sample_rate=sample_rate,
        waveform_samples=samples,
    )
    replay = replay_factory(spool_root=tmp_path).open(path)

    with sqlite3.connect(replay.spool_path) as connection:
        maximum_row, row_count = connection.execute(
            "SELECT MAX(length(raw_values)), COUNT(*) FROM waveform_chunks"
        ).fetchone()

    assert maximum_row <= 64 * 1024
    assert row_count >= 3
    frame = replay.frame(offset_seconds=0, output_time=200.0)
    assert len(frame.tracks[0]["recs"][0]["val"]) == 20_000
    replay.close()


def test_streaming_replay_spool_rejects_string_policy_and_cleans_partial_spool(
    tmp_path: Path,
) -> None:
    path = write_vital(tmp_path, version=VitalFileFormatVersion.V3)
    spool_root = tmp_path / "spool"
    spool_root.mkdir()

    with pytest.raises(VitalReplaySourceError) as error:
        StreamingVitalReplaySourceFactory(
            string_track_policy=LabReplayStringTrackPolicy.REJECT,
            gap_policy=LabReplayGapPolicy.OMIT_TRACK,
            spool_root=spool_root,
        ).open(path)

    assert error.value.code == "unsupportedStringTrack"
    assert list(spool_root.iterdir()) == []


def test_streaming_replay_spool_rejects_unbounded_frame_allocation(
    tmp_path: Path,
) -> None:
    path = write_vital(
        tmp_path,
        version=VitalFileFormatVersion.V3,
        sample_rate=100_001.0,
        waveform_samples=[1.25],
    )

    with pytest.raises(VitalReplaySourceError) as error:
        replay_factory(spool_root=tmp_path).open(path)

    assert error.value.code == "replayFrameTooLarge"


def test_streaming_replay_spool_reports_reads_after_explicit_close(
    tmp_path: Path,
) -> None:
    replay = replay_factory(spool_root=tmp_path).open(
        write_vital(tmp_path, version=VitalFileFormatVersion.V3)
    )
    replay.close()

    with pytest.raises(VitalReplaySourceError) as error:
        replay.frame(offset_seconds=0, output_time=200.0)

    assert error.value.code == "replaySpoolUnavailable"


def test_streaming_replay_reads_canonical_writer_artifact(tmp_path: Path) -> None:
    path = tmp_path / "canonical.vital"
    VitalDbVitalFileWriter().write(
        path,
        started_at=100.0,
        ended_at=102.0,
        tracks=(
            VitalTrack(
                dtname="Source/WAVE",
                kind=VitalTrackKind.WAVEFORM,
                records=(
                    VitalTrackRecord(dt=100.0, value=[1.25, 2.5]),
                    VitalTrackRecord(dt=101.0, value=[3.75, 5.0]),
                ),
                srate=2.0,
                unit="",
                mindisp=0.0,
                maxdisp=200.0,
                montype=0,
            ),
            VitalTrack(
                dtname="Source/HR",
                kind=VitalTrackKind.NUMERIC,
                records=(
                    VitalTrackRecord(dt=100.0, value=72.0),
                    VitalTrackRecord(dt=101.0, value=73.0),
                ),
                srate=0.0,
                unit="/min",
                mindisp=0.0,
                maxdisp=200.0,
                montype=2,
            ),
            VitalTrack(
                dtname="Source/LABEL",
                kind=VitalTrackKind.STRING,
                records=(VitalTrackRecord(dt=100.0, value="ready"),),
                srate=0.0,
                unit="",
                mindisp=0.0,
                maxdisp=0.0,
                montype=0,
            ),
        ),
    )

    replay = replay_factory(spool_root=tmp_path).open(path)

    first = {
        track["sourceTrack"]: track
        for track in replay.frame(offset_seconds=0, output_time=200.0).tracks
    }
    second = {
        track["sourceTrack"]: track
        for track in replay.frame(offset_seconds=1, output_time=201.0).tracks
    }
    assert first["Source/WAVE"]["recs"] == [{"dt": 200.0, "val": [1.25, 2.5]}]
    assert second["Source/HR"]["recs"] == [{"dt": 201.0, "val": 73.0}]
    replay.close()


def replay_factory(*, spool_root: Path) -> StreamingVitalReplaySourceFactory:
    return StreamingVitalReplaySourceFactory(
        string_track_policy=LabReplayStringTrackPolicy.SKIP,
        gap_policy=LabReplayGapPolicy.OMIT_TRACK,
        spool_root=spool_root,
    )


def write_vital(
    tmp_path: Path,
    *,
    version: VitalFileFormatVersion,
    sample_rate: float = 2.0,
    waveform_samples: list[float] | None = None,
) -> Path:
    values = waveform_samples or [1.25, 2.5, 3.75, 5.0]
    started_at = 100.0
    ended_at = started_at + len(values) / sample_rate
    header_body = struct.pack("<hI4B", -540, 7, 1, 2, 3, 4)
    if version is VitalFileFormatVersion.V3:
        header_body += struct.pack("<ddB", started_at, ended_at, 1)
    payload = b"".join(
        (
            b"VITA",
            struct.pack("<I", int(version)),
            struct.pack("<H", len(header_body)),
            header_body,
            packet(
                9,
                struct.pack("<I", 1)
                + text("monitor")
                + text("Source")
                + text("test-port"),
            ),
            track_packet(
                1,
                kind=VitalTrackKind.WAVEFORM,
                name="WAVE",
                sample_rate=sample_rate,
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
            record_packet(
                1,
                struct.pack("<I", len(values))
                + struct.pack(f"<{len(values)}f", *values),
                recorded_at=started_at,
            ),
            record_packet(2, struct.pack("<f", 72.0), recorded_at=started_at),
            record_packet(2, struct.pack("<f", 73.0), recorded_at=started_at + 1),
            record_packet(
                3,
                struct.pack("<I", 0) + text("ready"),
                recorded_at=started_at,
            ),
        )
    )
    path = tmp_path / f"Source_260721_12000{int(version)}.vital"
    path.write_bytes(gzip.compress(payload))
    return path


def track_packet(
    track_id: int,
    *,
    kind: VitalTrackKind,
    name: str,
    sample_rate: float,
) -> bytes:
    return packet(
        0,
        b"".join(
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
        ),
    )


def record_packet(track_id: int, value: bytes, *, recorded_at: float) -> bytes:
    return packet(1, struct.pack("<HdH", 10, recorded_at, track_id) + value)


def packet(packet_type: int, body: bytes) -> bytes:
    return struct.pack("<BI", packet_type, len(body)) + body


def text(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<I", len(encoded)) + encoded
