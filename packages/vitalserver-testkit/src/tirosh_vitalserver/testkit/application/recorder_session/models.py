"""Application contracts for virtual VRecorder sessions."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeSnapshot,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalSampleScenario,
)
from tirosh_vitalserver.testkit.domain.bed.identity import (
    normalize_bed_room_name,
    normalize_bed_room_names,
)
from tirosh_vitalserver.testkit.domain.bed.rules import (
    require_bed_capacity_for_recorders,
)
from tirosh_vitalserver.testkit.domain.signal import SignalQualityProfile


class VirtualRecorderSessionState(StrEnum):
    """Runtime state for a virtual recorder session."""

    STARTING = "starting"
    RUNNING = "running"
    PAUSED = "paused"
    STOPPING = "stopping"
    STOPPED = "stopped"
    FAILED = "failed"
    FINALIZING_VITAL = "finalizing-vital"
    VITAL_READY = "vital-ready"
    UPLOADING = "uploading"
    UPLOADED = "uploaded"
    UPLOAD_FAILED = "upload-failed"


class VirtualRecorderVitalExportStatus(StrEnum):
    """Explicit `.vital` artifact generation state."""

    NOT_REQUESTED = "not-requested"
    PENDING = "pending"
    FINALIZING = "finalizing"
    READY = "ready"
    FAILED = "failed"
    BLOCKED = "blocked"


class VirtualRecorderVitalUploadStatus(StrEnum):
    """Explicit `.vital` upload state."""

    NOT_REQUESTED = "not-requested"
    PENDING = "pending"
    BLOCKED = "blocked"
    UPLOADING = "uploading"
    UPLOADED = "uploaded"
    FAILED = "failed"


class RecorderTestScenario(StrEnum):
    """Clinical Test tab scenarios."""

    NORMAL_MONITORING = "normal_monitoring"
    TACHYCARDIA = "tachycardia"
    BRADYCARDIA = "bradycardia"
    HYPOTENSION = "hypotension"
    HYPERTENSION = "hypertension"
    DESATURATION = "desaturation"
    APNEA = "apnea"
    ARRHYTHMIA = "arrhythmia"
    HCT_DECREASING = "hct_decreasing"
    BLOODBAG_TRANSFUSION = "bloodbag_transfusion"
    PERIOPERATIVE_MONITORING = "perioperative_monitoring"
    SEDATION_MONITORING = "sedation_monitoring"
    FULL_MONITORING_REPLAY = "full_monitoring_replay"


class RecorderCondition(StrEnum):
    """Operational recorder conditions independent from clinical scenario."""

    NORMAL = "normal"
    DEVICE_DISCONNECT = "device_disconnect"


class RecorderSourceType(StrEnum):
    """Explicit recorder source selected for one session."""

    VITAL_FILE = "vitalFile"


@dataclass(frozen=True)
class RecorderScenarioWindow:
    """Explicit finite source window for a recorder test scenario."""

    start_offset_seconds: float | None = None
    duration_seconds: float | None = None

    def __post_init__(self) -> None:
        """Validate window timing."""

        if (
            self.start_offset_seconds is not None
            and self.start_offset_seconds < 0
        ):
            raise ValueError(
                "window.start_offset_seconds must be greater than or equal to 0"
            )
        if self.duration_seconds is not None and self.duration_seconds < 0:
            raise ValueError(
                "window.duration_seconds must be greater than or equal to 0"
            )


@dataclass(frozen=True)
class RecorderSource:
    """Explicit external recorder source selected for one session."""

    source_type: RecorderSourceType
    path: Path | None = None
    scenario: RealVitalSampleScenario | None = None
    start_offset_seconds: float = 0.0
    duration_seconds: int = 120

    def __post_init__(self) -> None:
        """Validate source-specific contract fields."""

        if self.source_type == RecorderSourceType.VITAL_FILE:
            if self.path is None:
                raise ValueError("source.path is required for vitalFile source")
            if self.scenario is None:
                raise ValueError("source.scenario is required for vitalFile source")
            if self.start_offset_seconds < 0:
                raise ValueError(
                    "source.start_offset_seconds must be greater than or equal to 0"
                )
            if self.duration_seconds < 1:
                raise ValueError("source.duration_seconds must be greater than 0")
            object.__setattr__(self, "path", Path(self.path))
            return

        raise ValueError(f"unsupported recorder source type: {self.source_type}")


@dataclass(frozen=True)
class RecorderSessionOutput:
    """Explicit output policy for one recorder test session."""

    export_vital: bool = False
    upload_vital: bool = False
    vital_upload_endpoint: str = "/upload"

    def __post_init__(self) -> None:
        """Validate output policy."""

        if self.upload_vital and not self.export_vital:
            raise ValueError("output.upload_vital requires output.export_vital")
        if not self.vital_upload_endpoint.strip():
            raise ValueError("output.vital_upload_endpoint is required")


@dataclass(frozen=True)
class VirtualRecorderSessionRequest:
    """Input contract for a virtual recorder streaming session."""

    target_url: str
    recorders: int = 1
    bedroom_name: str = "TestBedroom"
    bed_room_names: tuple[str, ...] = ()
    scenario: RecorderTestScenario = RecorderTestScenario.NORMAL_MONITORING
    window: RecorderScenarioWindow | None = None
    output: RecorderSessionOutput = field(default_factory=RecorderSessionOutput)
    vrcode: str | None = None
    version: str = "testkit"
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN
    recorder_condition: RecorderCondition = RecorderCondition.NORMAL
    source: RecorderSource | None = None
    real_sample_key: str | None = None
    interval_seconds: float = 1.0
    max_messages: int | None = None
    shift_time: bool = True
    generate_frames: bool = True

    def __post_init__(self) -> None:
        """Validate session options at the application boundary."""

        if not self.target_url:
            raise ValueError("target_url is required")
        if self.recorders < 1:
            raise ValueError("recorders must be greater than 0")
        if self.bed_room_names:
            try:
                bed_room_names = normalize_bed_room_names(self.bed_room_names)
            except ValueError as exc:
                raise ValueError(str(exc).replace("room_name", "bedroom_name")) from exc
            object.__setattr__(self, "bed_room_names", bed_room_names)
            object.__setattr__(self, "bedroom_name", bed_room_names[0])
        else:
            try:
                bedroom_name = normalize_bed_room_name(self.bedroom_name)
            except ValueError as exc:
                raise ValueError(str(exc).replace("room_name", "bedroom_name")) from exc
            object.__setattr__(self, "bedroom_name", bedroom_name)
            object.__setattr__(self, "bed_room_names", (bedroom_name,))
        require_bed_capacity_for_recorders(
            bed_count=len(self.bed_room_names),
            recorder_count=self.recorders,
        )
        if self.interval_seconds <= 0:
            raise ValueError("interval_seconds must be greater than 0")
        if self.max_messages is not None and self.max_messages < 1:
            raise ValueError("max_messages must be greater than 0")
        if self.real_sample_key is not None and not self.real_sample_key.strip():
            raise ValueError("real_sample_key must not be empty")
        if self.source is not None and self.real_sample_key is not None:
            raise ValueError("source and real_sample_key must not both be set")

    @property
    def duration_seconds(self) -> float | None:
        """Return the streaming duration requested by the scenario window."""

        if self.window is not None:
            return self.window.duration_seconds
        if self.source is not None:
            return float(self.source.duration_seconds)
        return None

    @property
    def export_vital(self) -> bool:
        """Return whether the session should export a `.vital` artifact."""

        return self.output.export_vital

    @property
    def upload_vital(self) -> bool:
        """Return whether the exported `.vital` artifact should be uploaded."""

        return self.output.upload_vital

    @property
    def vital_upload_endpoint(self) -> str:
        """Return the explicit VitalServer upload endpoint."""

        return self.output.vital_upload_endpoint


@dataclass(frozen=True)
class VirtualRecorderVitalArtifact:
    """Generated `.vital` artifact owned by a session."""

    path: str
    filename: str
    size_bytes: int
    created_at: float
    format: str
    retention_policy: str = "preserve-on-delete"


@dataclass(frozen=True)
class VirtualRecorderVitalUploadResult:
    """VitalServer upload result for a generated session artifact."""

    status_code: int
    ok: bool
    elapsed_seconds: float
    uploaded_at: float
    response_text: str
    error: str | None = None


@dataclass(frozen=True)
class VirtualRecorderSessionVitalState:
    """Explicit export/upload state for a virtual recorder session."""

    export_status: VirtualRecorderVitalExportStatus
    upload_status: VirtualRecorderVitalUploadStatus
    artifact: VirtualRecorderVitalArtifact | None = None
    export_error: str | None = None
    upload_error: str | None = None
    upload_result: VirtualRecorderVitalUploadResult | None = None

    @classmethod
    def for_request(
        cls,
        request: VirtualRecorderSessionRequest,
    ) -> VirtualRecorderSessionVitalState:
        """Return the initial vital artifact state for one request."""

        return cls(
            export_status=(
                VirtualRecorderVitalExportStatus.PENDING
                if request.output.export_vital
                else VirtualRecorderVitalExportStatus.NOT_REQUESTED
            ),
            upload_status=(
                VirtualRecorderVitalUploadStatus.PENDING
                if request.output.upload_vital
                else VirtualRecorderVitalUploadStatus.NOT_REQUESTED
            ),
        )


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
    vital_state: VirtualRecorderSessionVitalState = field(
        default_factory=lambda: VirtualRecorderSessionVitalState(
            export_status=VirtualRecorderVitalExportStatus.NOT_REQUESTED,
            upload_status=VirtualRecorderVitalUploadStatus.NOT_REQUESTED,
        )
    )
