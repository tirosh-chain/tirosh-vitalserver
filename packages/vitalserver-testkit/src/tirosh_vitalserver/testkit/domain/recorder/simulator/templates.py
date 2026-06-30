"""Vital Recorder simulator room templates."""

from __future__ import annotations

import time
from typing import cast
from uuid import uuid4

from tirosh_vitalserver.testkit.domain.bed import normalize_bed_room_names
from tirosh_vitalserver.testkit.domain.recorder.montypes import RecorderTrackMontype
from tirosh_vitalserver.testkit.domain.recorder.payloads.wire import (
    RecorderRecordPayload,
    RecorderRoomPayload,
    RecorderTrackPayload,
)
from tirosh_vitalserver.testkit.types.json import JsonArray, JsonObject


def build_simulated_recorder_payload(
    *,
    room_names: tuple[str, ...],
    now: float | None = None,
    frame_seconds: float = 1.0,
) -> JsonObject:
    """Build a simulated VRecorder payload for explicit bed room names."""

    started_at = time.time() if now is None else now
    ended_at = started_at + frame_seconds
    resolved_room_names = normalize_bed_room_names(room_names)

    rooms: JsonObject = {}
    for resolved_room_name in resolved_room_names:
        rooms[resolved_room_name] = build_simulated_room_payload(
            room_name=resolved_room_name,
            started_at=started_at,
            ended_at=ended_at,
        )

    return rooms


def unique_testkit_vrcode(*, prefix: str = "testkit-recorder") -> str:
    """Return a fresh VRecorder code for generated testkit sessions."""

    return f"{prefix}-{uuid4().hex}"


def build_simulated_room_payload(
    *,
    room_name: str,
    started_at: float,
    ended_at: float,
) -> JsonObject:
    """Build one simulated room payload."""

    room: RecorderRoomPayload = {
        "roomname": room_name,
        "seqid": 0,
        "dtstart": started_at,
        "dtend": ended_at,
        "dtcase": started_at,
        "dtapp": started_at,
        "dtserver": ended_at,
        "ptcon": 1,
        "recording": 1,
        "dgmt": -32400,
        "vrver": "testkit",
        "devs": [
            {"type": "Demo", "name": "Simulated Monitor", "status": "on"},
            {"type": "Demo", "name": "Simulated Ventilator", "status": "on"},
        ],
        "trks": [
            make_wave_track(
                track_id=1001,
                name="ECG",
                montype=RecorderTrackMontype.ECG_WAVE,
                sample_rate=100,
                unit="mV",
                mindisp=-1,
                maxdisp=2.5,
                values=[0.0, 0.05, 0.1, 0.02, -0.03, 0.0, 0.35, -0.12],
                now=started_at,
            ),
            make_wave_track(
                track_id=1002,
                name="PLETH",
                montype=RecorderTrackMontype.PLETH_WAVE,
                sample_rate=100,
                unit="%",
                mindisp=0,
                maxdisp=100,
                values=[40, 43, 46, 49, 47, 44, 42, 41],
                now=started_at,
            ),
            make_wave_track(
                track_id=1003,
                name="ART",
                montype=RecorderTrackMontype.ARTERIAL_PRESSURE_WAVE,
                sample_rate=100,
                unit="mmHg",
                mindisp=0,
                maxdisp=200,
                values=[78, 92, 124, 118, 96, 84, 76, 72],
                now=started_at,
            ),
            make_wave_track(
                track_id=1004,
                name="CO2",
                montype=RecorderTrackMontype.CO2_WAVE,
                sample_rate=20,
                unit="mmHg",
                mindisp=0,
                maxdisp=50,
                values=[0, 2, 8, 24, 36, 40, 34, 12],
                now=started_at,
            ),
            make_value_track(
                track_id=2001,
                name="HR",
                montype=RecorderTrackMontype.ECG_HEART_RATE,
                unit="/min",
                value=78,
            ),
            make_value_track(
                track_id=2002,
                name="PLETH_SPO2",
                montype=RecorderTrackMontype.PLETH_SPO2,
                unit="%",
                value=98,
            ),
            make_value_track(
                track_id=2003,
                name="ETCO2",
                montype=RecorderTrackMontype.CO2_CONCENTRATION,
                unit="mmHg",
                value=37,
            ),
            make_value_track(
                track_id=2004,
                name="RR",
                montype=RecorderTrackMontype.CO2_RESPIRATORY_RATE,
                unit="/min",
                value=14,
            ),
            make_value_track(
                track_id=2005,
                name="ART_SBP",
                montype=RecorderTrackMontype.ARTERIAL_SYSTOLIC_BP,
                unit="mmHg",
                value=118,
            ),
            make_value_track(
                track_id=2006,
                name="ART_DBP",
                montype=RecorderTrackMontype.ARTERIAL_DIASTOLIC_BP,
                unit="mmHg",
                value=66,
            ),
            make_value_track(
                track_id=2007,
                name="ART_MBP",
                montype=RecorderTrackMontype.ARTERIAL_MEAN_BP,
                unit="mmHg",
                value=83,
            ),
            make_value_track(
                track_id=2010,
                name="HCT",
                montype=RecorderTrackMontype.HCT,
                unit="%",
                value=35.0,
                now=started_at,
                device_name="Lab",
            ),
        ],
        "evts": [],
        "filts": [],
    }

    return cast(JsonObject, room)


def make_wave_track(
    *,
    track_id: int,
    name: str,
    montype: RecorderTrackMontype,
    sample_rate: int,
    unit: str,
    mindisp: int | float,
    maxdisp: int | float,
    values: list[int | float],
    now: float,
    device_name: str = "Demo",
) -> RecorderTrackPayload:
    """Create a simulated waveform track with one seed record."""

    return {
        "id": track_id,
        "type": "wav",
        "name": name,
        "dname": device_name,
        "montype": montype.value,
        "unit": unit,
        "srate": sample_rate,
        "mindisp": mindisp,
        "maxdisp": maxdisp,
        "recs": [make_record(dt=now, value=numeric_values_as_json(values))],
    }


def make_value_track(
    *,
    track_id: int,
    name: str,
    montype: RecorderTrackMontype,
    unit: str,
    value: int | float,
    now: float = 0.0,
    device_name: str = "Demo",
) -> RecorderTrackPayload:
    """Create a simulated numeric track with one seed record."""

    return {
        "id": track_id,
        "type": "num",
        "name": name,
        "dname": device_name,
        "montype": montype.value,
        "unit": unit,
        "recs": [make_record(dt=now, value=value)],
    }


def make_record(
    *,
    dt: float,
    value: JsonArray | int | float | str,
) -> RecorderRecordPayload:
    """Create one Vital Recorder record."""

    return {"dt": dt, "val": value}


def numeric_values_as_json(values: list[int | float]) -> JsonArray:
    """Copy numeric samples into the package-wide JSON array alias."""

    samples: JsonArray = []
    for value in values:
        samples.append(value)

    return samples
