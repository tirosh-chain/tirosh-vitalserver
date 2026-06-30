"""Signal scenario names for simulated biosignal generation."""

from __future__ import annotations

from enum import StrEnum


class RecorderSignalScenario(StrEnum):
    """Supported simulated signal scenario names.

    These names describe simulated biosignal generation presets. They are not
    diagnoses; they are test scenarios for VitalServer productization work.
    """

    # Baseline adult-like vital signs used for ordinary throughput checks.
    NORMAL = "normal"

    # Faster heart rhythm, useful when checking waveform density and HR display.
    TACHYCARDIA = "tachycardia"

    # Slower heart rhythm, useful when checking sparse beat rendering.
    BRADYCARDIA = "bradycardia"

    # Lower arterial pressure, useful for BP numeric and waveform behavior.
    HYPOTENSION = "hypotension"

    # Higher arterial pressure, useful for BP scale and alarm-like UI behavior.
    HYPERTENSION = "hypertension"

    # Lower pulse oxygen saturation, useful for SpO2 trend visibility checks.
    DESATURATION = "desaturation"

    # Paused or severely reduced respiration, useful for CO2/RR behavior checks.
    APNEA = "apnea"

    # Irregular beat timing, useful for stress-testing waveform continuity.
    ARRHYTHMIA = "arrhythmia"

    # Noisy or distorted samples, useful for renderer and transport resilience.
    ARTIFACT = "artifact"

    # Missing signal source, useful for testing stale data and disconnect states.
    DEVICE_DISCONNECT = "device_disconnect"

    # Gradually decreasing hematocrit, useful for bloodbag inference context.
    HCT_DECREASING = "hct_decreasing"
