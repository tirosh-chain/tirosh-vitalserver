# VitalServer Backup

VitalServer backup은 Helper가 관리하는 VitalServer 상태를 복구하기 위한 사용자-facing 계약입니다. 내부 command와 API 이름은 `runtime-data-backup`이지만, 제품 UI에서는 하나의 VitalServer backup으로 표시해야 합니다. 이 backup은 Host runtime state와 Guest Redis 및 PostgreSQL data를 함께 포함합니다.

## 1. 제품 계약

### 1-1. UI에서 보이는 이름

macOS Helper는 Advanced -> Recovery operations -> VitalServer backup에서 이 계약을 제공합니다. 사용자는 Create VitalServer Backup과 Restore VitalServer Backup action을 사용합니다. Restore는 Host가 제공한 backup 목록에서 명시적으로 선택한 VitalServer backup이 있어야 진행됩니다.

### 1-2. 자동 backup

자동 backup도 같은 VitalServer backup 계약을 사용합니다. Host launchd job `ai.tirosh.vitalserver.helper.automatic-backup`이 Settings의 `automaticBackupEnabled`, `backupScheduleTimes`, `backupRetentionCount`를 읽고 `runtime automatic-backup` command를 실행합니다.

이 command는 Helper app process가 떠 있는지와 무관하게 동작해야 하며, active runtime operation lease가 있으면 해당 run을 skipped로 기록합니다.

### 1-3. Retention 기준

`backupRetentionCount`는 `backups/vitalserver-helper` 아래의 검증된 VitalServer backup directory 보관 개수입니다. 통합 backup 생성에 사용한 Redis/PostgreSQL maintenance archive는 최종 package 검증 직후 삭제하므로 별도 retention 대상이 아닙니다. 사용자가 직접 만든 datastore별 maintenance backup에는 이 설정을 적용하지 않습니다.

### 1-4. 저장 위치와 compatibility baseline

VitalServer backup archive는 Host product root의 `/Library/Application Support/VitalServerHelper/backups/vitalserver-helper/` 아래에 저장합니다. 이 path, manifest `backupKind=vitalserver-helper`, 그리고 `restoreCompatibilityVersion=2`가 현재 compatibility baseline입니다.

PostgreSQL artifact가 없는 version 1 backup과 이전 `runtime-data` kind/path를 추정해서 읽는 fallback은 두지 않습니다.

### 1-5. 삭제 정책

VitalServer backup 삭제는 Danger Zone의 Delete VitalServer Backup으로 분리합니다. 이 작업은 Host가 보고한 VitalServer backup directory의 direct child만 삭제합니다.

Update/rollback backup 삭제는 별도 Delete Update Backup action이며, UI copy가 두 대상의 차이를 숨기면 안 됩니다.

Standard uninstall은 삭제 전에 같은 VitalServer backup을 필수로 생성합니다.
VM disk repair도 replacement 전에 같은 backup을 시도하지만, current VM disk
자체를 별도 archive하는 recovery workflow이므로 backup 실패를 명시적인
degraded best-effort 결과로 기록하고 disk archive 작업은 계속할 수 있습니다.

### 1-6. Redis-only backup의 위치

Redis-only 및 PostgreSQL-only backup/restore는 고급 maintenance 기능입니다. Surgical recovery나 repair workflow에는 유용하지만 기본 product backup model은 아닙니다. 일반 사용자는 Host, Redis, PostgreSQL archive를 따로 조합하지 말고 하나의 VitalServer backup을 만들고 복원해야 합니다.

## 2. Backup artifact

### 2-1. 필수 artifact

| Artifact | Owner | Role | Restore behavior |
|---|---|---|---|
| `redis-data` | Guest | Required recovery data | Guest Control `redis-restore` maintenance operation을 통한 Redis Docker volume |
| `postgres-database` | Guest | Required product database | Guest Control `postgres-restore` maintenance operation을 통한 custom-format database dump |
| `runtime-vm-config` | Host | Required Host config | 설치된 VM config document |
| `guest-runtime-config` | Host | Required Host-provided Guest config | 배포된 guest runtime config document |
| `guest-runtime-settings` | Host | Required settings contract | runtime settings document |
| `proxy-launch-daemon-settings` | Host | Required Host service config | proxy LaunchDaemon plist |
| `start-on-boot-state` | Host | Required generated Host config state | managed service의 launchctl enabled/disabled state |
| `runtime-status-document` | Host | Optional diagnostics/export artifact | Captured in manifest when available; restore must not write it back to current `runtime-status.json` |
| `runtime-events-document` | Host | Optional diagnostics/observability continuity artifact | Best-effort restore for event history continuity only; not current health/recovery state |
| `runtime-observability-database` | Host | Optional diagnostics/observability continuity artifact | Best-effort restore for event/query continuity only; not current health/VitalDB product source |

