"""Disk-backed bounded-memory Vital File replay adapter."""

from __future__ import annotations

import math
import sqlite3
import struct
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory

from tirosh_vitalserver.core.domain.vital_file import (
    VitalDeviceDefinition,
    VitalFileFormatError,
    VitalFileFormatVersion,
    VitalFileHeader,
    VitalTrackDefinition,
    VitalTrackKind,
)
from tirosh_vitalserver.vitalfile import (
    VitalFilePacketScanner,
    VitalFileReadError,
)

from .vital_replay import (
    MONITOR_TYPE_NAMES,
    LabReplayGapPolicy,
    LabReplayStringTrackPolicy,
    LabVitalReplayFrame,
    VitalReplaySourceError,
)

MAX_REPLAY_TRACKS = 4_096
MAX_REPLAY_FRAME_SAMPLES = 100_000

_FORMAT_STRUCTS: dict[int, struct.Struct] = {
    1: struct.Struct("<f"),
    2: struct.Struct("<d"),
    3: struct.Struct("<b"),
    4: struct.Struct("<B"),
    5: struct.Struct("<h"),
    6: struct.Struct("<H"),
    7: struct.Struct("<l"),
    8: struct.Struct("<L"),
}


@dataclass(frozen=True, slots=True)
class _SpoolTrack:
    source_id: int
    output_id: int
    definition: VitalTrackDefinition


class StreamingVitalReplaySourceFactory:
    """Validate one file into a request-owned SQLite replay spool."""

    def __init__(
        self,
        *,
        string_track_policy: LabReplayStringTrackPolicy,
        gap_policy: LabReplayGapPolicy,
        scanner: VitalFilePacketScanner | None = None,
        spool_root: Path | None = None,
    ) -> None:
        self.string_track_policy = string_track_policy
        self.gap_policy = gap_policy
        self.scanner = scanner or VitalFilePacketScanner()
        self.spool_root = spool_root

    def open(self, path: Path) -> StreamingVitalReplaySource:
        temporary: TemporaryDirectory[str] | None = None
        connection: sqlite3.Connection | None = None
        try:
            temporary = TemporaryDirectory(
                prefix="vitalserver-lab-replay-",
                dir=self.spool_root,
            )
            spool_path = Path(temporary.name) / "replay.sqlite3"
            connection = sqlite3.connect(spool_path)
            _initialize_spool(connection)
            sink = _ReplaySpoolSink(
                connection,
                string_track_policy=self.string_track_policy,
            )
            header = self.scanner.scan(path, sink)
            connection.commit()
            started_at, ended_at = sink.time_range(header)
            duration_seconds = math.ceil(ended_at - started_at)
            if duration_seconds < 1:
                raise VitalReplaySourceError(
                    f"Vital File replay source has no positive duration: {path.name}",
                    stage="fileValidation",
                    code="nonPositiveDuration",
                )
            if not sink.replay_tracks:
                raise VitalReplaySourceError(
                    f"Vital File contains no replayable tracks: {path.name}",
                    stage="fileValidation",
                    code="noReplayableTracks",
                )
            connection.close()
            connection = None
            owned_temporary = temporary
            temporary = None
            return StreamingVitalReplaySource(
                format_version=header.format_version,
                duration_seconds=duration_seconds,
                started_at=started_at,
                ended_at=ended_at,
                tracks=tuple(sink.replay_tracks),
                gap_policy=self.gap_policy,
                spool_path=spool_path,
                temporary=owned_temporary,
            )
        except VitalReplaySourceError:
            raise
        except (VitalFileFormatError, VitalFileReadError) as error:
            raise VitalReplaySourceError(
                f"Vital File replay source validation failed: {path.name}: {error}",
                stage="fileValidation",
                code=error.code,
            ) from error
        except (OSError, sqlite3.Error) as error:
            raise VitalReplaySourceError(
                f"Vital File replay spool write failed: {path.name}: {error}",
                stage="fileValidation",
                code="replaySpoolWriteFailed",
            ) from error
        finally:
            if connection is not None:
                connection.close()
            if temporary is not None:
                temporary.cleanup()


