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


def test_sqlalchemy_store_persists_session_and_children_as_one_start_transition(
    tmp_path: Path,
) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = SQLAlchemyLabSessionStore(url, id_factory=lambda: "lab_session_1")
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Atomic transition",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    started = store.start(created.session_id)
    reopened = SQLAlchemyLabSessionStore(url)

    assert started is not None
    assert started.state == "running"
    assert reopened.get(created.session_id).state == "running"
    assert {bed.state for bed in reopened.list_beds()} == {"running"}
    assert {recorder.state for recorder in reopened.list_recorders()} == {"running"}


def test_sqlalchemy_store_deletes_session_and_owned_children_atomically(
    tmp_path: Path,
) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = SQLAlchemyLabSessionStore(url, id_factory=lambda: "lab_session_1")
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Delete aggregate",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    remaining = store.delete_session(created.session_id)
    reopened = SQLAlchemyLabSessionStore(url)

    assert remaining == ()
    assert reopened.list_sessions() == ()
    assert reopened.list_beds() == ()
    assert reopened.list_recorders() == ()


def test_sqlalchemy_store_persists_only_archive_finalization_request_reference(
    tmp_path: Path,
) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = SQLAlchemyLabSessionStore(url, id_factory=lambda: "lab_session_1")
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Archive reference",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    stored = store.save_archive_finalization_request_ids(
        created.session_id,
        ("ingress-request-1",),
    )
    reopened = SQLAlchemyLabSessionStore(url)

    assert stored is not None
    assert stored.archive_finalization_request_ids == ("ingress-request-1",)
    assert reopened.get(created.session_id).archive_finalization_request_ids == (
        "ingress-request-1",
    )
    assert "archiveFinalizationRequestIds" not in stored.as_json()


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
