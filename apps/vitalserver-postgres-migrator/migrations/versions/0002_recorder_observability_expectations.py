"""Add explicit Recorder observability support expectations.

Revision ID: 0002_recorder_observability_expectations
Revises: 0001_initial_schema
Create Date: 2026-07-23
"""

from __future__ import annotations

from alembic import op

revision = "0002_recorder_observability_expectations"
down_revision = "0001_initial_schema"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE TABLE recorder_observability.expectations (
          vrcode text PRIMARY KEY
            CHECK (vrcode ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
          support_state text NOT NULL
            CHECK (support_state IN ('supported', 'unsupported')),
          source text NOT NULL
            CHECK (
              source IN (
                'deployment_assignment',
                'version_catalog',
                'manual'
              )
            ),
          recorder_version text,
          producer_version text,
          protocol_version text,
          catalog_revision text,
          expected_since timestamptz,
          evidence_document jsonb NOT NULL DEFAULT '{}'::jsonb
            CHECK (jsonb_typeof(evidence_document) = 'object'),
          updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
          CHECK (
            support_state = 'unsupported'
            OR expected_since IS NOT NULL
          )
        );

        COMMENT ON TABLE recorder_observability.expectations IS
          'Explicit deployment or compatibility evidence; absence is unknown, not unsupported';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive PostgreSQL schema downgrade is not supported; "
        "restore an explicit database backup instead"
    )
