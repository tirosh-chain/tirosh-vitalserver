# Runtime Data Backup

Runtime data backup is the recovery contract for UI continuity data, excluding logs.

The macOS Helper exposes this contract in Advanced -> Recovery operations -> Runtime data backup with Create Backup and Restore Backup actions. Restore requires an explicitly selected runtime data backup from the Host-provided backup list.

Required artifacts:

| Artifact | Owner | Restore target |
|---|---|---|
| `redis-data` | Guest | Redis Docker volume through explicit guest `redis-restore` request/result |
| `runtime-vm-config` | Host | installed VM config document |
| `guest-runtime-config` | Host | deployed guest runtime config document |
| `guest-runtime-settings` | Host | runtime settings document |
| `proxy-launch-daemon-settings` | Host | proxy LaunchDaemon plist |
| `start-on-boot-state` | Host | launchctl enabled/disabled state for managed services |
| `runtime-status-document` | Host | Host runtime status document |
| `runtime-events-document` | Host | Host runtime event document |
| `runtime-observability-database` | Host | `runtime-observability.sqlite` snapshot |

Backup creation writes a manifest last. Restore must reject missing, duplicated, non-archived, unchecked, size-mismatched, checksum-mismatched, or path-escaping artifacts. Missing backup directories, decode failures, permission failures, guest capability failures, and guest result read failures are operation failures; they are not empty backup lists or successful restores.

Redis restore is guest-owned. Host stages the selected archive into the shared runtime data directory and writes a `redis-restore.request`; the guest command poller dispatches `tirosh-vitalserver-redis-restore.service`, which validates the archive, stops Docker Compose, replaces the Redis volume contents, starts Compose, and writes `redis-restore-result.json`.

Older guests that do not report the `redisRestore` capability cannot complete runtime data restore. Host must report that capability failure explicitly instead of guessing Redis volume internals.
