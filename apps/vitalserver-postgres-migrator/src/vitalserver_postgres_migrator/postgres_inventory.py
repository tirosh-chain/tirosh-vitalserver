from __future__ import annotations

from datetime import datetime

from sqlalchemy import Engine, create_engine, text
from sqlalchemy.engine import Connection
from sqlalchemy.exc import SQLAlchemyError

from .cli import sqlalchemy_url
from .inventory_contract import (
    DatabaseInventorySnapshot,
    RelationInventory,
)


class PostgresInventoryReadError(RuntimeError):
    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


def collect_database_inventory(database_url: str) -> DatabaseInventorySnapshot:
    engine = create_engine(sqlalchemy_url(database_url), pool_pre_ping=True)
    try:
        return _collect(engine)
    except (SQLAlchemyError, TypeError, ValueError) as error:
        raise PostgresInventoryReadError(str(error)) from error
    finally:
        engine.dispose()


def _collect(engine: Engine) -> DatabaseInventorySnapshot:
    with engine.connect() as connection, connection.begin():
        connection.execute(text("SET TRANSACTION READ ONLY"))
        metadata = (
            connection.execute(
                text(
                    """
                SELECT CURRENT_TIMESTAMP AS captured_at,
                       current_database() AS database_name,
                       current_user AS database_user,
                       current_setting('server_version') AS server_version,
                       pg_database_size(current_database()) AS database_bytes,
                       current_setting('data_directory') AS data_directory,
                       current_setting('transaction_read_only') AS read_only
                """
                )
            )
            .mappings()
            .one()
        )
        installed_schemas = tuple(
            row.schema_name
            for row in connection.execute(
                text(
                    """
                    SELECT nspname AS schema_name
                      FROM pg_namespace
                     WHERE nspname <> 'information_schema'
                       AND nspname !~ '^pg_'
                     ORDER BY nspname
                    """
                )
            )
        )
        relations = tuple(
            RelationInventory(
                schema_name=row.schema_name,
                relation_name=row.relation_name,
                estimated_row_count=(
                    int(row.estimated_row_count)
                    if row.estimated_row_count is not None
                    else None
                ),
                table_bytes=int(row.table_bytes),
                index_bytes=int(row.index_bytes),
                total_bytes=int(row.total_bytes),
            )
            for row in connection.execute(
                text(
                    """
                    SELECT namespace.nspname AS schema_name,
                           relation.relname AS relation_name,
                           CASE
                             WHEN relation.reltuples >= 0
                             THEN relation.reltuples::bigint
                             ELSE NULL
                           END AS estimated_row_count,
                           pg_relation_size(relation.oid) AS table_bytes,
                           pg_indexes_size(relation.oid) AS index_bytes,
                           pg_total_relation_size(relation.oid) AS total_bytes
                      FROM pg_class AS relation
                      JOIN pg_namespace AS namespace
                        ON namespace.oid = relation.relnamespace
                     WHERE namespace.nspname <> 'information_schema'
                       AND namespace.nspname !~ '^pg_'
                       AND relation.relkind IN ('r', 'p')
                     ORDER BY namespace.nspname, relation.relname
                    """
                )
            )
        )
        revisions = _read_revisions(connection)
    captured_at = metadata.captured_at
    if not isinstance(captured_at, datetime):
        raise PostgresInventoryReadError(
            "database returned an invalid captured_at value"
        )
    return DatabaseInventorySnapshot(
        captured_at=captured_at.isoformat(),
        database_name=str(metadata.database_name),
        database_user=str(metadata.database_user),
        server_version=str(metadata.server_version),
        database_bytes=int(metadata.database_bytes),
        data_directory=str(metadata.data_directory),
        transaction_read_only=_read_only_value(metadata.read_only),
        installed_schemas=installed_schemas,
        revisions=revisions,
        relations=relations,
    )


def _read_revisions(connection: Connection) -> tuple[str, ...]:
    relation = connection.execute(
        text("SELECT to_regclass('public.alembic_version') AS relation")
    ).scalar_one()
    if relation is None:
        return ()
    return tuple(
        row.version_num
        for row in connection.execute(
            text(
                """
                SELECT version_num
                  FROM public.alembic_version
                 ORDER BY version_num
                """
            )
        )
    )


def _read_only_value(value: object) -> bool:
    if value == "on":
        return True
    if value == "off":
        return False
    raise PostgresInventoryReadError(
        "database returned an invalid transaction_read_only value"
    )
