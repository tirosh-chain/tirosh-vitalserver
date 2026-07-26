from __future__ import annotations

import gzip
import math
import struct
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any

import pytest

from tirosh_vitalserver.core.domain.vital_file import VitalFileFormatVersion
from vitalserver_lab.vital_replay import (
    LabReplayGapPolicy,
    LabReplayStringTrackPolicy,
    VitalDBReplaySourceFactory,
    VitalReplaySourceError,
)


class FakeVitalFile:
    def __init__(self, tracks: tuple[SimpleNamespace, ...]) -> None:
        self.dtstart = 100.0
        self.dtend = 102.0
        self.devs = {"Source": SimpleNamespace(name="Source", type="monitor", port="")}
        self.trks = {track.dtname: track for track in tracks}
        self.intervals: dict[str, float] = {}

    def get_track_samples(self, dtname: str, interval: float) -> list[float]:
        self.intervals[dtname] = interval
        track = self.trks[dtname]
        return list(track.samples)


def test_numeric_track_with_zero_sample_rate_is_replayed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="SNUADC/PLETH",
                track_type=1,
                sample_rate=2.0,
                samples=(0.1, 0.2, 0.3, 0.4),
            ),
            track(
                dtname="Solar8000/PLETH_HR",
                track_type=2,
                sample_rate=0.0,
                samples=(72.0, 73.0),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)
    path = vital_path(tmp_path)

    replay = replay_factory().open(path)
    first = replay.frame(offset_seconds=0, output_time=200.0)
    second = replay.frame(offset_seconds=1, output_time=201.0)

    assert source.intervals == {
        "SNUADC/PLETH": 0.5,
        "Solar8000/PLETH_HR": 1.0,
    }
    assert replay.format_version is VitalFileFormatVersion.V3
    assert [track["type"] for track in first.tracks] == ["wav", "num"]
    assert first.tracks[1]["recs"] == [{"dt": 200.0, "val": 72.0}]
    assert second.tracks[1]["recs"] == [{"dt": 201.0, "val": 73.0}]


