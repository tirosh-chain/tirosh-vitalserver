"""Socket.IO realtime recorder message helpers."""

from __future__ import annotations

from collections.abc import Mapping

from tirosh_vitalserver.testkit.types.json import JsonObject, JsonValue


def build_realtime_message(
    payload: Mapping[str, JsonValue],
    *,
    vrcode: str | None = None,
    version: str = "testkit",
) -> JsonObject:
    """Return the JSON shape expected by VitalServer Socket.IO `send_data`.

    VitalServer's upstream `monitor.send_data()` inflates a compressed JSON
    object with `vrcode`, `ver`, and `rooms`. Existing sample payloads may
    already be a room map, so this helper wraps them without mutating the
    original object.
    """

    if is_realtime_message(payload):
        return dict(payload)

    room_map = dict(payload)
    recorder_code = vrcode or infer_vrcode(room_map)

    return {
        "vrcode": recorder_code,
        "ver": version,
        "rooms": room_map,
    }


def is_realtime_message(payload: Mapping[str, JsonValue]) -> bool:
    """Return whether a payload is already a Socket.IO realtime message."""

    return (
        isinstance(payload.get("vrcode"), str)
        and isinstance(payload.get("rooms"), dict)
        and "ver" in payload
    )


def infer_vrcode(payload: Mapping[str, JsonValue]) -> str:
    """Infer a recorder code from a room map-like payload."""

    if len(payload) == 1:
        key = next(iter(payload))
        if key:
            return key

    return "testkit"
