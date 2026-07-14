# Host runtime state persistence

Status: accepted, incremental migration in progress.

## Decision

Authoritative mutable Host runtime state is stored in the Host-local `runtime-state.sqlite` database. JSON and JSONL files are diagnostic projections or generated boot contracts; they are not current state owners and must not be used for command guards, recovery, or state reconstruction.

Guest product persistence remains independent:

- Guest product/read-model state uses Postgres through SQLAlchemy repositories and mappers.
- Guest-local control state may use SQLite when Guest startup or Postgres repair must not depend on Postgres availability.
- The Host never requires Guest Postgres to start, stop, inspect, or recover the VM.

## State ownership

| State | Authoritative provider | JSON/JSONL role |
|---|---|---|
| Host operation lease | Host SQLite repository | diagnostic snapshot only |
| Host workflow operation/step state | Host SQLite repository | JSONL events and current snapshot |
| VM lifecycle and VM errors | Host SQLite repository | current diagnostic snapshot |
| Runtime endpoint | Host SQLite repository | current diagnostic snapshot |
| Host runtime settings | Host SQLite repository | generated boot contracts where required |
| Installed runtime version metadata | Host SQLite repository plus explicit package/resource proof | diagnostic snapshot |
| launchd/process/file/package existence | live Host provider | optional diagnostic snapshot |
| Guest product state | Guest Postgres/Guest-local repository | API JSON payload or diagnostics only |

Physical resources remain owned by their actual providers. A database metadata row cannot make a missing VM disk, backup archive, launchd job, executable, or package receipt present.

## Database location

The Host state database path is:

```text
/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite
```

`InstalledRuntimePaths.runtimeStateDatabase` is the single path composition owner. The database is separate from `runtime-observability.sqlite`; diagnostics indexing and authoritative state must not share ownership accidentally.

The installed database is owned by `root:wheel` with mode `0600`. Host settings may include secret-bearing Guest configuration, while diagnostic outbox payloads deliberately contain only revision and run metadata.

## Schema status

Schema version 1 establishes the persistence foundation:

- `schema_migrations`
- `runtime_metadata`
- `diagnostic_outbox`
- `diagnostic_projection_state`

Schema version 2 adds the first aggregate table:

- `runtime_operation_lease`

Schema version 3 adds the workflow aggregate table:

- `workflow_operation_states`

Schema version 4 adds VM-owned Host aggregates:

- `vm_lifecycle`
- `runtime_endpoint`

Schema version 5 adds the Host settings aggregate:

- `host_runtime_settings`

Schema version 6 adds explicit diagnostic projection failure counters and the latest projection error.

Schema version 7 adds the applied Host settings payload columns. The settings row keeps desired, materialized, boot, and applied revisions distinct, preserves desired and applied payloads independently, and binds a materialized revision to the VM lifecycle run ID that consumed it. A v6 applied revision has no provable applied payload, so the v7 migration explicitly clears that proof and requires a new VM boot/health proof; it never infers the applied payload from mutable files or the current desired payload. Settings JSON payloads are stored in SQLite; diagnostic outbox payloads contain revision/run metadata only and never copy secrets.

The workflow table stores the explicit operation ID/type, phase, paired current step and step status, message, reason codes, lifecycle timestamps, and monotonic revision. Every mutation and its `workflow-operation-state-created` or `workflow-operation-state-updated` outbox event commit in one immediate transaction.

The v2 repository serializes acquire, heartbeat, and release through an immediate transaction. It preserves a monotonically increasing revision and commits the corresponding diagnostic outbox record in the same transaction. A released row remains as explicit aggregate history while the application read contract reports that no active lease exists.

Adding a table and repository does not by itself complete an authoritative cutover. CLI, Platform Agent, and Control Panel composition must switch together. Creating unused lifecycle/settings tables before their own composition switches would falsely imply that ownership had moved.

Every connection enables foreign keys, uses WAL, uses a bounded busy timeout, and performs explicit integrity and schema checks. A readiness read never creates or migrates a missing database.

Readiness preserves these meanings:

- database missing;
- path inspection failure or unexpected path type;
- open/configuration failure;
- migration required, invalid sequence, or unsupported future schema;
- integrity failure;
- missing or invalid metadata;
- loaded metadata.

## Transaction and revision rules

