from __future__ import annotations

import json
import subprocess
from collections.abc import Callable
from dataclasses import replace
from typing import Any
from uuid import uuid4

from .model import (
    LabBed,
    LabBedCreateInput,
    LabBedDeleteInput,
    LabRecorder,
    LabRecorderCreateInput,
    LabRecorderDeleteInput,
    LabRecorderExecutionResult,
    LabSession,
    LabSessionCreateInput,
    LabSessionStoreUnavailable,
    lab_bed_for_session,
    lab_recorder_for_bed,
    explicit_beds_for_session,
    matching_beds,
    matching_beds_for_recorder_create,
    matching_recorders,
    next_recorder_index,
    recorder_with_execution_result,
    recorder_with_preserved_execution,
    resolved_bed_room_names,
    utc_now_iso,
)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS lab_sessions (
    session_id text PRIMARY KEY,
    document jsonb NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS lab_sessions_updated_at_idx
    ON lab_sessions (updated_at);
CREATE TABLE IF NOT EXISTS lab_beds (
    bed_id text PRIMARY KEY,
    document jsonb NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS lab_beds_updated_at_idx
    ON lab_beds (updated_at);
CREATE TABLE IF NOT EXISTS lab_recorders (
    recorder_id text PRIMARY KEY,
    document jsonb NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS lab_recorders_updated_at_idx
    ON lab_recorders (updated_at);
"""


class PostgresLabSessionStore:
    def __init__(
        self,
        database_url: str,
        *,
        psql_command: str = "psql",
        psql_timeout_seconds: float = 15,
        id_factory: Callable[[], str] | None = None,
    ) -> None:
        self.database_url = database_url
        self.psql_command = psql_command
        self.psql_timeout_seconds = psql_timeout_seconds
        self.id_factory = id_factory or (lambda: f"lab_{uuid4().hex}")

    def ensure_ready(self) -> None:
        self._run_psql(SCHEMA_SQL, stage="lab session schema migration")

    def create(self, request: LabSessionCreateInput) -> LabSession:
        now = utc_now_iso()
        selected_beds = (
            explicit_beds_for_session(self.list_beds(), request.bed_ids)
            if request.bed_ids
            else ()
        )
        bed_room_names = (
            tuple(bed.name for bed in selected_beds)
            if selected_beds
            else resolved_bed_room_names(request)
        )
        session = LabSession(
            session_id=self.id_factory(),
            scenario_id=request.scenario_id,
            name=request.name,
            recorder_count=len(selected_beds) if selected_beds else request.recorder_count,
            target_url=request.target_url,
            bed_room_names=bed_room_names,
            bed_ids=tuple(bed.bed_id for bed in selected_beds),
            vital_file_path=request.vital_file_path,
            state="accepted",
            created_at=now,
            updated_at=now,
        )
        self._save(session, stage="lab session create")
        if selected_beds:
            self._occupy_existing_read_model_beds(
                session,
                selected_beds,
                state="accepted",
            )
        else:
            self._save_session_read_model(session, state="accepted", with_recorders=True)
        return session

    def get(self, session_id: str) -> LabSession | None:
        sql = (
            "SELECT document::text FROM lab_sessions "
            f"WHERE session_id = {sql_literal(session_id)};"
        )
        completed = self._run_psql(sql, stage="lab session read")
        text = (completed.stdout or "").strip()
        if not text:
            return None
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise LabSessionStoreUnavailable(
                "postgres lab session document is invalid JSON",
                kind="postgresLabSessionDocumentInvalid",
            ) from error
        if not isinstance(document, dict):
            raise LabSessionStoreUnavailable(
                "postgres lab session document is not an object",
                kind="postgresLabSessionDocumentInvalid",
            )
        return session_from_json(document)

    def start(self, session_id: str) -> LabSession | None:
        return self._transition(session_id, state="running")

    def stop(self, session_id: str) -> LabSession | None:
        return self._transition(session_id, state="stopped")

    def _transition(self, session_id: str, *, state: str) -> LabSession | None:
        session = self.get(session_id)
        if session is None:
            return None
        session.state = state
        session.updated_at = utc_now_iso()
        self._save(session, stage=f"lab session {state}")
        self._save_session_state_read_model(session, state=state)
        return session

    def list_beds(self) -> tuple[LabBed, ...]:
        completed = self._run_psql(
            "SELECT document::text FROM lab_beds ORDER BY bed_id;",
            stage="lab bed read model read",
        )
        return tuple(
            bed_from_json(document)
            for document in json_documents_from_stdout(
                completed.stdout or "",
                kind="postgresLabBedDocumentInvalid",
                label="postgres lab bed document",
            )
        )

    def list_recorders(self) -> tuple[LabRecorder, ...]:
        completed = self._run_psql(
            "SELECT document::text FROM lab_recorders ORDER BY recorder_id;",
            stage="lab recorder read model read",
        )
        return tuple(
            recorder_from_json(document)
            for document in json_documents_from_stdout(
                completed.stdout or "",
                kind="postgresLabRecorderDocumentInvalid",
                label="postgres lab recorder document",
            )
        )

    def save_recorder_execution_results(
        self,
        results: tuple[LabRecorderExecutionResult, ...],
    ) -> None:
        recorders_by_id = {
            recorder.recorder_id: recorder for recorder in self.list_recorders()
        }
        statements: list[str] = []
        for result in results:
            recorder = recorders_by_id.get(result.recorder_id)
            if recorder is None:
                raise LabSessionStoreUnavailable(
                    f"Lab recorder read model is missing: {result.recorder_id}",
                    kind="labRecorderReadModelMissing",
                )
            updated = recorder_with_execution_result(recorder, result)
            statements.append(
                _upsert_read_model_sql(
                    table="lab_recorders",
                    key_field="recorder_id",
                    key_value=updated.recorder_id,
                    document=updated.as_json(),
                    updated_at=updated.updated_at,
                )
            )
        if statements:
            self._run_psql(
                "\n".join(statements),
                stage="lab recorder execution result save",
            )

    def create_beds(self, request: LabBedCreateInput) -> tuple[LabBed, ...]:
        now = utc_now_iso()
        session = LabSession(
            session_id=self.id_factory(),
            scenario_id="manual-lab-beds",
            name=request.prefix,
            recorder_count=request.count,
            target_url=request.target_url,
            bed_room_names=request.room_names,
            bed_ids=(),
            vital_file_path=None,
            state="accepted",
            created_at=now,
            updated_at=now,
        )
        self._save(session, stage="lab manual beds create")
        self._save_session_read_model(session, state="accepted", with_recorders=False)
        return self.list_beds()

    def delete_beds(self, request: LabBedDeleteInput) -> tuple[LabBed, ...]:
        matches = matching_beds(self.list_beds(), request)
        if not matches:
            raise LabSessionStoreUnavailable(
                "No Lab beds matched the delete request.",
                kind="labBedDeleteTargetMissing",
            )
        statements: list[str] = []
        for bed in matches:
            statements.append(
                f"DELETE FROM lab_recorders WHERE document->>'bedId' = {sql_literal(bed.bed_id)};"
            )
            statements.append(
                f"DELETE FROM lab_beds WHERE bed_id = {sql_literal(bed.bed_id)};"
            )
        self._run_psql("\n".join(statements), stage="lab bed delete")
        return self.list_beds()

    def reset_beds(self) -> tuple[LabBed, ...]:
        self._run_psql(
            "DELETE FROM lab_recorders;\nDELETE FROM lab_beds;",
            stage="lab bed reset",
        )
        return self.list_beds()

    def create_recorders(
        self,
        request: LabRecorderCreateInput,
    ) -> tuple[LabRecorder, ...]:
        beds = matching_beds_for_recorder_create(self.list_beds(), request)
        if not beds:
            raise LabSessionStoreUnavailable(
                "No Lab beds matched the recorder create request.",
                kind="labRecorderCreateTargetMissing",
            )
        existing = self.list_recorders()
        now = utc_now_iso()
        statements: list[str] = []
        for bed in beds:
            recorder = lab_recorder_for_bed(
                session_id=bed.session_id,
                bed_id=bed.bed_id,
                state=bed.state,
                index=next_recorder_index(existing, bed.session_id),
                created_at=now,
                updated_at=now,
            )
            existing = (*existing, recorder)
            statements.append(
                _upsert_read_model_sql(
                    table="lab_recorders",
                    key_field="recorder_id",
                    key_value=recorder.recorder_id,
                    document=recorder.as_json(),
                    updated_at=recorder.updated_at,
                )
            )
        self._run_psql("\n".join(statements), stage="lab recorder create")
        return self.list_recorders()

    def delete_recorders(
        self,
        request: LabRecorderDeleteInput,
    ) -> tuple[LabRecorder, ...]:
        matches = matching_recorders(self.list_recorders(), request)
        if not matches:
            raise LabSessionStoreUnavailable(
                "No Lab recorders matched the delete request.",
                kind="labRecorderDeleteTargetMissing",
            )
        statements = [
            f"DELETE FROM lab_recorders WHERE recorder_id = {sql_literal(recorder.recorder_id)};"
            for recorder in matches
        ]
        self._run_psql("\n".join(statements), stage="lab recorder delete")
        return self.list_recorders()

    def reset_recorders(self) -> tuple[LabRecorder, ...]:
        self._run_psql("DELETE FROM lab_recorders;", stage="lab recorder reset")
        return self.list_recorders()

    def _save(self, session: LabSession, *, stage: str) -> None:
        document = session.as_private_json()
        sql = (
            "INSERT INTO lab_sessions "
            "(session_id, document, created_at, updated_at) VALUES ("
            f"{sql_literal(session.session_id)}, "
            f"{jsonb_literal(document)}, "
            f"{sql_literal(session.created_at)}::timestamptz, "
            f"{sql_literal(session.updated_at)}::timestamptz"
            ") ON CONFLICT (session_id) DO UPDATE SET "
            "document = EXCLUDED.document, "
            "created_at = EXCLUDED.created_at, "
            "updated_at = EXCLUDED.updated_at;"
        )
        self._run_psql(sql, stage=stage)

    def _save_session_read_model(
        self,
        session: LabSession,
        *,
        state: str,
        with_recorders: bool,
    ) -> None:
        existing_recorders = {
            recorder.recorder_id: recorder
            for recorder in self.list_recorders()
            if recorder.session_id == session.session_id
        }
        for index, name in enumerate(session.bed_room_names, start=1):
            bed = lab_bed_for_session(
                session_id=session.session_id,
                name=name,
                state=state,
                index=index,
                created_at=session.created_at,
                updated_at=session.updated_at,
            )
            sql = _upsert_read_model_sql(
                table="lab_beds",
                key_field="bed_id",
                key_value=bed.bed_id,
                document=bed.as_json(),
                updated_at=bed.updated_at,
            )
            if with_recorders:
                recorder = lab_recorder_for_bed(
                    session_id=session.session_id,
                    bed_id=bed.bed_id,
                    state=state,
                    index=index,
                    created_at=session.created_at,
                    updated_at=session.updated_at,
                )
                previous_recorder = existing_recorders.get(recorder.recorder_id)
                if previous_recorder is not None:
                    recorder = recorder_with_preserved_execution(
                        recorder,
                        previous_recorder,
                    )
                sql += "\n" + _upsert_read_model_sql(
                    table="lab_recorders",
                    key_field="recorder_id",
                    key_value=recorder.recorder_id,
                    document=recorder.as_json(),
                    updated_at=recorder.updated_at,
                )
            self._run_psql(sql, stage="lab session read model save")

    def _save_session_state_read_model(self, session: LabSession, *, state: str) -> None:
        if session.bed_ids:
            self._occupy_existing_read_model_beds(
                session,
                explicit_beds_for_session(self.list_beds(), session.bed_ids),
                state=state,
            )
            return
        self._save_session_read_model(session, state=state, with_recorders=True)

    def _occupy_existing_read_model_beds(
        self,
        session: LabSession,
        beds: tuple[LabBed, ...],
        *,
        state: str,
    ) -> None:
        recorders_by_bed_id: dict[str, list[LabRecorder]] = {}
        for recorder in self.list_recorders():
            recorders_by_bed_id.setdefault(recorder.bed_id, []).append(recorder)
        statements: list[str] = []
        for index, bed in enumerate(beds, start=1):
            updated_bed = replace(
                bed,
                session_id=session.session_id,
                state=state,
                updated_at=session.updated_at,
            )
            statements.append(
                _upsert_read_model_sql(
                    table="lab_beds",
                    key_field="bed_id",
                    key_value=updated_bed.bed_id,
                    document=updated_bed.as_json(),
                    updated_at=updated_bed.updated_at,
                )
            )
            existing_recorders = sorted(
                recorders_by_bed_id.get(bed.bed_id, []),
                key=lambda recorder: recorder.recorder_id,
            )
            if existing_recorders:
                for recorder in existing_recorders:
                    updated_recorder = replace(
                        recorder,
                        session_id=session.session_id,
                        state=state,
                        updated_at=session.updated_at,
                    )
                    statements.append(
                        _upsert_read_model_sql(
                            table="lab_recorders",
                            key_field="recorder_id",
                            key_value=updated_recorder.recorder_id,
                            document=updated_recorder.as_json(),
                            updated_at=updated_recorder.updated_at,
                        )
                    )
                continue
            recorder = lab_recorder_for_bed(
                session_id=session.session_id,
                bed_id=bed.bed_id,
                state=state,
                index=index,
                created_at=session.created_at,
                updated_at=session.updated_at,
            )
            statements.append(
                _upsert_read_model_sql(
                    table="lab_recorders",
                    key_field="recorder_id",
                    key_value=recorder.recorder_id,
                    document=recorder.as_json(),
                    updated_at=recorder.updated_at,
                )
            )
        if statements:
            self._run_psql(
                "\n".join(statements),
                stage="lab session existing read model occupy",
            )

    def _run_psql(
        self,
        sql: str,
        *,
        stage: str,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            self.psql_command,
            self.database_url,
            "-v",
            "ON_ERROR_STOP=1",
            "-qAt",
            "-c",
            sql,
        ]
        try:
            return subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
                timeout=self.psql_timeout_seconds,
            )
        except OSError as error:
            raise LabSessionStoreUnavailable(
                f"postgres command could not start during {stage}: {error}",
                kind="postgresCommandUnavailable",
            ) from error
        except subprocess.TimeoutExpired as error:
            raise LabSessionStoreUnavailable(
                (
                    f"postgres command timed out during {stage}: "
                    f"timeoutSeconds={self.psql_timeout_seconds:g}"
                ),
                kind="postgresCommandTimedOut",
            ) from error
        except subprocess.CalledProcessError as error:
            message = (
                f"postgres command failed during {stage}: "
                f"exitCode={error.returncode}"
            )
            output = compact_process_output(error)
            if output:
                message += "\n" + output
            raise LabSessionStoreUnavailable(
                message,
                kind="postgresCommandFailed",
            ) from error


def compact_process_output(error: subprocess.CalledProcessError) -> str:
    sections: list[str] = []
    if error.stdout:
        sections.append(f"stdout:\n{error.stdout}")
    if error.stderr:
        sections.append(f"stderr:\n{error.stderr}")
    return "\n".join(sections)


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def jsonb_literal(document: dict[str, Any]) -> str:
    return sql_literal(json.dumps(document, sort_keys=True)) + "::jsonb"


def _upsert_read_model_sql(
    *,
    table: str,
    key_field: str,
    key_value: str,
    document: dict[str, Any],
    updated_at: str,
) -> str:
    return (
        f"INSERT INTO {table} ({key_field}, document, updated_at) VALUES ("
        f"{sql_literal(key_value)}, "
        f"{jsonb_literal(document)}, "
        f"{sql_literal(updated_at)}::timestamptz"
        f") ON CONFLICT ({key_field}) DO UPDATE SET "
        "document = EXCLUDED.document, "
        "updated_at = EXCLUDED.updated_at;"
    )


def session_from_json(document: dict[str, Any]) -> LabSession:
    return LabSession(
        session_id=required_string(document, "sessionId"),
        scenario_id=required_string(document, "scenarioId"),
        name=required_string(document, "name"),
        recorder_count=required_int(document, "recorderCount"),
        target_url=optional_string(document.get("targetURL")),
        bed_room_names=string_tuple(document.get("bedRoomNames"), "bedRoomNames"),
        bed_ids=string_tuple_or_empty(document.get("bedIds"), "bedIds"),
        vital_file_path=optional_string(document.get("vitalFilePath")),
        state=required_string(document, "state"),
        created_at=required_string(document, "createdAt"),
        updated_at=required_string(document, "updatedAt"),
    )


def bed_from_json(document: dict[str, Any]) -> LabBed:
    return LabBed(
        bed_id=required_string(document, "bedId"),
        session_id=required_string(document, "sessionId"),
        name=required_string(document, "name"),
        state=required_string(document, "state"),
        created_at=required_string(document, "createdAt"),
        updated_at=required_string(document, "updatedAt"),
    )


def recorder_from_json(document: dict[str, Any]) -> LabRecorder:
    return LabRecorder(
        recorder_id=required_string(document, "recorderId"),
        session_id=required_string(document, "sessionId"),
        bed_id=required_string(document, "bedId"),
        vrcode=required_string(document, "vrcode"),
        state=required_string(document, "state"),
        created_at=required_string(document, "createdAt"),
        updated_at=required_string(document, "updatedAt"),
        messages_sent=required_int(document, "messagesSent"),
        last_send_state=required_string(document, "lastSendState"),
        last_send_at=optional_string(document.get("lastSendAt")),
        last_send_error=optional_string(document.get("lastSendError")),
    )


def json_documents_from_stdout(
    stdout: str,
    *,
    kind: str,
    label: str,
) -> tuple[dict[str, Any], ...]:
    documents: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        text = line.strip()
        if not text:
            continue
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise LabSessionStoreUnavailable(
                f"{label} is invalid JSON",
                kind=kind,
            ) from error
        if not isinstance(document, dict):
            raise LabSessionStoreUnavailable(
                f"{label} is not an object",
                kind=kind,
            )
        documents.append(document)
    return tuple(documents)


def required_string(document: dict[str, Any], field: str) -> str:
    value = document.get(field)
    if not isinstance(value, str) or not value:
        raise LabSessionStoreUnavailable(
            f"postgres lab session document field is invalid: {field}",
            kind="postgresLabSessionDocumentInvalid",
        )
    return value


def required_int(document: dict[str, Any], field: str) -> int:
    value = document.get(field)
    if isinstance(value, bool) or not isinstance(value, int):
        raise LabSessionStoreUnavailable(
            f"postgres lab session document field is invalid: {field}",
            kind="postgresLabSessionDocumentInvalid",
        )
    return value


def optional_string(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    raise LabSessionStoreUnavailable(
        "postgres lab session document field is invalid: targetURL",
        kind="postgresLabSessionDocumentInvalid",
    )


def string_tuple(value: object, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        raise LabSessionStoreUnavailable(
            f"postgres lab session document field is invalid: {field}",
            kind="postgresLabSessionDocumentInvalid",
        )
    items: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item:
            raise LabSessionStoreUnavailable(
                f"postgres lab session document field is invalid: {field}",
                kind="postgresLabSessionDocumentInvalid",
            )
        items.append(item)
    return tuple(items)


def string_tuple_or_empty(value: object, field: str) -> tuple[str, ...]:
    if value is None:
        return ()
    if isinstance(value, list) and not value:
        return ()
    return string_tuple(value, field)
