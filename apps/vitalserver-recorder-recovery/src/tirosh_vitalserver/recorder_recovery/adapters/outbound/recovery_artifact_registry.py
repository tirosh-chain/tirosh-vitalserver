"""SQLite-backed recovery artifact receipt registry."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from tirosh_vitalserver.recorder_recovery.domain import (
    ArtifactPublishFailure,
    ArtifactPublishState,
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
    RecoveryArtifactRecord,
)


class RecoveryArtifactRegistryConflict(RuntimeError):
    """An artifact ID already exists with different immutable evidence."""


class RecoveryArtifactRegistryInvalid(RuntimeError):
    """Persisted registry evidence cannot be decoded."""


class RecoveryArtifactRegistryUnavailable(RuntimeError):
    """Registry storage could not be read or written."""


class SqliteRecoveryArtifactRegistry:
    """Own durable private paths and public receipts for recovery artifacts."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def register_export(self, receipt: RecoveryArtifactReceipt) -> None:
        document = _private_receipt_document(receipt)
        encoded = json.dumps(document, separators=(",", ":"), sort_keys=True)
        try:
            with self._connect() as connection:
                self._ensure_schema(connection)
                existing = connection.execute(
                    "SELECT receipt_json FROM recovery_artifacts WHERE artifact_id = ?",
                    (receipt.artifact_id,),
                ).fetchone()
                if existing is not None:
                    if not _same_immutable_receipt(existing[0], encoded):
                        raise RecoveryArtifactRegistryConflict(
                            "recovery artifact registry contains a different receipt "
                            f"artifactId={receipt.artifact_id}"
                        )
                    return
                connection.execute(
                    """
                    INSERT INTO recovery_artifacts (
                        artifact_id, origin, vrcode, created_at, export_state,
                        publish_state, receipt_json
                    ) VALUES (?, ?, ?, ?, 'exported', 'notRequested', ?)
                    """,
                    (
                        receipt.artifact_id,
                        receipt.origin.value,
                        receipt.vrcode,
                        receipt.created_at,
                        encoded,
                    ),
                )
        except (RecoveryArtifactRegistryConflict, RecoveryArtifactRegistryInvalid):
            raise
        except (OSError, sqlite3.Error) as error:
            raise RecoveryArtifactRegistryUnavailable(
                f"recovery artifact registry write failed path={self.path}: {error}"
            ) from error

    def get(self, artifact_id: str) -> RecoveryArtifactReceipt | None:
        try:
            with self._connect() as connection:
                self._ensure_schema(connection)
                row = connection.execute(
                    "SELECT receipt_json FROM recovery_artifacts WHERE artifact_id = ?",
                    (artifact_id,),
                ).fetchone()
        except (OSError, sqlite3.Error) as error:
            raise RecoveryArtifactRegistryUnavailable(
                f"recovery artifact registry read failed path={self.path}: {error}"
            ) from error
        if row is None:
            return None
        return _receipt_from_json(row[0])

    def list(self) -> tuple[RecoveryArtifactReceipt, ...]:
        try:
            with self._connect() as connection:
                self._ensure_schema(connection)
                rows = connection.execute(
                    """
                    SELECT receipt_json
                    FROM recovery_artifacts
                    ORDER BY created_at DESC, artifact_id ASC
                    """
                ).fetchall()
        except (OSError, sqlite3.Error) as error:
            raise RecoveryArtifactRegistryUnavailable(
                f"recovery artifact registry read failed path={self.path}: {error}"
            ) from error
        return tuple(_receipt_from_json(row[0]) for row in rows)

    def get_record(self, artifact_id: str) -> RecoveryArtifactRecord | None:
        try:
            with self._connect() as connection:
                self._ensure_schema(connection)
                row = connection.execute(
                    """
                    SELECT receipt_json, publish_state, publish_attempt_id,
                           publish_requested_at, publish_started_at,
                           upload_accepted_at, published_at,
                           indexed_relative_path, indexed_size_bytes,
                           failure_stage, failure_code, failure_message, failed_at
                    FROM recovery_artifacts
                    WHERE artifact_id = ?
                    """,
                    (artifact_id,),
                ).fetchone()
        except (OSError, sqlite3.Error) as error:
            raise RecoveryArtifactRegistryUnavailable(
                f"recovery artifact registry read failed path={self.path}: {error}"
            ) from error
        return None if row is None else _record_from_row(row)

    def list_records(self) -> tuple[RecoveryArtifactRecord, ...]:
        try:
            with self._connect() as connection:
                self._ensure_schema(connection)
                rows = connection.execute(
                    """
                    SELECT receipt_json, publish_state, publish_attempt_id,
                           publish_requested_at, publish_started_at,
                           upload_accepted_at, published_at,
                           indexed_relative_path, indexed_size_bytes,
                           failure_stage, failure_code, failure_message, failed_at
                    FROM recovery_artifacts
                    ORDER BY created_at DESC, artifact_id ASC
                    """
                ).fetchall()
        except (OSError, sqlite3.Error) as error:
            raise RecoveryArtifactRegistryUnavailable(
                f"recovery artifact registry read failed path={self.path}: {error}"
            ) from error
        return tuple(_record_from_row(row) for row in rows)

    def save_publish(self, record: RecoveryArtifactRecord) -> None:
        try:
            with self._connect() as connection:
                self._ensure_schema(connection)
                existing = connection.execute(
                    "SELECT receipt_json FROM recovery_artifacts WHERE artifact_id = ?",
                    (record.receipt.artifact_id,),
                ).fetchone()
                if existing is None:
                    raise RecoveryArtifactRegistryInvalid(
                        "publish state references an unregistered artifact: "
                        f"{record.receipt.artifact_id}"
                    )
                encoded = json.dumps(
                    _private_receipt_document(record.receipt),
                    separators=(",", ":"),
                    sort_keys=True,
                )
                if not _same_immutable_receipt(existing[0], encoded):
                    raise RecoveryArtifactRegistryConflict(
                        "publish state receipt differs from registered artifact "
                        f"artifactId={record.receipt.artifact_id}"
                    )
                failure = record.failure
                connection.execute(
                    """
                    UPDATE recovery_artifacts
                    SET publish_state = ?, publish_attempt_id = ?,
                        publish_requested_at = ?, publish_started_at = ?,
                        upload_accepted_at = ?, published_at = ?,
                        indexed_relative_path = ?, indexed_size_bytes = ?,
                        failure_stage = ?, failure_code = ?, failure_message = ?,
                        failed_at = ?
                    WHERE artifact_id = ?
                    """,
                    (
                        record.publish_state.value,
                        record.publish_attempt_id,
                        record.publish_requested_at,
                        record.publish_started_at,
                        record.upload_accepted_at,
                        record.published_at,
                        record.indexed_relative_path,
                        record.indexed_size_bytes,
                        None if failure is None else failure.stage,
                        None if failure is None else failure.code,
                        None if failure is None else failure.message,
                        None if failure is None else failure.failed_at,
                        record.receipt.artifact_id,
                    ),
                )
        except (
            RecoveryArtifactRegistryConflict,
            RecoveryArtifactRegistryInvalid,
        ):
            raise
        except (OSError, sqlite3.Error) as error:
            raise RecoveryArtifactRegistryUnavailable(
                f"recovery artifact registry write failed path={self.path}: {error}"
            ) from error

    def _connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        return sqlite3.connect(self.path)

    @staticmethod
    def _ensure_schema(connection: sqlite3.Connection) -> None:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS recovery_artifact_registry_metadata (
                singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                schema_version INTEGER NOT NULL
            )
            """
        )
        metadata = connection.execute(
            """
            SELECT schema_version
            FROM recovery_artifact_registry_metadata
            WHERE singleton = 1
            """
        ).fetchone()
        if metadata is None:
            connection.execute(
                """
                INSERT INTO recovery_artifact_registry_metadata (
                    singleton, schema_version
                ) VALUES (1, 2)
                """
            )
            _create_artifact_table_v2(connection)
            return
        if metadata[0] == 1:
            _migrate_schema_v1_to_v2(connection)
            return
        if metadata[0] != 2:
            raise RecoveryArtifactRegistryInvalid(
                "recovery artifact registry schema version is unsupported: "
                f"{metadata[0]}"
            )
        _create_artifact_table_v2(connection)


def _create_artifact_table_v2(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS recovery_artifacts (
            artifact_id TEXT PRIMARY KEY,
            origin TEXT NOT NULL,
            vrcode TEXT NOT NULL,
            created_at REAL NOT NULL,
            export_state TEXT NOT NULL CHECK (export_state = 'exported'),
            publish_state TEXT NOT NULL CHECK (
                publish_state IN (
                    'notRequested', 'publishRequested', 'publishing',
                    'reconciling', 'published', 'failed'
                )
            ),
            publish_attempt_id TEXT,
            publish_requested_at REAL,
            publish_started_at REAL,
            upload_accepted_at REAL,
            published_at REAL,
            indexed_relative_path TEXT,
            indexed_size_bytes INTEGER,
            failure_stage TEXT,
            failure_code TEXT,
            failure_message TEXT,
            failed_at REAL,
            receipt_json TEXT NOT NULL
        )
        """
    )


