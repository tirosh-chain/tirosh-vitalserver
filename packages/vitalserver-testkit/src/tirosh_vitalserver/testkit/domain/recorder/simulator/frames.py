"""Vital Recorder simulator frame generation."""

from __future__ import annotations

import math
from collections.abc import Callable, Mapping
from copy import deepcopy

from tirosh_vitalserver.testkit.domain.recorder.montypes import RecorderTrackMontype
from tirosh_vitalserver.testkit.domain.recorder.payloads.wire import (
    RealtimeRecorderMessagePayload,
)
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    SignalProfile,
    SignalQualityProfile,
    apply_signal_quality,
)
from tirosh_vitalserver.testkit.domain.signal.variation import (
    apply_numeric_variation,
    apply_signal_variation,
)
from tirosh_vitalserver.testkit.domain.signal.waveforms import (
    arterial_pressure_sample,
    co2_sample,
    ecg_sample,
    pleth_sample,
)
from tirosh_vitalserver.testkit.types.json import JsonArray, JsonObject, JsonValue

type WaveformGenerator = Callable[[float], float]


def generate_simulated_recorder_payload(
    payload: Mapping[str, JsonValue],
    *,
    now: float,
    frame_seconds: float,
    sequence: int,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
) -> JsonObject:
    """Generate a current-time recorder frame from a sample payload schema."""

    message_vrcode = payload.get("vrcode")
    message_version = payload.get("ver")
    message_rooms = payload.get("rooms")

    rooms = message_rooms if isinstance(message_rooms, dict) else payload
    generated_rooms = {
        key: generate_room_frame(
            room,
            now=now,
            frame_seconds=frame_seconds,
            sequence=sequence,
            signal_profile=signal_profile,
            signal_quality=signal_quality,
        )
        for key, room in rooms.items()
    }

    if isinstance(message_vrcode, str) and "ver" in payload:
        message: RealtimeRecorderMessagePayload = {
            "vrcode": message_vrcode,
            "ver": message_version,
            "rooms": generated_rooms,
        }

        return _message_as_json(message)

    return generated_rooms


def generate_room_frame(
    room: JsonValue,
    *,
    now: float,
    frame_seconds: float,
    sequence: int,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
) -> JsonValue:
    """Generate a current-time frame for one room payload."""

    if not isinstance(room, dict):
        return deepcopy(room)

    generated = deepcopy(room)
    generated["seqid"] = sequence
    generated["dtstart"] = now
    generated["dtend"] = now + frame_seconds
    generated["dtserver"] = now + frame_seconds

    if "dtcase" in generated:
        generated["dtcase"] = now - sequence * frame_seconds
    if "dtapp" in generated:
        generated["dtapp"] = now

    tracks = generated.get("trks")
    if isinstance(tracks, list):
        generated["trks"] = [
            generate_track_frame(
                track,
                now=now,
                frame_seconds=frame_seconds,
                signal_profile=signal_profile,
                signal_quality=signal_quality,
            )
            for track in tracks
        ]

    return generated


def generate_track_frame(
    track: JsonValue,
    *,
    now: float,
    frame_seconds: float,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
) -> JsonValue:
    """Generate current records for one track."""

    if not isinstance(track, dict):
        return deepcopy(track)

    generated = deepcopy(track)
    track_type = generated.get("type")

    if track_type == "wav":
        generated["recs"] = [
            generate_wave_record(
                generated,
                now,
                frame_seconds,
                signal_profile=signal_profile,
                signal_quality=signal_quality,
            )
        ]
    else:
        generated["recs"] = [
            generate_value_record(generated, now, signal_profile=signal_profile)
        ]

    return generated


def generate_wave_record(
    track: JsonObject,
    now: float,
    frame_seconds: float,
    *,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
) -> JsonObject:
    """Generate one waveform record from a track seed."""

    sample_rate = positive_number(track.get("srate"), default=1.0)
    sample_count = max(1, round(sample_rate * max(frame_seconds, 0.1)))
    values: JsonArray = []

    for index in range(sample_count):
        values.append(
            wave_value(
                track,
                index=index,
                sample_rate=sample_rate,
                now=now,
                signal_profile=signal_profile,
                signal_quality=signal_quality,
            )
        )

    return {"dt": now, "val": values}


def generate_value_record(
    track: JsonObject,
    now: float,
    *,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
) -> JsonObject:
    """Generate one numeric or textual record from a track seed."""

    montype = RecorderTrackMontype.parse(track.get("montype"))
    value = profile_value(track, now=now, signal_profile=signal_profile)

    if isinstance(value, int | float) and numeric_variation_enabled(montype):
        value = apply_numeric_variation(
            float(value),
            now=now,
            signal_profile=signal_profile,
        )

    return {"dt": now, "val": value}


def first_record_values(track: JsonObject) -> list[float]:
    """Return the first record as waveform seed values."""

    value = first_record_value(track)

    if not isinstance(value, list):
        return [0.0]

    values: list[float] = []
    for item in value:
        if isinstance(item, int | float):
            values.append(float(item))

    return values or [0.0]


def first_record_value(track: JsonObject) -> JsonValue:
    """Return the first record value from a track payload."""

    records = track.get("recs")

    if not isinstance(records, list) or not records:
        return 0

    first_record = records[0]
    if not isinstance(first_record, dict):
        return 0

    return first_record.get("val", 0)


