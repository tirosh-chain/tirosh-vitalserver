"""Outbound adapter for reading real `.vital` files through vitaldb."""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path

from tirosh_vitalserver.core.domain.vital_file import VitalTrackDefinition
from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalFileHeader,
    RealVitalReaderPort,
    RealVitalTrackHeader,
)
from tirosh_vitalserver.vitalfile import VitalDbVitalFileReader


class VitalDbRealVitalReader(RealVitalReaderPort):
    """Read `.vital` headers and samples with the vitaldb package."""

    def __init__(self, reader: VitalDbVitalFileReader | None = None) -> None:
        self.reader = reader or VitalDbVitalFileReader()

    def header(self, path: Path) -> RealVitalFileHeader:
        """Return explicit header state from one `.vital` file."""

        manifest = self.reader.inspect(path)

        return RealVitalFileHeader(
            path=path,
            format_version=manifest.header.format_version,
            dtstart=manifest.started_at,
            dtend=manifest.ended_at,
            tracks=tuple(track_header(track) for track in manifest.tracks),
        )

    def track_samples(
        self,
        path: Path,
        dtname: str,
        *,
        interval_seconds: float,
    ) -> Sequence[object]:
        """Return source samples for one track at an explicit interval."""

        source = self.reader.open(path)
        return source.track_samples(dtname, interval_seconds=interval_seconds)


def track_header(track: VitalTrackDefinition) -> RealVitalTrackHeader:
    """Convert one canonical track into the application header contract."""

    return RealVitalTrackHeader(
        dtname=track.dtname,
        kind=track.kind,
        dname=track.device_name,
        name=track.name,
        unit=track.unit,
        montype=track.monitor_type_id,
        srate=track.sample_rate,
        mindisp=track.minimum_display,
        maxdisp=track.maximum_display,
    )
