"""Outbound adapter that reads uploaded `.vital` files for Product Lab replay."""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any, Protocol

from tirosh_vitalserver.core.domain.vital_file import (
    VitalFileFormatError,
    VitalFileFormatVersion,
    VitalServerMonitorType,
    VitalTrackDefinition,
    VitalTrackKind,
)
from tirosh_vitalserver.vitalfile import (
    VitalDbVitalFileReader,
    VitalFileReadError,
)


@dataclass(frozen=True)
class LabVitalReplayFrame:
    devices: tuple[dict[str, object], ...]
    tracks: tuple[dict[str, object], ...]


class LabVitalReplaySource(Protocol):
    @property
    def format_version(self) -> VitalFileFormatVersion:
        """Return the source file wire format version."""
        ...

    @property
    def duration_seconds(self) -> int:
        """Return the explicit replay duration in whole seconds."""
        ...

    def frame(self, *, offset_seconds: int, output_time: float) -> LabVitalReplayFrame:
        """Read one explicit one-second frame from the source file."""

    def close(self) -> None:
        """Release operation-owned replay resources explicitly."""


class LabVitalReplaySourceFactory(Protocol):
    def open(self, path: Path) -> LabVitalReplaySource:
        """Open and validate one uploaded Vital File."""


class LabReplayStringTrackPolicy(StrEnum):
    """Configured Lab behavior for valid Vital string tracks."""

    REJECT = "reject"
    SKIP = "skip"


class LabReplayGapPolicy(StrEnum):
    """Configured Lab behavior when a track has no finite data for a frame."""

    OMIT_TRACK = "omitTrack"
    FAIL_FRAME = "failFrame"


@dataclass(frozen=True)
class _Track:
    track_id: int
    kind: VitalTrackKind
    dtname: str
    name: str
    device_name: str
    unit: str
    monitor_type: str
    sample_rate: float
    minimum_display: float
    maximum_display: float
    samples: Sequence[object]

    @property
    def is_wave(self) -> bool:
        return self.kind is VitalTrackKind.WAVEFORM


class VitalDBReplaySourceFactory:
    def __init__(
        self,
        *,
        string_track_policy: LabReplayStringTrackPolicy,
        gap_policy: LabReplayGapPolicy,
        reader: VitalDbVitalFileReader | None = None,
    ) -> None:
        self.string_track_policy = string_track_policy
        self.gap_policy = gap_policy
        self.reader = reader or VitalDbVitalFileReader()

    def open(self, path: Path) -> LabVitalReplaySource:
        try:
            source = self.reader.open(path)
        except (VitalFileFormatError, VitalFileReadError) as error:
            raise VitalReplaySourceError(
                f"Vital File replay source validation failed: {path.name}: {error}",
                stage="fileValidation",
                code=error.code,
            ) from error
        manifest = source.manifest
        duration_seconds = math.ceil(manifest.duration_seconds)
        if duration_seconds < 1:
            raise VitalReplaySourceError(
                f"Vital File replay source has no positive duration: {path.name}",
                stage="fileValidation",
                code="nonPositiveDuration",
            )

        string_tracks = tuple(
            track
            for track in manifest.tracks
            if track.kind is VitalTrackKind.STRING
        )
        if (
            string_tracks
            and self.string_track_policy is LabReplayStringTrackPolicy.REJECT
        ):
            raise VitalReplaySourceError(
                "Vital File string track replay is unsupported: "
                f"{string_tracks[0].dtname}",
                stage="fileValidation",
                code="unsupportedStringTrack",
            )
        replayable_definitions = tuple(
            track
            for track in manifest.tracks
            if track.kind is not VitalTrackKind.STRING
        )
        require_vitalserver_graph_track(
            replayable_definitions,
            source_name=path.name,
        )

        tracks: list[_Track] = []
        next_wave_id = 1001
        next_numeric_id = 2001
        for source_track in manifest.tracks:
            if source_track.kind is VitalTrackKind.STRING:
                continue

            is_wave = source_track.kind is VitalTrackKind.WAVEFORM
            track_id = next_wave_id if is_wave else next_numeric_id
            interval = 1.0 / source_track.sample_rate if is_wave else 1.0
            try:
                samples = source.track_samples(
                    source_track.dtname,
                    interval_seconds=interval,
                )
            except VitalFileReadError as error:
                raise VitalReplaySourceError(
                    error.detail,
                    stage="fileValidation",
                    code=error.code,
                ) from error
            tracks.append(
                _Track(
                    track_id=track_id,
                    kind=source_track.kind,
                    dtname=source_track.dtname,
                    name=source_track.name,
                    device_name=source_track.device_name or "Vital File",
                    unit=source_track.unit,
                    monitor_type=monitor_type_wire_name(
                        source_track.monitor_type_id
                    ),
                    sample_rate=source_track.sample_rate,
                    minimum_display=source_track.minimum_display,
                    maximum_display=source_track.maximum_display,
                    samples=samples,
                )
            )
            if is_wave:
                next_wave_id += 1
            else:
                next_numeric_id += 1
        if not tracks:
            raise VitalReplaySourceError(
                f"Vital File contains no replayable tracks: {path.name}",
                stage="fileValidation",
                code="noReplayableTracks",
            )
        return VitalDBReplaySource(
            format_version=manifest.header.format_version,
            duration_seconds=duration_seconds,
            tracks=tuple(tracks),
            gap_policy=self.gap_policy,
        )


