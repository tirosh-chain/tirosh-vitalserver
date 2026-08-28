from __future__ import annotations

from datetime import UTC, datetime

import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import Connection, inspect, text

from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError

CONTROL_SCHEMA_REVISIONS = (
    ("0001", "f5b6a98ac7a8d61d"),
    ("0002", "90d219e32282638f"),
    ("0003", "bbeb68e94438d0b5"),
    ("0004", "34993a7530a52d2f"),
)
CONTROL_SCHEMA_COLUMNS: dict[str, frozenset[str]] = {
    "control_schema_migrations": frozenset({"version", "checksum", "applied_at"}),
    "service_operations": frozenset(
        {
            "operation_id",
            "service",
            "command",
            "state",
            "document",
            "created_at",
            "updated_at",
        }
    ),
    "service_operation_events": frozenset(
        {"event_id", "operation_id", "state", "document", "observed_at"}
    ),
    "active_operation_leases": frozenset(
        {"resource_key", "operation_id", "acquired_at"}
    ),
    "service_status_snapshots": frozenset({"service", "document", "observed_at"}),
    "guest_service_resources": frozenset({"service", "document", "updated_at"}),
    "redis_relay_status_snapshots": frozenset(
        {"snapshot_id", "document", "observed_at"}
    ),
    "container_image_sets": frozenset({"identity", "digest", "created_at"}),
    "current_container_image_set": frozenset({"owner_key", "identity", "updated_at"}),
    "container_image_set_operations": frozenset(
        {
            "operation_id",
            "command",
            "expected_current_identity",
            "target_identity",
            "state",
            "document",
            "created_at",
            "updated_at",
        }
    ),
    "guest_runtime_releases": frozenset(
        {"identity", "archive", "digest", "created_at"}
    ),
    "active_guest_runtime_release": frozenset(
        {"owner_key", "identity", "updated_at"}
    ),
    "guest_runtime_release_operations": frozenset(
        {
            "operation_id",
            "command",
            "expected_active_identity",
            "target_identity",
            "state",
            "document",
            "created_at",
            "updated_at",
        }
    ),
    "initial_update_owner_provisioning": frozenset(
        {
            "owner_key",
            "contract_digest",
            "container_identity",
            "container_digest",
            "container_archive",
            "guest_runtime_identity",
            "guest_runtime_digest",
            "guest_runtime_archive",
            "completed_at",
        }
    ),
}


def migrate_control_schema(connection: Connection) -> None:
    """Apply reviewed control-store revisions while the caller owns the lock."""

    try:
        tables = set(inspect(connection).get_table_names())
        if "control_schema_migrations" not in tables:
            partial_control_tables = tables & set(CONTROL_SCHEMA_COLUMNS)
            if partial_control_tables:
                raise GuestControlDependencyError(
                    "control SQLite schema is partial without migration history: "
                    f"tables={sorted(partial_control_tables)!r}",
                    kind="controlStoreSchemaMismatch",
                )
            _upgrade_0001(connection)
        applied = _applied_revisions(connection)
        if applied == list(CONTROL_SCHEMA_REVISIONS[:1]):
            _upgrade_0002(connection)
            applied = _applied_revisions(connection)
        if applied == list(CONTROL_SCHEMA_REVISIONS[:2]):
            _upgrade_0003(connection)
            applied = _applied_revisions(connection)
        if applied == list(CONTROL_SCHEMA_REVISIONS[:3]):
            _upgrade_0004(connection)
        validate_control_schema(connection)
    except GuestControlDependencyError:
        raise
    except sa.exc.SQLAlchemyError as error:
        raise GuestControlDependencyError(
            f"control SQLite schema migration failed: {error}",
            kind="controlStoreSchemaMigrationFailed",
        ) from error