def test_replay_rejects_file_without_vitalserver_graph_monitor_types(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="SNUADC/PLETH",
                track_type=1,
                sample_rate=2.0,
                samples=(0.1, 0.2, 0.3, 0.4),
                monitor_type=0,
            ),
            track(
                dtname="Solar8000/PLETH_HR",
                track_type=2,
                sample_rate=0.0,
                samples=(72.0, 73.0),
                monitor_type=0,
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    with pytest.raises(VitalReplaySourceError) as error:
        replay_factory().open(vital_path(tmp_path))

    assert error.value.stage == "fileValidation"
    assert error.value.code == "noVitalServerGraphTracks"
    assert str(error.value) == (
        "Vital File contains no VitalServer graph-compatible tracks: sample.vital; "
        "tracks=SNUADC/PLETH(montype=0), Solar8000/PLETH_HR(montype=0)"
    )


def test_waveform_track_requires_positive_sample_rate(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="SNUADC/PLETH",
                track_type=1,
                sample_rate=0.0,
                samples=(),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    with pytest.raises(VitalReplaySourceError) as error:
        replay_factory().open(vital_path(tmp_path))

    assert error.value.stage == "fileValidation"
    assert error.value.code == "invalidWaveformSampleRate"
    assert "Vital waveform track requires a positive sample rate: SNUADC/PLETH" in str(
        error.value
    )


def test_string_track_is_rejected_with_distinct_error(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="Source/Unsupported",
                track_type=5,
                sample_rate=0.0,
                samples=(),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    with pytest.raises(VitalReplaySourceError) as error:
        replay_factory().open(vital_path(tmp_path))

    assert error.value.stage == "fileValidation"
    assert error.value.code == "unsupportedStringTrack"
    assert str(error.value) == (
        "Vital File string track replay is unsupported: Source/Unsupported"
    )


def test_unknown_track_type_is_rejected_explicitly(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="Source/Unsupported",
                track_type=9,
                sample_rate=0.0,
                samples=(),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    with pytest.raises(VitalReplaySourceError) as error:
        replay_factory().open(vital_path(tmp_path))

    assert error.value.code == "unsupportedTrackType"


def test_configured_string_track_skip_keeps_numeric_tracks(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="Source/Label",
                track_type=5,
                sample_rate=0.0,
                samples=(),
            ),
            track(
                dtname="Source/HR",
                track_type=2,
                sample_rate=0.0,
                samples=(72.0, 73.0),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    replay = replay_factory(string_policy=LabReplayStringTrackPolicy.SKIP).open(
        vital_path(tmp_path)
    )

    assert [
        item["sourceTrack"]
        for item in replay.frame(
            offset_seconds=0,
            output_time=200.0,
        ).tracks
    ] == ["Source/HR"]
    assert "Source/Label" not in source.intervals


def test_one_hertz_waveform_is_classified_by_track_type(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="Source/WAVE",
                track_type=1,
                sample_rate=1.0,
                samples=(0.1, 0.2),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    replay = replay_factory().open(vital_path(tmp_path))

    assert replay.frame(offset_seconds=0, output_time=200.0).tracks[0]["type"] == "wav"


def test_numeric_gap_is_not_filled_from_an_older_value(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="Source/WAVE",
                track_type=1,
                sample_rate=1.0,
                samples=(0.1, 0.2),
            ),
            track(
                dtname="Source/HR",
                track_type=2,
                sample_rate=0.0,
                samples=(72.0, math.nan),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    replay = replay_factory().open(vital_path(tmp_path))
    second = replay.frame(offset_seconds=1, output_time=201.0)

    assert [item["sourceTrack"] for item in second.tracks] == ["Source/WAVE"]


def test_configured_gap_failure_reports_track_and_offset(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="Source/HR",
                track_type=2,
                sample_rate=0.0,
                samples=(72.0, math.nan),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)
    replay = replay_factory(gap_policy=LabReplayGapPolicy.FAIL_FRAME).open(
        vital_path(tmp_path)
    )

    with pytest.raises(VitalReplaySourceError) as error:
        replay.frame(offset_seconds=1, output_time=201.0)

    assert error.value.stage == "replayFrame"
    assert error.value.code == "missingTrackRecord"


@pytest.mark.parametrize(
    "version",
    (
        VitalFileFormatVersion.V1,
        VitalFileFormatVersion.V2,
        VitalFileFormatVersion.V3,
    ),
)
def test_replay_factory_accepts_supported_header_versions(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    version: VitalFileFormatVersion,
) -> None:
    source = FakeVitalFile(
        (
            track(
                dtname="Source/HR",
                track_type=2,
                sample_rate=0.0,
                samples=(72.0, 73.0),
            ),
        )
    )
    install_fake_vitaldb(monkeypatch, source)

    replay = replay_factory().open(vital_path(tmp_path, version=version))

    assert replay.format_version is version


def test_replay_factory_rejects_unknown_future_version_before_reader(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(())
    install_fake_vitaldb(monkeypatch, source)

    with pytest.raises(VitalReplaySourceError) as error:
        replay_factory().open(vital_path(tmp_path, version=4))

    assert error.value.stage == "fileValidation"
    assert error.value.code == "unsupportedFormatVersion"


def test_replay_factory_maps_truncated_header_to_replay_error(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = FakeVitalFile(())
    install_fake_vitaldb(monkeypatch, source)
    path = tmp_path / "sample.vital"
    path.write_bytes(gzip.compress(b"VITA"))

    with pytest.raises(VitalReplaySourceError) as error:
        replay_factory().open(path)

    assert error.value.stage == "fileValidation"
    assert error.value.code == "truncatedHeader"


def track(
    *,
    dtname: str,
    track_type: int,
    sample_rate: float,
    samples: tuple[float, ...],
    monitor_type: int | None = None,
) -> SimpleNamespace:
    dname, name = dtname.split("/", maxsplit=1)
    return SimpleNamespace(
        dtname=dtname,
        name=name,
        dname=dname,
        type=track_type,
        fmt=1,
        srate=sample_rate,
        unit="",
        col=0,
        gain=1.0,
        offset=0.0,
        montype=(
            monitor_type
            if monitor_type is not None
            else {1: 8, 2: 9}.get(track_type, 0)
        ),
        mindisp=0,
        maxdisp=100,
        samples=samples,
    )


def install_fake_vitaldb(
    monkeypatch: pytest.MonkeyPatch,
    source: FakeVitalFile,
) -> None:
    module = ModuleType("vitaldb")

    def vital_file(_: str, *, header_only: bool = False) -> Any:
        del header_only
        return source

    module.VitalFile = vital_file  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "vitaldb", module)


def replay_factory(
    *,
    string_policy: LabReplayStringTrackPolicy = LabReplayStringTrackPolicy.REJECT,
    gap_policy: LabReplayGapPolicy = LabReplayGapPolicy.OMIT_TRACK,
) -> VitalDBReplaySourceFactory:
    return VitalDBReplaySourceFactory(
        string_track_policy=string_policy,
        gap_policy=gap_policy,
    )


def vital_path(
    tmp_path: Path,
    *,
    version: VitalFileFormatVersion | int = VitalFileFormatVersion.V3,
) -> Path:
    path = tmp_path / "sample.vital"
    base_header = struct.pack("<hII", -540, 0, 0)
    header_body = base_header
    if int(version) == 3:
        header_body += struct.pack("<ddB", 100.0, 102.0, 0)
    payload = (
        b"VITA"
        + int(version).to_bytes(4, "little")
        + len(header_body).to_bytes(2, "little")
        + header_body
    )
    path.write_bytes(gzip.compress(payload))
    return path
