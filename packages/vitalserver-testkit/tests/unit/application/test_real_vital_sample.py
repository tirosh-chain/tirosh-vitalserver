from __future__ import annotations

from pathlib import Path
from typing import cast

import pytest

from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalFileHeader,
    RealVitalReaderPort,
    RealVitalSampleScenario,
    RealVitalTrackHeader,
    build_real_vital_recorder_payload,
    real_vital_sample_metadata,
    real_vital_track_catalog,
    select_real_vital_tracks,
)
from tirosh_vitalserver.testkit.types.json import JsonObject


def test_bloodbag_sample_uses_real_sphb_and_derived_hct() -> None:
    reader = FakeRealVitalReader(
        tracks=(
            track("Root/PLETH", "Root", "PLETH", "", 8, 62.5),
            track("Root/SPO2", "Root", "SPO2", "%", 10, 1.0),
            track("Root/BPM", "Root", "BPM", "/min", 9, 1.0),
            track("Root/SPHB", "Root", "SPHB", "g/dL", 72, 1.0),
            track("Primus/CO2", "Primus", "CO2", "mmHg", 13, 62.5),
        ),
        samples={
            ("Root/PLETH", 1.0 / 62.5): [1.0] * 200,
            ("Primus/CO2", 1.0 / 62.5): [40.0] * 200,
            ("Root/SPO2", 1.0): [97.0, 98.0, 99.0],
            ("Root/BPM", 1.0): [56.0, 57.0, 58.0],
            ("Root/SPHB", 1.0): [14.0, 13.5, 13.0],
        },
    )

    payload = build_real_vital_recorder_payload(
        reader,
        Path("source.vital"),
        scenario=RealVitalSampleScenario.BLOODBAG,
        room_name="OR-A",
        start_offset_seconds=0,
        duration_seconds=2,
    )
    room = only_room(payload)
    tracks = track_map(room)

    assert set(tracks) == {"PLETH", "SPO2", "BPM", "SPHB", "CO2", "HCT"}
    assert tracks["SPHB"]["montype"] == "SPHB"
    assert tracks["SPHB"]["sourceMontype"] == 72
    assert first_value(tracks["SPHB"]) == 14.0
    assert tracks["HCT"]["dname"] == "LabDerived"
    assert tracks["HCT"]["derivedFormula"] == "HCT percent = SPHB g/dL * 3.0"
    assert first_value(tracks["HCT"]) == 42.0


def test_full_real_sample_preserves_all_source_tracks() -> None:
    reader = FakeRealVitalReader(
        tracks=(
            track("Root/SPHB", "Root", "SPHB", "g/dL", 72, 1.0),
            track("Primus/SET_FIO2", "Primus", "SET_FIO2", "%", 0, 1.0),
        ),
        samples={
            ("Root/SPHB", 1.0): [12.3],
            ("Primus/SET_FIO2", 1.0): [50.0],
        },
    )

    payload = build_real_vital_recorder_payload(
        reader,
        Path("source.vital"),
        scenario=RealVitalSampleScenario.FULL_REAL,
        duration_seconds=1,
    )
    room = only_room(payload)
    tracks = track_map(room)

    assert set(tracks) == {"SPHB", "SET_FIO2"}
    assert tracks["SPHB"]["montype"] == "SPHB"
    assert tracks["SET_FIO2"]["montype"] == "0"
    assert tracks["SET_FIO2"]["sourceMontype"] == 0


def test_bloodbag_sample_requires_sphb_source_track() -> None:
    reader = FakeRealVitalReader(
        tracks=(track("Root/PLETH", "Root", "PLETH", "", 8, 62.5),),
        samples={("Root/PLETH", 1.0 / 62.5): [1.0] * 100},
    )

    with pytest.raises(ValueError, match="bloodbag scenario requires source tracks"):
        build_real_vital_recorder_payload(
            reader,
            Path("source.vital"),
            scenario=RealVitalSampleScenario.BLOODBAG,
        )