def _migrate_schema_v1_to_v2(connection: sqlite3.Connection) -> None:
    published = connection.execute(
        "SELECT artifact_id FROM recovery_artifacts WHERE publish_state = 'published'"
    ).fetchone()
    if published is not None:
        raise RecoveryArtifactRegistryInvalid(
            "schema v1 published artifact lacks required index evidence: "
            f"artifactId={published[0]}"
        )
    connection.execute("ALTER TABLE recovery_artifacts RENAME TO recovery_artifacts_v1")
    _create_artifact_table_v2(connection)
    connection.execute(
        """
        INSERT INTO recovery_artifacts (
            artifact_id, origin, vrcode, created_at, export_state,
            publish_state, receipt_json
        )
        SELECT artifact_id, origin, vrcode, created_at, export_state,
               publish_state, receipt_json
        FROM recovery_artifacts_v1
        """
    )
    connection.execute("DROP TABLE recovery_artifacts_v1")
    connection.execute(
        """
        UPDATE recovery_artifact_registry_metadata
        SET schema_version = 2
        WHERE singleton = 1
        """
    )


def _record_from_row(row: sqlite3.Row | tuple[object, ...]) -> RecoveryArtifactRecord:
    try:
        state = ArtifactPublishState(str(row[1]))
        failure_values = row[9:13]
        failure_present = any(value is not None for value in failure_values)
        if failure_present and any(value is None for value in failure_values):
            raise TypeError("publish failure evidence is incomplete")
        failure = (
            ArtifactPublishFailure(
                stage=str(row[9]),
                code=str(row[10]),
                message=str(row[11]),
                failed_at=float(row[12]),
            )
            if failure_present
            else None
        )
        record = RecoveryArtifactRecord(
            receipt=_receipt_from_json(str(row[0])),
            publish_state=state,
            publish_attempt_id=_optional_string(row[2], "publish_attempt_id"),
            publish_requested_at=_optional_number(row[3], "publish_requested_at"),
            publish_started_at=_optional_number(row[4], "publish_started_at"),
            upload_accepted_at=_optional_number(row[5], "upload_accepted_at"),
            published_at=_optional_number(row[6], "published_at"),
            indexed_relative_path=_optional_string(
                row[7], "indexed_relative_path"
            ),
            indexed_size_bytes=_optional_integer(row[8], "indexed_size_bytes"),
            failure=failure,
        )
        _validate_publish_record(record)
        return record
    except (TypeError, ValueError) as error:
        raise RecoveryArtifactRegistryInvalid(
            f"recovery artifact publish state is invalid: {error}"
        ) from error


