"""Typed wire payload shapes used by Vital Recorder helpers."""

from __future__ import annotations

from typing import TypedDict

from tirosh_vitalserver.testkit.types.json import JsonArray, JsonValue


class RecorderDevicePayload(TypedDict, total=False):
    """Device metadata displayed by VitalServer Web Monitoring."""

    type: str
    name: str
    status: str
    ycable: str
    port: str


class RecorderRecordPayload(TypedDict):
    """One track record inside a Vital Recorder room payload."""

    dt: float
    val: JsonValue


class RecorderTrackPayload(TypedDict, total=False):
    """Track metadata and values sent by Vital Recorder."""

    id: int
    type: str
    name: str
    dname: str
    montype: str
    unit: str
    srate: int | float
    mindisp: int | float
    maxdisp: int | float
    recs: list[RecorderRecordPayload]


class RecorderRoomPayload(TypedDict, total=False):
    """Room-level payload stored by VitalServer as one bed."""

    roomname: str
    seqid: int
    dtstart: float
    dtend: float
    dtcase: float
    dtapp: float
    dtserver: float
    ptcon: int
    recording: int
    dgmt: int
    vrver: str
    devs: list[RecorderDevicePayload]
    trks: list[RecorderTrackPayload]
    evts: JsonArray
    filts: JsonArray


class RealtimeRecorderMessagePayload(TypedDict):
    """Socket.IO `send_data` message before zlib compression."""

    vrcode: str
    ver: JsonValue
    rooms: dict[str, JsonValue]


type RecorderRoomMapPayload = dict[str, RecorderRoomPayload]
