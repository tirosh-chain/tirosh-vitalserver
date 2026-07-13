from __future__ import annotations

import re
import sqlite3
from pathlib import Path

from vitalserver_lab.model import LabSessionCreateInput
from vitalserver_lab.persistence import SQLAlchemyLabSessionStore


def test_sqlalchemy_store_uses_same_domain_contract_with_sqlite(tmp_path: Path) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = SQLAlchemyLabSessionStore(url, id_factory=lambda: "lab_session_1")
    store.ensure_ready()
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Portable persistence",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    reopened = SQLAlchemyLabSessionStore(url)
    loaded = reopened.get(created.session_id)
    beds = reopened.list_beds()
    recorders = reopened.list_recorders()

    assert loaded == created
    assert re.fullmatch(r"bed_[A-Z0-9]{6}", beds[0].bed_id)
    assert re.fullmatch(r"rec_[A-Z0-9]{6}", recorders[0].recorder_id)
    assert re.fullmatch(r"LAB-[A-Z0-9]{6}", recorders[0].vrcode)


def test_sqlalchemy_store_writes_existing_timestamp_columns(tmp_path: Path) -> None:
    database_path = tmp_path / "legacy-schema.sqlite"
    with sqlite3.connect(database_path) as connection:
        connection.executescript(
            """
            CREATE TABLE lab_sessions (
                session_id TEXT PRIMARY KEY,
                document JSON NOT NULL,
                created_at TIMESTAMP NOT NULL,
                updated_at TIMESTAMP NOT NULL
            );
            CREATE TABLE lab_beds (
                bed_id TEXT PRIMARY KEY,
                document JSON NOT NULL,
                updated_at TIMESTAMP NOT NULL
            );
            CREATE TABLE lab_recorders (
                recorder_id TEXT PRIMARY KEY,
                document JSON NOT NULL,
                updated_at TIMESTAMP NOT NULL
            );
            """
        )
    store = SQLAlchemyLabSessionStore(
        f"sqlite:///{database_path}",
        id_factory=lambda: "lab_session_1",
    )

    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Existing schema",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    with sqlite3.connect(database_path) as connection:
        stored_timestamps = connection.execute(
            "SELECT created_at, updated_at FROM lab_sessions WHERE session_id = ?",
            (created.session_id,),
        ).fetchone()
    assert stored_timestamps is not None
    assert all(stored_timestamps)
