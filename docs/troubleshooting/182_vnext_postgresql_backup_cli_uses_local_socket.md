# vNext PostgreSQL backup or restore CLI connects to the local socket

> ID: TS-182
> Category: Data store / Guest bootstrap
> Owner: Runtime Platform vNext Guest Runtime PostgreSQL backup/restore adapters
> Status: active

## Symptoms

- C76 backup operation reaches `postgresql-snapshot` and fails with
  `postgresql-logical-snapshot-failed`.
- The underlying `pg_dump` output reports a local Unix socket and an unexpected
  operating-system role, for example:

  ```text
  connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed:
  FATAL: role "root" does not exist
  ```

- After fixing backup, restore can fail at `postgresql-restore` with
  `postgresql-restore-command-failed`.
- `pg_restore` can also report:

  ```text
  one of -d/--dbname and -f/--file must be specified
  ```

## Impact

SQLite snapshot or restore may already have succeeded, but the combined C76
operation terminates as failed. The immutable manifest is not published on a
failed backup, and a failed single-transaction PostgreSQL restore must not be
treated as restored state.

## Cause

The adapter placed the complete PostgreSQL connection URL in `PGDATABASE`.
PostgreSQL 16 command-line tools did not interpret that environment value as
the connection URL expected by the adapter, so `pg_dump` selected local libpq
defaults.

The restore adapter additionally passed only the database name through
`--dbname` while relying on the same invalid `PGDATABASE` value for host and
role. Removing `--dbname` entirely is also invalid because `pg_restore`
requires an explicit restore database selection.

## Checks

Read the C76 operation instead of inferring success from the presence of a
SQLite snapshot:

```sh
platformctl operational-state read --operation-id <operation-id>
```

In a controlled Guest or acceptance environment, compare the command behavior
with explicit libpq variables:

```sh
PGHOST=<host> PGPORT=<port> PGUSER=<role> PGDATABASE=<database> \
  pg_dump --format=custom --file=/tmp/owner.dump <owner schema arguments>
```

Do not print `PGPASSWORD`, the original database URL material, or other private
connection material in diagnostic output.

## Actions

1. Use a build containing the explicit PostgreSQL command environment adapter.
2. Re-run the failed backup as a new operation with a new request and operation
   ID.
3. Provision a genuinely empty PostgreSQL restore target and an absent SQLite
   target before retrying restore.
4. Verify the terminal operation and public owner reads. Do not reuse a target
   that may contain output from a previous successful restore.

## Prevention

- Parse the configured PostgreSQL URL once and replace inherited libpq state
  with explicit `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, optional
  `PGPASSWORD`, and supported TLS/session variables.
- Keep the complete URL and credentials out of process argv.
- Reject unsupported URL query parameters instead of silently losing their
  connection or TLS meaning.
- Pass the validated database name through `pg_restore --dbname` while the
  remaining connection state comes from the explicit libpq environment.
- Run the combined acceptance against PostgreSQL 16 with seeded owner evidence,
  an absent SQLite target, and an empty PostgreSQL target.

## Operational Notes

`pg_dump` or `pg_restore` process exit is not sufficient proof. C76 requires
snapshot inspection, digest comparison, exact Alembic revision, owner schema
proof, empty-target proof, and restored public owner reads before success.

## Related Cases

- `TS-179`

## Follow-up

- 2026-07-24: reproduced with PostgreSQL 16 in isolated source/target
  containers. The combined SQLite/PostgreSQL backup and restore acceptance,
  public owner API parity, and second-restore rejection passed after the
  adapter fix.
