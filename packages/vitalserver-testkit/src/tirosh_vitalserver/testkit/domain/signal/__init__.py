"""Simulated biosignal domain objects."""

from tirosh_vitalserver.testkit.domain.signal.models import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
)
from tirosh_vitalserver.testkit.domain.signal.presets import (
    profile_for_scenario,
    profile_with_hct_override,
)
from tirosh_vitalserver.testkit.domain.signal.scenarios import (
    RecorderSignalScenario,
)

__all__ = [
    "DEFAULT_SIGNAL_PROFILE",
    "RecorderSignalScenario",
    "SignalProfile",
    "profile_for_scenario",
    "profile_with_hct_override",
]
