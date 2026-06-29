"""Pure mapping from recorder payload frames to `.vital` export tracks."""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass

from tirosh_vitalserver.core.types.json import JsonValue


@dataclass(frozen=True)
class VitalTrackRecord:
    """One explicit record for a `.vital` track."""

    dt: float
    value: JsonValue


@dataclass(frozen=True)
class VitalTrack:
    """A `.vital` track assembled from sent recorder frames."""

    dtname: str
    records: tuple[VitalTrackRecord, ...]
    srate: float
    unit: str
    mindisp: float
    maxdisp: float
    montype: int


@dataclass(frozen=True)
class VitalSessionMetadata:
    """Metadata embedded into a generated session `.vital` file."""

    session_id: str
    vrcodes: tuple[str, ...]
    bed_room_names: tuple[str, ...]
    started_at: float | None
    stopped_at: float | None
    default_scenario: str
    channels: tuple[str, ...]
    playback_events: tuple[tuple[str, float], ...]

    def as_json(self) -> str:
        """Return metadata as a stable JSON string record."""

        return json.dumps(
            {
                "sessionId": self.session_id,
                "vrcodes": self.vrcodes,
                "bedRoomNames": self.bed_room_names,
                "startedAt": self.started_at,
                "stoppedAt": self.stopped_at,
                "defaultScenario": self.default_scenario,
                "channels": self.channels,
                "playbackEvents": tuple(
                    {"type": event_type, "at": at}
                    for event_type, at in self.playback_events
                ),
            },
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )


def collect_frame_tracks(
    payload: Mapping[str, JsonValue],
    *,
    track_records: dict[str, list[VitalTrackRecord]],
    track_configs: dict[str, tuple[float, str, float, float, int]],
) -> None:
    """Collect exportable track records from one recorder frame."""

    for room_key, room in frame_rooms(payload).items():
        if not isinstance(room, dict):
            continue

        room_name = string_value(room.get("roomname")) or room_key
        tracks = room.get("trks")
        if not isinstance(tracks, list):
            continue

        for track in tracks:
            if not isinstance(track, dict):
                continue

            dtname = vital_track_name(room_name, track)
            srate = positive_float(track.get("srate"))
            unit = string_value(track.get("unit"))
            mindisp = float_value(track.get("mindisp"))
            maxdisp = float_value(track.get("maxdisp"))
            montype = vital_monitor_type_id(track.get("montype"))
            track_configs.setdefault(
                dtname,
                (srate, unit, mindisp, maxdisp, montype),
            )
            records = track.get("recs")
            if not isinstance(records, list):
                continue

            for record in records:
                if not isinstance(record, dict):
                    continue
                dt = record.get("dt")
                if not isinstance(dt, int | float):
                    continue
                track_records.setdefault(dtname, []).append(
                    VitalTrackRecord(dt=float(dt), value=record.get("val"))
                )


def metadata_track(metadata: VitalSessionMetadata) -> VitalTrack:
    """Return a metadata track that can be embedded in `.vital`."""

    dt = metadata.started_at or metadata.stopped_at or 0.0
    return VitalTrack(
        dtname="RecorderRecovery/METADATA",
        records=(VitalTrackRecord(dt=dt, value=metadata.as_json()),),
        srate=0.0,
        unit="",
        mindisp=0.0,
        maxdisp=0.0,
        montype=0,
    )


def frame_rooms(payload: Mapping[str, JsonValue]) -> Mapping[str, JsonValue]:
    """Return the room map from a recorder frame payload."""

    rooms = payload.get("rooms")
    return rooms if isinstance(rooms, dict) else payload


def vital_track_name(room_name: str, track: Mapping[str, JsonValue]) -> str:
    """Return a VitalDB-compatible device/track name."""

    device = string_value(track.get("dname")) or "Demo"
    track_name = string_value(track.get("name")) or string_value(track.get("id"))
    if not track_name:
        track_name = "UNKNOWN"

    return f"{safe_name(room_name)}_{safe_name(device)}/{safe_name(track_name)}"


def safe_name(value: str) -> str:
    """Return a simple VitalDB track/device name segment."""

    cleaned = "".join(
        character if character.isalnum() or character in ("-", "_") else "_"
        for character in value.strip()
    )
    return cleaned or "unknown"


def vital_monitor_type_id(value: JsonValue) -> int:
    """Return the legacy VitalServer monitor type id for a recorder montype."""

    if not isinstance(value, str):
        return 0

    return VITALSERVER_MONITOR_TYPE_IDS.get(value, 0)


def string_value(value: JsonValue) -> str:
    """Return a string JSON value or an empty string."""

    return value if isinstance(value, str) else ""


def positive_float(value: JsonValue) -> float:
    """Return a positive numeric JSON value or zero."""

    if isinstance(value, int | float) and value > 0:
        return float(value)
    return 0.0


def float_value(value: JsonValue) -> float:
    """Return a numeric JSON value or zero."""

    if isinstance(value, int | float):
        return float(value)
    return 0.0


VITALSERVER_MONITOR_TYPE_IDS = {
    "ECG_WAV": 1,
    "ECG_HR": 2,
    "IABP_WAV": 4,
    "IABP_SBP": 5,
    "IABP_DBP": 6,
    "IABP_MBP": 7,
    "PLETH_WAV": 8,
    "PLETH_SPO2": 10,
    "CO2_WAV": 13,
    "CO2_RR": 14,
    "CO2_CONC": 15,
}
