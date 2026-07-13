from __future__ import annotations

from collections.abc import Callable
from threading import RLock

from sqlalchemy import create_engine, delete, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from ..model import (
    InMemoryLabSessionStore,
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
)
from .mappers import (
    bed_domain,
    bed_record,
    recorder_domain,
    recorder_record,
    session_domain,
    session_record,
)
from .records import LabBedRecord, LabRecordBase, LabRecorderRecord, LabSessionRecord


class SQLAlchemyLabSessionStore(InMemoryLabSessionStore):
    """Persistent Lab store whose domain contract is independent of SQL dialect."""

    def __init__(
        self, database_url: str, *, id_factory: Callable[[], str] | None = None
    ) -> None:
        super().__init__()
        if id_factory is not None:
            self.id_factory = id_factory
        self._engine = create_engine(_sqlalchemy_url(database_url), pool_pre_ping=True)
        self._lock = RLock()

    def ensure_ready(self) -> None:
        try:
            LabRecordBase.metadata.create_all(self._engine)
            with self._engine.connect() as connection:
                connection.exec_driver_sql("SELECT 1")
        except SQLAlchemyError as error:
            raise _unavailable("schema migration", error) from error

    def create(self, request: LabSessionCreateInput) -> LabSession:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).create(request)
        )

    def get(self, session_id: str) -> LabSession | None:
        return self._read(
            lambda: super(SQLAlchemyLabSessionStore, self).get(session_id)
        )

    def list_sessions(self) -> tuple[LabSession, ...]:
        return self._read(
            lambda: super(SQLAlchemyLabSessionStore, self).list_sessions()
        )

    def start(self, session_id: str) -> LabSession | None:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).start(session_id)
        )

    def stop(self, session_id: str) -> LabSession | None:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).stop(session_id)
        )

    def list_beds(self) -> tuple[LabBed, ...]:
        return self._read(lambda: super(SQLAlchemyLabSessionStore, self).list_beds())

    def list_recorders(self) -> tuple[LabRecorder, ...]:
        return self._read(
            lambda: super(SQLAlchemyLabSessionStore, self).list_recorders()
        )

    def create_beds(self, request: LabBedCreateInput) -> tuple[LabBed, ...]:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).create_beds(request)
        )

    def delete_beds(self, request: LabBedDeleteInput) -> tuple[LabBed, ...]:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).delete_beds(request)
        )

    def reset_beds(self) -> tuple[LabBed, ...]:
        return self._mutate(lambda: super(SQLAlchemyLabSessionStore, self).reset_beds())

    def create_recorders(
        self, request: LabRecorderCreateInput
    ) -> tuple[LabRecorder, ...]:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).create_recorders(request)
        )

    def delete_recorders(
        self, request: LabRecorderDeleteInput
    ) -> tuple[LabRecorder, ...]:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).delete_recorders(request)
        )

    def reset_recorders(self) -> tuple[LabRecorder, ...]:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).reset_recorders()
        )

    def start_recorder(self, session_id: str, recorder_id: str) -> LabRecorder | None:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).start_recorder(
                session_id, recorder_id
            )
        )

    def stop_recorder(self, session_id: str, recorder_id: str) -> LabRecorder | None:
        return self._mutate(
            lambda: super(SQLAlchemyLabSessionStore, self).stop_recorder(
                session_id, recorder_id
            )
        )

    def save_recorder_execution_results(
        self, results: tuple[LabRecorderExecutionResult, ...]
    ) -> None:
        self._mutate(
            lambda: super(
                SQLAlchemyLabSessionStore, self
            ).save_recorder_execution_results(results)
        )

    def _read(self, operation):
        with self._lock:
            self._load()
            return operation()

    def _mutate(self, operation):
        with self._lock:
            self._load()
            result = operation()
            self._persist()
            return result

    def _load(self) -> None:
        self.ensure_ready()
        try:
            with Session(self._engine) as session:
                sessions = session.scalars(select(LabSessionRecord)).all()
                beds = session.scalars(select(LabBedRecord)).all()
                recorders = session.scalars(select(LabRecorderRecord)).all()
            self.sessions = {
                item.session_id: item for item in map(session_domain, sessions)
            }
            self.beds = {item.bed_id: item for item in map(bed_domain, beds)}
            self.recorders = {
                item.recorder_id: item for item in map(recorder_domain, recorders)
            }
        except SQLAlchemyError as error:
            raise _unavailable("state read", error) from error

    def _persist(self) -> None:
        try:
            with Session(self._engine) as session, session.begin():
                session.execute(delete(LabRecorderRecord))
                session.execute(delete(LabBedRecord))
                session.execute(delete(LabSessionRecord))
                session.add_all(
                    [session_record(item) for item in self.sessions.values()]
                )
                session.add_all([bed_record(item) for item in self.beds.values()])
                session.add_all(
                    [recorder_record(item) for item in self.recorders.values()]
                )
        except SQLAlchemyError as error:
            raise _unavailable("state write", error) from error


def _sqlalchemy_url(value: str) -> str:
    return (
        "postgresql+psycopg://" + value.removeprefix("postgresql://")
        if value.startswith("postgresql://")
        else value
    )


def _unavailable(stage: str, error: object) -> LabSessionStoreUnavailable:
    return LabSessionStoreUnavailable(
        f"Lab database {stage} failed: {error}", kind="labSessionStoreUnavailable"
    )
