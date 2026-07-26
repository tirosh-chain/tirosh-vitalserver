"""Create the clean VitalServer PostgreSQL schema.

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-07-23
"""

from __future__ import annotations

from alembic import op
from sqlalchemy import text

revision = "0001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None

MANAGED_SCHEMAS = (
    "vitaldb_read_model",
    "product_lab",
    "recorder_observability",
)


def upgrade() -> None:
    require_clean_database()
    op.execute(INITIAL_SCHEMA_SQL)


def downgrade() -> None:
    raise RuntimeError(
        "destructive PostgreSQL schema downgrade is not supported; "
        "restore an explicit database backup instead"
    )


def require_clean_database() -> None:
    connection = op.get_bind()
    relations = connection.execute(
        text(
            """
            SELECT n.nspname, c.relname
              FROM pg_catalog.pg_class AS c
              JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
             WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
               AND n.nspname NOT IN ('pg_catalog', 'information_schema')
               AND n.nspname NOT LIKE 'pg_toast%'
               AND NOT (
                 n.nspname = 'public'
                 AND c.relname = 'alembic_version'
               )
             ORDER BY n.nspname, c.relname
            """
        )
    ).all()
    schemas = connection.execute(
        text(
            """
            SELECT nspname
              FROM pg_catalog.pg_namespace
             WHERE nspname = ANY(:managed_schemas)
             ORDER BY nspname
            """
        ),
        {"managed_schemas": list(MANAGED_SCHEMAS)},
    ).scalars().all()
    if relations or schemas:
        relation_names = [f"{schema}.{name}" for schema, name in relations]
        raise RuntimeError(
            "unmanaged_database_not_empty: "
            f"relations={relation_names} managedSchemas={list(schemas)}; "
            "back up and recreate the PostgreSQL data volume"
        )


