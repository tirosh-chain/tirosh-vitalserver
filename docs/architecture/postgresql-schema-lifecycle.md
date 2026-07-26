# PostgreSQL schema lifecycle

## Decision

`vitalserver-postgres-migrator` is the only owner that creates or changes the
VitalServer PostgreSQL schema. Product services map and verify their tables but
must not run DDL.

The migration history in
`apps/vitalserver-postgres-migrator/migrations/versions/` is the source of
truth. `public.alembic_version` records the applied revision. ORM metadata and
a generated schema dump are consumers or inspection artifacts, not migration
history.

This schema line starts from a clean database. It does not adopt tables created
by an older `metadata.create_all()` or Recorder ingress SQL runner. A database
that has user relations without an Alembic revision fails with
`unmanaged_database_not_empty`. The migrator must not infer that an arbitrary
existing relation is compatible.

## Namespace ownership

```text
public.alembic_version

vitaldb_read_model.observation_snapshots
vitaldb_read_model.recorder_activity_buckets
vitaldb_read_model.relationship_history_snapshots
vitaldb_read_model.entity_visibility

product_lab.sessions
product_lab.beds
product_lab.recorders

recorder_observability.requests
recorder_observability.records
recorder_observability.current
recorder_observability.expectations
```

Every application query or ORM record names its PostgreSQL schema explicitly.
The runtime does not use `search_path` to choose a bounded context.

## Runtime order

The Guest runtime owns the operation order:

```text
start PostgreSQL
→ wait for PostgreSQL health
→ run the postgres-migrate one-shot job
→ require Alembic head
→ start Redis
→ start product services
→ start the edge
```

`postgres-migrate` is a job, not a continuously running product service. Exit
code zero is its healthy terminal state. A migration failure stops the startup
workflow before Redis or product services are started.

Product repositories run read-only schema verification at startup. Missing
schema, missing columns, connection failure, and an empty table are different
states:

- missing or unreadable schema is a dependency failure;
- an existing, readable table with zero rows is loaded empty data;
- repositories never create a table to repair a failed verification.

## Migration rules

- Revisions are append-only and immutable after release.
- The revision graph has exactly one head.
- DDL uses explicit object names; it does not use `CREATE TABLE IF NOT EXISTS`.
- PostgreSQL transactional DDL and one session advisory lock serialize upgrades.
- Downgrade is not a recovery mechanism. Restore an explicit database backup.
- A data backfill with domain meaning is an explicit resumable application job;
  it is not hidden inside repository readiness.
- A schema change ships with empty-database, repeated-upgrade, invalid-state,
  consumer, Compose-order, and delivery tests.

## Managed backup and restore

VitalServer backup compatibility version 2 requires one Guest-owned PostgreSQL
archive in addition to Redis and Host artifacts. Guest Control creates a
custom-format dump of the whole `vitalserver` database so all owner schemas and
`public.alembic_version` belong to one PostgreSQL snapshot. The archive
manifest records the fixed database name, PostgreSQL server version, the single
Alembic revision, dump format/file, size, and checksum. The manifest does not
duplicate the migrator's schema/relation inventory.

Restore validates that manifest, checksum, and `pg_restore --list` proof before
stopping writers. It then stops the observation service and Compose product
stack, restores the database with PostgreSQL as the only running container,
and verifies that the restored database reports the manifest's Alembic
revision. Migrator startup and repository readiness remain the owners of
schema/object validation. In a coordinated VitalServer restore the operation
explicitly leaves runtime writers stopped; Redis restore is the final operation
that starts the full runtime. A missing proof or failed step remains a failed
operation and must not be converted into a usable empty database.

The real Compose restore proof is:

```bash
make runtime/proof/postgres-restore
```

It migrates an empty Compose database, writes representative documents from
the VitalDB read model, Product Lab, and Recorder observability schemas, dumps
and restores them into a new database, and compares the source/restored reads.
It uses the Guest Compose PostgreSQL port, so that port must be available.

See [VitalServer Backup](../runtime/macos/runtime-data-backup.md) for the
cross-store product contract. Redis and PostgreSQL receipts are independently
consistent snapshots; the current workflow does not claim cross-datastore
transactional atomicity.

## Clean database transition

The migrator never deletes data. An operator choosing this schema line must:

1. stop the runtime;
2. export any data that must be retained;
3. explicitly remove and recreate the PostgreSQL data volume;
4. start the runtime and let `postgres-migrate` apply the initial revision;
5. verify `public.alembic_version` and run runtime boot smoke.

Reinstalling the Helper without resetting an unmanaged PostgreSQL volume is
expected to fail. That failure prevents an accidental partial conversion.
