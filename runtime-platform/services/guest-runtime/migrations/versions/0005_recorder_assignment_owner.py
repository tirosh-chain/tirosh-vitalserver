"""Add Recorder assignment evidence and resolution owner.

Revision ID: 0005_recorder_assignment_owner
Revises: 0004_archive_source_admissions
Create Date: 2026-07-24
"""

from __future__ import annotations

from alembic import op

revision = "0005_recorder_assignment_owner"
down_revision = "0004_archive_source_admissions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE SCHEMA recorder_assignment;

        CREATE TABLE recorder_assignment.evidence (
          evidence_id text PRIMARY KEY,
          request_id text NOT NULL UNIQUE,
          command_digest char(64) NOT NULL
            CHECK (command_digest ~ '^[a-f0-9]{64}$'),
          recorder_id text NOT NULL,
          bed_name text NOT NULL,
          effective_from timestamptz NOT NULL,
          effective_until timestamptz,
          observed_at timestamptz NOT NULL,
          persisted_at timestamptz NOT NULL,
          source_kind text NOT NULL CHECK (source_kind = 'administrator'),
          source_reference jsonb NOT NULL
            CHECK (jsonb_typeof(source_reference) = 'object'),
          evidence_document jsonb NOT NULL
            CHECK (jsonb_typeof(evidence_document) = 'object'),
          CHECK (
            effective_until IS NULL
            OR effective_until > effective_from
          )
        );

        CREATE INDEX recorder_assignment_effective_bed_idx
        ON recorder_assignment.evidence (
          bed_name,
          effective_from,
          effective_until,
          recorder_id,
          evidence_id
        );

        CREATE TABLE recorder_assignment.resolutions (
          resolution_id text PRIMARY KEY,
          bed_name text NOT NULL,
          effective_at timestamptz NOT NULL,
          evidence_references jsonb NOT NULL
            CHECK (jsonb_typeof(evidence_references) = 'array'),
          candidate_recorder_ids jsonb NOT NULL
            CHECK (jsonb_typeof(candidate_recorder_ids) = 'array'),
          policy_version text NOT NULL
            CHECK (policy_version = 'time-bounded-assignment-v1'),
          resolved_at timestamptz NOT NULL,
          resolution_document jsonb NOT NULL
            CHECK (jsonb_typeof(resolution_document) = 'object')
        );

        COMMENT ON SCHEMA recorder_assignment IS
          'Guest-owned immutable Recorder-to-bed assignment evidence';
        COMMENT ON TABLE recorder_assignment.resolutions IS
          'Complete time-bounded candidate answer consumed by Archive attribution';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive Recorder assignment downgrade is unsupported; "
        "restore an explicit owner backup"
    )
