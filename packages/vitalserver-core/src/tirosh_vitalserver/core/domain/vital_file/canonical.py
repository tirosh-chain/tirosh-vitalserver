"""Canonical Vital File domain contracts independent of wire format versions."""

from __future__ import annotations

import math
from dataclasses import dataclass

from tirosh_vitalserver.core.domain.vital_file.format import (
    VitalFileHeader,
    VitalTrackKind,
)
from tirosh_vitalserver.core.errors import VitalFileFormatError


@dataclass(frozen=True, slots=True)
class VitalDeviceDefinition:
    """One device identity normalized from a version-specific reader."""

    name: str
    device_type: str
    port: str

    def __post_init__(self) -> None:
        if not self.name:
            raise VitalFileFormatError(
                code="invalidDeviceMetadata",
                detail="Vital device name must not be empty",
            )


@dataclass(frozen=True, slots=True)
class VitalTrackDefinition:
    """One explicit track definition shared by all Vital File consumers."""

    dtname: str
    name: str
    device_name: str
    kind: VitalTrackKind
    format_code: int
    unit: str
    sample_rate: float
    minimum_display: float
    maximum_display: float
    color: int
    gain: float
    offset: float
    monitor_type_id: int

    def __post_init__(self) -> None:
        if not self.dtname:
            raise VitalFileFormatError(
                code="invalidTrackMetadata",
                detail="Vital track dtname must not be empty",
            )
        if not self.name:
            raise VitalFileFormatError(
                code="invalidTrackMetadata",
                detail=f"Vital track name must not be empty: {self.dtname}",
            )
        numeric_values = (
            self.sample_rate,
            self.minimum_display,
            self.maximum_display,
            self.gain,
            self.offset,
        )
        if not all(math.isfinite(value) for value in numeric_values):
            raise VitalFileFormatError(
                code="invalidTrackMetadata",
                detail=f"Vital track metadata must be finite: {self.dtname}",
            )
        if self.sample_rate < 0:
            raise VitalFileFormatError(
                code="invalidTrackMetadata",
                detail=f"Vital track sample rate must not be negative: {self.dtname}",
            )
        if self.kind is VitalTrackKind.WAVEFORM and self.sample_rate == 0:
            raise VitalFileFormatError(
                code="invalidWaveformSampleRate",
                detail=(
                    "Vital waveform track requires a positive sample rate: "
                    f"{self.dtname}"
                ),
            )


@dataclass(frozen=True, slots=True)
class VitalFileManifest:
    """Canonical file metadata produced by every version-specific reader."""

    header: VitalFileHeader
    started_at: float
    ended_at: float
    devices: tuple[VitalDeviceDefinition, ...]
    tracks: tuple[VitalTrackDefinition, ...]

    def __post_init__(self) -> None:
        if not math.isfinite(self.started_at) or not math.isfinite(self.ended_at):
            raise VitalFileFormatError(
                code="invalidFileMetadata",
                detail="Vital File time range must be finite",
            )
        if self.ended_at < self.started_at:
            raise VitalFileFormatError(
                code="invalidFileMetadata",
                detail=(
                    "Vital File end time must not precede start time: "
                    f"start={self.started_at} end={self.ended_at}"
                ),
            )
        if not self.tracks:
            raise VitalFileFormatError(
                code="noTracks",
                detail="Vital File must contain at least one track",
            )

    @property
    def duration_seconds(self) -> float:
        """Return the explicit canonical file duration."""

        return self.ended_at - self.started_at

    def track(self, dtname: str) -> VitalTrackDefinition:
        """Return one explicitly named track or report its absence."""

        for track in self.tracks:
            if track.dtname == dtname:
                return track
        raise VitalFileFormatError(
            code="trackNotFound",
            detail=f"Vital File track does not exist: {dtname}",
        )
