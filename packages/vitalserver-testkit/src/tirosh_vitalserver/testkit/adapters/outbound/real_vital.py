"""Outbound adapter for reading real `.vital` files through vitaldb."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalFileHeader,
    RealVitalReaderPort,
    RealVitalTrackHeader,
)


class VitalDbRealVitalReader(RealVitalReaderPort):
    """Read `.vital` headers and samples with the vitaldb package."""

    def header(self, path: Path) -> RealVitalFileHeader:
        """Return explicit header state from one `.vital` file."""

        try:
            from vitaldb import VitalFile
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "vitaldb package is required for real vital samples"
            ) from exc

        vital_file = VitalFile(str(path), header_only=True)
        tracks = list(vital_file.trks.values())

        return RealVitalFileHeader(
            path=path,
            dtstart=float(vital_file.dtstart),
            dtend=float(vital_file.dtend),
            tracks=tuple(track_header(track) for track in tracks),
        )

    def track_samples(
        self,
        path: Path,
        dtname: str,
        *,
        interval_seconds: float,
    ) -> Any:
        """Return source samples for one track at an explicit interval."""

        try:
            from vitaldb import VitalFile
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "vitaldb package is required for real vital samples"
            ) from exc

        vital_file = VitalFile(str(path))

        return vital_file.get_track_samples(dtname, interval_seconds)


def track_header(track: Any) -> RealVitalTrackHeader:
    """Convert a vitaldb Track into the application header contract."""

    return RealVitalTrackHeader(
        dtname=str(getattr(track, "dtname", "")),
        dname=str(getattr(track, "dname", "")),
        name=str(getattr(track, "name", "")),
        unit=str(getattr(track, "unit", "")),
        montype=int(getattr(track, "montype", 0) or 0),
        srate=float(getattr(track, "srate", 0) or 0),
        mindisp=float(getattr(track, "mindisp", 0) or 0),
        maxdisp=float(getattr(track, "maxdisp", 0) or 0),
    )