@dataclass(frozen=True)
class VitalDBReplaySource:
    format_version: VitalFileFormatVersion
    duration_seconds: int
    tracks: tuple[_Track, ...]
    gap_policy: LabReplayGapPolicy

    def close(self) -> None:
        return None

    def frame(self, *, offset_seconds: int, output_time: float) -> LabVitalReplayFrame:
        if offset_seconds < 0 or offset_seconds >= self.duration_seconds:
            raise VitalReplaySourceError(
                "Vital File replay offset is outside source duration: "
                f"{offset_seconds}",
                stage="replayFrame",
                code="offsetOutsideSourceDuration",
            )
        track_payloads: list[dict[str, object]] = []
        for track in self.tracks:
            payload = _track_frame(
                track,
                offset_seconds=offset_seconds,
                output_time=output_time,
                gap_policy=self.gap_policy,
            )
            if payload is not None:
                track_payloads.append(payload)
        if not track_payloads:
            raise VitalReplaySourceError(
                "Vital File replay frame has no finite records: "
                f"offset={offset_seconds}",
                stage="replayFrame",
                code="noFiniteRecords",
            )
        devices: tuple[dict[str, object], ...] = tuple(
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
    def __init__(self, message: str, *, stage: str, code: str) -> None:
        super().__init__(message)
        self.stage = stage
        self.code = code


def require_vitalserver_graph_track(
    tracks: Sequence[VitalTrackDefinition],
    *,
    source_name: str,
) -> None:
    """Require an explicit monitor type understood by Web Monitoring."""

    if any(
        VitalServerMonitorType.from_id(track.monitor_type_id) is not None
        for track in tracks
    ):
        return

    described_tracks = ", ".join(
        f"{track.dtname}(montype={track.monitor_type_id})"
        for track in tracks[:8]
    )
    remaining = len(tracks) - 8
    if remaining > 0:
        described_tracks = f"{described_tracks}, +{remaining} more"
    raise VitalReplaySourceError(
        "Vital File contains no VitalServer graph-compatible tracks: "
        f"{source_name}; tracks={described_tracks}",
        stage="fileValidation",
        code="noVitalServerGraphTracks",
    )


def monitor_type_wire_name(monitor_type_id: int) -> str:
    """Preserve an unknown source id while formatting known wire names."""

    monitor_type = VitalServerMonitorType.from_id(monitor_type_id)
    return monitor_type.name if monitor_type is not None else str(monitor_type_id)


def _track_frame(
    track: _Track,
    *,
    offset_seconds: int,
    output_time: float,
    gap_policy: LabReplayGapPolicy,
) -> dict[str, object] | None:
    if track.is_wave:
        sample_count = max(1, round(track.sample_rate))
        begin = round(offset_seconds * track.sample_rate)
        values = _finite_wave_values(track.samples[begin : begin + sample_count])
        if values is None or len(values) != sample_count:
            _handle_missing_track_frame(
                track,
                offset_seconds=offset_seconds,
                gap_policy=gap_policy,
            )
            return None
        records: list[dict[str, object]] = [{"dt": output_time, "val": values}]
        track_type = "wav"
    else:
        value = _finite_value_at_index(track.samples, offset_seconds)
        if value is None:
            _handle_missing_track_frame(
                track,
                offset_seconds=offset_seconds,
                gap_policy=gap_policy,
            )
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


def _handle_missing_track_frame(
    track: _Track,
    *,
    offset_seconds: int,
    gap_policy: LabReplayGapPolicy,
) -> None:
    if gap_policy is LabReplayGapPolicy.OMIT_TRACK:
        return None
    raise VitalReplaySourceError(
        "Vital File replay track has no complete finite frame: "
        f"{track.dtname} offset={offset_seconds}",
        stage="replayFrame",
        code="missingTrackRecord",
    )


def _finite_wave_values(values: Sequence[object]) -> list[float] | None:
    cleaned: list[float] = []
    for raw in values:
        value = _finite_float(raw)
        if value is None:
            return None
        cleaned.append(round(value, 4))
    return cleaned


def _finite_value_at_index(values: Sequence[object], index: int) -> float | None:
    if index < 0 or index >= len(values):
        return None
    return _finite_float(values[index])


def _finite_float(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None