### 2-2. Optional artifact restore 정책

Restore process는 `runtime-events-document`, `runtime-observability-database`를 best-effort artifact로 취급합니다. Backup에 없으면 restore는 기존 Host-side file을 유지하고 required artifact만 복원합니다. `runtime-status-document`는 diagnostics/export artifact로 backup manifest에 남길 수 있지만 restore가 현재 `runtime-status.json` 위치에 되살리면 안 됩니다. Current runtime status는 Runtime Control owner reads와 새 status projection writer가 다시 제공해야 합니다.

## 3. Artifact schema 소유권

### 3-1. Backup manifest의 책임

VitalServer backup은 하나의 restore unit이지만 artifact마다 data schema owner가 다릅니다. Backup manifest는 artifact identity, path, size, checksum, backup-level `restoreCompatibilityVersion`을 기록합니다.

Manifest가 모든 artifact를 하나의 file format으로 합치거나 artifact별 compatibility version을 관리하는 것은 아닙니다.

### 3-2. Artifact별 schema owner

| Artifact | Data schema owner | Restore compatibility 기준 |
|---|---|---|
| `redis-data` | Guest VitalServer Redis schema | Guest Redis restore worker가 복원합니다. 현재 Guest runtime이 읽을 수 없는 Redis key/value layout 변경은 backup-level `restoreCompatibilityVersion` bump 또는 명시 migration이 필요합니다. |
| `postgres-database` | PostgreSQL owner schemas (`public`, `vitaldb_read_model`, `product_lab`, `recorder_observability`) | Guest PostgreSQL restore worker가 복원합니다. Dump manifest는 고정 database name, PostgreSQL version, 단일 Alembic revision, dump format/file, size/checksum을 증명합니다. |
| `runtime-vm-config` | Host VM runtime config contract | Host가 VM start 전후에 읽습니다. Breaking config change는 restore 전 compatibility bump 또는 config migration이 필요합니다. |
| `guest-runtime-config` | Guest deploy/runtime config contract | Host가 배포하고 Guest bootstrap/service가 소비합니다. Breaking field change는 compatibility bump 또는 migration이 필요합니다. |
| `guest-runtime-settings` | Runtime settings contract | Host UI와 Guest runtime이 함께 소비합니다. Settings schema 변경은 missing/invalid/default 의미를 명시적으로 보존해야 합니다. |
| `proxy-launch-daemon-settings` | macOS launchd plist contract | Host LaunchDaemon setup이 소비합니다. Service label/path 의미가 깨지는 변경은 compatibility review가 필요합니다. |
| `start-on-boot-state` | Host generated start-on-boot state document | 현재 schema는 `RuntimeDataBackupStartOnBootStateDocument.schemaVersion`입니다. Restore는 service state를 추정하지 말고 unsupported document schema를 거부해야 합니다. |
| `runtime-status-document` | Host runtime status document | Optional diagnostics/export artifact입니다. Missing은 unavailable을 뜻하며 restore는 status를 합성하거나 현재 status 위치에 복원하지 않습니다. Breaking status schema는 current runtime state로 승격하지 말고 diagnostics/export compatibility로만 다룹니다. |
| `runtime-events-document` | Host runtime event JSONL contract | Optional diagnostics/observability continuity artifact입니다. Decode/schema change를 empty event list로 숨기면 안 됩니다. |
| `runtime-observability-database` | Host SQLite observability projection schema | Optional diagnostics/observability continuity artifact입니다. SQLite schema change가 old snapshot을 unreadable하게 만들 수 있으므로, 현재 Helper가 DB를 열기 전에 gate 또는 migration이 필요합니다. |

