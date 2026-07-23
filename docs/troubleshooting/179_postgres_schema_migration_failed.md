# PostgreSQL schema migration failed

> ID: TS-179
> Category: Guest bootstrap / Data store
> Owner: PostgreSQL migration job
> Status: active

## Symptoms

The runtime stops during ordered startup before product services become
healthy. `postgres-migrate` is exited with a non-zero code and its log includes:

```text
postgres schema migration failed
stage=postgres-schema-migration
currentRevision=<none>
targetRevision=0001_initial_schema
```

An existing pre-migration database reports:

```text
unmanaged_database_not_empty
```

## Cause

`vitalserver-postgres-migrator` is the only PostgreSQL DDL owner. The initial
revision requires a clean database. Tables previously created by Product Lab,
the VitalDB read model, Recorder ingress, or a manual SQL operation are not
treated as compatible state.

Missing schema is not an empty product result, and an unknown existing table is
not a completed migration.

## Checks

```sh
docker compose ps -a postgres-migrate
docker compose logs postgres-migrate
docker compose exec -T postgres \
  psql -U vitalserver -d vitalserver \
  -c 'select version_num from public.alembic_version;'
docker compose exec -T postgres \
  psql -U vitalserver -d vitalserver \
  -c '\dn'
```

Record the `currentRevision`, `targetRevision`, failing revision and complete
migrator error before changing the database.

## Actions

For a clean installation, correct the reported connection, permission, DDL, or
revision problem and rerun ordered startup.

For `unmanaged_database_not_empty`, choose explicitly:

- keep the existing installation and do not install this clean schema line; or
- export required data, stop the runtime, reset only the named PostgreSQL data
  volume, and start the runtime again.

Do not drop individual tables until the migration happens to pass. The
migrator intentionally rejects partial state.

## Prevention

- Product services must not call SQLAlchemy `metadata.create_all()` or execute
  application-owned migration SQL.
- Every schema change is a new Alembic revision.
- CI upgrades an empty PostgreSQL 16 database to head twice and checks one head.
- Runtime startup always runs migration after PostgreSQL health and before
  product services.
