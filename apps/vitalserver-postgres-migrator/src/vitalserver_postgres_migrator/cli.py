from __future__ import annotations

import os
import sys
from collections.abc import Mapping
from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from sqlalchemy import create_engine
from sqlalchemy.exc import SQLAlchemyError

DATABASE_URL_ENV = "VITALSERVER_DATABASE_URL"
CONFIG_ENV = "VITALSERVER_POSTGRES_MIGRATION_CONFIG"
DEFAULT_CONFIG = Path(__file__).resolve().parents[2] / "alembic.ini"


def main() -> None:
    database_url = required_database_url(os.environ)
    config_path = Path(os.environ.get(CONFIG_ENV, DEFAULT_CONFIG))
    config = Config(str(config_path))
    config.set_main_option("sqlalchemy.url", sqlalchemy_url(database_url))
    target_revision = command_target(config)
    current_revision = read_current_revision(database_url)
    print(
        "postgres schema migration starting "
        f"stage=postgres-schema-migration "
        f"currentRevision={current_revision or '<none>'} "
        f"targetRevision={target_revision}",
        flush=True,
    )
    try:
        command.upgrade(config, "head")
    except Exception as error:
        print(
            "postgres schema migration failed "
            f"stage=postgres-schema-migration "
            f"currentRevision={current_revision or '<none>'} "
            f"targetRevision={target_revision} "
            f"reason={error}",
            file=sys.stderr,
            flush=True,
        )
        raise SystemExit(1) from error
    applied_revision = read_current_revision(database_url)
    if applied_revision != target_revision:
        print(
            "postgres schema migration failed "
            f"stage=postgres-schema-verification "
            f"currentRevision={applied_revision or '<none>'} "
            f"targetRevision={target_revision} "
            "reason=database did not reach the migration head",
            file=sys.stderr,
            flush=True,
        )
        raise SystemExit(1)
    print(
        "postgres schema migration completed "
        f"stage=postgres-schema-migration revision={applied_revision}",
        flush=True,
    )


def required_database_url(environment: Mapping[str, str]) -> str:
    value = environment.get(DATABASE_URL_ENV)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(
            "postgres schema migration failed "
            "stage=postgres-schema-configuration "
            f"reason=missing {DATABASE_URL_ENV}"
        )
    return value.strip()


def sqlalchemy_url(value: str) -> str:
    if value.startswith("postgresql://"):
        return "postgresql+psycopg://" + value.removeprefix("postgresql://")
    return value


def command_target(config: Config) -> str:
    script = config.get_main_option("script_location")
    if not script:
        raise SystemExit(
            "postgres schema migration failed "
            "stage=postgres-schema-configuration "
            "reason=Alembic script location is missing"
        )
    from alembic.script import ScriptDirectory

    heads = ScriptDirectory.from_config(config).get_heads()
    if len(heads) != 1:
        raise SystemExit(
            "postgres schema migration failed "
            "stage=postgres-schema-configuration "
            f"reason=expected one Alembic head actual={heads}"
        )
    return heads[0]


def read_current_revision(database_url: str) -> str | None:
    engine = create_engine(sqlalchemy_url(database_url), pool_pre_ping=True)
    try:
        with engine.connect() as connection:
            return MigrationContext.configure(connection).get_current_revision()
    except SQLAlchemyError as error:
        raise SystemExit(
            "postgres schema migration failed "
            "stage=postgres-schema-read "
            f"reason={error}"
        ) from error
    finally:
        engine.dispose()
