"""Value objects for Vital Recorder data."""

from __future__ import annotations

from dataclasses import dataclass

from tirosh_vitalserver.testkit.types.json import JsonObject


@dataclass(frozen=True)
class RecorderRoom:
    """Room identity derived from a recorder payload."""

    payload_key: str
    room_name: str
    bed_id: str


@dataclass(frozen=True)
class VirtualRecorderPayload:
    """Recorder payload generated to emulate one physical recorder."""

    vrcode: str
    payload: JsonObject