def _validate_publish_record(record: RecoveryArtifactRecord) -> None:
    if record.publish_state is ArtifactPublishState.NOT_REQUESTED:
        if any(
            value is not None
            for value in (
                record.publish_attempt_id,
                record.publish_requested_at,
                record.publish_started_at,
                record.upload_accepted_at,
                record.published_at,
                record.indexed_relative_path,
                record.indexed_size_bytes,
                record.failure,
            )
        ):
            raise TypeError("notRequested publish state contains operation evidence")
    elif not record.publish_attempt_id or record.publish_requested_at is None:
        raise TypeError("publish operation identity is missing")
    if record.publish_state is ArtifactPublishState.PUBLISHED and (
        record.published_at is None
        or not record.indexed_relative_path
        or record.indexed_size_bytes is None
    ):
        raise TypeError("published state lacks index evidence")
    if record.publish_state is ArtifactPublishState.FAILED and record.failure is None:
        raise TypeError("failed state lacks failure evidence")
    if record.publish_state is not ArtifactPublishState.FAILED and record.failure:
        raise TypeError("non-failed state contains failure evidence")


def _optional_string(value: object, label: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise TypeError(f"{label} must be a non-empty string or null")
    return value


def _optional_number(value: object, label: str) -> float | None:
    if value is None:
        return None
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise TypeError(f"{label} must be a number or null")
    return float(value)


def _optional_integer(value: object, label: str) -> int | None:
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError(f"{label} must be an integer or null")
    return value


def _private_receipt_document(receipt: RecoveryArtifactReceipt) -> dict[str, object]:
    return {
        "artifactId": receipt.artifact_id,
        "origin": receipt.origin.value,
        "producer": receipt.producer,
        "writerVersion": receipt.writer_version,
        "vrcode": receipt.vrcode,
        "roomNames": list(receipt.room_names),
        "sourceArchiveId": receipt.source_archive_id,
        "sourceStartOffset": receipt.source_start_offset,
        "sourceEndOffset": receipt.source_end_offset,
        "coverageStartedAt": receipt.coverage_started_at,
        "coverageEndedAt": receipt.coverage_ended_at,
        "formatVersion": receipt.format_version,
        "sha256": receipt.sha256,
        "path": receipt.path,
        "filename": receipt.filename,
        "sizeBytes": receipt.size_bytes,
        "createdAt": receipt.created_at,
        "trackCount": receipt.track_count,
    }


def _receipt_from_json(encoded: str) -> RecoveryArtifactReceipt:
    try:
        document = json.loads(encoded)
        if not isinstance(document, dict):
            raise TypeError("receipt must be an object")
        return RecoveryArtifactReceipt(
            artifact_id=_string(document, "artifactId"),
            origin=RecoveryArtifactOrigin(_string(document, "origin")),
            producer=_string(document, "producer"),
            writer_version=_string(document, "writerVersion"),
            vrcode=_string(document, "vrcode"),
            room_names=_strings(document, "roomNames"),
            source_archive_id=_string(document, "sourceArchiveId"),
            source_start_offset=_integer(document, "sourceStartOffset"),
            source_end_offset=_integer(document, "sourceEndOffset"),
            coverage_started_at=_number(document, "coverageStartedAt"),
            coverage_ended_at=_number(document, "coverageEndedAt"),
            format_version=_integer(document, "formatVersion"),
            sha256=_string(document, "sha256"),
            path=_string(document, "path"),
            filename=_string(document, "filename"),
            size_bytes=_integer(document, "sizeBytes"),
            created_at=_number(document, "createdAt"),
            track_count=_integer(document, "trackCount"),
        )
    except (json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        raise RecoveryArtifactRegistryInvalid(
            f"recovery artifact registry receipt is invalid: {error}"
        ) from error


def _same_immutable_receipt(existing: str, candidate: str) -> bool:
    try:
        existing_document = json.loads(existing)
        candidate_document = json.loads(candidate)
    except json.JSONDecodeError as error:
        raise RecoveryArtifactRegistryInvalid(
            f"recovery artifact registry receipt is invalid: {error}"
        ) from error
    if not isinstance(existing_document, dict) or not isinstance(
        candidate_document, dict
    ):
        raise RecoveryArtifactRegistryInvalid(
            "recovery artifact registry receipt must be an object"
        )
    existing_document.pop("createdAt", None)
    candidate_document.pop("createdAt", None)
    return existing_document == candidate_document


def _string(document: dict[str, Any], key: str) -> str:
    value = document[key]
    if not isinstance(value, str) or not value:
        raise TypeError(f"{key} must be a non-empty string")
    return value


def _strings(document: dict[str, Any], key: str) -> tuple[str, ...]:
    value = document[key]
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item for item in value
    ):
        raise TypeError(f"{key} must be an array of non-empty strings")
    return tuple(value)


def _integer(document: dict[str, Any], key: str) -> int:
    value = document[key]
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError(f"{key} must be an integer")
    return value


def _number(document: dict[str, Any], key: str) -> float:
    value = document[key]
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise TypeError(f"{key} must be a number")
    return float(value)
