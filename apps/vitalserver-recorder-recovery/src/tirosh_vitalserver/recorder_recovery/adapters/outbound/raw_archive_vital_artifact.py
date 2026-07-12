"""Export recorder-ingress raw archive JSONL into `.vital` artifacts."""

from __future__ import annotations

import gzip
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tirosh_vitalserver.core.domain.vital_file import (
    VitalSessionMetadata,
    VitalTrack,
    metadata_track,
    raw_archive_payloads_from_jsonl_lines,
    vital_tracks_by_vrcode_from_raw_archive,
)
from tirosh_vitalserver.core.types.json import JsonValue


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
                scenario="raw-archive",
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
    return f"{prefix}_{timestamp}_auto_export.vital"


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
        for character in (room_name or "recorder-recovery").strip()
    )

    return cleaned or "recorder-recovery"
