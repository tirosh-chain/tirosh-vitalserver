"""Top-level use case for running VRecorder-compatible streams."""

from __future__ import annotations

from collections.abc import Iterable, Mapping

from tirosh_vitalserver.testkit.application.ports import SocketIoConnectorPort
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeRegistry,
)
from tirosh_vitalserver.testkit.application.results import StreamSummary
from tirosh_vitalserver.testkit.application.usecases.recorder.transfer import (
    stream_virtual_recorder_payloads,
)
from tirosh_vitalserver.testkit.domain.recorder.models import VirtualRecorderPayload
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
    SignalQualityProfile,
)


def stream_vrecorder_session(
    base_url: str,
    payloads: Iterable[VirtualRecorderPayload],
    *,
    timeout: float = 30.0,
    interval_seconds: float = 1.0,
    duration_seconds: float | None = None,
    max_messages: int | None = None,
    shift_time: bool = True,
    generate_frames: bool = True,
    default_signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
    signal_profiles: Mapping[int, SignalProfile] | None = None,
    runtime_registry: RecorderRuntimeRegistry | None = None,
    connector: SocketIoConnectorPort,
) -> StreamSummary:
    """Run one or more VRecorder-compatible Socket.IO streaming sessions."""

    if runtime_registry is None:
        runtime_registry = RecorderRuntimeRegistry()

    return stream_virtual_recorder_payloads(
        base_url,
        payloads,
        timeout=timeout,
        interval_seconds=interval_seconds,
        duration_seconds=duration_seconds,
        max_messages=max_messages,
        shift_time=shift_time,
        generate_frames=generate_frames,
        default_signal_profile=default_signal_profile,
        signal_quality=signal_quality,
        signal_profiles=signal_profiles,
        runtime_registry=runtime_registry,
        connector=connector,
    )
