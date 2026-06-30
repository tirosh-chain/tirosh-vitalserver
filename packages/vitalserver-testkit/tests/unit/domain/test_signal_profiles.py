from __future__ import annotations

from tirosh_vitalserver.testkit.domain.signal import (
    RecorderSignalScenario,
    profile_for_scenario,
)


def test_signal_profile_presets_provide_scenario_specific_values() -> None:
    normal = profile_for_scenario(RecorderSignalScenario.NORMAL)
    tachycardia = profile_for_scenario(RecorderSignalScenario.TACHYCARDIA)
    desaturation = profile_for_scenario(RecorderSignalScenario.DESATURATION)
    hypotension = profile_for_scenario(RecorderSignalScenario.HYPOTENSION)
    apnea = profile_for_scenario(RecorderSignalScenario.APNEA)
    hct_decreasing = profile_for_scenario(RecorderSignalScenario.HCT_DECREASING)

    assert normal.heart_rate_bpm == 78
    assert normal.hct_percent == 35
    assert tachycardia.heart_rate_bpm > normal.heart_rate_bpm
    assert desaturation.spo2_percent < normal.spo2_percent
    assert hypotension.systolic_bp_mmhg < normal.systolic_bp_mmhg
    assert apnea.respiratory_rate_bpm < normal.respiratory_rate_bpm
    assert hct_decreasing.hct_percent == 35
    assert hct_decreasing.hct_trend_percent_per_second < 0
