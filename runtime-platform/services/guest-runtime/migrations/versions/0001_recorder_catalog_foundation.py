"""Create the vNext Recorder Observation Catalog foundation.

Revision ID: 0001_catalog_foundation
Revises:
Create Date: 2026-07-24
"""

from __future__ import annotations

from alembic import op

revision = "0001_catalog_foundation"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE SCHEMA recorder_catalog;

        CREATE TABLE recorder_catalog.admission_requests (
          request_id text PRIMARY KEY,
          command_digest char(64) NOT NULL
            CHECK (command_digest ~ '^[a-f0-9]{64}$'),
          source_key text,
          envelope_digest char(64)
            CHECK (envelope_digest ~ '^[a-f0-9]{64}$'),
          source_identity text NOT NULL,
          media_type text NOT NULL,
          received_bytes bigint NOT NULL CHECK (received_bytes >= 0),
          outcome text NOT NULL CHECK (
            outcome IN ('accepted', 'duplicate', 'quarantined')
          ),
          issue jsonb CHECK (
            issue IS NULL OR jsonb_typeof(issue) = 'object'
          ),
          admission_document jsonb NOT NULL
            CHECK (jsonb_typeof(admission_document) = 'object'),
          source_document jsonb NOT NULL
            CHECK (jsonb_typeof(source_document) = 'object'),
          received_at timestamptz NOT NULL,
          persisted_at timestamptz NOT NULL,
          CHECK (
            (
              outcome IN ('accepted', 'duplicate')
              AND issue IS NULL
              AND source_key IS NOT NULL
              AND envelope_digest IS NOT NULL
            )
            OR (
              outcome = 'quarantined'
              AND issue IS NOT NULL
              AND source_key IS NULL
              AND envelope_digest IS NULL
            )
          )
        );

        CREATE INDEX admission_requests_source_key_idx
        ON recorder_catalog.admission_requests
          (source_key, persisted_at DESC, request_id DESC);

        CREATE TABLE recorder_catalog.observations (
          observation_id text PRIMARY KEY,
          request_id text NOT NULL UNIQUE
            REFERENCES recorder_catalog.admission_requests(request_id)
            ON DELETE RESTRICT,
          recorder_id text NOT NULL,
          boot_id text NOT NULL,
          sequence bigint NOT NULL CHECK (sequence >= 0),
          protocol_version text NOT NULL,
          occurred_at timestamptz NOT NULL,
          received_at timestamptz NOT NULL,
          persisted_at timestamptz NOT NULL,
          envelope_sha256 char(64) NOT NULL
            CHECK (envelope_sha256 ~ '^[a-f0-9]{64}$'),
          document jsonb NOT NULL
            CHECK (jsonb_typeof(document) = 'object'),
          UNIQUE (recorder_id, boot_id, sequence)
        );

        CREATE INDEX observations_recorder_occurred_idx
        ON recorder_catalog.observations
          (recorder_id, occurred_at DESC, observation_id DESC);

        CREATE INDEX observations_recorder_received_idx
        ON recorder_catalog.observations
          (recorder_id, received_at DESC, observation_id DESC);

        CREATE INDEX observations_recorder_persisted_idx
        ON recorder_catalog.observations
          (recorder_id, persisted_at DESC, observation_id DESC);

        CREATE TABLE recorder_catalog.recorder_current (
          recorder_id text PRIMARY KEY,
          resource_revision bigint NOT NULL CHECK (resource_revision > 0),
          support_state text NOT NULL CHECK (
            support_state IN ('supported', 'unsupported', 'unknown')
          ),
          expectation_state text NOT NULL CHECK (
            expectation_state IN ('expected', 'not-expected', 'unset')
          ),
          report_state text NOT NULL CHECK (
            report_state IN ('never-reported', 'current', 'stale')
          ),
          latest_observation_id text
            REFERENCES recorder_catalog.observations(observation_id)
            ON DELETE RESTRICT,
          latest_boot_id text,
          latest_sequence bigint CHECK (
            latest_sequence IS NULL OR latest_sequence >= 0
          ),
          latest_occurred_at timestamptz,
          latest_received_at timestamptz,
          latest_persisted_at timestamptz,
          document jsonb NOT NULL
            CHECK (jsonb_typeof(document) = 'object'),
          updated_at timestamptz NOT NULL,
          CHECK (
            (
              report_state = 'never-reported'
              AND latest_observation_id IS NULL
              AND latest_boot_id IS NULL
              AND latest_sequence IS NULL
              AND latest_occurred_at IS NULL
              AND latest_received_at IS NULL
              AND latest_persisted_at IS NULL
            )
            OR (
              report_state IN ('current', 'stale')
              AND latest_observation_id IS NOT NULL
              AND latest_boot_id IS NOT NULL
              AND latest_sequence IS NOT NULL
              AND latest_occurred_at IS NOT NULL
              AND latest_received_at IS NOT NULL
              AND latest_persisted_at IS NOT NULL
            )
          )
        );

        COMMENT ON SCHEMA recorder_catalog IS
          'Guest Runtime Recorder Observation Catalog owner';
        COMMENT ON TABLE recorder_catalog.observations IS
          'Immutable accepted Recorder-owned self-observations';
        COMMENT ON TABLE recorder_catalog.recorder_current IS
          'Catalog-owned current projection; absence never proves unsupported';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive Recorder Catalog downgrade is unsupported; "
        "restore an explicit owner backup"
    )