def first_record_dt(track: JsonObject) -> float | None:
    """Return the first record timestamp when it is explicitly positive."""

    records = track.get("recs")

    if not isinstance(records, list) or not records:
        return None

    first_record = records[0]
    if not isinstance(first_record, dict):
        return None

    value = first_record.get("dt")
    if isinstance(value, int | float) and value > 0:
        return float(value)

    return None


def profile_value(
    track: JsonObject,
    *,
    now: float,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
) -> JsonValue:
    """Return the numeric value represented by a signal profile and track."""

    montype = RecorderTrackMontype.parse(track.get("montype"))

    if montype == RecorderTrackMontype.ECG_HEART_RATE:
        return signal_profile.heart_rate_bpm
    if montype == RecorderTrackMontype.PLETH_SPO2:
        return signal_profile.spo2_percent
    if montype == RecorderTrackMontype.CO2_CONCENTRATION:
        return signal_profile.etco2_mmhg
    if montype == RecorderTrackMontype.CO2_RESPIRATORY_RATE:
        return signal_profile.respiratory_rate_bpm
    if montype == RecorderTrackMontype.ARTERIAL_SYSTOLIC_BP:
        return signal_profile.systolic_bp_mmhg
    if montype == RecorderTrackMontype.ARTERIAL_DIASTOLIC_BP:
        return signal_profile.diastolic_bp_mmhg
    if montype == RecorderTrackMontype.ARTERIAL_MEAN_BP:
        return round(
            signal_profile.diastolic_bp_mmhg
            + (signal_profile.systolic_bp_mmhg - signal_profile.diastolic_bp_mmhg) / 3
        )
    if montype == RecorderTrackMontype.HCT:
        return hct_profile_value(
            track,
            now=now,
            signal_profile=signal_profile,
        )

    return first_record_value(track)


def hct_profile_value(
    track: JsonObject,
    *,
    now: float,
    signal_profile: SignalProfile,
) -> float:
    """Return HCT percent from the profile and explicit track time base."""

    start_dt = first_record_dt(track)
    elapsed_seconds = 0.0 if start_dt is None else max(0.0, now - start_dt)
    value = (
        signal_profile.hct_percent
        + signal_profile.hct_trend_percent_per_second * elapsed_seconds
    )

    return round(min(100.0, max(0.0, value)), 2)


def numeric_variation_enabled(montype: RecorderTrackMontype | None) -> bool:
    """Return whether synthetic transport noise should be applied."""

    return montype != RecorderTrackMontype.HCT


def wave_value(
    track: JsonObject,
    *,
    index: int,
    sample_rate: float,
    now: float,
    signal_profile: SignalProfile = DEFAULT_SIGNAL_PROFILE,
    signal_quality: SignalQualityProfile = SignalQualityProfile.CLEAN,
) -> float:
    """Generate one simulated waveform sample."""

    montype = RecorderTrackMontype.parse(track.get("montype"))
    sample_time = now + index / sample_rate

    generator = waveform_generator(montype, signal_profile=signal_profile)
    if generator is not None:
        value = generator(sample_time)

        varied = apply_signal_variation(
            value,
            sample_time=sample_time,
            signal_profile=signal_profile,
        )
        return apply_signal_quality(
            varied,
            sample_time=sample_time,
            quality=signal_quality,
            mindisp=float_value_or_none(track.get("mindisp")),
            maxdisp=float_value_or_none(track.get("maxdisp")),
        )

    base_values = first_record_values(track)
    base = base_values[index % len(base_values)]
    phase = 2 * math.pi * sample_time

    return apply_signal_quality(
        round(base + math.sin(phase) * 0.01, 4),
        sample_time=sample_time,
        quality=signal_quality,
        mindisp=float_value_or_none(track.get("mindisp")),
        maxdisp=float_value_or_none(track.get("maxdisp")),
    )


def waveform_generator(
    montype: RecorderTrackMontype | None,
    *,
    signal_profile: SignalProfile,
) -> WaveformGenerator | None:
    """Return the waveform generator for a recorder monitor type."""

    if montype == RecorderTrackMontype.ECG_WAVE:
        return lambda sample_time: ecg_sample(
            sample_time,
            signal_profile=signal_profile,
        )
    if montype == RecorderTrackMontype.PLETH_WAVE:
        return lambda sample_time: pleth_sample(
            sample_time,
            signal_profile=signal_profile,
        )
    if montype == RecorderTrackMontype.ARTERIAL_PRESSURE_WAVE:
        return lambda sample_time: arterial_pressure_sample(
            sample_time,
            signal_profile=signal_profile,
        )
    if montype == RecorderTrackMontype.CO2_WAVE:
        return lambda sample_time: co2_sample(
            sample_time,
            signal_profile=signal_profile,
        )

    return None


def positive_number(value: JsonValue, *, default: float) -> float:
    """Return a positive numeric JSON value or a default."""

    if isinstance(value, int | float) and value > 0:
        return float(value)

    return default


def float_value_or_none(value: JsonValue) -> float | None:
    """Return a numeric JSON value when present."""

    return float(value) if isinstance(value, int | float) else None


def _message_as_json(message: RealtimeRecorderMessagePayload) -> JsonObject:
    return {
        "vrcode": message["vrcode"],
        "ver": message["ver"],
        "rooms": message["rooms"],
    }
