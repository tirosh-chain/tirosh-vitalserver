"""Outbound adapter that reads uploaded `.vital` files for Product Lab replay."""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol


@dataclass(frozen=True)
class LabVitalReplayFrame:
    devices: tuple[dict[str, object], ...]
    tracks: tuple[dict[str, object], ...]


class LabVitalReplaySource(Protocol):
    duration_seconds: int

    def frame(self, *, offset_seconds: int, output_time: float) -> LabVitalReplayFrame:
        """Read one explicit one-second frame from the source file."""


class LabVitalReplaySourceFactory(Protocol):
    def open(self, path: Path) -> LabVitalReplaySource:
        """Open and validate one uploaded Vital File."""


@dataclass(frozen=True)
class _Track:
    track_id: int
    dtname: str
    name: str
    device_name: str
    unit: str
    monitor_type: str
    sample_rate: float
    minimum_display: float
    maximum_display: float
    samples: Sequence[float]

    @property
    def is_wave(self) -> bool:
        return self.sample_rate > 1.0


class VitalDBReplaySourceFactory:
    def open(self, path: Path) -> LabVitalReplaySource:
        if path.suffix.lower() != ".vital" or not path.is_file():
            raise VitalReplaySourceError(
                f"Vital File replay source is unavailable: {path}"
            )
        try:
            from vitaldb import VitalFile
        except ModuleNotFoundError as error:
            raise VitalReplaySourceError(
                "vitaldb package is required for Vital File replay"
            ) from error
        try:
            source = VitalFile(str(path))
        except Exception as error:
            raise VitalReplaySourceError(
                f"Vital File replay source decode failed: {path.name}: {error}"
            ) from error
        duration_seconds = math.ceil(float(source.dtend) - float(source.dtstart))
        if duration_seconds < 1:
            raise VitalReplaySourceError(
                f"Vital File replay source has no positive duration: {path.name}"
            )

        tracks: list[_Track] = []
        next_wave_id = 1001
        next_numeric_id = 2001
        for source_track in source.trks.values():
            sample_rate = float(getattr(source_track, "srate", 0) or 0)
            if sample_rate <= 0:
                raise VitalReplaySourceError(
                    "Vital File track has an invalid sample rate: "
                    f"{getattr(source_track, 'dtname', '')}"
                )
            is_wave = sample_rate > 1.0
            track_id = next_wave_id if is_wave else next_numeric_id
            interval = 1.0 / sample_rate if is_wave else 1.0
            dtname = str(getattr(source_track, "dtname", ""))
            try:
                samples = source.get_track_samples(dtname, interval)
            except Exception as error:
                raise VitalReplaySourceError(
                    f"Vital File track read failed: {dtname}: {error}"
                ) from error
            tracks.append(
                _Track(
                    track_id=track_id,
                    dtname=dtname,
                    name=str(getattr(source_track, "name", "")) or dtname,
                    device_name=str(getattr(source_track, "dname", "")) or "Vital File",
                    unit=str(getattr(source_track, "unit", "")),
                    monitor_type=MONITOR_TYPE_NAMES.get(
                        int(getattr(source_track, "montype", 0) or 0),
                        str(int(getattr(source_track, "montype", 0) or 0)),
                    ),
                    sample_rate=sample_rate,
                    minimum_display=float(getattr(source_track, "mindisp", 0) or 0),
                    maximum_display=float(getattr(source_track, "maxdisp", 0) or 0),
                    samples=samples,
                )
            )
            if is_wave:
                next_wave_id += 1
            else:
                next_numeric_id += 1
        if not tracks:
            raise VitalReplaySourceError(f"Vital File contains no tracks: {path.name}")
        return VitalDBReplaySource(
            duration_seconds=duration_seconds,
            tracks=tuple(tracks),
        )


@dataclass(frozen=True)
class VitalDBReplaySource:
    duration_seconds: int
    tracks: tuple[_Track, ...]

    def frame(self, *, offset_seconds: int, output_time: float) -> LabVitalReplayFrame:
        if offset_seconds < 0 or offset_seconds >= self.duration_seconds:
            raise VitalReplaySourceError(
                f"Vital File replay offset is outside source duration: {offset_seconds}"
            )
        track_payloads: list[dict[str, object]] = []
        for track in self.tracks:
            payload = _track_frame(
                track,
                offset_seconds=offset_seconds,
                output_time=output_time,
            )
            if payload is not None:
                track_payloads.append(payload)
        if not track_payloads:
            raise VitalReplaySourceError(
                "Vital File replay frame has no finite records: "
                f"offset={offset_seconds}"
            )
        devices = tuple(
            {
                "type": "VitalFileReplay",
                "name": device_name,
                "status": "connected",
            }
            for device_name in sorted(
                {str(payload["dname"]) for payload in track_payloads}
            )
        )
        return LabVitalReplayFrame(devices=devices, tracks=tuple(track_payloads))


class VitalReplaySourceError(Exception):
    pass


def _track_frame(
    track: _Track,
    *,
    offset_seconds: int,
    output_time: float,
) -> dict[str, object] | None:
    if track.is_wave:
        sample_count = max(1, round(track.sample_rate))
        begin = round(offset_seconds * track.sample_rate)
        values = _finite_wave_values(track.samples[begin : begin + sample_count])
        if not values:
            return None
        records: list[dict[str, object]] = [{"dt": output_time, "val": values}]
        track_type = "wav"
    else:
        value = _finite_value_at_or_before(track.samples, offset_seconds)
        if value is None:
            return None
        records = [{"dt": output_time, "val": round(value, 4)}]
        track_type = "num"

    payload: dict[str, object] = {
        "id": track.track_id,
        "type": track_type,
        "name": track.name,
        "dname": track.device_name,
        "montype": track.monitor_type,
        "unit": track.unit,
        "sourceTrack": track.dtname,
        "recs": records,
    }
    if track.is_wave:
        payload["srate"] = track.sample_rate
        payload["mindisp"] = track.minimum_display
        payload["maxdisp"] = track.maximum_display
    return payload


def _finite_wave_values(values: Sequence[float]) -> list[float]:
    cleaned: list[float | None] = []
    previous: float | None = None
    first: float | None = None
    for raw in values:
        value = _finite_float(raw)
        if value is not None:
            previous = value
            first = value if first is None else first
            cleaned.append(round(value, 4))
        else:
            cleaned.append(None if previous is None else round(previous, 4))
    if first is None:
        return []
    return [first if value is None else value for value in cleaned]


def _finite_value_at_or_before(values: Sequence[float], index: int) -> float | None:
    cursor = min(index, len(values) - 1)
    while cursor >= 0:
        value = _finite_float(values[cursor])
        if value is not None:
            return value
        cursor -= 1
    return None


def _finite_float(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


MONITOR_TYPE_NAMES = {
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
