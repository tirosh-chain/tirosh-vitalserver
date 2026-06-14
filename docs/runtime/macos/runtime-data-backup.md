# VitalServer Backup

VitalServer backup is the user-facing recovery contract for Helper-managed VitalServer
state. The internal command and API name remains `runtime-data-backup`, but product
UI must present this as one VitalServer backup because the archive includes both Host
runtime state and Guest Redis data.

The macOS Helper exposes this contract in Advanced -> Recovery operations ->
VitalServer backup with Create VitalServer Backup and Restore VitalServer Backup
actions. Restore requires an explicitly selected VitalServer backup from the
Host-provided backup list.

VitalServer backup deletion is exposed separately in Danger Zone as Delete
VitalServer Backup. It deletes only an explicitly selected direct child of the
Host-reported VitalServer backup directory. Update/rollback backup deletion is a
separate Delete Update Backup action and must not share UI copy that hides the
target type.

Redis-only backup/restore is an advanced repair affordance. It is useful for
surgical recovery or repair workflows, but it is not the default product backup
model. Normal users should create and restore one VitalServer backup instead of
coordinating separate runtime and Redis archives.

Required artifacts:

| Artifact | Owner | Restore target |
|---|---|---|
| `redis-data` | Guest | Redis Docker volume through explicit guest `redis-restore` request/result |
| `runtime-vm-config` | Host | installed VM config document |
| `guest-runtime-config` | Host | deployed guest runtime config document |
| `guest-runtime-settings` | Host | runtime settings document |
| `proxy-launch-daemon-settings` | Host | proxy LaunchDaemon plist |
| `start-on-boot-state` | Host | launchctl enabled/disabled state for managed services |
| `runtime-status-document` | Host | Host runtime status document *(optional: skipped when missing)* |
| `runtime-events-document` | Host | Host runtime event document *(optional: skipped when missing)* |
| `runtime-observability-database` | Host | `runtime-observability.sqlite` snapshot *(optional: skipped when missing)* |

The restore process treats `runtime-status-document`, `runtime-events-document`, and `runtime-observability-database` as best-effort artifacts. If missing, restore will continue using existing host-side files and still restore required artifacts.

## Artifact Schema Ownership

VitalServer backup is one restore unit, but every artifact has its own data schema owner.
The backup manifest records artifact identity, path, size, checksum, and the global
`dataCompatibilityVersion`. The manifest does not make every artifact share one file
format.

| Artifact | Data schema owner | Restore compatibility note |
|---|---|---|
| `redis-data` | Guest VitalServer Redis schema | Restored by Guest Redis restore worker. Redis key/value layout changes that cannot be read by the current Guest runtime require a `dataCompatibilityVersion` bump or an explicit migration. |
| `runtime-vm-config` | Host VM runtime config contract | Host reads this file before/while starting the VM. Breaking config changes require a compatibility bump or an explicit config migration before restore. |
| `guest-runtime-config` | Guest deploy/runtime config contract | Host deploys the file; Guest bootstrap and services consume it. Breaking field changes require a compatibility bump or migration. |
| `guest-runtime-settings` | Runtime settings contract | Host UI and Guest runtime both consume this document. Settings schema changes must preserve explicit missing/invalid/default meanings. |
| `proxy-launch-daemon-settings` | macOS launchd plist contract | Host LaunchDaemon setup consumes it. Breaking service label/path semantics require compatibility review. |
| `start-on-boot-state` | Host generated start-on-boot state document | Current schema is `RuntimeDataBackupStartOnBootStateDocument.schemaVersion`. Restore must reject unsupported document schema instead of guessing service state. |
| `runtime-status-document` | Host runtime status document | Optional UI continuity artifact. Missing means unavailable; restore does not synthesize status. Breaking status schema can be skipped or gated by backup compatibility. |
| `runtime-events-document` | Host runtime event JSONL contract | Optional observability continuity artifact. Decode or schema changes must not be hidden as an empty event list. |
| `runtime-observability-database` | Host SQLite observability projection schema | Optional UI continuity artifact. SQLite schema changes can make old snapshots unreadable; restore must be gated or migrated before the current Helper opens the database. |

## Compatibility Contract

Runtime data backup restore is gated by `RuntimeDataBackupManifest.dataCompatibilityVersion`.
The current Helper writes `RuntimeDataBackupCompatibility.currentDataCompatibilityVersion`
when creating a backup. Restore rejects a backup when:

- the manifest is missing `dataCompatibilityVersion`;
- the manifest declares a version not supported by the current Helper;
- the manifest schema, product, required artifact set, artifact state, size, checksum,
  or relative artifact path validation fails.

This compatibility version is a data layout contract, not a product version string.
`runtimeVersion` is still recorded for operator context, but restore must not use it as
the only compatibility decision. Product version and data compatibility version can
move at different speeds.

### When To Bump `dataCompatibilityVersion`

Bump the compatibility version when a backup made by the previous format can no longer
be restored safely by the current runtime without an explicit migration. Examples:

- Redis key/value layout changes in a way the current VitalServer cannot read old data;
- `runtime-vm-config`, `guest-runtime-config`, or `guest-runtime-settings` changes remove
  or reinterpret required fields;
- `runtime-observability.sqlite` schema changes make restored snapshots unreadable or
  unsafe for read-only query paths;
- launchd service labels or start-on-boot state semantics change in a non-compatible way.

Do not bump the compatibility version for additive optional fields that older backups can
restore with explicit missing-state handling. Missing, invalid, failed, stale, zero, and
empty meanings must remain distinct.

If restore support for an older compatibility version is required, add an explicit
migration path before any file is written to runtime destinations. Restore must not
partially apply a backup and then discover that a later artifact is incompatible.

Backup creation writes a manifest last. Restore must reject missing, duplicated,
non-archived, unchecked, size-mismatched, checksum-mismatched, path-escaping, or
compatibility-incompatible artifacts. Missing backup directories, decode failures,
permission failures, guest capability failures, and guest result read failures are
operation failures; they are not empty backup lists or successful restores.

Redis restore is guest-owned. Host stages the selected archive into the shared runtime data directory and writes a `redis-restore.request`; the guest command poller dispatches `tirosh-vitalserver-redis-restore.service`, which validates the archive, stops Docker Compose, replaces the Redis volume contents, starts Compose, and writes `redis-restore-result.json`.

Older guests that do not report the `redisRestore` capability cannot complete runtime data restore. Host must report that capability failure explicitly instead of guessing Redis volume internals.

## Troubleshooting

### Create backup fails with missing `redis-data`

Symptom:

```text
required runtime data backup artifact is missing id=redis-data path=/mnt/tirosh/backups/redis/<archive>.tar.gz
```

Cause: the guest `redis-backup-result.json` reports the archive path from the guest mount namespace (`/mnt/tirosh/...`). The Host backup store reads from the macOS filesystem, so it must translate that path through the explicit shared data directory contract before archiving.

Fix direction: convert `/mnt/tirosh/<relative>` to `<installed data directory>/<relative>` before passing the Redis archive to `RuntimeDataBackupStore.createBackup`.

Prevention principle: Host may consume guest-reported paths only through an explicit mount contract. It must not treat guest absolute paths as Host paths or infer equivalent locations from filenames.
