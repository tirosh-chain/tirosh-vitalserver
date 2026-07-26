"""Pure mapping from recorder playback windows to `.vital` export tracks."""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass

from tirosh_vitalserver.core.domain.vital_file import (
    VitalServerMonitorType,
    VitalTrack,
    VitalTrackKind,
    VitalTrackRecord,
)
from tirosh_vitalserver.core.domain.vital_file.session_recording import (
    recorder_track_kind,
    recorder_track_sample_rate,
)
from tirosh_vitalserver.testkit.domain.recorder.montypes import RecorderTrackMontype
from tirosh_vitalserver.testkit.domain.recorder.simulator.frames import (
    generate_simulated_recorder_payload,
)
from tirosh_vitalserver.testkit.domain.signal import SignalProfile
from tirosh_vitalserver.testkit.types.json import JsonObject, JsonValue


@dataclass(frozen=True)
class VitalSessionMetadata:
    """Metadata embedded into a generated session `.vital` file."""

    session_id: str
    vrcodes: tuple[str, ...]
    bed_room_names: tuple[str, ...]
    started_at: float | None
    stopped_at: float | None
    scenario: str
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
                "scenario": self.scenario,
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


def vital_tracks_from_recorder_playback(
    playback: tuple[tuple[str, JsonObject, int], ...],
    *,
    started_at: float,
    frame_seconds: float,
    generate_frames: bool,
    signal_profile: SignalProfile,
    playback_events: tuple[tuple[str, float], ...],
) -> tuple[VitalTrack, ...]:
    """Return `.vital` tracks regenerated from an explicit play window."""

    track_records: dict[str, list[VitalTrackRecord]] = {}
    track_configs: dict[
        str,
        tuple[VitalTrackKind, float, str, float, float, int],
    ] = {}

    for _vrcode, payload, messages_sent in playback:
        for sequence in range(messages_sent):
            frame_payload = playback_frame_payload(
                payload,
                sequence=sequence,
                started_at=started_at,
                frame_seconds=frame_seconds,
                generate_frames=generate_frames,
                signal_profile=signal_profile,
                playback_events=playback_events,
            )
            collect_frame_tracks(
                frame_payload,
                track_records=track_records,
                track_configs=track_configs,
            )

    return tuple(
        VitalTrack(
            dtname=dtname,
            kind=track_configs[dtname][0],
            records=tuple(sorted(records, key=lambda record: record.dt)),
            srate=track_configs[dtname][1],
            unit=track_configs[dtname][2],
            mindisp=track_configs[dtname][3],
            maxdisp=track_configs[dtname][4],
            montype=track_configs[dtname][5],
        )
        for dtname, records in sorted(track_records.items())
        if records
    )


def playback_frame_payload(
    payload: Mapping[str, JsonValue],
    *,
    sequence: int,
    started_at: float,
    frame_seconds: float,
    generate_frames: bool,
    signal_profile: SignalProfile,
    playback_events: tuple[tuple[str, float], ...],
) -> Mapping[str, JsonValue]:
    """Return the frame payload for one explicit playback sequence."""

    now = playback_time_for_sequence(
        sequence,
        started_at=started_at,
        frame_seconds=frame_seconds,
        playback_events=playback_events,
    )

    if not generate_frames:
        return payload

    return generate_simulated_recorder_payload(
        payload,
        now=now,
        frame_seconds=frame_seconds,
        sequence=sequence,
        signal_profile=signal_profile,
    )


def playback_time_for_sequence(
    sequence: int,
    *,
    started_at: float,
    frame_seconds: float,
    playback_events: tuple[tuple[str, float], ...],
) -> float:
    """Map active playback sequence time onto session time, skipping pauses."""

    if sequence < 0:
        raise ValueError("playback sequence must not be negative")
    active_offset = sequence * frame_seconds
    remaining = active_offset
    active_start = started_at
    paused_at: float | None = None
    last_at = started_at

    for event_type, at in playback_events:
        if at < last_at:
            raise ValueError("playback events must be ordered by time")
        last_at = at

        if event_type == "started":
            continue
        if event_type == "paused":
            if paused_at is not None:
                raise ValueError("playback received paused while already paused")
            active_length = max(0.0, at - active_start)
            if remaining < active_length:
                return active_start + remaining
            remaining -= active_length
            paused_at = at
            continue
        if event_type == "resumed":
            if paused_at is None:
                raise ValueError("playback received resumed without paused")
            active_start = at
            paused_at = None
            continue
        if event_type == "stopped":
            break
        raise ValueError(f"unknown playback event type: {event_type}")

    if paused_at is not None:
        raise ValueError("playback ended while paused before all records were placed")

    return active_start + remaining


def collect_frame_tracks(
    payload: Mapping[str, JsonValue],
    *,
    track_records: dict[str, list[VitalTrackRecord]],
    track_configs: dict[
        str,
        tuple[VitalTrackKind, float, str, float, float, int],
    ],
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
            kind = recorder_track_kind(track.get("type"), dtname=dtname)
            srate = recorder_track_sample_rate(
                kind,
                track.get("srate"),
                dtname=dtname,
            )
            unit = string_value(track.get("unit"))
            mindisp = float_value(track.get("mindisp"))
            maxdisp = float_value(track.get("maxdisp"))
            montype = vital_monitor_type_id(track.get("montype"))
            track_configs.setdefault(
                dtname,
                (kind, srate, unit, mindisp, maxdisp, montype),
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
        dtname="TestKit/METADATA",
        kind=VitalTrackKind.STRING,
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

    montype = RecorderTrackMontype.parse(value)
    if montype is None:
        return 0

    monitor_type = VitalServerMonitorType.from_wire_name(montype.value)
    return monitor_type.value if monitor_type is not None else 0


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
