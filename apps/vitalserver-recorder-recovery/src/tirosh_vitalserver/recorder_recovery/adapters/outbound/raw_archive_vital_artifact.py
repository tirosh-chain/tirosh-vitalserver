"""Export recorder-ingress raw archive JSONL into `.vital` artifacts."""

from __future__ import annotations

import hashlib
import json
import time
from collections.abc import Iterator
from pathlib import Path

from tirosh_vitalserver.core.domain.vital_file import (
    VitalSessionMetadata,
    iter_raw_archive_payloads_from_jsonl_lines,
    metadata_track,
)
from tirosh_vitalserver.recorder_recovery.domain import (
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
)
from tirosh_vitalserver.vitalfile import VitalDbVitalFileWriter

from .raw_archive_vital_spool import (
    RawArchiveVitalSpool,
)

ARCHIVE_READ_CHUNK_BYTES = 64 * 1024
ARTIFACT_HASH_CHUNK_BYTES = 1024 * 1024
RECOVERY_ARTIFACT_PRODUCER = "vitalserver-recorder-recovery"
RECOVERY_ARTIFACT_WRITER_VERSION = "2"


class RawArchiveVitalFileExporter:
    """Write vrcode-grouped raw archive payloads as VitalDB `.vital` files."""

    def __init__(
        self,
        writer: VitalDbVitalFileWriter | None = None,
    ) -> None:
        self._writer = writer or VitalDbVitalFileWriter()

    def export_raw_archive(
        self,
        raw_archive_path: Path,
        output_dir: Path,
        *,
        vrcode: str | None = None,
        start_offset: int = 0,
        end_offset: int | None = None,
        origin: RecoveryArtifactOrigin = RecoveryArtifactOrigin.COLD_PATH_RECOVERY,
    ) -> tuple[RecoveryArtifactReceipt, ...]:
        """Create `.vital` artifacts from one raw archive JSONL file."""

        archive_size = raw_archive_path.stat().st_size
        resolved_end = archive_size if end_offset is None else end_offset
        if start_offset < 0 or resolved_end < start_offset:
            raise ValueError("raw archive byte window is invalid")
        if resolved_end > archive_size:
            raise ValueError("raw archive byte window exceeds the current archive")
        decoded_payloads = iter_raw_archive_payloads_from_jsonl_lines(
            _iter_archive_window_lines(
                raw_archive_path,
                start_offset=start_offset,
                end_offset=resolved_end,
            )
        )
        output_dir.mkdir(parents=True, exist_ok=True)
        exported_at = time.time()
        artifacts: list[RecoveryArtifactReceipt] = []
        source_archive_id = str(raw_archive_path.resolve())

        with RawArchiveVitalSpool(output_dir.parent) as spool:
            for payload in decoded_payloads:
                if vrcode is None or payload.vrcode == vrcode:
                    spool.append(payload)
            for artifact in spool.iter_artifacts():
                group = artifact.group
                tracks = group.tracks
                started_at = artifact.coverage_started_at
                stopped_at = artifact.coverage_ended_at
                metadata = VitalSessionMetadata(
                    session_id=(
                        f"recorder-ingress-raw-{group.vrcode}-{int(started_at)}"
                    ),
                    vrcodes=(group.vrcode,),
                    bed_room_names=group.room_names,
                    started_at=started_at,
                    stopped_at=stopped_at,
                    scenario="raw-archive",
                    channels=tuple(track.dtname for track in tracks),
                    # Artifact bytes must be deterministic for the same explicit
                    # source window and writer version. Wall-clock export time is
                    # receipt evidence, not Vital File payload state.
                    playback_events=(("raw-archive-exported", stopped_at),),
                )

                artifact_path = output_dir / artifact_filename(
                    group.vrcode,
                    started_at,
                )
                receipt = self._writer.write(
                    artifact_path,
                    started_at=started_at,
                    ended_at=stopped_at,
                    tracks=(*tracks, metadata_track(metadata)),
                )
                artifact_sha256 = _file_sha256(artifact_path)
                artifact_id = _artifact_id(
                    origin=origin,
                    vrcode=group.vrcode,
                    room_names=group.room_names,
                    source_archive_id=source_archive_id,
                    source_start_offset=start_offset,
                    source_end_offset=resolved_end,
                    coverage_started_at=started_at,
                    coverage_ended_at=stopped_at,
                    sha256=artifact_sha256,
                )
                artifacts.append(
                    RecoveryArtifactReceipt(
                        artifact_id=artifact_id,
                        origin=origin,
                        producer=RECOVERY_ARTIFACT_PRODUCER,
                        writer_version=RECOVERY_ARTIFACT_WRITER_VERSION,
                        vrcode=group.vrcode,
                        room_names=group.room_names,
                        source_archive_id=source_archive_id,
                        source_start_offset=start_offset,
                        source_end_offset=resolved_end,
                        coverage_started_at=started_at,
                        coverage_ended_at=stopped_at,
                        format_version=int(receipt.format_version),
                        sha256=artifact_sha256,
                        path=str(artifact_path),
                        filename=artifact_path.name,
                        size_bytes=receipt.size_bytes,
                        created_at=exported_at,
                        track_count=receipt.track_count,
                    )
                )

        if not artifacts:
            raise ValueError("raw archive did not contain exportable vital tracks")
        return tuple(artifacts)


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(ARTIFACT_HASH_CHUNK_BYTES):
            digest.update(chunk)
    return digest.hexdigest()


