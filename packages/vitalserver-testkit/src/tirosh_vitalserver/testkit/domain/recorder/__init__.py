"""Vital Recorder domain value objects and pure payload helpers."""

from tirosh_vitalserver.testkit.domain.recorder.frame_playback import (
    RecorderFrameRequest,
    RecorderFrameSource,
    RecorderFrameSourceKind,
    materialize_recorder_frame,
    recorder_frame_source_uses_current_time,
)
from tirosh_vitalserver.testkit.domain.recorder.frame_post_policy import (
    DEFAULT_RECORDER_FRAME_POST_POLICY,
    RecorderFramePostPolicy,
    apply_disconnected_recorder_condition,
    apply_recorder_frame_post_policy,
)
from tirosh_vitalserver.testkit.domain.recorder.models import (
    RecorderRoom,
    VirtualRecorderPayload,
)
from tirosh_vitalserver.testkit.domain.recorder.montypes import RecorderTrackMontype
from tirosh_vitalserver.testkit.domain.recorder.payloads import (
    bed_id_for_room,
    build_realtime_message,
    build_virtual_recorder_payloads,
    combine_virtual_recorder_rooms,
    iter_recorder_rooms,
    recorder_payload_size_bytes,
    replay_recorded_recorder_payload,
    shift_recorder_payload_time,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.frames import (
    generate_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.templates import (
    build_simulated_recorder_payload,
    unique_testkit_vrcode,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario

__all__ = [
    "DEFAULT_RECORDER_FRAME_POST_POLICY",
    "RecorderFramePostPolicy",
    "RecorderFrameRequest",
    "RecorderFrameSource",
    "RecorderFrameSourceKind",
    "RecorderRoom",
    "RecorderSignalScenario",
    "RecorderTrackMontype",
    "VirtualRecorderPayload",
    "apply_disconnected_recorder_condition",
    "apply_recorder_frame_post_policy",
    "bed_id_for_room",
    "build_realtime_message",
    "build_simulated_recorder_payload",
    "build_virtual_recorder_payloads",
    "combine_virtual_recorder_rooms",
    "generate_simulated_recorder_payload",
    "iter_recorder_rooms",
    "materialize_recorder_frame",
    "recorder_frame_source_uses_current_time",
    "recorder_payload_size_bytes",
    "replay_recorded_recorder_payload",
    "shift_recorder_payload_time",
    "unique_testkit_vrcode",
]
