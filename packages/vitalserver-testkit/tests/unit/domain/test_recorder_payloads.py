from __future__ import annotations

import json
import zlib
from typing import cast

from tirosh_vitalserver.testkit import encode_realtime_payload
from tirosh_vitalserver.testkit.domain.recorder import (
    bed_id_for_room,
    build_realtime_message,
    build_simulated_recorder_payload,
    build_virtual_recorder_payloads,
    combine_virtual_recorder_rooms,
    generate_simulated_recorder_payload,
    iter_recorder_rooms,
    recorder_payload_size_bytes,
    shift_recorder_payload_time,
)
from tirosh_vitalserver.testkit.domain.signal import (
    RecorderSignalScenario,
    SignalProfile,
)
from tirosh_vitalserver.testkit.types.json import JsonArray, JsonObject


def test_realtime_payload_is_wrapped_and_compressed() -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "BED01",
            "dtstart": 1000.0,
            "trks": [],
        }
    }

    message = build_realtime_message(recorder_payload, version="2.3.4")
    encoded = encode_realtime_payload(
        recorder_payload,
        version="2.3.4",
        shift_time=False,
    )
    decoded = cast(JsonObject, json.loads(zlib.decompress(encoded)))

    assert message["vrcode"] == "recorder-code"
    assert message["ver"] == "2.3.4"
    assert message["rooms"] == recorder_payload
    assert decoded == message


def test_recorder_room_bed_ids_match_vitalserver_hash() -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "mnw4anvs4",
            "trks": [],
        }
    }

    rooms = iter_recorder_rooms(recorder_payload)

    assert len(rooms) == 1
    assert rooms[0].room_name == "mnw4anvs4"
    assert rooms[0].bed_id == "de8d5733096db32506a924ac566c903c343e2338"
    assert bed_id_for_room("mnw4anvs4") == rooms[0].bed_id


def test_virtual_recorder_payloads_create_distinct_rooms() -> None:
    recorder_payload: JsonObject = {
        "recorder-code": {
            "roomname": "BED01",
            "trks": [],
        }
    }

    virtual_payloads = build_virtual_recorder_payloads(
        recorder_payload,
        count=3,
        version="2.3.4",
    )
    visibility_payload = combine_virtual_recorder_rooms(
        virtual_payloads,
        version="2.3.4",
    )
    rooms = iter_recorder_rooms(visibility_payload)

    assert [payload.vrcode for payload in virtual_payloads] == [
        "recorder-code-001",
        "recorder-code-002",
        "recorder-code-003",
    ]
    assert [room.room_name for room in rooms] == [
        "BED01-001",
        "BED01-002",
        "BED01-003",
    ]


def test_shift_recorder_payload_time_preserves_relative_offsets() -> None:
    payload: JsonObject = {
        "recorder-code": {
            "dtstart": 1000.0,
            "dtend": 1001.5,
            "dtapp": 900.0,
            "dtcase": 800.0,
            "trks": [{"recs": [{"dt": 1000.25, "val": [1, 2]}]}],
        }
    }

    shifted = shift_recorder_payload_time(payload, now=2000.0)
    original_recorder = cast(JsonObject, payload["recorder-code"])
    shifted_recorder = cast(JsonObject, shifted["recorder-code"])
    shifted_tracks = cast(JsonArray, shifted_recorder["trks"])
    shifted_track = cast(JsonObject, shifted_tracks[0])
    shifted_recs = cast(JsonArray, shifted_track["recs"])
    shifted_rec = cast(JsonObject, shifted_recs[0])

    assert original_recorder["dtstart"] == 1000.0
    assert shifted_recorder["dtstart"] == 2000.0
    assert shifted_recorder["dtend"] == 2001.5
    assert shifted_recorder["dtapp"] == 1900.0
    assert shifted_recorder["dtcase"] == 1800.0
    assert shifted_rec["dt"] == 2000.25
    assert recorder_payload_size_bytes(shifted) > 0


def test_simulated_recorder_payload_is_valid_room_map() -> None:
    payload = build_simulated_recorder_payload(now=1000.0)
    recorder = cast(JsonObject, payload["testkit-recorder"])
    tracks = cast(JsonArray, recorder["trks"])
    first_track = cast(JsonObject, tracks[0])

    rooms = iter_recorder_rooms(payload)

    assert len(rooms) == 1
    assert rooms[0].room_name == "testkit-bed"
    assert first_track["id"] == 1001
    assert first_track["montype"] == "ECG_WAV"
    assert first_track["dname"] == "Demo"
    assert recorder_payload_size_bytes(payload) > 0


def test_simulated_recorder_frame_generates_current_wave_samples() -> None:
    payload = build_simulated_recorder_payload(now=1000.0)

    generated = generate_simulated_recorder_payload(
        payload,
        now=2000.0,
        frame_seconds=1.0,
        sequence=7,
    )
    recorder = cast(JsonObject, generated["testkit-recorder"])
    tracks = cast(JsonArray, recorder["trks"])
    wave_track = cast(JsonObject, tracks[0])
    records = cast(JsonArray, wave_track["recs"])
    record = cast(JsonObject, records[0])
    values = cast(JsonArray, record["val"])

    assert recorder["seqid"] == 7
    assert recorder["dtstart"] == 2000.0
    assert recorder["dtend"] == 2001.0
    assert record["dt"] == 2000.0
    assert len(values) == 100


def test_simulated_ecg_waveform_uses_heart_rate_period() -> None:
    payload = build_simulated_recorder_payload(now=1000.0)

    generated = generate_simulated_recorder_payload(
        payload,
        now=2000.0,
        frame_seconds=2.0,
        sequence=1,
    )
    recorder = cast(JsonObject, generated["testkit-recorder"])
    tracks = cast(JsonArray, recorder["trks"])
    ecg_track = cast(JsonObject, tracks[0])
    records = cast(JsonArray, ecg_track["recs"])
    record = cast(JsonObject, records[0])
    values = [
        float(value)
        for value in cast(JsonArray, record["val"])
        if isinstance(value, int | float)
    ]
    peak_count = count_ecg_peaks(values)

    assert 2 <= peak_count <= 3


def test_simulated_ecg_waveform_uses_signal_profile_heart_rate() -> None:
    payload = build_simulated_recorder_payload(now=1000.0)
    signal_profile = SignalProfile(heart_rate_bpm=120.0)

    generated = generate_simulated_recorder_payload(
        payload,
        now=2000.0,
        frame_seconds=2.0,
        sequence=1,
        signal_profile=signal_profile,
    )
    recorder = cast(JsonObject, generated["testkit-recorder"])
    tracks = cast(JsonArray, recorder["trks"])
    ecg_track = cast(JsonObject, tracks[0])
    records = cast(JsonArray, ecg_track["recs"])
    record = cast(JsonObject, records[0])
    values = [
        float(value)
        for value in cast(JsonArray, record["val"])
        if isinstance(value, int | float)
    ]

    assert 3 <= count_ecg_peaks(values) <= 5


def test_recorder_signal_scenarios_are_stable_strings() -> None:
    assert RecorderSignalScenario.NORMAL == "normal"
    assert RecorderSignalScenario.TACHYCARDIA == "tachycardia"
    assert RecorderSignalScenario.DEVICE_DISCONNECT == "device_disconnect"


def count_ecg_peaks(values: list[float], *, threshold: float = 0.35) -> int:
    return sum(
        1
        for index in range(1, len(values) - 1)
        if values[index] > threshold
        and values[index] >= values[index - 1]
        and values[index] >= values[index + 1]
    )