def _artifact_id(
    *,
    origin: RecoveryArtifactOrigin,
    vrcode: str,
    room_names: tuple[str, ...],
    source_archive_id: str,
    source_start_offset: int,
    source_end_offset: int,
    coverage_started_at: float,
    coverage_ended_at: float,
    sha256: str,
) -> str:
    identity = json.dumps(
        {
            "origin": origin.value,
            "producer": RECOVERY_ARTIFACT_PRODUCER,
            "writerVersion": RECOVERY_ARTIFACT_WRITER_VERSION,
            "vrcode": vrcode,
            "roomNames": room_names,
            "sourceArchiveId": source_archive_id,
            "sourceStartOffset": source_start_offset,
            "sourceEndOffset": source_end_offset,
            "coverageStartedAt": coverage_started_at,
            "coverageEndedAt": coverage_ended_at,
            "sha256": sha256,
        },
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(identity).hexdigest()


def _iter_archive_window_lines(
    path: Path,
    *,
    start_offset: int,
    end_offset: int,
) -> Iterator[str]:
    """Yield UTF-8 JSONL records from one explicit byte window."""

    remaining = end_offset - start_offset
    pending = bytearray()
    line_number = 0
    with path.open("rb") as stream:
        stream.seek(start_offset)
        while remaining:
            chunk = stream.read(min(ARCHIVE_READ_CHUNK_BYTES, remaining))
            if not chunk:
                raise ValueError("raw archive changed while reading the byte window")
            remaining -= len(chunk)
            pending.extend(chunk)
            while True:
                newline = pending.find(b"\n")
                if newline < 0:
                    break
                encoded_line = bytes(pending[:newline])
                del pending[: newline + 1]
                line_number += 1
                yield _decode_archive_line(encoded_line, line_number=line_number)
        if pending:
            line_number += 1
            yield _decode_archive_line(bytes(pending), line_number=line_number)


def _decode_archive_line(encoded: bytes, *, line_number: int) -> str:
    try:
        return encoded.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(
            "raw archive byte window is not aligned to UTF-8 records: "
            f"line={line_number}"
        ) from exc


def artifact_filename(vrcode: str, started_at: float) -> str:
    """Return a VitalServer-compatible filename for raw archive export."""

    prefix = artifact_filename_prefix(vrcode)
    timestamp = time.strftime("%y%m%d_%H%M%S", time.localtime(started_at))
    # VitalServer derives its storage path from the final 20 characters of a
    # filename: ``_YYMMDD_HHMMSS.vital``.  Keep export provenance in the
    # artifact metadata, not in the filename, otherwise VitalServer indexes
    # the file under a malformed bed/date path and the library cannot read it.
    return f"{prefix}_{timestamp}.vital"


def artifact_filename_prefix(room_name: str | None) -> str:
    """Return a VitalServer-compatible filename prefix."""

    cleaned = "".join(
        character if character.isalnum() or character in ("-", "_") else "_"
        for character in (room_name or "recorder-recovery").strip()
    )

    return cleaned or "recorder-recovery"
