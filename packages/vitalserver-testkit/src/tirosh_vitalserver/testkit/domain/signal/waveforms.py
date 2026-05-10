"""Simulated biosignal waveform generation."""

from __future__ import annotations

import math

from tirosh_vitalserver.testkit.domain.signal.models import SignalProfile
from tirosh_vitalserver.testkit.domain.signal.scenarios import RecorderSignalScenario


def ecg_sample(sample_time: float, *, signal_profile: SignalProfile) -> float:
    """Return a simple ECG-like value at physiologic heart-rate timing."""

    phase = cardiac_phase(sample_time, signal_profile=signal_profile)
    value = (
        gaussian(phase, center=0.18, width=0.025, amplitude=0.06)
        - gaussian(phase, center=0.36, width=0.012, amplitude=0.18)
        + gaussian(phase, center=0.39, width=0.008, amplitude=1.0)
        - gaussian(phase, center=0.42, width=0.014, amplitude=0.28)
        + gaussian(phase, center=0.65, width=0.055, amplitude=0.22)
    )

    return round(value - 0.02, 4)


def pleth_sample(sample_time: float, *, signal_profile: SignalProfile) -> float:
    """Return a pulse oximetry plethysmography-like value."""

    phase = cardiac_phase(sample_time, signal_profile=signal_profile)

    if phase < 0.18:
        value = 38 + phase / 0.18 * 26
    elif phase < 0.42:
        value = 64 - (phase - 0.18) / 0.24 * 9
    else:
        value = 55 - (phase - 0.42) / 0.58 * 17

    dicrotic_notch = gaussian(phase, center=0.32, width=0.018, amplitude=3.0)

    return round(value - dicrotic_notch, 3)


def arterial_pressure_sample(
    sample_time: float,
    *,
    signal_profile: SignalProfile,
) -> float:
    """Return an invasive arterial pressure-like waveform value."""

    phase = cardiac_phase(sample_time, signal_profile=signal_profile)

    if phase < 0.16:
        value = 72 + phase / 0.16 * 52
    elif phase < 0.30:
        value = 124 - (phase - 0.16) / 0.14 * 18
    else:
        value = 106 - (phase - 0.30) / 0.70 * 34

    notch = gaussian(phase, center=0.34, width=0.018, amplitude=6.0)

    return round(value - notch, 3)


def co2_sample(sample_time: float, *, signal_profile: SignalProfile) -> float:
    """Return a capnography-like waveform value."""

    phase = cycle_phase(
        sample_time,
        cycles_per_minute=signal_profile.respiratory_rate_bpm,
    )

    if phase < 0.35:
        value = 0.0
    elif phase < 0.48:
        value = (phase - 0.35) / 0.13 * 38
    elif phase < 0.82:
        value = 38 + math.sin((phase - 0.48) / 0.34 * math.pi) * 2
    else:
        value = max(0.0, 38 * (1 - (phase - 0.82) / 0.18))

    return round(value, 3)


def cardiac_phase(sample_time: float, *, signal_profile: SignalProfile) -> float:
    """Return cardiac cycle phase with scenario-level timing variation."""

    phase = cycle_phase(
        sample_time,
        cycles_per_minute=signal_profile.heart_rate_bpm,
    )

    if signal_profile.scenario == RecorderSignalScenario.ARRHYTHMIA:
        phase += math.sin(sample_time * 0.9) * 0.12
        phase += math.sin(sample_time * 2.7) * 0.04

    return phase % 1


def cycle_phase(sample_time: float, *, cycles_per_minute: float) -> float:
    """Return normalized phase within one physiologic cycle."""

    if cycles_per_minute <= 0:
        return 0.0

    cycles_per_second = cycles_per_minute / 60

    return (sample_time * cycles_per_second) % 1


def gaussian(phase: float, *, center: float, width: float, amplitude: float) -> float:
    """Return a wrapped Gaussian pulse on a normalized cycle."""

    distance = min(abs(phase - center), 1 - abs(phase - center))

    return amplitude * math.exp(-0.5 * (distance / width) ** 2)
