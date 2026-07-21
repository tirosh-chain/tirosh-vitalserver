from __future__ import annotations

import gzip
import struct
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    VitalFileFormatError,
    VitalFileFormatVersion,
    VitalTrackKind,
)
from tirosh_vitalserver.vitalfile import (
    VitalDbVitalFileReader,
    VitalFileReadError,
)


class FakeVitalFile:
    def __init__(self) -> None:
        self.dtstart = 100.0
        self.dtend = 102.0
        self.devs = {
            "Source": SimpleNamespace(
                name="Source",
                type="monitor",
                port="",
            )
        }
        self.trks = {
            "Source/WAVE": source_track(
                name="WAVE",
                track_type=1,
                sample_rate=1.0,
            ),
            "Source/HR": source_track(
                name="HR",
                track_type=2,
                sample_rate=0.0,
            ),
            "Source/LABEL": source_track(
                name="LABEL",
                track_type=5,
                sample_rate=0.0,
            ),
        }
        self.sample_reads: list[tuple[str, float]] = []

    def get_track_samples(self, dtname: str, interval: float) -> list[float]:
        self.sample_reads.append((dtname, interval))
        return [72.0, 73.0]


@pytest.mark.parametrize(
    "version",
    (
        VitalFileFormatVersion.V1,
        VitalFileFormatVersion.V2,
        VitalFileFormatVersion.V3,
    ),
)
def test_reader_dispatches_supported_versions_to_one_canonical_manifest(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    version: VitalFileFormatVersion,
) -> None:
    fake = FakeVitalFile()
    constructor_paths = install_fake_vitaldb(monkeypatch, fake)
    path = vital_path(tmp_path, version=version)

    source = VitalDbVitalFileReader().open(path)

    assert constructor_paths == [(str(path), False)]
    assert source.manifest.header.format_version is version
    assert source.manifest.duration_seconds == 2.0
    assert [track.kind for track in source.manifest.tracks] == [
        VitalTrackKind.WAVEFORM,
        VitalTrackKind.NUMERIC,
        VitalTrackKind.STRING,
    ]
    assert source.manifest.track("Source/WAVE").sample_rate == 1.0
    assert source.manifest.track("Source/HR").sample_rate == 0.0


def test_reader_rejects_future_version_before_vitaldb_decode(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    constructor_paths = install_fake_vitaldb(monkeypatch, FakeVitalFile())

    with pytest.raises(VitalFileFormatError) as error:
        VitalDbVitalFileReader().open(vital_path(tmp_path, version=4))

    assert error.value.code == "unsupportedFormatVersion"
    assert constructor_paths == []


@pytest.mark.parametrize(
    ("version", "expected_header_only"),
    [
        (VitalFileFormatVersion.V1, False),
        (VitalFileFormatVersion.V2, False),
        (VitalFileFormatVersion.V3, True),
    ],
)
def test_inspect_uses_version_specific_record_policy(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    version: VitalFileFormatVersion,
    expected_header_only: bool,
) -> None:
    constructor_calls = install_fake_vitaldb(monkeypatch, FakeVitalFile())
    path = vital_path(tmp_path, version=version)

    manifest = VitalDbVitalFileReader().inspect(path)

    assert manifest.header.format_version is version
    assert constructor_calls == [(str(path), expected_header_only)]


def test_reader_rejects_waveform_without_positive_rate(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake = FakeVitalFile()
    fake.trks = {
        "Source/WAVE": source_track(
            name="WAVE",
            track_type=1,
            sample_rate=0.0,
        )
    }
    install_fake_vitaldb(monkeypatch, fake)

    with pytest.raises(VitalFileFormatError) as error:
        VitalDbVitalFileReader().open(vital_path(tmp_path))

    assert error.value.code == "invalidWaveformSampleRate"


def test_source_validates_track_and_interval_before_sample_read(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake = FakeVitalFile()
    install_fake_vitaldb(monkeypatch, fake)
    source = VitalDbVitalFileReader().open(vital_path(tmp_path))

    assert source.track_samples("Source/HR", interval_seconds=1.0) == [72.0, 73.0]
    assert fake.sample_reads == [("Source/HR", 1.0)]

    with pytest.raises(VitalFileReadError) as error:
        source.track_samples("Source/HR", interval_seconds=0.0)
    assert error.value.code == "invalidSampleInterval"

    with pytest.raises(VitalFileFormatError) as error:
        source.track_samples("Source/MISSING", interval_seconds=1.0)
    assert error.value.code == "trackNotFound"


def source_track(
    *,
    name: str,
    track_type: int,
    sample_rate: float,
) -> SimpleNamespace:
    return SimpleNamespace(
        dtname=f"Source/{name}",
        dname="Source",
        name=name,
        type=track_type,
        fmt=1,
        unit="",
        srate=sample_rate,
        mindisp=0.0,
        maxdisp=100.0,
        col=0,
        gain=1.0,
        offset=0.0,
        montype=0,
    )


def install_fake_vitaldb(
    monkeypatch: pytest.MonkeyPatch,
    source: FakeVitalFile,
) -> list[tuple[str, bool]]:
    module = ModuleType("vitaldb")
    constructor_paths: list[tuple[str, bool]] = []

    def vital_file(path: str, *, header_only: bool = False) -> Any:
        constructor_paths.append((path, header_only))
        return source

    module.VitalFile = vital_file  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "vitaldb", module)
    return constructor_paths


def vital_path(
    tmp_path: Path,
    *,
    version: VitalFileFormatVersion | int = VitalFileFormatVersion.V3,
) -> Path:
    path = tmp_path / "sample.vital"
    body = struct.pack("<hII", -540, 0, 0)
    if int(version) == 3:
        body += struct.pack("<ddB", 100.0, 102.0, 0)
    payload = (
        b"VITA"
        + int(version).to_bytes(4, "little")
        + len(body).to_bytes(2, "little")
        + body
    )
    path.write_bytes(gzip.compress(payload))
    return path
