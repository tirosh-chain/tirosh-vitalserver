"""Bed domain value objects."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Bed:
    """A VitalServer bed created for test traffic."""

    room_name: str
    bed_id: str


@dataclass(frozen=True)
class BedRecorderAssignment:
    """A VitalServer live relationship between one bed and one VRecorder."""

    bed: Bed
    vrcode: str
