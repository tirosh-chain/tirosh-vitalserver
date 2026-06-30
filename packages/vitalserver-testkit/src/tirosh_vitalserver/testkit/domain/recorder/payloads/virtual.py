"""Virtual recorder payload fan-out helpers."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from copy import deepcopy

from tirosh_vitalserver.testkit.domain.bed import require_bed_capacity_for_recorders
from tirosh_vitalserver.testkit.domain.recorder.models import VirtualRecorderPayload
from tirosh_vitalserver.testkit.domain.recorder.payloads.realtime import infer_vrcode
from tirosh_vitalserver.testkit.domain.recorder.payloads.rooms import (
    payload_rooms,
)
from tirosh_vitalserver.testkit.errors import RecorderCountInvalidError
from tirosh_vitalserver.testkit.types.json import JsonObject, JsonValue


def build_virtual_recorder_payloads(
    payload: Mapping[str, JsonValue],
    *,
    count: int,
    vrcode: str | None = None,
    version: str = "testkit",
) -> tuple[VirtualRecorderPayload, ...]:
    """Create VRecorder payloads connected to existing bed rooms."""

    if count < 1:
        raise RecorderCountInvalidError()

    rooms = payload_rooms(payload)
    room_groups = split_rooms_for_recorders(rooms, count=count)
    base_vrcode = vrcode or payload_vrcode(payload) or infer_vrcode(rooms)
    virtual_payloads: list[VirtualRecorderPayload] = []

    for recorder_number in range(1, count + 1):
        suffix = f"{recorder_number:03d}"
        virtual_vrcode = base_vrcode if count == 1 else f"{base_vrcode}-{suffix}"
        virtual_payloads.append(
            VirtualRecorderPayload(
                vrcode=virtual_vrcode,
                payload={
                    "vrcode": virtual_vrcode,
                    "ver": version,
                    "rooms": room_groups[recorder_number - 1],
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


def split_rooms_for_recorders(
    rooms: Mapping[str, JsonValue],
    *,
    count: int,
) -> tuple[JsonObject, ...]:
    """Assign explicit test bedrooms to virtual recorders."""

    room_items = tuple(rooms.items())
    if len(room_items) == 1 and count > 1:
        room_name, room = room_items[0]
        return tuple({room_name: deepcopy(room)} for _ in range(count))

    require_bed_capacity_for_recorders(
        bed_count=len(room_items),
        recorder_count=count,
    )

    groups: list[JsonObject] = []
    cursor = 0
    for index in range(count):
        remaining_rooms = len(room_items) - cursor
        remaining_recorders = count - index
        group_size = max(1, remaining_rooms // remaining_recorders)
        group_items = room_items[cursor : cursor + group_size]
        groups.append({key: deepcopy(room) for key, room in group_items})
        cursor += group_size

    return tuple(groups)


def payload_vrcode(payload: Mapping[str, JsonValue]) -> str | None:
    """Return a realtime message recorder code when present."""

    vrcode = payload.get("vrcode")

    return vrcode if isinstance(vrcode, str) else None
