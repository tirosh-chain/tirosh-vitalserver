# PKG reinstall leaves VM Starting after activity projection migration OOM

> ID: TS-165
> Category: Packaging / Guest bootstrap / Data store / Observability
> Owner: Guest read model
> Status: superseded by clean PostgreSQL schema line

> Historical note: the activity backfill and
> `vitaldb_schema_migrations` marker described below are no longer part of the
> runtime. The clean schema line introduced by
> [TS-179](179_postgres_schema_migration_failed.md) requires an explicitly
> recreated PostgreSQL data volume and runs only central Alembic revisions.
> This entry remains as failure history and as guidance for any future bounded
> data-conversion job.

## Symptoms

After a data-preserving PKG reinstall, Host platform services are running but the VM remains
`Starting`. Runtime product service reads fail with Guest Control `503`, and
`bootstrap-result.json` is terminal `failed` with `guest-bootstrap-failed`.

The Guest console repeatedly reports an OOM kill similar to:

```text
Out of memory: Killed process ... (tirosh-runtime-) total-vm:... anon-rss:7159276kB
```

Runtime data preparation can then fail with an explicit unit-state proof:

```text
RuntimeError: systemd units did not stop: tirosh-vitalserver-compose.service=failed
```

## Impact

The preserved VM disk, runtime data disk, PostgreSQL data, and Vital Files remain present. The Guest
cannot complete bootstrap because `tirosh-runtime-observation` repeatedly consumes nearly the entire
8 GiB VM memory allocation. Compose may be killed or left `failed`, so product endpoints do not start.

This failure does not require deleting the preserved installation data.

## Cause

The activity-history fix introduced a one-time migration from existing
`vitaldb_observation_snapshots` rows into `vitaldb_recorder_activity_buckets`. The first implementation
selected every historical JSON snapshot in one SQLAlchemy result and performed the full backfill in
one transaction. Runtime observation runs every five seconds, so a two-day installation can contain
tens of thousands of snapshots. The PostgreSQL driver and ORM materialized enough history for the
migration process to grow beyond 7 GiB and be killed by the Guest kernel.

There was a second lifecycle race. On a preserved VM disk, enabled Guest services start before the new
cloud-init bootstrap. Runtime data preparation stopped the container-log and compose consumers but did
not stop `tirosh-runtime-observation`, even though that service consumes the PostgreSQL container and
its preserved data. It could therefore continue or restart the unbounded migration while Compose and
Docker were stopping.

## Checks

Confirm the install and bootstrap result through their state owners:

```sh
pkgutil --pkg-info ai.tirosh.vitalserver.helper
sudo cat "/Library/Application Support/VitalServerHelper/vm/data/run/bootstrap-result.json"
```

Inspect Guest console evidence for the memory failure:

```sh
sudo rg -n "Out of memory|Killed process|cloud-final|compose" \
  "/Library/Application Support/VitalServerHelper/logs/runtime/launchd.out.log"
```

Inside the Guest, inspect explicit service and migration state:

```sh
systemctl show --property=ActiveState --value tirosh-runtime-observation.service
systemctl show --property=ActiveState --value tirosh-vitalserver-compose.service
sudo -u postgres psql vitalserver -c \
  "select count(*) from vitaldb_observation_snapshots;"
sudo -u postgres psql vitalserver -c \
  "select migration_id, applied_at from vitaldb_schema_migrations order by applied_at;"
```

Absence of the migration marker means the backfill did not complete. It is not an empty-history success
state.

## Actions

1. Stop repeated recovery/reboot attempts until a fixed PKG is available; each attempt reruns the same
   failed migration.
2. Install a PKG containing the TS-165 fix over the existing installation. The reinstall remains
   data-preserving.
3. Verify that bootstrap reaches terminal `completed`, both runtime-observation and compose are
   `active`, and the activity migration marker exists.
4. Verify the oldest and newest recorder activity buckets through the Guest activity endpoint before
   declaring the long-range chart recovered.

The fix reads observation snapshots by increasing `snapshot_id` in bounded 256-row transactions,
merges duplicate rolling-window buckets within each batch, and upserts the durable projection. The
migration remains idempotent after interruption and writes its completion marker only after every
batch succeeds. Warm runtime-data preparation now stops `tirosh-runtime-observation` before the
container-log and compose consumers and proves all consumer units are `inactive` before stopping
Docker providers.

## Prevention

- Existing-data migrations must be tested with history cardinality derived from the production write
  interval, not a one-row fixture only.
- A migration over an unbounded table must use bounded reads and bounded transactions.
- Completion markers are terminal proof; missing markers and partially projected rows must not be
  interpreted as success.
- Warm bootstrap must stop every explicit consumer of a provider before stopping or migrating that
  provider.
- Reinstall acceptance must include a preserved multi-day read model, not only a fresh database.

## Related Cases

- `TS-031`: Recorder activity history was truncated to the latest 1,000 observation snapshots.
- `TS-164`: Warm reinstall used an invalid Docker stop deadline and lacked final unit-state proof.
- `TS-166`: The preserved VM started the old observation service before the replacement wheel was
  installed, so the bounded migration could not prevent the first OOM by itself.

## Follow-up

- 2026-07-20: Confirmed the corrected PKG receipt and Guest wheel were installed successfully, then
  observed repeated `tirosh-runtime-` OOM kills at approximately 7 GiB RSS.
- 2026-07-20: Correlated the OOM process with the newly introduced all-history activity projection
  migration and the enabled runtime-observation service.
- 2026-07-20: Added bounded keyset migration batches, idempotent bucket merge/upsert behavior,
  runtime-observation-first shutdown, and focused migration/stop-order tests.
- 2026-07-20: A rebuilt PKG proved that the old enabled observation service can begin the old
  migration before cloud-init installs the corrected wheel. Bootstrap now requests consumer
  quiescence before Guest Tools installation; see `TS-166`.
