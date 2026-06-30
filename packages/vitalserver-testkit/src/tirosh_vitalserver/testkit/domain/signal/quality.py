"""Signal quality transforms applied over clinical signal profiles."""

from __future__ import annotations

import math
from enum import StrEnum


class SignalQualityProfile(StrEnum):
    """Independent signal quality profiles for generated recorder frames."""

    CLEAN = "clean"
    NOISE = "noise"
    BASELINE_WANDER = "baseline_wander"
    MOTION_ARTIFACT = "motion_artifact"
    DROPOUT = "dropout"
    FLATLINE = "flatline"
    LOW_AMPLITUDE = "low_amplitude"
    CLIPPING = "clipping"


def apply_signal_quality(
    value: float,
    *,
    sample_time: float,
    quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
    mindisp: float | None = None,
    maxdisp: float | None = None,
) -> float:
    """Apply a quality transform without changing the clinical profile."""

    if quality == SignalQualityProfile.CLEAN:
        return value
    if quality == SignalQualityProfile.NOISE:
        return round(value + math.sin(sample_time * 97.0) * 0.08, 4)
    if quality == SignalQualityProfile.BASELINE_WANDER:
        return round(value + math.sin(sample_time * 0.33) * 0.18, 4)
    if quality == SignalQualityProfile.MOTION_ARTIFACT:
        artifact = 0.0
        if int(sample_time * 2) % 11 == 0:
            artifact = math.sin(sample_time * 53.0) * 0.9
        return round(value + artifact, 4)
    if quality == SignalQualityProfile.DROPOUT:
        return 0.0 if int(sample_time * 4) % 9 in {0, 1} else value
    if quality == SignalQualityProfile.FLATLINE:
        return 0.0
    if quality == SignalQualityProfile.LOW_AMPLITUDE:
        return round(value * 0.25, 4)
    if quality == SignalQualityProfile.CLIPPING:
        low = mindisp if mindisp is not None else -0.5
        high = maxdisp if maxdisp is not None else 0.5
        return min(high, max(low, value))

    return value
