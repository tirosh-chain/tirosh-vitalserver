"""Application runtime for virtual VRecorder sessions."""

from tirosh_vitalserver.testkit.application.recorder_session.documents import (
    deletion_result_to_document,
    recorder_snapshot_to_document,
    session_snapshot_to_document,
)
from tirosh_vitalserver.testkit.application.recorder_session.manager import (
    VirtualRecorderSessionManager,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    RecorderCondition,
    RecorderScenarioWindow,
    RecorderSessionOutput,
    RecorderTestScenario,
    VirtualRecorderCleanupError,
    VirtualRecorderDeletionResult,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionSnapshot,
    VirtualRecorderSessionState,
    VirtualRecorderSessionVitalState,
    VirtualRecorderVitalArtifact,
    VirtualRecorderVitalExportStatus,
    VirtualRecorderVitalUploadResult,
    VirtualRecorderVitalUploadStatus,
)
from tirosh_vitalserver.testkit.application.recorder_session.real_samples import (
    PackagedRecordedFrameSourceProvider,
    load_packaged_real_sample_manifest,
    load_packaged_real_sample_payload,
    packaged_real_sample_catalog_document,
)
from tirosh_vitalserver.testkit.application.recorder_session.recording import (
    SessionPlaybackEvent,
    SessionPlaybackEventType,
    SessionRecorderPlayback,
    SessionVitalPlayback,
)
from tirosh_vitalserver.testkit.application.recorder_session.scenarios import (
    RecorderScenarioDefinition,
    RecorderScenarioProvider,
    default_scenario_catalog,
    require_scenario_definition,
    scenario_definition_to_document,
)
from tirosh_vitalserver.testkit.application.recorder_session.session import (
    VirtualRecorderSession,
)
from tirosh_vitalserver.testkit.application.recorder_session.store import (
    VirtualRecorderSessionStorePort,
)

__all__ = [
    "RecorderCondition",
    "RecorderScenarioDefinition",
    "RecorderScenarioProvider",
    "RecorderScenarioWindow",
    "RecorderSessionOutput",
    "RecorderTestScenario",
    "SessionPlaybackEvent",
    "SessionPlaybackEventType",
    "SessionRecorderPlayback",
    "SessionVitalPlayback",
    "VirtualRecorderCleanupError",
    "VirtualRecorderDeletionResult",
    "VirtualRecorderSession",
    "VirtualRecorderSessionManager",
    "VirtualRecorderSessionRequest",
    "VirtualRecorderSessionSnapshot",
    "VirtualRecorderSessionState",
    "VirtualRecorderSessionStorePort",
    "VirtualRecorderSessionVitalState",
    "VirtualRecorderVitalArtifact",
    "VirtualRecorderVitalExportStatus",
    "VirtualRecorderVitalUploadResult",
    "VirtualRecorderVitalUploadStatus",
    "PackagedRecordedFrameSourceProvider",
    "default_scenario_catalog",
    "deletion_result_to_document",
    "load_packaged_real_sample_manifest",
    "load_packaged_real_sample_payload",
    "packaged_real_sample_catalog_document",
    "recorder_snapshot_to_document",
    "require_scenario_definition",
    "scenario_definition_to_document",
    "session_snapshot_to_document",
]
