# Backup & Restore Contracts

이 문서는 Vital Server Helper의 backup/restore 구현 계약을 정리합니다.
Release `usage.md`는 운영자가 눌러야 하는 메뉴와 판단 순서를 다루고, 이 문서는
artifact 구성, data schema owner, restore compatibility, migration tool의 구현 기준을 다룹니다.

## 1. Product Surfaces

| Product surface | Internal operation | Intended use |
|---|---|---|
| VitalServer backup | `runtime-data-backup` | Helper-managed runtime state와 Guest Redis data를 하나의 복구 단위로 backup/restore |
| Redis-only recovery | Redis backup/restore request | VM disk repair, uninstall, migration, 장애 분석처럼 Redis data만 분리해야 하는 고급 조치 |
| Upstream Redis backup command | Troubleshooting Tools command | 기존 upstream VitalServer Redis data directory를 Helper Redis-only import archive로 변환 |

일반 운영자는 VitalServer backup을 사용합니다. Redis-only recovery는 전체 runtime 상태를 되돌리는
기능이 아니라 Redis data만 바꾸는 repair 기능입니다.

## 2. Runtime Data Backup Artifacts

VitalServer backup은 하나의 restore unit이지만 artifact마다 schema owner가 다릅니다.

| Artifact | Owner | Schema owner | Restore target |
|---|---|---|---|
| `redis-data` | Guest | VitalServer Redis key/value layout | Redis Docker volume through guest `redis-restore` |
| `runtime-vm-config` | Host | VM runtime config contract | installed VM config document |
| `guest-runtime-config` | Host | Guest deploy/runtime config contract | deployed guest runtime config document |
| `guest-runtime-settings` | Host | Runtime settings contract | runtime settings document |
| `proxy-launch-daemon-settings` | Host | macOS launchd plist contract | proxy LaunchDaemon plist |
| `start-on-boot-state` | Host | `RuntimeDataBackupStartOnBootStateDocument` | launchctl enabled/disabled state |
| `runtime-status-document` | Host | Host runtime status document | optional UI continuity state |
| `runtime-events-document` | Host | Host runtime event JSONL contract | optional UI continuity event history |
| `runtime-observability-database` | Host | SQLite observability projection schema | optional UI continuity projection snapshot |

Required recovery artifacts are Redis data, VM config, guest config, guest settings,
proxy LaunchDaemon settings, and start-on-boot state. Status, events, and observability
SQLite are optional continuity artifacts: if they are missing from the backup, restore
continues without synthesizing replacement state.

## 3. Compatibility Gate

Restore must check `RuntimeDataBackupManifest.dataCompatibilityVersion` before writing any
artifact to runtime destinations.

The compatibility version is a data layout contract. It is not the same as product
`runtimeVersion`. Product version is recorded for operator context, but restore must not
infer compatibility from product version, filenames, artifact presence, or successful
checksums alone.

Restore rejects a backup when:

- `dataCompatibilityVersion` is missing;
- the declared compatibility version is not supported by the current Helper;
- manifest schema/product/artifact identity validation fails;
- required artifact state, path, size, or checksum validation fails.

If old backup support is required, implement an explicit migration before restore writes
files. A restore flow must not partially apply artifacts and then discover later that
another artifact is incompatible.

## 4. When To Bump Compatibility

Bump `RuntimeDataBackupCompatibility.currentDataCompatibilityVersion` when an older backup
cannot be restored safely by the current runtime without migration.

Typical bump triggers:

- Redis key/value layout changes in a way current VitalServer cannot read old data;
- VM config, guest runtime config, or guest runtime settings removes or reinterprets a
  required field;
- start-on-boot service labels or launchd plist semantics change incompatibly;
- `runtime-observability.sqlite` schema changes make restored snapshots unsafe or
  unreadable for current read-only query paths.

Do not bump for additive optional fields that can be handled through explicit missing-state
semantics. Missing, invalid, failed, stale, zero, and empty must remain different meanings.

## 5. Redis-only And Upstream Migration

Redis-only backup/restore is Guest-owned. Host stages or selects an archive, writes a typed
request, waits for a typed result, and reports capability/read failures explicitly. Host must
not infer Redis internals from filenames, logs, or Docker volume paths.

The DMG Troubleshooting Tools command `Create Upstream Redis Backup.command` is a migration
helper for existing upstream VitalServer Redis data. It asks for the upstream Redis data
directory and creates `redis-upstream-import.tar.gz` for Helper import.

The command may run bundled Redis tooling to issue `SAVE` before archiving. `SAVE` does not
stop Redis, but it can briefly block Redis while writing `dump.rdb`. If automatic refresh is
skipped, the operator must ensure `dump.rdb` is current by running `SAVE`/`BGSAVE` or stopping
upstream Redis before selecting the data directory.

Generated upstream Redis archives are imported through Advanced -> Recovery operations ->
Redis-only recovery -> Import Backups, then restored with Restore Redis-only Backup.

Troubleshooting Tools command logs are written under the current user's temp directory:

| Command | Log |
|---|---|
| Reset for Reinstall | `tirosh-vitalserver-reset-for-reinstall.log` |
| Create Upstream Redis Backup | `tirosh-vitalserver-upstream-redis-backup.log` |

## 6. Documentation Rule

When backup/restore behavior changes, update both:

- release usage docs with the operator-visible menu/result change;
- this dev contract with schema owner, compatibility, or migration implications.

Repeated restore failures must also be promoted into troubleshooting docs with symptom,
cause, fix direction, and prevention.
