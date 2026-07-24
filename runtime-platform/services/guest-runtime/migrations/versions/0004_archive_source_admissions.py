"""Add idempotent Archive source admission receipts.

Revision ID: 0004_archive_source_admissions
Revises: 0003_archive_lineage
Create Date: 2026-07-24
"""

from __future__ import annotations

from alembic import op

revision = "0004_archive_source_admissions"
down_revision = "0003_archive_lineage"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        r"""
        CREATE TABLE archive_export.source_admission_requests (
          request_id text PRIMARY KEY,
          command_digest char(64) NOT NULL
            CHECK (command_digest ~ '^[a-f0-9]{64}$'),
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
          outcome text NOT NULL CHECK (
            outcome IN ('accepted', 'duplicate', 'quarantined')
          ),
          artifact_id text
            REFERENCES archive_export.artifacts(artifact_id)
            ON DELETE RESTRICT,
          issue jsonb CHECK (
            issue IS NULL OR jsonb_typeof(issue) = 'object'
          ),
          admission_document jsonb NOT NULL
            CHECK (jsonb_typeof(admission_document) = 'object'),
          command_document jsonb NOT NULL
            CHECK (jsonb_typeof(command_document) = 'object'),
          received_at timestamptz NOT NULL,
          persisted_at timestamptz NOT NULL,
          CHECK (
            (outcome IN ('accepted', 'duplicate')
              AND artifact_id IS NOT NULL
              AND issue IS NULL)
            OR (outcome = 'quarantined'
              AND artifact_id IS NULL
              AND issue IS NOT NULL)
          )
        );

        CREATE INDEX archive_source_admission_source_idx
        ON archive_export.source_admission_requests (
          source_kind,
          source_receipt_type,
          source_receipt_id,
          persisted_at DESC
        );

        COMMENT ON TABLE archive_export.source_admission_requests IS
          'Idempotent Archive source request receipts; artifact identity remains owned by archive_export.artifacts';
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "destructive Archive source admission downgrade is unsupported; "
        "restore an explicit owner backup"
    )
