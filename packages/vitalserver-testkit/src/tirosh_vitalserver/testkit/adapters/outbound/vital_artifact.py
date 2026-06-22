"""Outbound adapters for session `.vital` artifacts."""

from __future__ import annotations

import gzip
import time
from pathlib import Path
from typing import Any

from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionSnapshot,
    VirtualRecorderVitalArtifact,
    VirtualRecorderVitalUploadResult,
)
from tirosh_vitalserver.testkit.application.recorder_session.recording import (
    SessionVitalPlayback,
)
from tirosh_vitalserver.testkit.domain.signal import profile_for_scenario
from tirosh_vitalserver.testkit.domain.vital_file import (
    VitalSessionMetadata,
    VitalTrack,
    metadata_track,
    vital_tracks_from_recorder_playback,
)
from tirosh_vitalserver.testkit.types.json import JsonValue


class VitalDbSessionVitalFileExporter:
    """Write a session playback window as a VitalDB `.vital` file."""

    def __init__(self, artifact_dir: Path) -> None:
        self._artifact_dir = artifact_dir

    def export_session_vital_file(
        self,
        snapshot: VirtualRecorderSessionSnapshot,
        playback: SessionVitalPlayback,
    ) -> VirtualRecorderVitalArtifact:
        """Create a `.vital` artifact from explicit session playback state."""

        if not playback.recorders:
            raise ValueError(
                "no recorder playback is available for vital export"
            )

        try:
            import numpy as np
            from vitaldb import VitalFile
        except ModuleNotFoundError as exc:
            raise RuntimeError("vitaldb package is required for vital export") from exc

        exported_at = time.time()
        artifact_path = self._artifact_path(snapshot, playback)
        artifact_path.parent.mkdir(parents=True, exist_ok=True)

        tracks = vital_tracks_from_recorder_playback(
            tuple(
                (recorder.vrcode, recorder.payload, recorder.messages_sent)
                for recorder in playback.recorders
            ),
            started_at=playback.started_at,
            frame_seconds=playback.interval_seconds,
            generate_frames=playback.generate_frames,
            signal_profile=profile_for_scenario(playback.default_scenario),
            playback_events=tuple(
                (event.type.value, event.at)
                for event in playback.events
            ),
        )
        if not tracks:
            raise ValueError("playback did not contain exportable vital tracks")

        metadata = VitalSessionMetadata(
            session_id=snapshot.session_id,
            vrcodes=tuple(recorder.vrcode for recorder in playback.recorders),
            bed_room_names=snapshot.request.bed_room_names,
            started_at=playback.started_at,
            stopped_at=playback.stopped_at,
            default_scenario=playback.default_scenario.value,
            channels=tuple(track.dtname for track in tracks),
            playback_events=tuple(
                (event.type.value, event.at)
                for event in playback.events
            ),
        )

        vital_file = VitalFile()
        vital_file.dtstart = playback.started_at
        vital_file.dtend = max(
            playback.stopped_at,
            latest_record_time(tracks) + playback.interval_seconds,
        )

        for track in (*tracks, metadata_track(metadata)):
            vitaldb_track = vital_file.add_track(
                track.dtname,
                vital_recs_for_track(track, np=np),
                srate=track.srate,
                unit=track.unit,
                mindisp=track.mindisp,
                maxdisp=track.maxdisp,
            )
            if vitaldb_track is None:
                raise RuntimeError(f"vitaldb failed to add track {track.dtname}")
            vitaldb_track.montype = track.montype

        result = vital_file.to_vital(str(artifact_path))
        if result is not True:
            raise RuntimeError(f"vitaldb failed to write {artifact_path}")
        rewrite_vital_header_for_vitalserver_legacy_parser(artifact_path)

        stat = artifact_path.stat()
        return VirtualRecorderVitalArtifact(
            path=str(artifact_path),
            filename=artifact_path.name,
            size_bytes=stat.st_size,
            created_at=exported_at,
            format="vitaldb-vital",
        )

    def _artifact_path(
        self,
        snapshot: VirtualRecorderSessionSnapshot,
        playback: SessionVitalPlayback,
    ) -> Path:
        prefix = artifact_filename_prefix(playback_bed_room_name(playback))
        started_at = playback.started_at
        timestamp = time.strftime(
            "%y%m%d_%H%M%S",
            time.localtime(started_at),
        )

        return self._artifact_dir / snapshot.session_id / f"{prefix}_{timestamp}.vital"