## 4. Compatibility 계약

### 4-1. Restore gate

VitalServer backup restore는 `RuntimeDataBackupManifest.restoreCompatibilityVersion`으로 gate합니다. 현재 Helper는 backup 생성 시 `RuntimeDataBackupCompatibility.currentRestoreCompatibilityVersion`을 씁니다. Restore는 아래 경우 backup을 거부합니다.

- manifest에 `restoreCompatibilityVersion`이 없음
- manifest가 현재 Helper가 지원하지 않는 version을 선언함
- manifest schema, product, required artifact set, artifact state, size, checksum, relative artifact path validation 실패

Restore compatibility version은 backup unit 전체의 restore 계약이며 product version string이 아닙니다. `runtimeVersion`은 운영자 context를 위해 계속 기록하지만 restore compatibility의 유일한 판단 기준이 되어서는 안 됩니다. Product version과 restore compatibility version은 서로 다른 속도로 움직일 수 있습니다.

### 4-2. `restoreCompatibilityVersion`을 올리는 기준

이전 format으로 만든 backup을 현재 runtime이 명시 migration 없이 안전하게 restore할 수 없으면 restore compatibility version을 올립니다. 예시는 아래와 같습니다.

- 현재 VitalServer가 old data를 읽을 수 없을 정도로 Redis key/value layout이 변경됨
- PostgreSQL dump format 또는 migration compatibility가 현재 restore validator와 호환되지 않게 변경됨
- `runtime-vm-config`, `guest-runtime-config`, `guest-runtime-settings`에서 required field가 제거되거나 의미가 바뀜
- `runtime-observability.sqlite` schema 변경으로 restored snapshot이 unreadable하거나 read-only query path에서 unsafe함
- launchd service label 또는 start-on-boot state 의미가 호환되지 않게 바뀜

명시적인 missing-state 처리로 restore 가능한 additive optional field 때문에 compatibility version을 올리면 안 됩니다. Missing, invalid, failed, stale, zero, empty는 서로 다른 의미로 유지해야 합니다.

### 4-3. Legacy backup 정책

오래된 compatibility version을 지원해야 한다면 restore가 runtime destination에 file을 쓰기 전에 명시 migration path를 추가합니다. Restore가 일부 artifact를 적용한 뒤 나중에 다른 artifact가 incompatible하다는 사실을 발견하면 안 됩니다.

이 compatibility baseline 이전의 legacy backup은 지원하지 않습니다. Restore는 legacy kind, legacy directory name, missing compatibility field를 추정해서 받아들이지 않습니다.

### 4-4. Backup 생성과 restore 검증

Backup creation은 manifest를 마지막에 씁니다. Restore는 missing, duplicated, non-archived, unchecked, size-mismatched, checksum-mismatched, path-escaping, compatibility-incompatible artifact를 거부해야 합니다.

Missing backup directory, decode failure, permission failure, Guest Control capability failure, Guest Control operation read failure는 operation failure입니다. Empty backup list나 successful restore로 바꾸면 안 됩니다.

## 5. Guest datastore backup/restore 책임

### 5-1. Guest-owned PostgreSQL backup

Guest Control API `POST /runtime/maintenance/postgres-backup`은 `pg_dump --format=custom`으로 `vitalserver` database 전체를 한 snapshot으로 생성합니다. Dump를 `pg_restore --list`로 읽을 수 있어야 하고, 고정 database name, PostgreSQL version, 단일 Alembic revision, dump format/file, size, checksum이 담긴 manifest와 함께 archive를 만든 뒤에만 operation을 completed로 전이합니다.

Redis와 PostgreSQL backup operation은 각각 독립적인 receipt를 제공합니다. 현재 product backup은 두 receipt를 순서대로 수집하며, 두 datastore 사이의 distributed transaction 또는 같은 시점의 atomic snapshot을 주장하지 않습니다. 하나라도 실패하면 VitalServer backup은 생성되지 않습니다.

두 backup POST는 Guest가 archive 생성과 operation terminal document 저장을 마친 뒤 응답합니다. Host Guest Control adapter는 일반 상태 조회의 5초 timeout을 이 경계에 재사용하지 않고, Redis/PostgreSQL backup에 각각 명시적인 900초 request timeout을 사용합니다. 이 값은 무기한 대기나 성공 fallback이 아닙니다. 900초 안에 terminal operation document를 받지 못하면 transport failure로 중단하며, archive나 로그 존재로 성공을 추정하지 않습니다.

