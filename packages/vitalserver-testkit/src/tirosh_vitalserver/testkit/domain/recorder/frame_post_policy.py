"""Post-processing policy for materialized recorder frames."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass

from tirosh_vitalserver.testkit.types.json import JsonObject


@dataclass(frozen=True)
class RecorderFramePostPolicy:
    """Source-independent post policy for one materialized recorder frame."""

    disconnected: bool = False


DEFAULT_RECORDER_FRAME_POST_POLICY = RecorderFramePostPolicy()


def apply_recorder_frame_post_policy(
    payload: JsonObject,
    policy: RecorderFramePostPolicy = DEFAULT_RECORDER_FRAME_POST_POLICY,
) -> JsonObject:
    """Apply source-independent post policy to a materialized frame."""

    if policy.disconnected:
        return apply_disconnected_recorder_condition(payload)

    return payload


def apply_disconnected_recorder_condition(payload: JsonObject) -> JsonObject:
    """Return payload with explicit disconnected device state."""

    disconnected = deepcopy(payload)
    rooms = disconnected.get("rooms")
    room_map = rooms if isinstance(rooms, dict) else disconnected

    for room in room_map.values():
        if not isinstance(room, dict):
            continue
        room["ptcon"] = 0
        room["recording"] = 0

        devices = room.get("devs")
        if isinstance(devices, list):
            for device in devices:
                if isinstance(device, dict):
                    device["status"] = "off"

        tracks = room.get("trks")
        if isinstance(tracks, list):
            for track in tracks:
                if isinstance(track, dict):
                    track["recs"] = []

    return disconnected