INITIAL_SCHEMA_SQL = r"""
CREATE SCHEMA vitaldb_read_model;
CREATE SCHEMA product_lab;
CREATE SCHEMA recorder_observability;

CREATE TABLE vitaldb_read_model.observation_snapshots (
  snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
  observed_at timestamptz NOT NULL
);

CREATE INDEX observation_snapshots_observed_at_idx
ON vitaldb_read_model.observation_snapshots (observed_at);

CREATE TABLE vitaldb_read_model.recorder_activity_buckets (
  vrcode text NOT NULL,
  bucket_started_at text NOT NULL,
  bucket_seconds integer NOT NULL CHECK (bucket_seconds > 0),
  message_count bigint NOT NULL CHECK (message_count >= 0),
  byte_count bigint NOT NULL CHECK (byte_count >= 0),
  room_count integer NOT NULL CHECK (room_count >= 0),
  first_observed_at text NOT NULL,
  last_observed_at text NOT NULL,
  PRIMARY KEY (vrcode, bucket_started_at, bucket_seconds)
);

CREATE TABLE vitaldb_read_model.relationship_history_snapshots (
  snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
  observed_at timestamptz NOT NULL
);

CREATE INDEX relationship_history_snapshots_observed_at_idx
ON vitaldb_read_model.relationship_history_snapshots (observed_at);

CREATE TABLE vitaldb_read_model.entity_visibility (
  entity_kind text NOT NULL,
  entity_id text NOT NULL,
  visibility text NOT NULL CHECK (visibility IN ('visible', 'hidden', 'deleted')),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (entity_kind, entity_id)
);

CREATE TABLE product_lab.sessions (
  session_id text PRIMARY KEY,
  document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE product_lab.beds (
  bed_id text PRIMARY KEY,
  document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
  updated_at timestamptz NOT NULL
);

CREATE TABLE product_lab.recorders (
  recorder_id text PRIMARY KEY,
  document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
  updated_at timestamptz NOT NULL
);

CREATE TABLE recorder_observability.requests (
  request_id uuid PRIMARY KEY,
  resource_type text NOT NULL CHECK (
    resource_type IN (
      'observation',
      'diagnosticEvent',
      'kernelIncident',
      'recorderProfile',
      'bootEvent'
    )
  ),
  vrcode text NOT NULL CHECK (vrcode ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  request_device_id text NOT NULL CHECK (length(request_device_id) BETWEEN 1 AND 128),
  source_ip inet,
  received_at timestamptz NOT NULL,
  line_count integer NOT NULL CHECK (line_count >= 0),
  accepted_count integer NOT NULL CHECK (accepted_count >= 0),
  duplicate_count integer NOT NULL CHECK (duplicate_count >= 0),
  quarantined_count integer NOT NULL CHECK (quarantined_count >= 0),
  contract_receipts jsonb NOT NULL DEFAULT '[]'::jsonb,
  CHECK (line_count = accepted_count + duplicate_count + quarantined_count)
);

CREATE TABLE recorder_observability.records (
  record_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES recorder_observability.requests(request_id)
    ON DELETE RESTRICT,
  line_number integer NOT NULL CHECK (line_number > 0),
  disposition text NOT NULL CHECK (
    disposition IN ('accepted', 'duplicate', 'quarantined')
  ),
  resource_type text NOT NULL CHECK (
    resource_type IN (
      'observation',
      'diagnosticEvent',
      'kernelIncident',
      'recorderProfile',
      'bootEvent'
    )
  ),
  vrcode text NOT NULL CHECK (vrcode ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  request_device_id text NOT NULL,
  document_device_id text,
  claimed_event_id text,
  schema_version text,
  kind text,
  site_id text,
  boot_id text,
  sequence bigint CHECK (sequence IS NULL OR sequence >= 0),
  device_observed_at timestamptz,
  device_time_state text,
  raw_sha256 char(64) NOT NULL CHECK (raw_sha256 ~ '^[a-f0-9]{64}$'),
  canonical_sha256 char(64) CHECK (
    canonical_sha256 IS NULL OR canonical_sha256 ~ '^[a-f0-9]{64}$'
  ),
  raw_document text,
  document jsonb,
  duplicate_of_record_id bigint REFERENCES recorder_observability.records(record_id)
    ON DELETE RESTRICT,
  failure_code text,
  failure_detail text,
  projection_state text NOT NULL CHECK (
    projection_state IN (
      'pending',
      'applied',
      'ignored',
      'failed',
      'not_applicable'
    )
  ),
  projection_version integer NOT NULL DEFAULT 1 CHECK (projection_version > 0),
  projected_at timestamptz,
  projection_error text,
  received_at timestamptz NOT NULL,
  UNIQUE (request_id, line_number),
  CHECK (
    (
      disposition = 'accepted'
      AND document_device_id IS NOT NULL
      AND claimed_event_id IS NOT NULL
      AND schema_version IS NOT NULL
      AND kind IS NOT NULL
      AND canonical_sha256 IS NOT NULL
      AND document IS NOT NULL
      AND raw_document IS NULL
      AND duplicate_of_record_id IS NULL
      AND failure_code IS NULL
      AND projection_state IN ('pending', 'applied', 'ignored', 'failed')
    )
    OR (
      disposition = 'duplicate'
      AND document_device_id IS NOT NULL
      AND claimed_event_id IS NOT NULL
      AND schema_version IS NOT NULL
      AND kind IS NOT NULL
      AND canonical_sha256 IS NOT NULL
      AND document IS NULL
      AND raw_document IS NULL
      AND duplicate_of_record_id IS NOT NULL
      AND failure_code IS NULL
      AND projection_state = 'not_applicable'
    )
    OR (
      disposition = 'quarantined'
      AND raw_document IS NOT NULL
      AND duplicate_of_record_id IS NULL
      AND failure_code IS NOT NULL
      AND projection_state = 'not_applicable'
    )
  )
);

CREATE UNIQUE INDEX records_event_identity_uq
ON recorder_observability.records (vrcode, claimed_event_id)
WHERE disposition = 'accepted';

CREATE INDEX records_history_idx
ON recorder_observability.records (
  vrcode,
  resource_type,
  device_observed_at DESC NULLS LAST,
  received_at DESC,
  record_id DESC
)
WHERE disposition = 'accepted';

CREATE INDEX records_projection_pending_idx
ON recorder_observability.records (record_id)
WHERE disposition = 'accepted' AND projection_state = 'pending';

CREATE INDEX records_profile_association_idx
ON recorder_observability.records (
  vrcode,
  document_device_id,
  boot_id,
  received_at DESC,
  record_id DESC
)
WHERE disposition = 'accepted' AND resource_type = 'recorderProfile';

CREATE TABLE recorder_observability.current (
  vrcode text PRIMARY KEY,
  profile_record_id bigint
    REFERENCES recorder_observability.records(record_id) ON DELETE SET NULL,
  health_record_id bigint
    REFERENCES recorder_observability.records(record_id) ON DELETE SET NULL,
  boot_record_id bigint
    REFERENCES recorder_observability.records(record_id) ON DELETE SET NULL,
  projection_version integer NOT NULL CHECK (projection_version > 0),
  document jsonb NOT NULL DEFAULT '{}'::jsonb,
  device_id text NOT NULL,
  site_id text,
  boot_id text,
  report_state text NOT NULL,
  severity text NOT NULL,
  profile_state text NOT NULL,
  collection_state text,
  latest_received_at timestamptz NOT NULL,
  recent_restart_at timestamptz,
  active_signal_count integer NOT NULL DEFAULT 0 CHECK (active_signal_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (jsonb_typeof(document) = 'object')
);

COMMENT ON SCHEMA vitaldb_read_model IS 'VitalDB read-model persistence';
COMMENT ON SCHEMA product_lab IS 'VitalServer Product Lab persistence';
COMMENT ON SCHEMA recorder_observability IS 'Recorder observability persistence';
"""
