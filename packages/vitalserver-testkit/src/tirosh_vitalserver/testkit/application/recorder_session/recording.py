"""Explicit playback contract for virtual recorder session exports."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario
from tirosh_vitalserver.testkit.types.json import JsonObject


class SessionPlaybackEventType(StrEnum):
    """Lifecycle events that shape `.vital` playback time."""

    STARTED = "started"
    PAUSED = "paused"
    RESUMED = "resumed"
    STOPPED = "stopped"


@dataclass(frozen=True)
class SessionPlaybackEvent:
    """One explicit session-time event for playback reconstruction."""

    type: SessionPlaybackEventType
    at: float


@dataclass(frozen=True)
class SessionRecorderPlayback:
    """The finite play range for one streamed virtual recorder."""

    vrcode: str
    payload: JsonObject
    messages_sent: int


@dataclass(frozen=True)
class SessionVitalPlayback:
    """Finite session input used to regenerate a `.vital` artifact."""

    recorders: tuple[SessionRecorderPlayback, ...]
    events: tuple[SessionPlaybackEvent, ...]
    started_at: float
    stopped_at: float
    interval_seconds: float
    generate_frames: bool
    default_scenario: RecorderSignalScenario
