"""Build recorder payload samples from explicit real `.vital` inputs."""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from tirosh_vitalserver.testkit.types.json import JsonArray, JsonObject


class RealVitalSampleScenario(StrEnum):
    """Track selection scenarios for real `.vital` sample extraction."""

    BASIC_MONITOR = "basic_monitor"
    PERIOP_FULL = "periop_full"
    BLOODBAG = "bloodbag"
    ROOT_SEDATION = "root_sedation"
    FULL_REAL = "full_real"


@dataclass(frozen=True, slots=True)
class RealVitalTrackHeader:
    """Explicit source track state read from a `.vital` file header."""

    dtname: str
    dname: str
    name: str
    unit: str
    montype: int
    srate: float
    mindisp: float
    maxdisp: float


@dataclass(frozen=True, slots=True)
class RealVitalFileHeader:
    """Explicit source file state needed to extract recorder samples."""

    path: Path
    dtstart: float
    dtend: float
    tracks: tuple[RealVitalTrackHeader, ...]


class RealVitalReaderPort:
    """Port for reading `.vital` header and sample data."""

    def header(self, path: Path) -> RealVitalFileHeader:
        raise NotImplementedError

    def track_samples(
        self,
        path: Path,
        dtname: str,
        *,
        interval_seconds: float,
    ) -> Sequence[float]:
        raise NotImplementedError


@dataclass(frozen=True, slots=True)
class SelectedRealVitalTrack:
    """One source track selected for recorder payload output."""

    header: RealVitalTrackHeader
    output_name: str
    output_device_name: str
    output_montype: str


@dataclass(frozen=True, slots=True)
class RealVitalTrackCatalogItem:
    """One merged source track entry in a real `.vital` catalog."""

    dtname: str
    dname: str
    name: str
    unit: str
    montype: int
    srate: float
    track_type: str
    files: int


def build_real_vital_recorder_payload(
    reader: RealVitalReaderPort,
    path: Path,
    *,
    scenario: RealVitalSampleScenario,
    room_name: str | None = None,
    vrcode: str | None = None,
    version: str = "real-vital-sample",
    start_offset_seconds: float = 0.0,
    duration_seconds: int = 20,
) -> JsonObject:
    """Return a realtime recorder payload extracted from a real `.vital` file."""

    if start_offset_seconds < 0:
        raise ValueError("start_offset_seconds must be greater than or equal to 0")
    if duration_seconds < 1:
        raise ValueError("duration_seconds must be greater than 0")

    header = reader.header(path)
    selected_tracks = select_real_vital_tracks(header.tracks, scenario=scenario)
    started_at = header.dtstart + start_offset_seconds
    ended_at = started_at + duration_seconds
    resolved_room_name = room_name or default_room_name(path, scenario=scenario)
    tracks: JsonArray = []
    skipped_tracks: list[str] = []
    next_wave_id = 1001
    next_num_id = 2001

    for selected in selected_tracks:
        track_id = next_wave_id if is_wave_track(selected.header) else next_num_id
        try:
            track = track_payload_from_source(
                reader,
                path,
                selected,
                started_at=started_at,
                start_offset_seconds=start_offset_seconds,
                duration_seconds=duration_seconds,
                track_id=track_id,
            )
        except SourceTrackHasNoFiniteSamplesError:
            skipped_tracks.append(selected.header.dtname)
            continue
        tracks.append(track)
        if is_wave_track(selected.header):
            next_wave_id += 1
        else:
            next_num_id += 1

    if scenario == RealVitalSampleScenario.BLOODBAG:
        hct_track = derived_hct_payload_from_sphb(
            reader,
            path,
            selected_tracks,
            started_at=started_at,
            start_offset_seconds=start_offset_seconds,
            duration_seconds=duration_seconds,
            track_id=2010,
        )
        tracks.append(hct_track)

    if not tracks:
        raise ValueError(
            f"{scenario.value} scenario produced no finite source track records"
        )

    devices = sorted(
        {
            str(track["dname"])
            for track in tracks
            if isinstance(track, dict) and isinstance(track.get("dname"), str)
        }
    )
    room: JsonObject = {
        "roomname": resolved_room_name,
        "seqid": 0,
        "dtstart": round(started_at, 6),
        "dtend": round(ended_at, 6),
        "dtcase": round(started_at, 6),
        "dtapp": round(started_at, 6),
        "dtserver": round(ended_at, 6),
        "ptcon": 1,
        "recording": 1,
        "dgmt": -32400,
        "vrver": version,
        "devs": [
            {
                "type": "RealVitalSample",
                "name": device_name,
                "status": "on",
            }
            for device_name in devices
        ],
        "trks": tracks,
        "evts": sample_events(
            source_path=path,
            scenario=scenario,
            started_at=started_at,
            skipped_tracks=tuple(skipped_tracks),
        ),
        "filts": [],
    }

    return {
        "vrcode": vrcode or default_vrcode(path, scenario=scenario),
        "ver": version,
        "rooms": {resolved_room_name: room},
    }


