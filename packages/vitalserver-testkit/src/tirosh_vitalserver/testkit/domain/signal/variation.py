"""Deterministic variation helpers for simulated biosignals."""

from __future__ import annotations

import math

from tirosh_vitalserver.testkit.domain.signal.models import SignalProfile


def apply_signal_variation(
    value: float,
    *,
    sample_time: float,
    signal_profile: SignalProfile,
) -> float:
    """Apply deterministic noise-like variation from the signal profile."""

    generated = value

    if signal_profile.drift_level:
        generated += math.sin(sample_time / 12) * max(
            abs(value) * signal_profile.drift_level,
            signal_profile.drift_level,
        )

    if signal_profile.noise_level:
        generated += (
            pseudo_random_unit(sample_time, salt=value)
            * max(abs(value) * signal_profile.noise_level, signal_profile.noise_level)
        )

    if signal_profile.artifact_rate and artifact_gate(
        sample_time,
        artifact_rate=signal_profile.artifact_rate,
    ):
        generated += signal_profile.artifact_rate * 10

    return round(generated, 4)


def apply_numeric_variation(
    base: float,
    *,
    now: float,
    signal_profile: SignalProfile,
) -> int | float:
    """Generate one simulated numeric value with deterministic variation."""

    if base == 0:
        return 0

    variation = math.sin(now / 5) * max(abs(base) * 0.01, 0.1)
    variation += math.sin(now / 31) * abs(base) * signal_profile.drift_level
    variation += (
        pseudo_random_unit(now, salt=base)
        * max(abs(base) * signal_profile.noise_level, 0.05)
    )
    generated = base + variation

    if base.is_integer():
        return round(generated)

    return round(generated, 3)


def artifact_gate(sample_time: float, *, artifact_rate: float) -> bool:
    """Return a deterministic sparse artifact gate for simulated signals."""

    if artifact_rate <= 0:
        return False

    return math.sin(sample_time * 17.0) > 1 - artifact_rate


def pseudo_random_unit(value: float, *, salt: float) -> float:
    """Return a deterministic pseudo-random value in the -1..1 range."""

    raw = math.sin(value * 12.9898 + salt * 78.233) * 43758.5453
    fraction = raw - math.floor(raw)

    return fraction * 2 - 1
