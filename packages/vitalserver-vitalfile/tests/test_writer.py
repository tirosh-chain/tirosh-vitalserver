from __future__ import annotations

import gzip
from pathlib import Path

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    VitalFileFormatVersion,
    VitalTrack,
    VitalTrackKind,
    VitalTrackRecord,
)
from tirosh_vitalserver.core.types.json import JsonValue
from tirosh_vitalserver.vitalfile import (
    VitalDbVitalFileReader,
    VitalDbVitalFileWriter,
)


def test_writer_emits_verified_v3_with_explicit_track_kinds(tmp_path: Path) -> None:
    path = tmp_path / "Source_260721_120000.vital"
    tracks = (
        track(
            "Source/WAVE",
            VitalTrackKind.WAVEFORM,
            1.0,
            [0.1],
        ),
        track("Source/HR", VitalTrackKind.NUMERIC, 0.0, 72.0),
        track("Source/LABEL", VitalTrackKind.STRING, 0.0, "ready"),
    )

    receipt = VitalDbVitalFileWriter().write(
        path,
        started_at=100.0,
        ended_at=101.0,
        tracks=tracks,
    )

    assert receipt.format_version is VitalFileFormatVersion.V3
    assert receipt.header_length == 27
    assert receipt.track_count == 3
    assert receipt.size_bytes > 0
    decompressed = gzip.decompress(path.read_bytes())
    assert int.from_bytes(decompressed[4:8], "little") == 3
    assert int.from_bytes(decompressed[8:10], "little") == 27
    manifest = VitalDbVitalFileReader().inspect(path)
    assert {item.dtname: item.kind for item in manifest.tracks} == {
        "Source/WAVE": VitalTrackKind.WAVEFORM,
        "Source/HR": VitalTrackKind.NUMERIC,
        "Source/LABEL": VitalTrackKind.STRING,
    }


@pytest.mark.parametrize(
    ("kind", "sample_rate", "value", "message"),
    [
        (VitalTrackKind.WAVEFORM, 1.0, 72.0, "non-empty array"),
        (VitalTrackKind.NUMERIC, 0.0, [72.0], "must be numeric"),
        (VitalTrackKind.STRING, 0.0, 72.0, "must be a string"),
    ],
)
def test_writer_does_not_coerce_values_between_track_kinds(
    tmp_path: Path,
    kind: VitalTrackKind,
    sample_rate: float,
    value: JsonValue,
    message: str,
) -> None:
    path = tmp_path / "invalid.vital"

    with pytest.raises(ValueError, match=message):
        VitalDbVitalFileWriter().write(
            path,
            started_at=100.0,
            ended_at=101.0,
            tracks=(track("Source/INVALID", kind, sample_rate, value),),
        )


@pytest.mark.parametrize(
    ("kind", "sample_rate", "message"),
    [
        (VitalTrackKind.WAVEFORM, 0.0, "requires positive sample rate"),
        (VitalTrackKind.NUMERIC, 1.0, "requires zero sample rate"),
        (VitalTrackKind.STRING, 1.0, "requires zero sample rate"),
    ],
)
def test_writer_rejects_invalid_track_rate_before_creating_an_artifact(
    tmp_path: Path,
    kind: VitalTrackKind,
    sample_rate: float,
    message: str,
) -> None:
    path = tmp_path / "invalid-rate.vital"

    with pytest.raises(ValueError, match=message):
        VitalDbVitalFileWriter().write(
            path,
            started_at=100.0,
            ended_at=101.0,
            tracks=(
                track(
                    "Source/INVALID",
                    kind,
                    sample_rate,
                    ([72.0] if kind is VitalTrackKind.WAVEFORM else 72.0),
                ),
            ),
        )

    assert not path.exists()


def track(
    dtname: str,
    kind: VitalTrackKind,
    sample_rate: float,
    value: JsonValue,
) -> VitalTrack:
    return VitalTrack(
        dtname=dtname,
        kind=kind,
        records=(VitalTrackRecord(dt=100.0, value=value),),
        srate=sample_rate,
        unit="",
        mindisp=0.0,
        maxdisp=100.0,
        montype=0,
    )
