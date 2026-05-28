"""Application contracts for virtual VRecorder sessions."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeSnapshot,
)
from tirosh_vitalserver.testkit.domain.bed import (
    normalize_bed_room_names,
    require_bed_capacity_for_recorders,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario


class VirtualRecorderSessionState(StrEnum):
    """Runtime state for a virtual recorder session."""

    STARTING = "starting"
    RUNNING = "running"
    PAUSED = "paused"
    STOPPING = "stopping"
    STOPPED = "stopped"
    FAILED = "failed"


class VirtualRecorderSessionScenario(StrEnum):
    """Session-level traffic/lifecycle scenario for virtual recorders."""

    NORMAL = "normal"
    MULTIPLE_RECORDERS = "multiple_recorders"
    BURST_TRAFFIC = "burst_traffic"
    DISCONNECT_RECONNECT = "disconnect_reconnect"
    STALE_RECORDER = "stale_recorder"
    SIGNAL_ANOMALY = "signal_anomaly"


@dataclass(frozen=True)
class VirtualRecorderSessionRequest:
    """Input contract for a virtual recorder streaming session."""

    target_url: str
    recorders: int = 1
    bed_room_names: tuple[str, ...] = ()
    vrcode: str | None = None
    version: str = "testkit"
    interval_seconds: float = 1.0
    duration_seconds: float | None = None
    max_messages: int | None = None
    shift_time: bool = True
    generate_frames: bool = True
    scenario: VirtualRecorderSessionScenario = VirtualRecorderSessionScenario.NORMAL
    default_scenario: RecorderSignalScenario = RecorderSignalScenario.NORMAL

    def __post_init__(self) -> None:
        """Validate session options at the application boundary."""

        if not self.target_url:
            raise ValueError("target_url is required")
        if self.recorders < 1:
            raise ValueError("recorders must be greater than 0")
        if not self.bed_room_names:
            raise ValueError("bed_room_names is required")
        try:
            bed_room_names = normalize_bed_room_names(self.bed_room_names)
        except ValueError as exc:
            raise ValueError(str(exc).replace("room_names", "bed_room_names")) from exc
        object.__setattr__(self, "bed_room_names", bed_room_names)
        require_bed_capacity_for_recorders(
            bed_count=len(self.bed_room_names),
            recorder_count=self.recorders,
        )
        if self.interval_seconds <= 0:
            raise ValueError("interval_seconds must be greater than 0")
        if self.duration_seconds is not None and self.duration_seconds < 0:
            raise ValueError("duration_seconds must be greater than or equal to 0")
        if self.max_messages is not None and self.max_messages < 1:
            raise ValueError("max_messages must be greater than 0")


@dataclass(frozen=True)
class VirtualRecorderCleanupError:
    """One failed VitalServer cleanup operation for a virtual recorder."""

    vrcode: str
    target_url: str
    error: str


@dataclass(frozen=True)
class VirtualRecorderDeletionResult:
    """Result of a direct VitalServer VRecorder deletion request."""

    vrcode: str
    target_url: str
    deleted: bool
    error: str | None = None


@dataclass(frozen=True)
class VirtualRecorderSessionSnapshot:
    """Serializable session state for UI/API consumers."""

    session_id: str
    state: VirtualRecorderSessionState
    request: VirtualRecorderSessionRequest
    created_at: float
    started_at: float | None
    stopped_at: float | None
    recorders: tuple[RecorderRuntimeSnapshot, ...]
    messages_sent: int
    bytes_sent: int
    error: str | None
    cleanup_errors: tuple[VirtualRecorderCleanupError, ...] = ()
