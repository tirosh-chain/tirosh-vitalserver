"""Export recorder-ingress raw archive JSONL into `.vital` artifacts."""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.outbound.vital_artifact import (
    artifact_filename_prefix,
    latest_record_time,
    rewrite_vital_header_for_vitalserver_legacy_parser,
    vital_recs_for_track,
)
from tirosh_vitalserver.testkit.domain.vital_file import (
    VitalSessionMetadata,
    metadata_track,
    raw_archive_payloads_from_jsonl_lines,
    vital_tracks_by_vrcode_from_raw_archive,
)


@dataclass(frozen=True)
class RawArchiveVitalArtifact:
    """One `.vital` artifact exported from raw archive payloads."""

    vrcode: str
    path: str
    filename: str
    size_bytes: int
    created_at: float
    track_count: int


class RawArchiveVitalFileExporter:
    """Write vrcode-grouped raw archive payloads as VitalDB `.vital` files."""

    def export_raw_archive(
        self,
        raw_archive_path: Path,
        output_dir: Path,
    ) -> tuple[RawArchiveVitalArtifact, ...]:
        """Create `.vital` artifacts from one raw archive JSONL file."""

        try:
            import numpy as np
            from vitaldb import VitalFile
        except ModuleNotFoundError as exc:
            raise RuntimeError("vitaldb package is required for vital export") from exc

        payloads = raw_archive_payloads_from_jsonl_lines(
            raw_archive_path.read_text(encoding="utf-8").splitlines()
        )
        grouped_tracks = vital_tracks_by_vrcode_from_raw_archive(payloads)
        if not grouped_tracks:
            raise ValueError("raw archive did not contain exportable payloads")

        output_dir.mkdir(parents=True, exist_ok=True)
        exported_at = time.time()
        artifacts: list[RawArchiveVitalArtifact] = []

        for vrcode, tracks in grouped_tracks.items():
            if not tracks:
                continue
            started_at = min(record.dt for track in tracks for record in track.records)
            stopped_at = max(latest_record_time(tracks), started_at + 0.001)
            metadata = VitalSessionMetadata(
                session_id=f"recorder-ingress-raw-{vrcode}-{int(started_at)}",
                vrcodes=(vrcode,),
                bed_room_names=(vrcode,),
                started_at=started_at,
                stopped_at=stopped_at,
                default_scenario="raw-archive",
                channels=tuple(track.dtname for track in tracks),
                playback_events=(("raw-archive-exported", exported_at),),
            )

            vital_file = VitalFile()
            vital_file.dtstart = started_at
            vital_file.dtend = stopped_at
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

            artifact_path = output_dir / artifact_filename(vrcode, started_at)
            result = vital_file.to_vital(str(artifact_path))
            if result is not True:
                raise RuntimeError(f"vitaldb failed to write {artifact_path}")
            rewrite_vital_header_for_vitalserver_legacy_parser(artifact_path)
            stat = artifact_path.stat()
            artifacts.append(
                RawArchiveVitalArtifact(
                    vrcode=vrcode,
                    path=str(artifact_path),
                    filename=artifact_path.name,
                    size_bytes=stat.st_size,
                    created_at=exported_at,
                    track_count=len(tracks),
                )
            )

        if not artifacts:
            raise ValueError("raw archive did not contain exportable vital tracks")
        return tuple(artifacts)


def artifact_filename(vrcode: str, started_at: float) -> str:
    """Return a VitalServer-compatible filename for raw archive export."""

    prefix = artifact_filename_prefix(vrcode)
    timestamp = time.strftime("%y%m%d_%H%M%S", time.localtime(started_at))
    return f"{prefix}_{timestamp}.vital"