def validate_control_schema(connection: Connection) -> None:
    """Check the complete persisted schema without changing it."""

    try:
        inspector = inspect(connection)
        tables = set(inspector.get_table_names())
        missing_tables = set(CONTROL_SCHEMA_COLUMNS) - tables
        if missing_tables:
            kind = (
                "controlStoreSchemaMissing"
                if "control_schema_migrations" in missing_tables
                else "controlStoreSchemaMismatch"
            )
            raise GuestControlDependencyError(
                "control SQLite schema tables are missing: "
                f"tables={sorted(missing_tables)!r}",
                kind=kind,
            )

        missing_columns = {
            table: sorted(
                required_columns
                - {column["name"] for column in inspector.get_columns(table)}
            )
            for table, required_columns in CONTROL_SCHEMA_COLUMNS.items()
        }
        missing_columns = {
            table: columns for table, columns in missing_columns.items() if columns
        }
        if missing_columns:
            raise GuestControlDependencyError(
                "control SQLite schema columns are missing: "
                f"columns={missing_columns!r}",
                kind="controlStoreSchemaMismatch",
            )

        actual = _applied_revisions(connection)
        if actual != list(CONTROL_SCHEMA_REVISIONS):
            raise GuestControlDependencyError(
                f"control SQLite schema version is unsupported: {actual!r}",
                kind="controlStoreSchemaMismatch",
            )
    except GuestControlDependencyError:
        raise
    except sa.exc.SQLAlchemyError as error:
        raise GuestControlDependencyError(
            f"control SQLite schema validation failed: {error}",
            kind="controlStoreSchemaMismatch",
        ) from error


