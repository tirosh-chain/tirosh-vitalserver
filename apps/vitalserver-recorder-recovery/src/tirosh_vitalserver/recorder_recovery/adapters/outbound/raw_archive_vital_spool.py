"""Operation-owned SQLite spool for raw archive materialization."""

from __future__ import annotations

import json
import math
import sqlite3
import tempfile
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from types import TracebackType

from tirosh_vitalserver.core.domain.vital_file import (
    RawArchivePayload,
    RawArchiveVitalGroup,
    VitalTrack,
    VitalTrackKind,
    VitalTrackRecord,
    collect_frame_tracks,
)
from tirosh_vitalserver.core.domain.vital_file.raw_archive import recorder_room_names


@dataclass(frozen=True, slots=True)
class RawArchiveVitalArtifact:
    """One recorder artifact loaded from the disk spool."""

    coverage_started_at: float
    coverage_ended_at: float
    group: RawArchiveVitalGroup


class RawArchiveVitalSpool:
    """Persist decoded records before loading one recorder artifact at a time."""

    def __init__(self, spool_parent: Path) -> None:
        spool_parent.mkdir(parents=True, exist_ok=True)
        self._temporary_directory = tempfile.TemporaryDirectory(
            prefix=".raw-archive-vital-spool-",
            dir=spool_parent,
        )
        self.path = Path(self._temporary_directory.name) / "records.sqlite3"
        self._connection = sqlite3.connect(self.path)
        self._create_schema()

    def __enter__(self) -> RawArchiveVitalSpool:
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        del exc_type, exc_value, traceback
        self.close()

    def close(self) -> None:
        self._connection.close()
        self._temporary_directory.cleanup()

    def append(self, payload: RawArchivePayload) -> None:
        """Append one decoded payload without retaining prior payload records."""

        track_records: dict[str, list[VitalTrackRecord]] = {}
        track_configs: dict[
            str,
            tuple[VitalTrackKind, float, str, float, float, int],
        ] = {}
        collect_frame_tracks(
            payload.payload,
            track_records=track_records,
            track_configs=track_configs,
        )
        for dtname, records in track_records.items():
            config = track_configs[dtname]
            self._register_track(
                vrcode=payload.vrcode,
                dtname=dtname,
                config=config,
            )
            for record in records:
                if not math.isfinite(record.dt):
                    raise ValueError("raw archive track record time must be finite")
                self._connection.execute(
                    """
                    INSERT INTO records (vrcode, dtname, dt, value_json)
                    VALUES (?, ?, ?, ?)
                    """,
                    (
                        payload.vrcode,
                        dtname,
                        record.dt,
                        _encode_value(record.value, dtname=dtname),
                    ),
                )
        for room_name in recorder_room_names(payload.payload):
            self._connection.execute(
                "INSERT OR IGNORE INTO rooms (vrcode, room_name) VALUES (?, ?)",
                (payload.vrcode, room_name),
            )
        self._connection.commit()

    def iter_artifacts(self) -> Iterator[RawArchiveVitalArtifact]:
        """Load one complete artifact per recorder in the source byte window."""

        rows = self._connection.execute(
            "SELECT DISTINCT vrcode FROM records ORDER BY vrcode ASC"
        ).fetchall()
        for row in rows:
            yield self._load_artifact(vrcode=str(row[0]))

    def _load_artifact(self, *, vrcode: str) -> RawArchiveVitalArtifact:
        room_rows = self._connection.execute(
            "SELECT room_name FROM rooms WHERE vrcode = ? ORDER BY room_name ASC",
            (vrcode,),
        ).fetchall()
        track_rows = self._connection.execute(
            """
            SELECT dtname, kind, srate, unit, mindisp, maxdisp, montype
            FROM tracks
            WHERE vrcode = ?
            ORDER BY dtname ASC
            """,
            (vrcode,),
        ).fetchall()
        tracks: list[VitalTrack] = []
        coverage_started_at = math.inf
        coverage_ended_at = -math.inf
        for row in track_rows:
            dtname = str(row[0])
            kind = VitalTrackKind.from_code(row[1])
            srate = float(row[2])
            record_rows = self._connection.execute(
                """
                SELECT dt, value_json
                FROM records
                WHERE vrcode = ? AND dtname = ?
                ORDER BY dt ASC, sequence ASC
                """,
                (vrcode, dtname),
            ).fetchall()
            records = tuple(
                VitalTrackRecord(dt=float(record[0]), value=json.loads(record[1]))
                for record in record_rows
            )
            if not records:
                continue
            track = VitalTrack(
                dtname=dtname,
                kind=kind,
                records=records,
                srate=srate,
                unit=str(row[3]),
                mindisp=float(row[4]),
                maxdisp=float(row[5]),
                montype=int(row[6]),
            )
            tracks.append(track)
            coverage_started_at = min(coverage_started_at, records[0].dt)
            coverage_ended_at = max(
                coverage_ended_at,
                *(_record_end(record, kind=kind, srate=srate) for record in records),
            )
        if not tracks or not math.isfinite(coverage_started_at):
            raise RuntimeError(
                "raw archive spool artifact has no materializable records "
                f"vrcode={vrcode}"
            )
        return RawArchiveVitalArtifact(
            coverage_started_at=coverage_started_at,
            coverage_ended_at=max(coverage_ended_at, coverage_started_at + 0.001),
            group=RawArchiveVitalGroup(
                vrcode=vrcode,
                room_names=tuple(str(row[0]) for row in room_rows),
                tracks=tuple(tracks),
            ),
        )

    def _register_track(
        self,
        *,
        vrcode: str,
        dtname: str,
        config: tuple[VitalTrackKind, float, str, float, float, int],
    ) -> None:
        values = (
            vrcode,
            dtname,
            int(config[0]),
            config[1],
            config[2],
            config[3],
            config[4],
            config[5],
        )
        self._connection.execute(
            """
            INSERT OR IGNORE INTO tracks (
                vrcode, dtname, kind, srate, unit, mindisp, maxdisp, montype
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values,
        )
        existing = self._connection.execute(
            """
            SELECT kind, srate, unit, mindisp, maxdisp, montype
            FROM tracks
            WHERE vrcode = ? AND dtname = ?
            """,
            (vrcode, dtname),
        ).fetchone()
        if existing != values[2:]:
            raise ValueError(
                "raw archive track metadata changed inside one artifact: "
                f"vrcode={vrcode} track={dtname}"
            )

    def _create_schema(self) -> None:
        self._connection.executescript(
            """
            CREATE TABLE tracks (
                vrcode TEXT NOT NULL,
                dtname TEXT NOT NULL,
                kind INTEGER NOT NULL,
                srate REAL NOT NULL,
                unit TEXT NOT NULL,
                mindisp REAL NOT NULL,
                maxdisp REAL NOT NULL,
                montype INTEGER NOT NULL,
                PRIMARY KEY (vrcode, dtname)
            );
            CREATE TABLE records (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                vrcode TEXT NOT NULL,
                dtname TEXT NOT NULL,
                dt REAL NOT NULL,
                value_json TEXT NOT NULL
            );
            CREATE INDEX records_artifact_track
                ON records (vrcode, dtname, dt, sequence);
            CREATE TABLE rooms (
                vrcode TEXT NOT NULL,
                room_name TEXT NOT NULL,
                PRIMARY KEY (vrcode, room_name)
            );
            """
        )


def _record_end(
    record: VitalTrackRecord,
    *,
    kind: VitalTrackKind,
    srate: float,
) -> float:
    if kind is VitalTrackKind.WAVEFORM and isinstance(record.value, list):
        return record.dt + (len(record.value) / srate)
    return record.dt


def _encode_value(value: object, *, dtname: str) -> str:
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            separators=(",", ":"),
            allow_nan=False,
        )
    except (TypeError, ValueError) as error:
        raise ValueError(
            f"raw archive track record is not finite JSON: {dtname}"
        ) from error