1. A state mutation and its diagnostic outbox event commit in one transaction.
2. Aggregate writes use an explicit revision guard.
3. Stale revisions fail; they are not retried as unconditional writes.
4. Lease acquisition uses a uniqueness constraint and an immediate transaction.
5. A locked, read-only, corrupt, or full database is an explicit dependency failure.
6. Repository failure never becomes missing, empty, expired, released, stopped, or healthy state.

## Diagnostics projection

The diagnostic projector consumes the committed outbox.

- `host-runtime-state-events.jsonl` is append-only and carries stable event ID, outbox sequence, aggregate identity, and aggregate revision.
- `host-runtime-state.json` is generated from a consistent database read and replaced atomically.
- Snapshot metadata includes database identity and source revision so stale output is detectable.
- Projection failures remain pending/retryable in the outbox and are reported explicitly.
- Deleting or corrupting diagnostic files does not change API state, lifecycle, recovery, or command behavior.

JSONL is not an event-store fallback. JSON is not a repository backup. Database restoration from either format requires a separately named and explicitly authorized migration/recovery operation.

## Boot materialization

The VM and Guest may still require file contracts before their databases or services are available. `vm-config.json`, `runtime-config.json`, and `runtime-settings.json` therefore remain generated boot artifacts.

Install/configure performs this order:

1. read complete authoritative settings;
2. validate the settings contract;
3. commit a new desired SQLite revision;
4. materialize all boot documents atomically per file;
5. read every document back and prove the complete payload equals the committed revision;
6. mark that revision materialized;
7. start the VM and bind the revision to its new lifecycle run ID;
8. mark the revision applied only after that run passes runtime health.

A failure at steps 4-8 leaves the desired revision unapplied and is returned as a command failure. It is not converted to a successful save, an empty state, or an applied projection.

Boot artifacts do not become settings owners merely because boot consumers read them.

## Cutover and legacy migration

Migration is aggregate-by-aggregate. For each cutover:

1. add the SQLite schema migration and repository contract tests;
2. add one explicit legacy file migration path when required;
3. validate all legacy documents before the database transaction;
4. persist migrated state and an initial outbox event in one transaction;
5. switch every composition root for the aggregate;
6. remove the legacy production reader/writer in the same focused change;
7. add an architecture test forbidding its return.

There is no dual-source period after cutover and no runtime fallback to legacy files. Missing, invalid, stale, permission-denied, and decode-failed legacy documents stop migration with the migration run ID, stage, reason, database path, and legacy paths.

## Incremental status

The schema/connection/readiness/outbox foundation and operation lease cutover are complete:

- CLI, Platform Agent, and Control Panel reads use the SQLite lease owner;
- the one-time legacy lease import is explicit;
- install proves database readiness;
- the JSON lease repository was deleted and an architecture test prevents its return.

Workflow state cutover is in progress:

- apply-bundle uses the acquired lease ID as its workflow operation ID;
- standalone rollback owns a distinct SQLite workflow operation, while apply-bundle recovery is explicitly identified by its parent operation ID and remains part of the parent failure lifecycle;
- install captures fresh-install/provision evidence before database initialization, then persists every explicit install transition to SQLite;
- the Runtime Control operation-state API reads the latest workflow state directly from SQLite;
- a nonterminal workflow document may provide the active operation explicitly when no lease exists, which is required during early install;
- install JSON is written only after the SQLite commit and is a best-effort diagnostic current snapshot;
- uninstall uses the SQLite workflow repository for every persisted transition and no longer writes a standalone uninstall JSON state document;
- before removing an installed product root, uninstall atomically relocates the complete root to a same-volume, operation-unique tombstone and explicitly switches the repository to the relocated database;
- receipt verification and the terminal workflow commit therefore occur while the authoritative database still exists; after the terminal commit, successful tombstone disposal removes the uninstalled product and its state owner together;
- if tombstone disposal fails, the command reports a finalizer failure and leaves the terminal SQLite state at the reported tombstone path instead of overwriting completion with an inferred failure;
- `runtime-progress.json` remains a diagnostic artifact and is not read by the live operation-state API.

Phase 3 workflow state cutover is complete for install, apply-bundle, standalone rollback, nested rollback ownership, uninstall, and Runtime Control reads. Phase 4 VM lifecycle/runtime endpoint cutover and Phase 5 Host settings desired/materialized/boot/applied revision and payload ownership are implemented in SQLite. The diagnostics projector writes independent append-only event and current-snapshot checkpoints; a projection failure stays retryable and cannot mutate watchdog/command state. Installed runtime version metadata remains a subsequent aggregate.
