"""Value objects for simulated biosignal generation."""

from __future__ import annotations

from dataclasses import dataclass

from tirosh_vitalserver.testkit.domain.signal.scenarios import (
    RecorderSignalScenario,
)


@dataclass(frozen=True, slots=True)
class SignalProfile:
    """Physiologic baseline values used to synthesize recorder frames."""

    scenario: RecorderSignalScenario = RecorderSignalScenario.NORMAL
    heart_rate_bpm: float = 78.0
    respiratory_rate_bpm: float = 14.0
    spo2_percent: float = 98.0
    systolic_bp_mmhg: float = 118.0
    diastolic_bp_mmhg: float = 66.0
    etco2_mmhg: float = 37.0
    noise_level: float = 0.006
    drift_level: float = 0.015
    artifact_rate: float = 0.0


DEFAULT_SIGNAL_PROFILE = SignalProfile()
