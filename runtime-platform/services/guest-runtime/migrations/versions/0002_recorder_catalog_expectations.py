"""Add explicit Recorder observability expectation command state.

Revision ID: 0002_catalog_expectations
Revises: 0001_catalog_foundation
Create Date: 2026-07-24
"""

from __future__ import annotations

from alembic import op

revision = "0002_catalog_expectations"
down_revision = "0001_catalog_foundation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE TABLE recorder_catalog.expectation_events (
          event_id text PRIMARY KEY,
          request_id text NOT NULL UNIQUE,
          command_digest char(64) NOT NULL
            CHECK (command_digest ~ '^[a-f0-9]{64}$'),
          recorder_id text NOT NULL,
          previous_revision bigint NOT NULL CHECK (previous_revision >= 0),
          revision bigint NOT NULL CHECK (revision = previous_revision + 1),
          action text NOT NULL CHECK (action IN ('set', 'clear')),
          expectation_state text CHECK (
            expectation_state IN ('expected', 'not-expected')
          ),
          support_state text CHECK (
            support_state IN ('supported', 'unsupported')
          ),
          source text,
          reason text,
          evidence_document jsonb NOT NULL
            CHECK (jsonb_typeof(evidence_document) = 'object'),
          event_document jsonb NOT NULL
            CHECK (jsonb_typeof(event_document) = 'object'),
          decided_at timestamptz NOT NULL,
          received_at timestamptz NOT NULL,
          persisted_at timestamptz NOT NULL,
          UNIQUE (recorder_id, revision),
          CHECK (
            (
              action = 'set'
              AND expectation_state IS NOT NULL
              AND source IS NOT NULL
              AND length(source) > 0
            )
            OR (
              action = 'clear'
              AND expectation_state IS NULL
              AND support_state IS NULL
              AND source IS NULL
              AND reason IS NULL
              AND evidence_document = '{}'::jsonb
            )
          )
        );

        CREATE TABLE recorder_catalog.recorder_expectations (
          recorder_id text PRIMARY KEY,
          revision bigint NOT NULL CHECK (revision > 0),
          lifecycle_state text NOT NULL CHECK (
            lifecycle_state IN ('active', 'cleared')
          ),
          expectation_state text CHECK (
            expectation_state IN ('expected', 'not-expected')
          ),
          support_state text CHECK (
            support_state IN ('supported', 'unsupported')
          ),
          source text,
          reason text,
          evidence_document jsonb NOT NULL
            CHECK (jsonb_typeof(evidence_document) = 'object'),
          expectation_document jsonb NOT NULL
            CHECK (jsonb_typeof(expectation_document) = 'object'),
          source_event_id text NOT NULL UNIQUE
            REFERENCES recorder_catalog.expectation_events(event_id)
            ON DELETE RESTRICT,
          updated_at timestamptz NOT NULL,
          CHECK (
            (
              lifecycle_state = 'active'
              AND expectation_state IS NOT NULL
              AND source IS NOT NULL
              AND length(source) > 0
            )
            OR (
              lifecycle_state = 'cleared'
              AND expectation_state IS NULL
              AND support_state IS NULL
              AND source IS NULL
              AND reason IS NULL
              AND evidence_document = '{}'::jsonb
            )
          )
        );

        COMMENT ON TABLE recorder_catalog.expectation_events IS
          'Immutable Recorder observability expectation command receipts';
        COMMENT ON TABLE recorder_catalog.recorder_expectations IS
          'Current explicit expectation projection; absence means unset';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive Recorder Catalog downgrade is unsupported; "
        "restore an explicit owner backup"
    )
