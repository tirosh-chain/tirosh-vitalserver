"""Application contracts for virtual VRecorder sessions."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeSnapshot,
)
from tirosh_vitalserver.testkit.domain.bed.identity import (
    normalize_bed_room_name,
    normalize_bed_room_names,
)


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
    """Purpose-centered Test tab scenarios."""

    NORMAL_MONITORING = "normal_monitoring"
    TACHYCARDIA = "tachycardia"
    DESATURATION = "desaturation"
    SIGNAL_ARTIFACT = "signal_artifact"
    DEVICE_DISCONNECT = "device_disconnect"
    HCT_DECREASING = "hct_decreasing"
    BLOODBAG_TRANSFUSION = "bloodbag_transfusion"
    PERIOPERATIVE_MONITORING = "perioperative_monitoring"
    SEDATION_MONITORING = "sedation_monitoring"
    FULL_MONITORING_REPLAY = "full_monitoring_replay"


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
        if self.interval_seconds <= 0:
            raise ValueError("interval_seconds must be greater than 0")
        if self.max_messages is not None and self.max_messages < 1:
            raise ValueError("max_messages must be greater than 0")

    @property
    def duration_seconds(self) -> float | None:
        """Return the streaming duration requested by the scenario window."""

        return None if self.window is None else self.window.duration_seconds

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
