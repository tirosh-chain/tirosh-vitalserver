"""VitalServer load and transfer test helpers."""

from .adapters.outbound.recorder import connect_socketio
from .adapters.outbound.vitalserver import VitalServerClient
from .application.metrics import (
    stream_total_bytes_sent,
    stream_total_messages_sent,
)
from .application.recorder_runtime import RecorderRuntimeRegistry
from .application.results import (
    RealtimeSendResult,
    RealtimeStreamResult,
    RecorderSendResult,
    RecorderVisibilityResult,
    StreamSummary,
    TransferSummary,
    UploadResult,
)
from .application.usecases import (
    send_realtime_payloads,
    send_recorder_payloads,
    send_virtual_recorder_payloads,
    stream_virtual_recorder_payloads,
    stream_vrecorder_session,
    upload_vital_files,
    wait_for_server,
)
from .application.usecases.recorder import (
    encode_realtime_payload,
    send_realtime_payload,
    stream_realtime_payload,
)
from .application.usecases.recorder.visibility import wait_for_recorder_visibility
from .domain.recorder import (
    RecorderRoom,
    RecorderTrackMontype,
    VirtualRecorderPayload,
    bed_id_for_room,
    build_realtime_message,
    build_simulated_recorder_payload,
    build_virtual_recorder_payloads,
    combine_virtual_recorder_rooms,
    iter_recorder_rooms,
    recorder_payload_size_bytes,
    shift_recorder_payload_time,
)
from .domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    RecorderSignalScenario,
    SignalProfile,
    profile_for_scenario,
)
from .domain.vital_file import (
    PayloadFile,
    assert_vital_filenames,
    iter_vital_files,
)
from .schemas.payloads import load_recorder_payload

__all__ = [
    "DEFAULT_SIGNAL_PROFILE",
    "PayloadFile",
    "RealtimeSendResult",
    "RealtimeStreamResult",
    "RecorderRoom",
    "RecorderRuntimeRegistry",
    "RecorderSendResult",
    "RecorderSignalScenario",
    "RecorderTrackMontype",
    "RecorderVisibilityResult",
    "SignalProfile",
    "StreamSummary",
    "TransferSummary",
    "UploadResult",
    "VirtualRecorderPayload",
    "VitalServerClient",
    "__version__",
    "assert_vital_filenames",
    "bed_id_for_room",
    "build_realtime_message",
    "build_simulated_recorder_payload",
    "build_virtual_recorder_payloads",
    "combine_virtual_recorder_rooms",
    "connect_socketio",
    "encode_realtime_payload",
    "iter_recorder_rooms",
    "iter_vital_files",
    "load_recorder_payload",
    "profile_for_scenario",
    "recorder_payload_size_bytes",
    "send_realtime_payload",
    "send_realtime_payloads",
    "send_recorder_payloads",
    "send_virtual_recorder_payloads",
    "shift_recorder_payload_time",
    "stream_realtime_payload",
    "stream_total_bytes_sent",
    "stream_total_messages_sent",
    "stream_virtual_recorder_payloads",
    "stream_vrecorder_session",
    "upload_vital_files",
    "wait_for_recorder_visibility",
    "wait_for_server",
]

__version__ = "0.1.0"