def _upgrade_0001(connection: Connection) -> None:
    context = MigrationContext.configure(connection)
    operations = Operations(context)
    operations.create_table(
        "control_schema_migrations",
        sa.Column("version", sa.String(), primary_key=True),
        sa.Column("checksum", sa.String(), nullable=False),
        sa.Column("applied_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_table(
        "service_operations",
        sa.Column("operation_id", sa.String(), primary_key=True),
        sa.Column("service", sa.String(), nullable=False),
        sa.Column("command", sa.String(), nullable=False),
        sa.Column("state", sa.String(), nullable=False),
        sa.Column("document", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_index(
        "service_operations_updated_at_idx",
        "service_operations",
        ["updated_at"],
    )
    operations.create_table(
        "service_operation_events",
        sa.Column("event_id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "operation_id",
            sa.String(),
            sa.ForeignKey("service_operations.operation_id"),
            nullable=False,
        ),
        sa.Column("state", sa.String(), nullable=False),
        sa.Column("document", sa.Text(), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sqlite_autoincrement=True,
    )
    operations.create_index(
        "service_operation_events_operation_id_idx",
        "service_operation_events",
        ["operation_id"],
    )
    operations.create_index(
        "service_operation_events_observed_at_idx",
        "service_operation_events",
        ["observed_at"],
    )
    operations.create_table(
        "active_operation_leases",
        sa.Column("resource_key", sa.String(), primary_key=True),
        sa.Column(
            "operation_id",
            sa.String(),
            sa.ForeignKey("service_operations.operation_id"),
            nullable=False,
            unique=True,
        ),
        sa.Column("acquired_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_table(
        "service_status_snapshots",
        sa.Column("service", sa.String(), primary_key=True),
        sa.Column("document", sa.Text(), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_index(
        "service_status_snapshots_observed_at_idx",
        "service_status_snapshots",
        ["observed_at"],
    )
    operations.create_table(
        "guest_service_resources",
        sa.Column("service", sa.String(), primary_key=True),
        sa.Column("document", sa.Text(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_index(
        "guest_service_resources_updated_at_idx",
        "guest_service_resources",
        ["updated_at"],
    )
    operations.create_table(
        "redis_relay_status_snapshots",
        sa.Column("snapshot_id", sa.String(), primary_key=True),
        sa.Column("document", sa.Text(), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_index(
        "redis_relay_status_snapshots_observed_at_idx",
        "redis_relay_status_snapshots",
        ["observed_at"],
    )
    connection.execute(
        text(
            "INSERT INTO control_schema_migrations "
            "(version, checksum, applied_at) VALUES "
            "(:version, :checksum, :applied_at)"
        ),
        {
            "version": CONTROL_SCHEMA_REVISIONS[0][0],
            "checksum": CONTROL_SCHEMA_REVISIONS[0][1],
            # `text()` does not carry SQLAlchemy's DateTime bind processor.
            # Persist an explicit ISO-8601 string instead of relying on the
            # deprecated sqlite3 implicit datetime adapter.
            "applied_at": datetime.now(UTC).isoformat(),
        },
    )


def _upgrade_0002(connection: Connection) -> None:
    context = MigrationContext.configure(connection)
    operations = Operations(context)
    operations.create_table(
        "container_image_sets",
        sa.Column("identity", sa.String(), primary_key=True),
        sa.Column("digest", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_table(
        "current_container_image_set",
        sa.Column("owner_key", sa.String(), primary_key=True),
        sa.Column(
            "identity",
            sa.String(),
            sa.ForeignKey("container_image_sets.identity"),
            nullable=False,
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_table(
        "container_image_set_operations",
        sa.Column("operation_id", sa.String(), primary_key=True),
        sa.Column("command", sa.String(), nullable=False),
        sa.Column("expected_current_identity", sa.String(), nullable=False),
        sa.Column(
            "target_identity",
            sa.String(),
            sa.ForeignKey("container_image_sets.identity"),
            nullable=False,
        ),
        sa.Column("state", sa.String(), nullable=False),
        sa.Column("document", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_index(
        "container_image_set_operations_updated_at_idx",
        "container_image_set_operations",
        ["updated_at"],
    )
    connection.execute(
        text(
            "INSERT INTO control_schema_migrations "
            "(version, checksum, applied_at) VALUES "
            "(:version, :checksum, :applied_at)"
        ),
        {
            "version": CONTROL_SCHEMA_REVISIONS[1][0],
            "checksum": CONTROL_SCHEMA_REVISIONS[1][1],
            "applied_at": datetime.now(UTC).isoformat(),
        },
    )


def _applied_revisions(connection: Connection) -> list[tuple[str, str]]:
    applied = connection.execute(
        text(
            "SELECT version, checksum FROM control_schema_migrations "
            "ORDER BY version ASC"
        )
    ).all()
    return [tuple(row) for row in applied]


def _upgrade_0003(connection: Connection) -> None:
    context = MigrationContext.configure(connection)
    operations = Operations(context)
    operations.create_table(
        "guest_runtime_releases",
        sa.Column("identity", sa.String(), primary_key=True),
        sa.Column("archive", sa.String(), nullable=False, unique=True),
        sa.Column("digest", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_table(
        "active_guest_runtime_release",
        sa.Column("owner_key", sa.String(), primary_key=True),
        sa.Column(
            "identity",
            sa.String(),
            sa.ForeignKey("guest_runtime_releases.identity"),
            nullable=False,
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_table(
        "guest_runtime_release_operations",
        sa.Column("operation_id", sa.String(), primary_key=True),
        sa.Column("command", sa.String(), nullable=False),
        sa.Column("expected_active_identity", sa.String(), nullable=False),
        sa.Column(
            "target_identity",
            sa.String(),
            sa.ForeignKey("guest_runtime_releases.identity"),
            nullable=False,
        ),
        sa.Column("state", sa.String(), nullable=False),
        sa.Column("document", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    operations.create_index(
        "guest_runtime_release_operations_updated_at_idx",
        "guest_runtime_release_operations",
        ["updated_at"],
    )
    connection.execute(
        text(
            "INSERT INTO control_schema_migrations "
            "(version, checksum, applied_at) VALUES "
            "(:version, :checksum, :applied_at)"
        ),
        {
            "version": CONTROL_SCHEMA_REVISIONS[2][0],
            "checksum": CONTROL_SCHEMA_REVISIONS[2][1],
            "applied_at": datetime.now(UTC).isoformat(),
        },
    )


def _upgrade_0004(connection: Connection) -> None:
    context = MigrationContext.configure(connection)
    operations = Operations(context)
    operations.create_table(
        "initial_update_owner_provisioning",
        sa.Column("owner_key", sa.String(), primary_key=True),
        sa.Column("contract_digest", sa.String(), nullable=False),
        sa.Column("container_identity", sa.String(), nullable=False),
        sa.Column("container_digest", sa.String(), nullable=False),
        sa.Column("container_archive", sa.String(), nullable=False),
        sa.Column("guest_runtime_identity", sa.String(), nullable=False),
        sa.Column("guest_runtime_digest", sa.String(), nullable=False),
        sa.Column("guest_runtime_archive", sa.String(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=False),
    )
    connection.execute(
        text(
            "INSERT INTO control_schema_migrations "
            "(version, checksum, applied_at) VALUES "
            "(:version, :checksum, :applied_at)"
        ),
        {
            "version": CONTROL_SCHEMA_REVISIONS[3][0],
            "checksum": CONTROL_SCHEMA_REVISIONS[3][1],
            "applied_at": datetime.now(UTC).isoformat(),
        },
    )
