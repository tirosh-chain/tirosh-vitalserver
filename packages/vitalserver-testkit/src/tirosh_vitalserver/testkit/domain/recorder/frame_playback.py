"""Recorder frame source and playback policy."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum

from tirosh_vitalserver.testkit.domain.recorder.payloads.replay import (
    replay_recorded_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.frames import (
    generate_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
    SignalQualityProfile,
)
from tirosh_vitalserver.testkit.types.json import JsonObject, JsonValue


class RecorderFrameSourceKind(StrEnum):
    """Supported frame source families."""

    GENERATED = "generated"
    RECORDED = "recorded"
    STATIC = "static"


@dataclass(frozen=True)
class RecorderFrameSource:
    """Explicit source data for realtime recorder frame playback."""

    kind: RecorderFrameSourceKind
    payload: Mapping[str, JsonValue]
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN


@dataclass(frozen=True)
class RecorderFrameRequest:
    """One realtime frame request."""

    sequence: int
    now: float
    frame_seconds: float

    def __post_init__(self) -> None:
        """Validate frame request timing."""

        if self.sequence < 0:
            raise ValueError("sequence must not be negative")
        if self.frame_seconds <= 0:
            raise ValueError("frame_seconds must be greater than 0")


def materialize_recorder_frame(
    source: RecorderFrameSource,
    request: RecorderFrameRequest,
) -> JsonObject:
    """Return the current recorder frame for one source."""

    if source.kind == RecorderFrameSourceKind.GENERATED:
        return generate_simulated_recorder_payload(
            source.payload,
            now=request.now,
            frame_seconds=request.frame_seconds,
            sequence=request.sequence,
            signal_profile=source.signal_profile,
            signal_quality=source.signal_quality,
        )

    if source.kind == RecorderFrameSourceKind.RECORDED:
        return replay_recorded_recorder_payload(
            source.payload,
            now=request.now,
            frame_seconds=request.frame_seconds,
            sequence=request.sequence,
        )

    if source.kind == RecorderFrameSourceKind.STATIC:
        return dict(source.payload)

    raise ValueError(f"unsupported recorder frame source kind: {source.kind}")


def recorder_frame_source_uses_current_time(source: RecorderFrameSource) -> bool:
    """Return whether frame materialization already projected timestamps."""

    return source.kind in {
        RecorderFrameSourceKind.GENERATED,
        RecorderFrameSourceKind.RECORDED,
    }
