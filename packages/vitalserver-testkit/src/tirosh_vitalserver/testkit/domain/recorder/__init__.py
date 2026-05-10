"""Vital Recorder domain value objects and pure payload helpers."""

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
    shift_recorder_payload_time,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.frames import (
    generate_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.recorder.simulator.templates import (
    build_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario

__all__ = [
    "RecorderRoom",
    "RecorderSignalScenario",
    "RecorderTrackMontype",
    "VirtualRecorderPayload",
    "bed_id_for_room",
    "build_realtime_message",
    "build_simulated_recorder_payload",
    "build_virtual_recorder_payloads",
    "combine_virtual_recorder_rooms",
    "generate_simulated_recorder_payload",
    "iter_recorder_rooms",
    "recorder_payload_size_bytes",
    "shift_recorder_payload_time",
]