Host는 두 maintenance archive를 VitalServer backup 안에 복사하고 최종 manifest와 checksum을 검증한 뒤, 이번 통합 backup operation이 만든 원본 archive만 삭제합니다. 최종 backup은 원본 archive cleanup 실패와 관계없이 보존되며, cleanup 실패는 `completedWithCleanupFailure`로 보고합니다. 최종 package 생성 또는 검증이 실패해도 이미 생성된 중간 archive cleanup을 시도하고 원래 실패를 유지합니다.

### 5-2. Guest-owned coordinated restore

Host는 선택한 Redis/PostgreSQL archive를 shared runtime data directory에 staging하고 Guest Control maintenance API에 guest mount path를 전달합니다.

PostgreSQL restore는 writer를 멈추기 전에 archive members, manifest, checksum과 custom dump readability를 검증합니다. 그 뒤 observation writer와 Compose stack을 정지하고 PostgreSQL만 올려 database를 교체합니다. Restore 후 단일 Alembic revision이 manifest와 같아야 성공입니다. Schema/object readiness는 migrator와 각 repository의 startup verification이 소유합니다.

VitalServer backup restore에서 Host는 `restartRuntime=false`를 명시합니다. 따라서 PostgreSQL 복원 후 writer는 계속 멈춰 있고, 다음 Redis restore가 Redis volume을 교체한 뒤 전체 Compose stack과 observation writer를 한 번만 시작합니다. PostgreSQL operation result의 `runtimeRestarted=false` proof가 없으면 Host는 복원을 성공으로 처리하지 않습니다.

### 5-3. Capability failure

`maintenance:postgres-backup:create`, `maintenance:postgres-restore:create`, `maintenance:redis-backup:create`, `maintenance:redis-restore:create` 중 필요한 capability를 보고하지 않는 Guest는 VitalServer backup 또는 restore를 완료할 수 없습니다. Host는 Guest datastore internals를 추정하지 말고 capability/operation failure를 명시적으로 보고해야 합니다.

### 5-4. 실제 Compose restore proof

다음 target은 Guest Compose PostgreSQL에 실제 migration과 대표 데이터를 적용하고, custom dump를 새 database에 restore한 뒤 세 owner schema의 JSON read와 Alembic revision이 동일한지 비교합니다.

```bash
make runtime/proof/postgres-restore
```

이 proof는 전용 Compose project와 volume을 만들고 종료 시 삭제합니다. Guest Compose의 PostgreSQL host port를 사용하므로 실행 중인 runtime과 동시에 실행하지 않습니다.

### 5-5. 명시적 제외 범위

VitalServer backup은 `.vital` 업로드/cold-path 파일, runtime log, VM disk image를 포함하지 않습니다. `.vital` 파일은 ingress와 cold-path가 구분된 각 owner 정책을 따르고, VM disk repair archive는 VitalServer backup과 다른 recovery artifact입니다. 이 파일들의 존재를 PostgreSQL이나 backup manifest에서 추정하지 않습니다.

## 6. Troubleshooting

### 6-1. `redis-data` 누락으로 backup 생성 실패

증상:

```text
required runtime data backup artifact is missing id=redis-data path=/mnt/tirosh/backups/redis/<archive>.tar.gz
```

원인: Guest Control Redis backup operation result는 guest mount namespace 기준 archive path (`/mnt/tirosh/...`)를 보고합니다. Host backup store는 macOS filesystem을 읽으므로, archiving 전에 이 path를 명시적인 shared data directory contract를 통해 변환해야 합니다.

수정 방향: Redis archive를 `RuntimeDataBackupStore.createBackup`에 넘기기 전에 `/mnt/tirosh/<relative>`를 `<installed data directory>/<relative>`로 변환합니다.

예방 원칙: Host는 guest-reported path를 명시 mount contract를 통해서만 소비해야 합니다. Guest absolute path를 Host path로 취급하거나 filename으로 equivalent location을 추정하면 안 됩니다.