def test_scenario_metadata_lists_selected_and_derived_tracks() -> None:
    reader = FakeRealVitalReader(
        tracks=(
            track("Root/PLETH", "Root", "PLETH", "", 8, 62.5),
            track("Root/SPHB", "Root", "SPHB", "g/dL", 72, 1.0),
        ),
        samples={
            ("Root/PLETH", 1.0 / 62.5): [1.0] * 100,
            ("Root/SPHB", 1.0): [14.0],
        },
    )

    metadata = real_vital_sample_metadata(
        reader,
        Path("source.vital"),
        scenario=RealVitalSampleScenario.BLOODBAG,
        start_offset_seconds=10.0,
        duration_seconds=20,
        payload_path=Path("payload.json"),
    )

    assert metadata["sourceVitalFile"] == "source.vital"
    assert metadata["scenario"] == "bloodbag"
    assert metadata["payload"] == "payload.json"
    selected = metadata["selectedTracks"]
    assert isinstance(selected, list)
    selected_tracks = cast(list[JsonObject], selected)
    derived = metadata["derivedTracks"]
    assert isinstance(derived, list)
    derived_tracks = cast(list[JsonObject], derived)
    assert [item["sourceTrack"] for item in selected_tracks] == [
        "Root/PLETH",
        "Root/SPHB",
    ]
    assert derived_tracks[0]["outputName"] == "HCT"


def test_periop_full_selects_primus_and_bx50_tracks() -> None:
    tracks = (
        track("Root/SPHB", "Root", "SPHB", "g/dL", 72, 1.0),
        track("Primus/CO2", "Primus", "CO2", "mmHg", 13, 62.5),
        track("Bx50/ECG1", "Bx50", "ECG1", "mV", 1, 300.0),
    )

    selected = select_real_vital_tracks(
        tracks,
        scenario=RealVitalSampleScenario.PERIOP_FULL,
    )

    assert [track.header.dtname for track in selected] == [
        "Primus/CO2",
        "Bx50/ECG1",
    ]


def test_real_vital_track_catalog_merges_source_headers() -> None:
    reader = FakeRealVitalReader(
        tracks=(
            track("Root/SPHB", "Root", "SPHB", "g/dL", 72, 1.0),
            track("Root/PLETH", "Root", "PLETH", "", 8, 62.5),
        ),
        samples={},
    )

    catalog = real_vital_track_catalog(
        reader,
        (Path("one.vital"), Path("two.vital")),
    )

    assert catalog["filesScanned"] == 2
    assert catalog["uniqueTracks"] == 2
    assert catalog["waveTracks"] == 1
    assert catalog["numericTracks"] == 1
    tracks = catalog["tracks"]
    assert isinstance(tracks, list)
    catalog_tracks = cast(list[JsonObject], tracks)
    sphb = next(item for item in catalog_tracks if item["dtname"] == "Root/SPHB")
    assert sphb["files"] == 2
    assert sphb["montype"] == 72


class FakeRealVitalReader(RealVitalReaderPort):
    def __init__(
        self,
        *,
        tracks: tuple[RealVitalTrackHeader, ...],
        samples: dict[tuple[str, float], list[float]],
    ) -> None:
        self._header = RealVitalFileHeader(
            path=Path("source.vital"),
            dtstart=1000.0,
            dtend=1100.0,
            tracks=tracks,
        )
        self._samples = samples

    def header(self, path: Path) -> RealVitalFileHeader:
        del path
        return self._header

    def track_samples(
        self,
        path: Path,
        dtname: str,
        *,
        interval_seconds: float,
    ) -> list[float]:
        del path
        return self._samples[(dtname, interval_seconds)]


def track(
    dtname: str,
    dname: str,
    name: str,
    unit: str,
    montype: int,
    srate: float,
) -> RealVitalTrackHeader:
    return RealVitalTrackHeader(
        dtname=dtname,
        dname=dname,
        name=name,
        unit=unit,
        montype=montype,
        srate=srate,
        mindisp=0,
        maxdisp=100,
    )


def only_room(payload: JsonObject) -> JsonObject:
    rooms = payload["rooms"]
    assert isinstance(rooms, dict)
    room = next(iter(rooms.values()))
    assert isinstance(room, dict)
    return room


def track_map(room: JsonObject) -> dict[str, JsonObject]:
    tracks = room["trks"]
    assert isinstance(tracks, list)
    result: dict[str, JsonObject] = {}
    for item in tracks:
        assert isinstance(item, dict)
        name = item["name"]
        assert isinstance(name, str)
        result[name] = item
    return result


def first_value(track_payload: JsonObject) -> float:
    records = track_payload["recs"]
    assert isinstance(records, list)
    first_record = records[0]
    assert isinstance(first_record, dict)
    value = first_record["val"]
    assert isinstance(value, int | float)
    return float(value)