def real_vital_sample_metadata(
    reader: RealVitalReaderPort,
    path: Path,
    *,
    scenario: RealVitalSampleScenario,
    start_offset_seconds: float,
    duration_seconds: int,
    payload_path: Path | None = None,
) -> JsonObject:
    """Return sidecar metadata for a generated real `.vital` recorder sample."""

    header = reader.header(path)
    selected_tracks = select_real_vital_tracks(header.tracks, scenario=scenario)

    return {
        "sourceVitalFile": str(path),
        "sourceVitalDtstart": header.dtstart,
        "sourceVitalDtend": header.dtend,
        "sourceWindowSeconds": {
            "startOffset": start_offset_seconds,
            "duration": duration_seconds,
        },
        "scenario": scenario.value,
        "selectedTracks": [
            {
                "sourceTrack": selected.header.dtname,
                "outputDevice": selected.output_device_name,
                "outputName": selected.output_name,
                "outputMontype": selected.output_montype,
                "sourceMontype": selected.header.montype,
                "unit": selected.header.unit,
                "srate": selected.header.srate,
            }
            for selected in selected_tracks
        ],
        "derivedTracks": (
            [
                {
                    "sourceTrack": "Root/SPHB",
                    "outputDevice": "LabDerived",
                    "outputName": "HCT",
                    "outputMontype": "HCT",
                    "formula": "HCT percent = SPHB g/dL * 3.0",
                }
            ]
            if scenario == RealVitalSampleScenario.BLOODBAG
            else []
        ),
        "payload": None if payload_path is None else str(payload_path),
    }


def real_vital_track_catalog(
    reader: RealVitalReaderPort,
    paths: Sequence[Path],
) -> JsonObject:
    """Return a merged source track catalog for real `.vital` files."""

    catalog: dict[str, RealVitalTrackCatalogItem] = {}
    files: JsonArray = []
    for path in paths:
        header = reader.header(path)
        files.append(
            {
                "path": str(path),
                "dtstart": header.dtstart,
                "dtend": header.dtend,
                "trackCount": len(header.tracks),
            }
        )
        for track in header.tracks:
            item = catalog.get(track.dtname)
            if item is None:
                item = RealVitalTrackCatalogItem(
                    dtname=track.dtname,
                    dname=track.dname,
                    name=track.name,
                    unit=track.unit,
                    montype=track.montype,
                    srate=track.srate,
                    track_type="wav" if is_wave_track(track) else "num",
                    files=0,
                )
            catalog[track.dtname] = RealVitalTrackCatalogItem(
                dtname=item.dtname,
                dname=item.dname,
                name=item.name,
                unit=item.unit,
                montype=item.montype,
                srate=item.srate,
                track_type=item.track_type,
                files=item.files + 1,
            )

    tracks = sorted(catalog.values(), key=lambda item: item.dtname)

    return {
        "filesScanned": len(paths),
        "uniqueTracks": len(tracks),
        "waveTracks": sum(1 for track in tracks if track.track_type == "wav"),
        "numericTracks": sum(1 for track in tracks if track.track_type == "num"),
        "tracks": [
            {
                "dtname": track.dtname,
                "dname": track.dname,
                "name": track.name,
                "unit": track.unit,
                "montype": track.montype,
                "srate": track.srate,
                "type": track.track_type,
                "files": track.files,
            }
            for track in tracks
        ],
        "files": files,
    }