class VitalServerSessionVitalFileUploader:
    """Upload a generated `.vital` file to VitalServer."""

    def upload_session_vital_file(
        self,
        *,
        target_url: str,
        artifact_path: str | Path,
        vrcode: str | None,
        endpoint: str,
    ) -> VirtualRecorderVitalUploadResult:
        """Upload one `.vital` artifact and return an explicit result."""

        uploaded_at = time.time()
        client = VitalServerClient(target_url)
        response = client.upload_vital_file(
            artifact_path,
            vrcode=vrcode,
            endpoint=endpoint,
        )
        response_text = response.text
        ok = vitalserver_upload_succeeded(response.status_code, response_text)
        error = None if ok else vitalserver_upload_error(
            response.status_code,
            response_text,
        )

        return VirtualRecorderVitalUploadResult(
            status_code=response.status_code,
            ok=ok,
            elapsed_seconds=response.elapsed_seconds,
            uploaded_at=uploaded_at,
            response_text=response_text,
            error=error,
        )


def vital_recs_for_track(track: VitalTrack, *, np: Any) -> list[dict[str, Any]]:
    """Return VitalDB writer records for one track."""

    records: list[dict[str, Any]] = []
    for record in track.records:
        value = record.value
        if track.srate > 0:
            records.append(
                {
                    "dt": record.dt,
                    "val": np.asarray(numeric_array(value), dtype=np.float32),
                }
            )
        else:
            records.append({"dt": record.dt, "val": scalar_value(value)})

    return records


def latest_record_time(tracks: tuple[VitalTrack, ...]) -> float:
    """Return the latest record timestamp in generated tracks."""

    return max(record.dt for track in tracks for record in track.records)


def rewrite_vital_header_for_vitalserver_legacy_parser(path: Path) -> None:
    """Rewrite Python vitaldb v3 headers for bundled VitalServer indexing."""

    payload = gzip.decompress(path.read_bytes())
    if len(payload) < 20 or payload[:4] != b"VITA":
        raise RuntimeError(f"vitaldb wrote an invalid vital payload: {path}")

    header_len = int.from_bytes(payload[8:10], byteorder="little")
    if header_len == 10:
        return
    if header_len != 27 or len(payload) < 37:
        raise RuntimeError(
            "vitaldb wrote an unsupported vital header length "
            f"{header_len} for {path}"
        )

    legacy_payload = (
        payload[:8]
        + (10).to_bytes(2, byteorder="little")
        + payload[10:20]
        + payload[37:]
    )
    with gzip.GzipFile(str(path), mode="wb", compresslevel=9) as vital_file:
        vital_file.write(legacy_payload)


def numeric_array(value: JsonValue) -> list[float]:
    """Return a waveform sample array from an explicit JSON value."""

    if not isinstance(value, list):
        raise ValueError("waveform vital record value must be an array")

    samples: list[float] = []
    for sample in value:
        if not isinstance(sample, int | float):
            raise ValueError("waveform vital record samples must be numeric")
        samples.append(float(sample))

    return samples


def scalar_value(value: JsonValue) -> float | str:
    """Return a numeric or string scalar for VitalDB writer records."""

    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        raise ValueError("numeric vital record value must not be an array")
    return str(value)


def artifact_filename_prefix(room_name: str | None) -> str:
    """Return a VitalServer-compatible filename prefix."""

    cleaned = "".join(
        character if character.isalnum() or character in ("-", "_") else "_"
        for character in (room_name or "testkit-session").strip()
    )

    return cleaned or "testkit-session"


def playback_bed_room_name(playback: SessionVitalPlayback) -> str | None:
    """Return the first bed room name actually attached to session playback."""

    for recorder in playback.recorders:
        rooms = recorder.payload.get("rooms")
        room_map = rooms if isinstance(rooms, dict) else recorder.payload
        for room_key, room in room_map.items():
            if isinstance(room, dict):
                room_name = room.get("roomname")
                if isinstance(room_name, str) and room_name.strip():
                    return room_name
            if room_key.strip():
                return room_key

    return None


def vitalserver_upload_succeeded(status_code: int, response_text: str) -> bool:
    """Return whether upstream VitalServer accepted and indexed the upload."""

    return 200 <= status_code < 300 and response_text.strip() == "success"


def vitalserver_upload_error(status_code: int, response_text: str) -> str:
    """Return explicit VitalServer upload failure text."""

    text = response_text.strip()
    if text:
        return text
    return f"vital upload failed with HTTP {status_code}"
