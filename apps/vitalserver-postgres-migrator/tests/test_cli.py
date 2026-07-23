from __future__ import annotations

from pathlib import Path

import pytest
from vitalserver_postgres_migrator.cli import required_database_url, sqlalchemy_url

MIGRATION = (
    Path(__file__).resolve().parents[1] / "migrations/versions/0001_initial_schema.py"
)


def test_requires_explicit_database_url() -> None:
    with pytest.raises(SystemExit) as error:
        required_database_url({})
    assert "missing VITALSERVER_DATABASE_URL" in str(error.value)


def test_uses_psycopg_sqlalchemy_driver() -> None:
    assert sqlalchemy_url("postgresql://user:secret@postgres/db") == (
        "postgresql+psycopg://user:secret@postgres/db"
    )


def test_initial_revision_is_clean_and_namespaced() -> None:
    source = MIGRATION.read_text(encoding="utf-8")
    assert "CREATE TABLE IF NOT EXISTS" not in source
    assert "CREATE SCHEMA vitaldb_read_model" in source
    assert "CREATE SCHEMA product_lab" in source
    assert "CREATE SCHEMA recorder_observability" in source
    assert "vitaldb_read_model.observation_snapshots" in source
    assert "product_lab.sessions" in source
    assert "recorder_observability.records" in source
    assert "unmanaged_database_not_empty" in source
    assert "'S', 'f'" in source