class _ReplaySpoolSink:
    def __init__(
        self,
        connection: sqlite3.Connection,
        *,
        string_track_policy: LabReplayStringTrackPolicy,
    ) -> None:
        self.connection = connection
        self.string_track_policy = string_track_policy
        self.header: VitalFileHeader | None = None
        self.tracks: dict[int, VitalTrackDefinition] = {}
        self.replay_tracks: list[_SpoolTrack] = []
        self.observed_start: float | None = None
        self.observed_end: float | None = None
        self.next_wave_id = 1001
        self.next_numeric_id = 2001

    def on_header(self, header: VitalFileHeader) -> None:
        self.header = header

    def on_device(
        self,
        *,
        device_id: int,
        device: VitalDeviceDefinition,
    ) -> None:
        del device_id
        del device

    def on_track(self, *, track_id: int, track: VitalTrackDefinition) -> None:
        if len(self.tracks) >= MAX_REPLAY_TRACKS:
            raise VitalReplaySourceError(
                "Vital File replay source contains too many tracks: "
                f"maximum={MAX_REPLAY_TRACKS}",
                stage="fileValidation",
                code="tooManyTracks",
            )
        self.tracks[track_id] = track
        if track.kind is VitalTrackKind.STRING:
            if self.string_track_policy is LabReplayStringTrackPolicy.REJECT:
                raise VitalReplaySourceError(
                    f"Vital File string track replay is unsupported: {track.dtname}",
                    stage="fileValidation",
                    code="unsupportedStringTrack",
                )
            return
        if track.kind is VitalTrackKind.WAVEFORM:
            frame_samples = max(1, round(track.sample_rate))
            if frame_samples > MAX_REPLAY_FRAME_SAMPLES:
                raise VitalReplaySourceError(
                    "Vital File waveform replay frame exceeds the explicit limit: "
                    f"{track.dtname} samples={frame_samples} "
                    f"maximum={MAX_REPLAY_FRAME_SAMPLES}",
                    stage="fileValidation",
                    code="replayFrameTooLarge",
                )
            output_id = self.next_wave_id
            self.next_wave_id += 1
        else:
            output_id = self.next_numeric_id
            self.next_numeric_id += 1
        self.replay_tracks.append(
            _SpoolTrack(
                source_id=track_id,
                output_id=output_id,
                definition=track,
            )
        )

    def on_waveform_chunk(
        self,
        *,
        track_id: int,
        recorded_at: float,
        sample_offset: int,
        sample_count: int,
        raw_values: bytes,
    ) -> None:
        track = self.tracks[track_id]
        self.connection.execute(
            """
            INSERT INTO waveform_chunks(
                track_id, recorded_at, sample_offset, sample_count, raw_values
            ) VALUES (?, ?, ?, ?, ?)
            """,
            (
                track_id,
                recorded_at,
                sample_offset,
                sample_count,
                sqlite3.Binary(raw_values),
            ),
        )
        self._observe(recorded_at)
        self._observe(recorded_at + (sample_offset + sample_count) / track.sample_rate)

    def on_numeric_record(
        self,
        *,
        track_id: int,
        recorded_at: float,
        value: float,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO numeric_records(track_id, recorded_at, value)
            VALUES (?, ?, ?)
            """,
            (track_id, recorded_at, value),
        )
        self._observe(recorded_at)

    def on_string_record(
        self,
        *,
        track_id: int,
        recorded_at: float,
        value: str,
    ) -> None:
        del track_id
        del value
        self._observe(recorded_at)

    def time_range(self, header: VitalFileHeader) -> tuple[float, float]:
        started_at = header.started_at
        ended_at = header.ended_at
        if started_at is None:
            started_at = self.observed_start
        if ended_at is None:
            ended_at = self.observed_end
        if started_at is None or ended_at is None:
            raise VitalReplaySourceError(
                "Vital File replay source has no record time range.",
                stage="fileValidation",
                code="missingTimeRange",
            )
        if not math.isfinite(started_at) or not math.isfinite(ended_at):
            raise VitalReplaySourceError(
                "Vital File replay source time range is not finite.",
                stage="fileValidation",
                code="invalidTimeRange",
            )
        if ended_at < started_at:
            raise VitalReplaySourceError(
                "Vital File replay source end precedes its start: "
                f"start={started_at} end={ended_at}",
                stage="fileValidation",
                code="invalidTimeRange",
            )
        return started_at, ended_at

    def _observe(self, timestamp: float) -> None:
        if self.observed_start is None or timestamp < self.observed_start:
            self.observed_start = timestamp
        if self.observed_end is None or timestamp > self.observed_end:
            self.observed_end = timestamp


class StreamingVitalReplaySource:
    def __init__(
        self,
        *,
        format_version: VitalFileFormatVersion,
        duration_seconds: int,
        started_at: float,
        ended_at: float,
        tracks: tuple[_SpoolTrack, ...],
        gap_policy: LabReplayGapPolicy,
        spool_path: Path,
        temporary: TemporaryDirectory[str],
    ) -> None:
        self.format_version = format_version
        self.duration_seconds = duration_seconds
        self.started_at = started_at
        self.ended_at = ended_at
        self.tracks = tracks
        self.gap_policy = gap_policy
        self.spool_path = spool_path
        self._temporary: TemporaryDirectory[str] | None = temporary

    def frame(self, *, offset_seconds: int, output_time: float) -> LabVitalReplayFrame:
        if offset_seconds < 0 or offset_seconds >= self.duration_seconds:
            raise VitalReplaySourceError(
                "Vital File replay offset is outside source duration: "
                f"{offset_seconds}",
                stage="replayFrame",
                code="offsetOutsideSourceDuration",
            )
        if self._temporary is None:
            raise VitalReplaySourceError(
                "Vital File replay spool is already closed.",
                stage="replayFrame",
                code="replaySpoolUnavailable",
            )
        try:
            connection = sqlite3.connect(f"file:{self.spool_path}?mode=ro", uri=True)
        except sqlite3.Error as error:
            raise VitalReplaySourceError(
                f"Vital File replay spool open failed: {error}",
                stage="replayFrame",
                code="replaySpoolReadFailed",
            ) from error
        try:
            track_payloads: list[dict[str, object]] = []
            for track in self.tracks:
                payload = self._track_frame(
                    connection,
                    track=track,
                    offset_seconds=offset_seconds,
                    output_time=output_time,
                )
                if payload is not None:
                    track_payloads.append(payload)
        except sqlite3.Error as error:
            raise VitalReplaySourceError(
                f"Vital File replay spool read failed: {error}",
                stage="replayFrame",
                code="replaySpoolReadFailed",
            ) from error
        finally:
            connection.close()
        if not track_payloads:
            raise VitalReplaySourceError(
                "Vital File replay frame has no finite records: "
                f"offset={offset_seconds}",
                stage="replayFrame",
                code="noFiniteRecords",
            )
        devices: tuple[dict[str, object], ...] = tuple(
            {
                "type": "VitalFileReplay",
                "name": device_name,
                "status": "connected",
            }
            for device_name in sorted(
                {str(payload["dname"]) for payload in track_payloads}
            )
        )
        return LabVitalReplayFrame(devices=devices, tracks=tuple(track_payloads))

    def close(self) -> None:
        temporary = self._temporary
        self._temporary = None
        if temporary is not None:
            temporary.cleanup()

    def _track_frame(
        self,
        connection: sqlite3.Connection,
        *,
        track: _SpoolTrack,
        offset_seconds: int,
        output_time: float,
    ) -> dict[str, object] | None:
        definition = track.definition
        if definition.kind is VitalTrackKind.WAVEFORM:
            values = self._waveform_values(
                connection,
                track=track,
                offset_seconds=offset_seconds,
            )
            if values is None:
                self._missing_track(track, offset_seconds=offset_seconds)
                return None
            records: list[dict[str, object]] = [{"dt": output_time, "val": values}]
            track_type = "wav"
        else:
            value = self._numeric_value(
                connection,
                track=track,
                offset_seconds=offset_seconds,
            )
            if value is None:
                self._missing_track(track, offset_seconds=offset_seconds)
                return None
            records = [{"dt": output_time, "val": round(value, 4)}]
            track_type = "num"
        payload: dict[str, object] = {
            "id": track.output_id,
            "type": track_type,
            "name": definition.name,
            "dname": definition.device_name or "Vital File",
            "montype": MONITOR_TYPE_NAMES.get(
                definition.monitor_type_id,
                str(definition.monitor_type_id),
            ),
            "unit": definition.unit,
            "sourceTrack": definition.dtname,
            "recs": records,
        }
        if definition.kind is VitalTrackKind.WAVEFORM:
            payload["srate"] = definition.sample_rate
            payload["mindisp"] = definition.minimum_display
            payload["maxdisp"] = definition.maximum_display
        return payload

    def _waveform_values(
        self,
        connection: sqlite3.Connection,
        *,
        track: _SpoolTrack,
        offset_seconds: int,
    ) -> list[float] | None:
        definition = track.definition
        sample_rate = definition.sample_rate
        sample_count = max(1, round(sample_rate))
        target_begin = round(offset_seconds * sample_rate)
        target_end = target_begin + sample_count
        frame_start = self.started_at + offset_seconds
        frame_end = frame_start + 1.0
        values = [math.nan] * sample_count
        rows = connection.execute(
            """
            SELECT recorded_at, sample_offset, sample_count, raw_values
            FROM waveform_chunks
            WHERE track_id = ?
              AND recorded_at < ?
              AND recorded_at + ((sample_offset + sample_count) / ?) > ?
            ORDER BY sequence
            """,
            (track.source_id, frame_end, sample_rate, frame_start),
        )
        value_struct = _FORMAT_STRUCTS[definition.format_code]
        for recorded_at, sample_offset, stored_count, raw_values in rows:
            base_index = math.ceil(
                (float(recorded_at) - self.started_at) * sample_rate
            ) + int(sample_offset)
            decoded = value_struct.iter_unpack(bytes(raw_values))
            for index, raw in enumerate(decoded):
                absolute_index = base_index + index
                if absolute_index < target_begin or absolute_index >= target_end:
                    continue
                value = float(raw[0])
                if definition.format_code > 2:
                    value = value * definition.gain + definition.offset
                if math.isinf(value) or value > 4e9:
                    value = math.nan
                values[absolute_index - target_begin] = value
            if len(bytes(raw_values)) != int(stored_count) * value_struct.size:
                raise VitalReplaySourceError(
                    "Vital File replay spool waveform row is invalid: "
                    f"{definition.dtname}",
                    stage="replayFrame",
                    code="replaySpoolInvalid",
                )
        if any(not math.isfinite(value) for value in values):
            return None
        return [round(value, 4) for value in values]

    def _numeric_value(
        self,
        connection: sqlite3.Connection,
        *,
        track: _SpoolTrack,
        offset_seconds: int,
    ) -> float | None:
        frame_start = self.started_at + offset_seconds
        frame_end = frame_start + 1.0
        include_end = offset_seconds == self.duration_seconds - 1
        comparison = "<=" if include_end else "<"
        row = connection.execute(
            f"""
            SELECT value
            FROM numeric_records
            WHERE track_id = ? AND recorded_at >= ? AND recorded_at {comparison} ?
            ORDER BY sequence DESC
            LIMIT 1
            """,
            (track.source_id, frame_start, frame_end),
        ).fetchone()
        if row is None:
            return None
        value = float(row[0])
        return value if math.isfinite(value) else None

    def _missing_track(
        self,
        track: _SpoolTrack,
        *,
        offset_seconds: int,
    ) -> None:
        if self.gap_policy is LabReplayGapPolicy.OMIT_TRACK:
            return None
        raise VitalReplaySourceError(
            "Vital File replay track has no complete finite frame: "
            f"{track.definition.dtname} offset={offset_seconds}",
            stage="replayFrame",
            code="missingTrackRecord",
        )


def _initialize_spool(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        CREATE TABLE waveform_chunks (
            sequence INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id INTEGER NOT NULL,
            recorded_at REAL NOT NULL,
            sample_offset INTEGER NOT NULL,
            sample_count INTEGER NOT NULL,
            raw_values BLOB NOT NULL
        );
        CREATE INDEX waveform_chunks_track_time
            ON waveform_chunks(track_id, recorded_at);
        CREATE TABLE numeric_records (
            sequence INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id INTEGER NOT NULL,
            recorded_at REAL NOT NULL,
            value REAL NOT NULL
        );
        CREATE INDEX numeric_records_track_time
            ON numeric_records(track_id, recorded_at);
        """
    )
