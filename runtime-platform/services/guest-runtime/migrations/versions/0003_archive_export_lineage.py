"""Add Archive Export artifact lineage and upstream receipts.

Revision ID: 0003_archive_lineage
Revises: 0002_catalog_expectations
Create Date: 2026-07-24
"""

from __future__ import annotations

from alembic import op

revision = "0003_archive_lineage"
down_revision = "0002_catalog_expectations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE SCHEMA archive_export;

        CREATE TABLE archive_export.artifacts (
          artifact_id text PRIMARY KEY,
          source_kind text NOT NULL CHECK (
            source_kind IN (
              'recorder-upload',
              'gateway-cold-path',
              'lab-export',
              'manual-upload'
            )
          ),
          source_receipt_type text NOT NULL,
          source_receipt_id text NOT NULL,
          manifest_id text NOT NULL UNIQUE,
          original_file_name text NOT NULL,
          media_type text NOT NULL,
          byte_size bigint NOT NULL CHECK (byte_size >= 0),
          sha256 char(64) NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
          finalization_state text NOT NULL CHECK (
            finalization_state IN ('finalized', 'failed')
          ),
          manifest_document jsonb NOT NULL
            CHECK (jsonb_typeof(manifest_document) = 'object'),
          created_at timestamptz NOT NULL,
          finalized_at timestamptz,
          UNIQUE (source_kind, source_receipt_type, source_receipt_id),
          CHECK (
            (finalization_state = 'finalized' AND finalized_at IS NOT NULL)
            OR (finalization_state = 'failed' AND finalized_at IS NULL)
          )
        );

        CREATE TABLE archive_export.recorder_attributions (
          artifact_id text PRIMARY KEY
            REFERENCES archive_export.artifacts(artifact_id)
            ON DELETE RESTRICT,
          reported_bed_name text,
          evidence_observed_at timestamptz NOT NULL,
          assignment_evidence_reference jsonb,
          candidate_recorder_ids jsonb NOT NULL DEFAULT '[]'::jsonb
            CHECK (jsonb_typeof(candidate_recorder_ids) = 'array'),
          outcome text NOT NULL CHECK (
            outcome IN ('matched', 'unresolved', 'ambiguous')
          ),
          matched_recorder_id text,
          policy_version text NOT NULL,
          resolved_at timestamptz NOT NULL,
          CHECK (
            assignment_evidence_reference IS NULL
            OR jsonb_typeof(assignment_evidence_reference) = 'object'
          ),
          CHECK (
            (outcome = 'matched' AND matched_recorder_id IS NOT NULL)
            OR (outcome IN ('unresolved', 'ambiguous')
                AND matched_recorder_id IS NULL)
          )
        );

        CREATE INDEX recorder_attributions_matched_recorder_idx
        ON archive_export.recorder_attributions
          (matched_recorder_id, resolved_at DESC)
        WHERE outcome = 'matched';

        CREATE TABLE archive_export.upload_attempts (
          attempt_id text PRIMARY KEY,
          request_id text NOT NULL UNIQUE,
          artifact_id text NOT NULL
            REFERENCES archive_export.artifacts(artifact_id)
            ON DELETE RESTRICT,
          provider_reference jsonb NOT NULL
            CHECK (jsonb_typeof(provider_reference) = 'object'),
          state text NOT NULL CHECK (
            state IN ('requested', 'running', 'succeeded', 'failed', 'unknown')
          ),
          issue jsonb CHECK (
            issue IS NULL OR jsonb_typeof(issue) = 'object'
          ),
          started_at timestamptz NOT NULL,
          finished_at timestamptz,
          CHECK (
            (state IN ('requested', 'running') AND finished_at IS NULL)
            OR (state IN ('succeeded', 'failed', 'unknown')
                AND finished_at IS NOT NULL)
          ),
          CHECK (
            (state IN ('failed', 'unknown') AND issue IS NOT NULL)
            OR (state NOT IN ('failed', 'unknown') AND issue IS NULL)
          )
        );

        CREATE INDEX upload_attempts_artifact_started_idx
        ON archive_export.upload_attempts
          (artifact_id, started_at DESC, attempt_id DESC);

        CREATE TABLE archive_export.indexing_receipts (
          receipt_id text PRIMARY KEY,
          artifact_id text NOT NULL
            REFERENCES archive_export.artifacts(artifact_id)
            ON DELETE RESTRICT,
          upload_attempt_id text NOT NULL UNIQUE
            REFERENCES archive_export.upload_attempts(attempt_id)
            ON DELETE RESTRICT,
          provider_receipt_id text,
          outcome text NOT NULL CHECK (
            outcome IN (
              'indexed',
              'not-indexed',
              'unknown',
              'unsupported',
              'failed'
            )
          ),
          issue jsonb CHECK (
            issue IS NULL OR jsonb_typeof(issue) = 'object'
          ),
          observed_at timestamptz NOT NULL,
          persisted_at timestamptz NOT NULL,
          CHECK (
            (outcome = 'indexed' AND provider_receipt_id IS NOT NULL
              AND issue IS NULL)
            OR (outcome <> 'indexed' AND issue IS NOT NULL)
          )
        );

        COMMENT ON SCHEMA archive_export IS
          'Guest Runtime Archive Export artifact and receipt owner';
        COMMENT ON COLUMN archive_export.recorder_attributions.reported_bed_name IS
          'Attribution evidence only; never a Recorder identity';
        COMMENT ON TABLE archive_export.indexing_receipts IS
          'Upstream indexing is independent from upload transport success';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive Archive Export downgrade is unsupported; "
        "restore an explicit owner backup"
    )
