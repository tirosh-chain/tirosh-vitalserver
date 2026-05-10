"""Virtual recorder payload fan-out helpers."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from copy import deepcopy
from typing import cast

from tirosh_vitalserver.testkit.domain.recorder.models import VirtualRecorderPayload
from tirosh_vitalserver.testkit.domain.recorder.payloads.realtime import infer_vrcode
from tirosh_vitalserver.testkit.domain.recorder.payloads.rooms import (
    payload_rooms,
)
from tirosh_vitalserver.testkit.types.json import JsonObject, JsonValue


def build_virtual_recorder_payloads(
    payload: Mapping[str, JsonValue],
    *,
    count: int,
    vrcode: str | None = None,
    version: str = "testkit",
) -> tuple[VirtualRecorderPayload, ...]:
    """Create distinct recorder payloads from one sample payload."""

    if count < 1:
        raise ValueError("count must be greater than 0")

    rooms = payload_rooms(payload)
    base_vrcode = vrcode or payload_vrcode(payload) or infer_vrcode(rooms)
    virtual_payloads: list[VirtualRecorderPayload] = []

    for recorder_number in range(1, count + 1):
        suffix = f"{recorder_number:03d}"
        virtual_vrcode = base_vrcode if count == 1 else f"{base_vrcode}-{suffix}"
        virtual_rooms = build_virtual_rooms(rooms, suffix=suffix, rename=count > 1)
        virtual_payloads.append(
            VirtualRecorderPayload(
                vrcode=virtual_vrcode,
                payload={
                    "vrcode": virtual_vrcode,
                    "ver": version,
                    "rooms": virtual_rooms,
                },
            )
        )

    return tuple(virtual_payloads)


def combine_virtual_recorder_rooms(
    payloads: Iterable[VirtualRecorderPayload],
    *,
    version: str = "testkit",
) -> JsonObject:
    """Combine virtual recorder rooms into one payload for visibility checks."""

    rooms: JsonObject = {}

    for payload in payloads:
        rooms.update(payload_rooms(payload.payload))

    return {
        "vrcode": "combined-virtual-recorders",
        "ver": version,
        "rooms": rooms,
    }


def build_virtual_rooms(
    rooms: Mapping[str, JsonValue],
    *,
    suffix: str,
    rename: bool,
) -> JsonObject:
    """Build renamed rooms for one virtual recorder."""

    virtual_rooms: JsonObject = {}

    for key, room_payload in rooms.items():
        virtual_key = key if not rename else f"{key}-{suffix}"
        virtual_rooms[virtual_key] = build_virtual_room(
            key,
            room_payload,
            suffix=suffix,
            rename=rename,
        )

    return virtual_rooms


def build_virtual_room(
    key: str,
    room_payload: JsonValue,
    *,
    suffix: str,
    rename: bool,
) -> JsonValue:
    """Build one renamed room payload for a virtual recorder."""

    cloned = deepcopy(room_payload)

    if not isinstance(cloned, dict):
        return cast(JsonValue, cloned)

    room_name = cloned.get("roomname")
    base_room_name = room_name if isinstance(room_name, str) and room_name else key
    cloned["roomname"] = base_room_name if not rename else f"{base_room_name}-{suffix}"

    return cast(JsonValue, cloned)


def payload_vrcode(payload: Mapping[str, JsonValue]) -> str | None:
    """Return a realtime message recorder code when present."""

    vrcode = payload.get("vrcode")

    return vrcode if isinstance(vrcode, str) else None
