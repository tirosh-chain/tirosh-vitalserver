"""Bed domain rules."""

from __future__ import annotations

from tirosh_vitalserver.testkit.errors import InsufficientBedsForRecordersError


def require_bed_capacity_for_recorders(
    *,
    bed_count: int,
    recorder_count: int,
) -> None:
    """Enforce the VitalServer live model: one active VRecorder per bed."""

    if bed_count < recorder_count:
        raise InsufficientBedsForRecordersError()
