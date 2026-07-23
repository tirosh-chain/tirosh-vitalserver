"""Add the Recorder observability expectation command journal.

Revision ID: 0003_expectation_workflow
Revises: 0002_observability_expectations
Create Date: 2026-07-24
"""

from __future__ import annotations

from alembic import op

revision = "0003_expectation_workflow"
down_revision = "0002_observability_expectations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE TABLE recorder_observability.expectation_events (
          event_id uuid PRIMARY KEY,
          command_id uuid NOT NULL UNIQUE,
          vrcode text NOT NULL
            CHECK (vrcode ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
          previous_revision integer NOT NULL CHECK (previous_revision >= 0),
          revision integer NOT NULL CHECK (revision = previous_revision + 1),
          action text NOT NULL CHECK (action IN ('set', 'clear')),
          support_state text
            CHECK (support_state IN ('supported', 'unsupported')),
          source text
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
          evidence_document jsonb NOT NULL
            CHECK (jsonb_typeof(evidence_document) = 'object'),
          decided_at timestamptz NOT NULL,
          received_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
          UNIQUE (vrcode, revision),
          CHECK (
            (
              action = 'set'
              AND support_state IS NOT NULL
              AND source IS NOT NULL
              AND (
                support_state = 'unsupported'
                OR expected_since IS NOT NULL
              )
            )
            OR (
              action = 'clear'
              AND support_state IS NULL
              AND source IS NULL
              AND recorder_version IS NULL
              AND producer_version IS NULL
              AND protocol_version IS NULL
              AND catalog_revision IS NULL
              AND expected_since IS NULL
              AND evidence_document = '{}'::jsonb
            )
          )
        );

        ALTER TABLE recorder_observability.expectations
          ADD COLUMN revision integer,
          ADD COLUMN lifecycle_state text,
          ADD COLUMN source_event_id uuid;

        ALTER TABLE recorder_observability.expectations
          ALTER COLUMN support_state DROP NOT NULL,
          ALTER COLUMN source DROP NOT NULL;

        INSERT INTO recorder_observability.expectation_events (
          event_id,
          command_id,
          vrcode,
          previous_revision,
          revision,
          action,
          support_state,
          source,
          recorder_version,
          producer_version,
          protocol_version,
          catalog_revision,
          expected_since,
          evidence_document,
          decided_at,
          received_at
        )
        SELECT
          md5('expectation-event:' || vrcode)::uuid,
          md5('expectation-command:' || vrcode)::uuid,
          vrcode,
          0,
          1,
          'set',
          support_state,
          source,
          recorder_version,
          producer_version,
          protocol_version,
          catalog_revision,
          expected_since,
          evidence_document,
          updated_at,
          updated_at
        FROM recorder_observability.expectations;

        UPDATE recorder_observability.expectations
           SET revision = 1,
               lifecycle_state = 'active',
               source_event_id =
                 md5('expectation-event:' || vrcode)::uuid;

        ALTER TABLE recorder_observability.expectations
          ALTER COLUMN revision SET NOT NULL,
          ALTER COLUMN lifecycle_state SET NOT NULL,
          ALTER COLUMN source_event_id SET NOT NULL,
          ADD CONSTRAINT expectations_revision_positive
            CHECK (revision > 0),
          ADD CONSTRAINT expectations_lifecycle_state_valid
            CHECK (lifecycle_state IN ('active', 'cleared')),
          ADD CONSTRAINT expectations_source_event_unique
            UNIQUE (source_event_id),
          ADD CONSTRAINT expectations_source_event_fk
            FOREIGN KEY (source_event_id)
            REFERENCES recorder_observability.expectation_events(event_id),
          ADD CONSTRAINT expectations_lifecycle_fields_valid
            CHECK (
              (
                lifecycle_state = 'active'
                AND support_state IS NOT NULL
                AND source IS NOT NULL
                AND (
                  support_state = 'unsupported'
                  OR expected_since IS NOT NULL
                )
              )
              OR (
                lifecycle_state = 'cleared'
                AND support_state IS NULL
                AND source IS NULL
                AND recorder_version IS NULL
                AND producer_version IS NULL
                AND protocol_version IS NULL
                AND catalog_revision IS NULL
                AND expected_since IS NULL
                AND evidence_document = '{}'::jsonb
              )
            );

        COMMENT ON TABLE recorder_observability.expectation_events IS
          'Immutable command receipts for Recorder observability support expectations';
        COMMENT ON COLUMN recorder_observability.expectations.lifecycle_state IS
          'Current active or explicitly cleared expectation projection';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive PostgreSQL schema downgrade is not supported; "
        "restore an explicit database backup instead"
    )