def select_real_vital_tracks(
    tracks: Sequence[RealVitalTrackHeader],
    *,
    scenario: RealVitalSampleScenario,
) -> tuple[SelectedRealVitalTrack, ...]:
    """Return explicit source tracks for one real sample scenario."""

    by_dtname = {track.dtname: track for track in tracks}

    if scenario == RealVitalSampleScenario.FULL_REAL:
        return tuple(selected_track(track) for track in tracks)
    if scenario == RealVitalSampleScenario.PERIOP_FULL:
        selected = [
            selected_track(track)
            for track in tracks
            if track.dtname.startswith(("Bx50/", "Primus/"))
        ]
        return require_selected(selected, scenario=scenario)
    if scenario == RealVitalSampleScenario.ROOT_SEDATION:
        selected = [
            selected_track(track)
            for track in tracks
            if track.dtname.startswith("Root/")
        ]
        return require_selected(selected, scenario=scenario)
    if scenario == RealVitalSampleScenario.BASIC_MONITOR:
        selected = [
            selected_track(by_dtname[dtname])
            for dtname in BASIC_MONITOR_TRACKS
            if dtname in by_dtname
        ]
        return require_selected(selected, scenario=scenario)
    if scenario == RealVitalSampleScenario.BLOODBAG:
        require_tracks(by_dtname, ("Root/PLETH", "Root/SPHB"), scenario=scenario)
        return tuple(
            selected_track(by_dtname[dtname])
            for dtname in BLOODBAG_TRACKS
            if dtname in by_dtname
        )

    raise ValueError(f"unknown real vital sample scenario: {scenario}")


def track_payload_from_source(
    reader: RealVitalReaderPort,
    path: Path,
    selected: SelectedRealVitalTrack,
    *,
    started_at: float,
    start_offset_seconds: float,
    duration_seconds: int,
    track_id: int,
) -> JsonObject:
    """Return one recorder track payload from a real source track."""

    header = selected.header
    if is_wave_track(header):
        return wave_track_payload_from_source(
            reader,
            path,
            selected,
            started_at=started_at,
            start_offset_seconds=start_offset_seconds,
            duration_seconds=duration_seconds,
            track_id=track_id,
        )

    return numeric_track_payload_from_source(
        reader,
        path,
        selected,
        started_at=started_at,
        start_offset_seconds=start_offset_seconds,
        duration_seconds=duration_seconds,
        track_id=track_id,
    )


def wave_track_payload_from_source(
    reader: RealVitalReaderPort,
    path: Path,
    selected: SelectedRealVitalTrack,
    *,
    started_at: float,
    start_offset_seconds: float,
    duration_seconds: int,
    track_id: int,
) -> JsonObject:
    """Return one waveform recorder track payload from source samples."""

    header = selected.header
    sample_rate = header.srate
    sample_count = max(1, round(sample_rate))
    samples = reader.track_samples(
        path,
        header.dtname,
        interval_seconds=1.0 / sample_rate,
    )
    start_index = round(start_offset_seconds * sample_rate)
    recs: JsonArray = []

    for second in range(duration_seconds):
        begin = start_index + second * sample_count
        end = begin + sample_count
        values = finite_wave_values(samples[begin:end])
        if not values:
            continue
        recs.append({"dt": round(started_at + second, 6), "val": values})

    if not recs:
        raise SourceTrackHasNoFiniteSamplesError(header.dtname)

    return source_track_payload(
        selected,
        track_id=track_id,
        track_type="wav",
        records=recs,
    )


def numeric_track_payload_from_source(
    reader: RealVitalReaderPort,
    path: Path,
    selected: SelectedRealVitalTrack,
    *,
    started_at: float,
    start_offset_seconds: float,
    duration_seconds: int,
    track_id: int,
) -> JsonObject:
    """Return one numeric recorder track payload from source samples."""

    header = selected.header
    samples = reader.track_samples(path, header.dtname, interval_seconds=1.0)
    start_index = round(start_offset_seconds)
    recs: JsonArray = []

    for second in range(duration_seconds):
        value = finite_value_at_or_before(samples, start_index + second)
        if value is None:
            continue
        recs.append({"dt": round(started_at + second, 6), "val": round(value, 4)})

    if not recs:
        raise SourceTrackHasNoFiniteSamplesError(header.dtname)

    return source_track_payload(
        selected,
        track_id=track_id,
        track_type="num",
        records=recs,
    )


