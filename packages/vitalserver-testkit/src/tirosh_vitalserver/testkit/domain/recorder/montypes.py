"""Vital Recorder monitor type identifiers."""

from __future__ import annotations

from enum import StrEnum
from typing import Self

from tirosh_vitalserver.testkit.types.json import JsonValue


class RecorderTrackMontype(StrEnum):
    """Known Vital Recorder `montype` values used by simulated payloads."""

    ECG_WAVE = "ECG_WAV"
    PLETH_WAVE = "PLETH_WAV"
    ARTERIAL_PRESSURE_WAVE = "IABP_WAV"
    CO2_WAVE = "CO2_WAV"
    ECG_HEART_RATE = "ECG_HR"
    PLETH_SPO2 = "PLETH_SPO2"
    CO2_CONCENTRATION = "CO2_CONC"
    CO2_RESPIRATORY_RATE = "CO2_RR"
    ARTERIAL_SYSTOLIC_BP = "IABP_SBP"
    ARTERIAL_DIASTOLIC_BP = "IABP_DBP"
    ARTERIAL_MEAN_BP = "IABP_MBP"
    HCT = "HCT"

    @classmethod
    def parse(cls, value: JsonValue) -> Self | None:
        """Return a known monitor type or None for external unknown values."""

        if not isinstance(value, str):
            return None

        try:
            return cls(value)
        except ValueError:
            return None
