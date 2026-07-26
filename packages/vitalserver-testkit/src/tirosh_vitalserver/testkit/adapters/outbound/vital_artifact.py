"""Outbound adapters for session `.vital` artifacts."""

from __future__ import annotations

import time
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionSnapshot,
    VirtualRecorderVitalArtifact,
    VirtualRecorderVitalUploadResult,
)
from tirosh_vitalserver.testkit.application.recorder_session.recording import (
    SessionVitalPlayback,
)
from tirosh_vitalserver.testkit.application.recorder_session.scenarios import (
    RecorderScenarioProvider,
    require_scenario_definition,
)
from tirosh_vitalserver.testkit.domain.signal import (
    DEFAULT_SIGNAL_PROFILE,
    profile_for_scenario,
)
from tirosh_vitalserver.testkit.domain.vital_file import (
    VitalSessionMetadata,
    VitalTrack,
    metadata_track,
    vital_tracks_from_recorder_playback,
)
from tirosh_vitalserver.vitalfile import VitalDbVitalFileWriter


class VitalDbSessionVitalFileExporter:
    """Write a session playback window as a VitalDB `.vital` file."""

    def __init__(
        self,
        artifact_dir: Path,
        writer: VitalDbVitalFileWriter | None = None,
    ) -> None:
        self._artifact_dir = artifact_dir
        self._writer = writer or VitalDbVitalFileWriter()

    def export_session_vital_file(
        self,
        snapshot: VirtualRecorderSessionSnapshot,
        playback: SessionVitalPlayback,
    ) -> VirtualRecorderVitalArtifact:
        """Create a `.vital` artifact from explicit session playback state."""

        if not playback.recorders:
            raise ValueError("no recorder playback is available for vital export")

        exported_at = time.time()
        artifact_path = self._artifact_path(snapshot, playback)
        artifact_path.parent.mkdir(parents=True, exist_ok=True)

        definition = require_scenario_definition(playback.scenario)
        if definition.provider == RecorderScenarioProvider.GENERATED_PROFILE:
            if definition.signal_profile is None:
                raise ValueError(
                    f"scenario {playback.scenario.value} is missing signal profile"
                )
            signal_profile = profile_for_scenario(definition.signal_profile)
            generate_frames = playback.generate_frames
        else:
            signal_profile = DEFAULT_SIGNAL_PROFILE
            generate_frames = False

        tracks = vital_tracks_from_recorder_playback(
            tuple(
                (recorder.vrcode, recorder.payload, recorder.messages_sent)
                for recorder in playback.recorders
            ),
            started_at=playback.started_at,
            frame_seconds=playback.interval_seconds,
            generate_frames=generate_frames,
            signal_profile=signal_profile,
            playback_events=tuple(
                (event.type.value, event.at) for event in playback.events
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
            scenario=playback.scenario.value,
            channels=tuple(track.dtname for track in tracks),
            playback_events=tuple(
                (event.type.value, event.at) for event in playback.events
            ),
        )

        ended_at = max(
            playback.stopped_at,
            latest_record_time(tracks) + playback.interval_seconds,
        )
        receipt = self._writer.write(
            artifact_path,
            started_at=playback.started_at,
            ended_at=ended_at,
            tracks=(*tracks, metadata_track(metadata)),
        )
        return VirtualRecorderVitalArtifact(
            path=str(artifact_path),
            filename=artifact_path.name,
            size_bytes=receipt.size_bytes,
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
        error = (
            None
            if ok
            else vitalserver_upload_error(
                response.status_code,
                response_text,
            )
        )

        return VirtualRecorderVitalUploadResult(
            status_code=response.status_code,
            ok=ok,
            elapsed_seconds=response.elapsed_seconds,
            uploaded_at=uploaded_at,
            response_text=response_text,
            error=error,
        )


def latest_record_time(tracks: tuple[VitalTrack, ...]) -> float:
    """Return the latest record timestamp in generated tracks."""

    return max(record.dt for track in tracks for record in track.records)


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