def derived_hct_payload_from_sphb(
    reader: RealVitalReaderPort,
    path: Path,
    selected_tracks: Sequence[SelectedRealVitalTrack],
    *,
    started_at: float,
    start_offset_seconds: float,
    duration_seconds: int,
    track_id: int,
) -> JsonObject:
    """Return derived HCT records from explicit Root/SPHB source records."""

    sphb = next(
        (
            selected.header
            for selected in selected_tracks
            if selected.header.dtname == "Root/SPHB"
        ),
        None,
    )
    if sphb is None:
        raise ValueError("bloodbag scenario requires Root/SPHB for derived HCT")

    samples = reader.track_samples(path, sphb.dtname, interval_seconds=1.0)
    start_index = round(start_offset_seconds)
    recs: JsonArray = []

    for second in range(duration_seconds):
        value = finite_value_at_or_before(samples, start_index + second)
        if value is None:
            continue
        recs.append({"dt": round(started_at + second, 6), "val": round(value * 3.0, 2)})

    if not recs:
        raise ValueError("Root/SPHB has no finite samples for derived HCT")

    return {
        "id": track_id,
        "type": "num",
        "name": "HCT",
        "dname": "LabDerived",
        "montype": "HCT",
        "unit": "%",
        "sourceTrack": "Root/SPHB",
        "sourceMontype": sphb.montype,
        "derivedFormula": "HCT percent = SPHB g/dL * 3.0",
        "recs": recs,
    }


def source_track_payload(
    selected: SelectedRealVitalTrack,
    *,
    track_id: int,
    track_type: str,
    records: JsonArray,
) -> JsonObject:
    """Return recorder payload metadata preserving source track state."""

    header = selected.header
    payload: JsonObject = {
        "id": track_id,
        "type": track_type,
        "name": selected.output_name,
        "dname": selected.output_device_name,
        "montype": selected.output_montype,
        "unit": header.unit,
        "sourceTrack": header.dtname,
        "sourceMontype": header.montype,
        "recs": records,
    }
    if track_type == "wav":
        payload["srate"] = header.srate
        payload["mindisp"] = header.mindisp
        payload["maxdisp"] = header.maxdisp

    return payload


def selected_track(track: RealVitalTrackHeader) -> SelectedRealVitalTrack:
    """Return the default recorder output identity for one source track."""

    return SelectedRealVitalTrack(
        header=track,
        output_name=track.name or safe_segment(track.dtname),
        output_device_name=track.dname or "RealVital",
        output_montype=monitor_type_name(track),
    )


def monitor_type_name(track: RealVitalTrackHeader) -> str:
    """Return a recorder montype name that preserves explicit source identity."""

    return SOURCE_MONITOR_TYPE_NAMES.get(track.montype, str(track.montype))


def finite_wave_values(values: Sequence[float]) -> JsonArray:
    """Return JSON waveform samples with finite gaps filled from track context."""

    cleaned: JsonArray = []
    previous: float | None = None
    first_finite: float | None = None
    for raw in values:
        value = finite_float(raw)
        if value is not None:
            previous = value
            first_finite = value if first_finite is None else first_finite
            cleaned.append(round(value, 4))
            continue
        if previous is not None:
            cleaned.append(round(previous, 4))
        else:
            cleaned.append(None)

    if first_finite is None:
        return []

    return [first_finite if value is None else value for value in cleaned]


def finite_value_at_or_before(values: Sequence[float], index: int) -> float | None:
    """Return the nearest finite sample at or before one integer sample index."""

    cursor = min(index, len(values) - 1)
    while cursor >= 0:
        value = finite_float(values[cursor])
        if value is not None:
            return value
        cursor -= 1

    return None


def finite_float(value: object) -> float | None:
    """Return a finite float or None for missing/non-finite source values."""

    try:
        number = float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None

    return number if math.isfinite(number) else None


def is_wave_track(track: RealVitalTrackHeader) -> bool:
    """Return whether the source track should be emitted as waveform data."""

    return track.srate > 1.0


def require_tracks(
    by_dtname: dict[str, RealVitalTrackHeader],
    required_dtname: tuple[str, ...],
    *,
    scenario: RealVitalSampleScenario,
) -> None:
    """Raise when a scenario's explicit source track contract is missing."""

    missing = tuple(dtname for dtname in required_dtname if dtname not in by_dtname)
    if missing:
        raise ValueError(
            f"{scenario.value} scenario requires source tracks: "
            + ", ".join(missing)
        )


