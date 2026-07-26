#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "${script_directory}/.." && pwd)"
proof_project="${VITALSERVER_POSTGRES_PROOF_PROJECT:-vitalserver-postgres-restore-proof}"
compose_file="${repository_root}/apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
proof_database="vitalserver_restore_proof"
proof_id="compose-restore-proof"
proof_directory=""
read -r -a compose_command <<< "${DOCKER_COMPOSE:-docker compose}"

compose() {
  "${compose_command[@]}" \
    --project-name "${proof_project}" \
    --project-directory "${repository_root}" \
    --file "${compose_file}" \
    "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  if [[ -n "${proof_directory}" && -d "${proof_directory}" ]]; then
    rm -f "${proof_directory}/database.dump"
    rmdir "${proof_directory}"
  fi
}
trap cleanup EXIT

cleanup
compose up --detach --build postgres
compose run --rm --build postgres-migrate

compose exec -T postgres psql \
  --username=vitalserver \
  --dbname=vitalserver \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 <<SQL
INSERT INTO vitaldb_read_model.observation_snapshots (document, observed_at)
VALUES ('{"proofId":"${proof_id}","value":17}'::jsonb, CURRENT_TIMESTAMP);

INSERT INTO product_lab.sessions (session_id, document, created_at, updated_at)
VALUES (
  '${proof_id}',
  '{"proofId":"${proof_id}","state":"ready"}'::jsonb,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);

INSERT INTO recorder_observability.expectation_events (
  event_id,
  command_id,
  vrcode,
  previous_revision,
  revision,
  action,
  support_state,
  source,
  expected_since,
  evidence_document,
  decided_at
)
VALUES (
  '30000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  'PROOF-RECORDER',
  0,
  1,
  'set',
  'supported',
  'manual',
  CURRENT_TIMESTAMP,
  '{"proofId":"${proof_id}"}'::jsonb,
  CURRENT_TIMESTAMP
);

INSERT INTO recorder_observability.expectations (
  vrcode,
  revision,
  lifecycle_state,
  source_event_id,
  support_state,
  source,
  expected_since,
  evidence_document
)
VALUES (
  'PROOF-RECORDER',
  1,
  'active',
  '30000000-0000-4000-8000-000000000001',
  'supported',
  'manual',
  CURRENT_TIMESTAMP,
  '{"proofId":"${proof_id}"}'::jsonb
);
SQL

proof_directory="$(mktemp -d)"
dump_file="${proof_directory}/database.dump"

compose exec -T postgres pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --username=vitalserver \
  --dbname=vitalserver >"${dump_file}"

compose exec -T postgres pg_restore --list <"${dump_file}" >/dev/null
compose exec -T postgres dropdb \
  --if-exists \
  --username=vitalserver \
  "${proof_database}"
compose exec -T postgres createdb \
  --username=vitalserver \
  "${proof_database}"
compose exec -T postgres pg_restore \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  --username=vitalserver \
  --dbname="${proof_database}" <"${dump_file}"

read_query="
SELECT jsonb_build_object(
  'alembicRevision',
    (SELECT version_num FROM public.alembic_version),
  'observation',
    (SELECT document
       FROM vitaldb_read_model.observation_snapshots
      WHERE document->>'proofId' = '${proof_id}'),
  'labSession',
    (SELECT document
       FROM product_lab.sessions
      WHERE session_id = '${proof_id}'),
  'recorderExpectation',
    (SELECT evidence_document
       FROM recorder_observability.expectations
      WHERE vrcode = 'PROOF-RECORDER'),
  'recorderExpectationEvent',
    (SELECT jsonb_build_object(
       'commandId', command_id,
       'revision', revision,
       'action', action
     )
       FROM recorder_observability.expectation_events
      WHERE vrcode = 'PROOF-RECORDER')
)::text;
"

source_read="$(
  compose exec -T postgres psql \
    --username=vitalserver \
    --dbname=vitalserver \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --set=ON_ERROR_STOP=1 \
    --command="${read_query}"
)"
restored_read="$(
  compose exec -T postgres psql \
    --username=vitalserver \
    --dbname="${proof_database}" \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --set=ON_ERROR_STOP=1 \
    --command="${read_query}"
)"

if [[ "${source_read}" != "${restored_read}" ]]; then
  printf 'PostgreSQL restore proof mismatch\nsource=%s\nrestored=%s\n' \
    "${source_read}" \
    "${restored_read}" >&2
  exit 1
fi

printf 'PostgreSQL restore proof passed project=%s database=%s\n' \
  "${proof_project}" \
  "${proof_database}"
