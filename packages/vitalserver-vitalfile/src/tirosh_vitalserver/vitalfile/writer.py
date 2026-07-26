"""Canonical latest-version Vital File writer."""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tirosh_vitalserver.core.domain.vital_file import (
    VitalFileFormatVersion,
    VitalTrack,
    VitalTrackKind,
)
from tirosh_vitalserver.vitalfile.reader import VitalDbVitalFileReader


@dataclass(frozen=True, slots=True)
class VitalFileWriteReceipt:
    """Proof that a canonical latest-version artifact was written and read back."""

    path: Path
    format_version: VitalFileFormatVersion
    header_length: int
    track_count: int
    size_bytes: int


class VitalDbVitalFileWriter:
    """Write v3 artifacts from explicit canonical track kinds."""

    def __init__(self, reader: VitalDbVitalFileReader | None = None) -> None:
        self.reader = reader or VitalDbVitalFileReader()

    def write(
        self,
        path: Path,
        *,
        started_at: float,
        ended_at: float,
        tracks: tuple[VitalTrack, ...],
    ) -> VitalFileWriteReceipt:
        """Write and verify one canonical v3 Vital File."""

        if path.suffix.lower() != ".vital":
            raise ValueError(f"Vital File output must use .vital extension: {path}")
        if not math.isfinite(started_at) or not math.isfinite(ended_at):
            raise ValueError("Vital File output time range must be finite")
        if ended_at < started_at:
            raise ValueError("Vital File output end must not precede start")
        if not tracks:
            raise ValueError("Vital File output requires at least one track")
        for track in tracks:
            _validate_track_contract(track)

        try:
            import numpy as np
            from vitaldb import VitalFile
        except ModuleNotFoundError as error:
            raise RuntimeError(
                "vitaldb and numpy are required for Vital File writes"
            ) from error

        path.parent.mkdir(parents=True, exist_ok=True)
        vital_file = VitalFile()
        vital_file.dtstart = started_at
        vital_file.dtend = ended_at

        for track in tracks:
            writer_track = vital_file.add_track(
                track.dtname,
                _writer_records(track, np=np),
                srate=(track.srate if track.kind is VitalTrackKind.WAVEFORM else 0.0),
                unit=track.unit,
                mindisp=track.mindisp,
                maxdisp=track.maxdisp,
            )
            if writer_track is None:
                raise RuntimeError(f"vitaldb failed to add track {track.dtname}")
            writer_track.type = int(track.kind)
            writer_track.montype = track.montype

        result = vital_file.to_vital(str(path))
        if result is not True:
            raise RuntimeError(f"vitaldb failed to write {path}")

        manifest = self.reader.inspect(path)
        if manifest.header.format_version is not VitalFileFormatVersion.V3:
            raise RuntimeError(
                "vitaldb writer did not produce canonical v3 output: "
                f"{manifest.header.format_version}"
            )
        expected_kinds = {track.dtname: track.kind for track in tracks}
        actual_kinds = {track.dtname: track.kind for track in manifest.tracks}
        if actual_kinds != expected_kinds:
            raise RuntimeError(
                "Vital File write verification track contract mismatch: "
                f"expected={expected_kinds} actual={actual_kinds}"
            )

        return VitalFileWriteReceipt(
            path=path,
            format_version=manifest.header.format_version,
            header_length=manifest.header.header_length,
            track_count=len(manifest.tracks),
            size_bytes=path.stat().st_size,
        )


def _writer_records(track: VitalTrack, *, np: Any) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for record in track.records:
        if not math.isfinite(record.dt):
            raise ValueError(f"Vital track record time must be finite: {track.dtname}")
        if track.kind is VitalTrackKind.WAVEFORM:
            value: object = np.asarray(
                _waveform_value(record.value, dtname=track.dtname),
                dtype=np.float32,
            )
        elif track.kind is VitalTrackKind.NUMERIC:
            value = _numeric_value(record.value, dtname=track.dtname)
        else:
            value = _string_value(record.value, dtname=track.dtname)
        records.append({"dt": record.dt, "val": value})
    if not records:
        raise ValueError(f"Vital track requires at least one record: {track.dtname}")
    return records


def _validate_track_contract(track: VitalTrack) -> None:
    if not track.dtname:
        raise ValueError("Vital track name must not be empty")
    if not isinstance(track.kind, VitalTrackKind):
        raise ValueError(f"Vital track kind must be explicit: {track.dtname}")
    metadata = (track.srate, track.mindisp, track.maxdisp)
    if not all(math.isfinite(value) for value in metadata):
        raise ValueError(f"Vital track metadata must be finite: {track.dtname}")
    if track.kind is VitalTrackKind.WAVEFORM:
        if track.srate <= 0:
            raise ValueError(
                f"waveform Vital track requires positive sample rate: {track.dtname}"
            )
    elif track.srate != 0:
        raise ValueError(
            f"non-waveform Vital track requires zero sample rate: {track.dtname}"
        )


def _waveform_value(value: object, *, dtname: str) -> list[float]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"waveform Vital record must be a non-empty array: {dtname}")
    samples: list[float] = []
    for sample in value:
        if isinstance(sample, bool) or not isinstance(sample, int | float):
            raise ValueError(f"waveform Vital samples must be numeric: {dtname}")
        number = float(sample)
        if not math.isfinite(number):
            raise ValueError(f"waveform Vital samples must be finite: {dtname}")
        samples.append(number)
    return samples


def _numeric_value(value: object, *, dtname: str) -> float:
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise ValueError(f"numeric Vital record must be numeric: {dtname}")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"numeric Vital record must be finite: {dtname}")
    return number


def _string_value(value: object, *, dtname: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"string Vital record must be a string: {dtname}")
    return value
