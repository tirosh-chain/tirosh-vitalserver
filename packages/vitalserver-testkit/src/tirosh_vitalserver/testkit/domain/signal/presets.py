"""Scenario presets for simulated biosignal generation."""

from __future__ import annotations

from dataclasses import replace

from tirosh_vitalserver.testkit.domain.signal.models import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
)
from tirosh_vitalserver.testkit.domain.signal.scenarios import RecorderSignalScenario


def profile_for_scenario(scenario: RecorderSignalScenario) -> SignalProfile:
    """Return the default simulated signal profile for one scenario."""

    match scenario:
        case RecorderSignalScenario.NORMAL:
            return DEFAULT_SIGNAL_PROFILE
        case RecorderSignalScenario.TACHYCARDIA:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                heart_rate_bpm=128.0,
            )
        case RecorderSignalScenario.BRADYCARDIA:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                heart_rate_bpm=44.0,
            )
        case RecorderSignalScenario.HYPOTENSION:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                systolic_bp_mmhg=82.0,
                diastolic_bp_mmhg=46.0,
            )
        case RecorderSignalScenario.HYPERTENSION:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                systolic_bp_mmhg=172.0,
                diastolic_bp_mmhg=98.0,
            )
        case RecorderSignalScenario.DESATURATION:
            return replace(DEFAULT_SIGNAL_PROFILE, scenario=scenario, spo2_percent=86.0)
        case RecorderSignalScenario.APNEA:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                respiratory_rate_bpm=3.0,
                etco2_mmhg=8.0,
            )
        case RecorderSignalScenario.ARRHYTHMIA:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                heart_rate_bpm=96.0,
                noise_level=0.012,
                drift_level=0.08,
            )
        case RecorderSignalScenario.ARTIFACT:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                noise_level=0.12,
                drift_level=0.03,
                artifact_rate=0.08,
            )
        case RecorderSignalScenario.DEVICE_DISCONNECT:
            return replace(
                DEFAULT_SIGNAL_PROFILE,
                scenario=scenario,
                heart_rate_bpm=0.0,
                respiratory_rate_bpm=0.0,
                spo2_percent=0.0,
                systolic_bp_mmhg=0.0,
                diastolic_bp_mmhg=0.0,
                etco2_mmhg=0.0,
                noise_level=0.0,
                drift_level=0.0,
                artifact_rate=0.0,
            )
