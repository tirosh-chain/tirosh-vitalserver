# VitalServer Backup

VitalServer backup is the user-facing recovery contract for Helper-managed VitalServer
state. The internal command and API name remains `runtime-data-backup`, but product
UI must present this as one VitalServer backup because the archive includes both Host
runtime state and Guest Redis data.

The macOS Helper exposes this contract in Advanced -> Recovery operations ->
VitalServer backup with Create VitalServer Backup and Restore VitalServer Backup
actions. Restore requires an explicitly selected VitalServer backup from the
Host-provided backup list.

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

Backup creation writes a manifest last. Restore must reject missing, duplicated, non-archived, unchecked, size-mismatched, checksum-mismatched, or path-escaping artifacts. Missing backup directories, decode failures, permission failures, guest capability failures, and guest result read failures are operation failures; they are not empty backup lists or successful restores.

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
