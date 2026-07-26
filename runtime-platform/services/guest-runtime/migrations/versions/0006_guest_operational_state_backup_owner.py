"""Add Guest operational-state PostgreSQL backup identity.

Revision ID: 0006_backup_owner
Revises: 0005_recorder_assignment_owner
Create Date: 2026-07-24
"""

from __future__ import annotations

from alembic import op

revision = "0006_backup_owner"
down_revision = "0005_recorder_assignment_owner"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE SCHEMA guest_operational_state;

        CREATE TABLE guest_operational_state.metadata (
          singleton boolean PRIMARY KEY DEFAULT true
            CHECK (singleton),
          database_id text NOT NULL UNIQUE
            CHECK (
              database_id ~
              '^guest-postgresql-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            ),
          backup_contract_version text NOT NULL
            CHECK (backup_contract_version = 'v1'),
          created_at timestamptz NOT NULL
        );

        INSERT INTO guest_operational_state.metadata (
          singleton,
          database_id,
          backup_contract_version,
          created_at
        ) VALUES (
          true,
          'guest-postgresql-' || gen_random_uuid()::text,
          'v1',
          CURRENT_TIMESTAMP
        );

        COMMENT ON SCHEMA guest_operational_state IS
          'Guest-owned PostgreSQL identity and backup contract state';
        COMMENT ON TABLE guest_operational_state.metadata IS
          'Singleton identity preserved by C76 backup and restore';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive Guest operational-state backup-owner downgrade is "
        "unsupported; restore an explicit owner backup"
    )
