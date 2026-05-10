from __future__ import annotations

from tirosh_vitalserver.testkit.domain.signal import (
    RecorderSignalScenario,
    profile_for_scenario,
)


def test_signal_profile_presets_provide_scenario_specific_values() -> None:
    normal = profile_for_scenario(RecorderSignalScenario.NORMAL)
    tachycardia = profile_for_scenario(RecorderSignalScenario.TACHYCARDIA)
    desaturation = profile_for_scenario(RecorderSignalScenario.DESATURATION)
    device_disconnect = profile_for_scenario(RecorderSignalScenario.DEVICE_DISCONNECT)

    assert normal.heart_rate_bpm == 78
    assert tachycardia.heart_rate_bpm > normal.heart_rate_bpm
    assert desaturation.spo2_percent < normal.spo2_percent
    assert device_disconnect.heart_rate_bpm == 0