def require_selected(
    selected: list[SelectedRealVitalTrack],
    *,
    scenario: RealVitalSampleScenario,
) -> tuple[SelectedRealVitalTrack, ...]:
    """Return selected tracks or raise a clear scenario/source mismatch."""

    if not selected:
        raise ValueError(f"{scenario.value} scenario did not match source tracks")

    return tuple(selected)


def sample_events(
    *,
    source_path: Path,
    scenario: RealVitalSampleScenario,
    started_at: float,
    skipped_tracks: tuple[str, ...] = (),
) -> JsonArray:
    """Return source provenance events embedded in the recorder payload."""

    events: JsonArray = [
        {
            "dt": round(started_at, 6),
            "val": f"real .vital sample source={source_path} scenario={scenario.value}",
        }
    ]
    if scenario == RealVitalSampleScenario.BLOODBAG:
        events.append(
            {
                "dt": round(started_at, 6),
                "val": (
                    "HCT is derived from measured Root/SPHB as HCT=SPHB*3. "
                    "Source file has SPHB, not direct HCT."
                ),
            }
        )
    if skipped_tracks:
        events.append(
            {
                "dt": round(started_at, 6),
                "val": (
                    "Skipped source tracks with no finite samples in selected "
                    f"window: {', '.join(skipped_tracks)}"
                ),
            }
        )

    return events


def default_room_name(path: Path, *, scenario: RealVitalSampleScenario) -> str:
    """Return a deterministic room name for a generated sample."""

    return f"{safe_segment(path.stem)}_{safe_segment(scenario.value)}"


def default_vrcode(path: Path, *, scenario: RealVitalSampleScenario) -> str:
    """Return a deterministic VRecorder code for a generated sample."""

    return f"{safe_segment(path.stem)}-{scenario.value}"


def safe_segment(value: str) -> str:
    """Return a simple recorder identity segment."""

    cleaned = "".join(
        character if character.isalnum() or character in ("-", "_") else "_"
        for character in value.strip()
    )

    return cleaned or "real-vital"


BASIC_MONITOR_TRACKS = (
    "Bx50/ECG1",
    "Bx50/PLETH",
    "Bx50/IBP1",
    "Primus/CO2",
    "Bx50/HR",
    "Bx50/PLETH_SPO2",
    "Primus/ETCO2",
    "Primus/RR_CO2",
    "Bx50/ART1_SBP",
    "Bx50/ART1_DBP",
    "Bx50/ART1_MBP",
    "Bx50/NIBP_SBP",
    "Bx50/NIBP_DBP",
    "Bx50/NIBP_MBP",
    "Bx50/BT1",
    "Bx50/CVP3",
    "Bx50/PPV",
)

BLOODBAG_TRACKS = (
    "Root/PLETH",
    "Root/SPO2",
    "Root/BPM",
    "Root/PI",
    "Root/PVI",
    "Root/ORI",
    "Root/SPHB",
    "Primus/CO2",
    "Primus/ETCO2",
    "Primus/RR_CO2",
)

SOURCE_MONITOR_TYPE_NAMES = {
    1: "ECG_WAV",
    2: "ECG_HR",
    4: "IABP_WAV",
    5: "IABP_SBP",
    6: "IABP_DBP",
    7: "IABP_MBP",
    8: "PLETH_WAV",
    9: "PLETH_HR",
    10: "PLETH_SPO2",
    12: "CO2_RR",
    13: "CO2_WAV",
    15: "CO2_CONC",
    16: "NIBP_SBP",
    17: "NIBP_DBP",
    18: "NIBP_MBP",
    19: "BT",
    21: "CVP",
    23: "TV",
    25: "PIP",
    26: "GAS_AGENT",
    27: "GAS_EXPIRED",
    37: "AWP",
    38: "PEEP",
    39: "ST",
    51: "PPV",
    70: "PSI",
    71: "PVI",
    72: "SPHB",
    73: "ORI",
    82: "SEFL",
    85: "NMT_T4_T1",
    86: "NMT_TOF_CNT",
    95: "EEG",
}


class SourceTrackHasNoFiniteSamplesError(ValueError):
    """Raised when a selected source track has no finite samples in the window."""

    def __init__(self, dtname: str) -> None:
        super().__init__(f"source track has no finite samples: {dtname}")
        self.dtname = dtname
