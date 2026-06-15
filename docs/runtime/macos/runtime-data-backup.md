# VitalServer Backup

VitalServer backup은 Helper가 관리하는 VitalServer 상태를 복구하기 위한 사용자-facing 계약입니다.
내부 command와 API 이름은 `runtime-data-backup`이지만, 제품 UI에서는 하나의 VitalServer backup으로
표시해야 합니다. 이 backup은 Host runtime state와 Guest Redis data를 함께 포함하기 때문입니다.

macOS Helper는 Advanced -> Recovery operations -> VitalServer backup에서 이 계약을 제공합니다.
사용자는 Create VitalServer Backup과 Restore VitalServer Backup action을 사용합니다. Restore는
Host가 제공한 backup 목록에서 명시적으로 선택한 VitalServer backup이 있어야 진행됩니다.

자동 backup도 같은 VitalServer backup 계약을 사용합니다. Host launchd job
`ai.tirosh.vitalserver.helper.automatic-backup`이 Settings의 `automaticBackupEnabled`,
`backupScheduleTimes`, `backupRetentionCount`를 읽고 `runtime automatic-backup` command를 실행합니다.
이 command는 Helper app process가 떠 있는지와 무관하게 동작해야 하며, active runtime operation lease가
있으면 해당 run을 skipped로 기록합니다.

`backupRetentionCount`는 `backups/vitalserver-helper` 아래의 VitalServer backup directory 보관 개수입니다.
Redis-only archive 보관 개수가 아니며, Redis-only recovery/migration archive에는 적용하지 않습니다.

VitalServer backup archive는 Host product root의
`/Library/Application Support/VitalServerHelper/backups/vitalserver-helper/` 아래에 저장합니다.
이 버전부터 이 path와 manifest `backupKind=vitalserver-helper`가 compatibility baseline입니다.
이전 `runtime-data` kind/path를 추정해서 읽는 fallback은 두지 않습니다.

VitalServer backup 삭제는 Danger Zone의 Delete VitalServer Backup으로 분리합니다. 이 작업은
Host가 보고한 VitalServer backup directory의 direct child만 삭제합니다. Update/rollback backup 삭제는
별도 Delete Update Backup action이며, UI copy가 두 대상의 차이를 숨기면 안 됩니다.

Redis-only backup/restore는 고급 repair 기능입니다. Surgical recovery나 repair workflow에는 유용하지만
기본 product backup model은 아닙니다. 일반 사용자는 runtime archive와 Redis archive를 따로 조합하지
말고 하나의 VitalServer backup을 만들고 복원해야 합니다.

필수 artifact:

| Artifact | Owner | Restore 대상 |
|---|---|---|
| `redis-data` | Guest | 명시적인 guest `redis-restore` request/result를 통한 Redis Docker volume |
| `runtime-vm-config` | Host | 설치된 VM config document |
| `guest-runtime-config` | Host | 배포된 guest runtime config document |
| `guest-runtime-settings` | Host | runtime settings document |
| `proxy-launch-daemon-settings` | Host | proxy LaunchDaemon plist |
| `start-on-boot-state` | Host | managed service의 launchctl enabled/disabled state |
| `runtime-status-document` | Host | Host runtime status document *(optional: 없으면 skip)* |
| `runtime-events-document` | Host | Host runtime event document *(optional: 없으면 skip)* |
| `runtime-observability-database` | Host | `runtime-observability.sqlite` snapshot *(optional: 없으면 skip)* |

Restore process는 `runtime-status-document`, `runtime-events-document`,
`runtime-observability-database`를 best-effort artifact로 취급합니다. Backup에 없으면 restore는
기존 Host-side file을 유지하고 required artifact만 복원합니다.

## Artifact Schema 소유권

VitalServer backup은 하나의 restore unit이지만 artifact마다 data schema owner가 다릅니다.
Backup manifest는 artifact identity, path, size, checksum, backup-level
`restoreCompatibilityVersion`을 기록합니다. Manifest가 모든 artifact를 하나의 file format으로
합치거나 artifact별 compatibility version을 관리하는 것은 아닙니다.

| Artifact | Data schema owner | Restore compatibility 기준 |
|---|---|---|
| `redis-data` | Guest VitalServer Redis schema | Guest Redis restore worker가 복원합니다. 현재 Guest runtime이 읽을 수 없는 Redis key/value layout 변경은 backup-level `restoreCompatibilityVersion` bump 또는 명시 migration이 필요합니다. |
| `runtime-vm-config` | Host VM runtime config contract | Host가 VM start 전후에 읽습니다. Breaking config change는 restore 전 compatibility bump 또는 config migration이 필요합니다. |
| `guest-runtime-config` | Guest deploy/runtime config contract | Host가 배포하고 Guest bootstrap/service가 소비합니다. Breaking field change는 compatibility bump 또는 migration이 필요합니다. |
| `guest-runtime-settings` | Runtime settings contract | Host UI와 Guest runtime이 함께 소비합니다. Settings schema 변경은 missing/invalid/default 의미를 명시적으로 보존해야 합니다. |
| `proxy-launch-daemon-settings` | macOS launchd plist contract | Host LaunchDaemon setup이 소비합니다. Service label/path 의미가 깨지는 변경은 compatibility review가 필요합니다. |
| `start-on-boot-state` | Host generated start-on-boot state document | 현재 schema는 `RuntimeDataBackupStartOnBootStateDocument.schemaVersion`입니다. Restore는 service state를 추정하지 말고 unsupported document schema를 거부해야 합니다. |
| `runtime-status-document` | Host runtime status document | Optional UI continuity artifact입니다. Missing은 unavailable을 뜻하며 restore는 status를 합성하지 않습니다. Breaking status schema는 skip하거나 backup compatibility로 gate해야 합니다. |
| `runtime-events-document` | Host runtime event JSONL contract | Optional observability continuity artifact입니다. Decode/schema change를 empty event list로 숨기면 안 됩니다. |
| `runtime-observability-database` | Host SQLite observability projection schema | Optional UI continuity artifact입니다. SQLite schema change가 old snapshot을 unreadable하게 만들 수 있으므로, 현재 Helper가 DB를 열기 전에 gate 또는 migration이 필요합니다. |

## Compatibility 계약

VitalServer backup restore는 `RuntimeDataBackupManifest.restoreCompatibilityVersion`으로 gate합니다.
현재 Helper는 backup 생성 시 `RuntimeDataBackupCompatibility.currentRestoreCompatibilityVersion`을
씁니다. Restore는 아래 경우 backup을 거부합니다.

- manifest에 `restoreCompatibilityVersion`이 없음
- manifest가 현재 Helper가 지원하지 않는 version을 선언함
- manifest schema, product, required artifact set, artifact state, size, checksum,
  relative artifact path validation 실패

Restore compatibility version은 backup unit 전체의 restore 계약이며 product version string이 아닙니다.
`runtimeVersion`은 운영자 context를 위해 계속 기록하지만 restore compatibility의 유일한 판단 기준이
되어서는 안 됩니다. Product version과 restore compatibility version은 서로 다른 속도로 움직일 수 있습니다.

### `restoreCompatibilityVersion`을 올리는 기준

이전 format으로 만든 backup을 현재 runtime이 명시 migration 없이 안전하게 restore할 수 없으면
restore compatibility version을 올립니다. 예시는 아래와 같습니다.

- 현재 VitalServer가 old data를 읽을 수 없을 정도로 Redis key/value layout이 변경됨
- `runtime-vm-config`, `guest-runtime-config`, `guest-runtime-settings`에서 required field가 제거되거나
  의미가 바뀜
- `runtime-observability.sqlite` schema 변경으로 restored snapshot이 unreadable하거나 read-only query
  path에서 unsafe함
- launchd service label 또는 start-on-boot state 의미가 호환되지 않게 바뀜

명시적인 missing-state 처리로 restore 가능한 additive optional field 때문에 compatibility version을
올리면 안 됩니다. Missing, invalid, failed, stale, zero, empty는 서로 다른 의미로 유지해야 합니다.

오래된 compatibility version을 지원해야 한다면 restore가 runtime destination에 file을 쓰기 전에
명시 migration path를 추가합니다. Restore가 일부 artifact를 적용한 뒤 나중에 다른 artifact가
incompatible하다는 사실을 발견하면 안 됩니다.

이 compatibility baseline 이전의 legacy backup은 지원하지 않습니다. Restore는 legacy kind, legacy
directory name, missing compatibility field를 추정해서 받아들이지 않습니다.

Backup creation은 manifest를 마지막에 씁니다. Restore는 missing, duplicated, non-archived,
unchecked, size-mismatched, checksum-mismatched, path-escaping, compatibility-incompatible artifact를
거부해야 합니다. Missing backup directory, decode failure, permission failure, guest capability failure,
guest result read failure는 operation failure입니다. Empty backup list나 successful restore로 바꾸면
안 됩니다.

Redis restore는 Guest-owned입니다. Host는 선택한 archive를 shared runtime data directory에 staging하고
`redis-restore.request`를 씁니다. Guest command poller는 `tirosh-vitalserver-redis-restore.service`를
dispatch하고, 이 service는 archive를 검증하고 Docker Compose를 stop한 뒤 Redis volume contents를
교체하고 Compose를 start한 다음 `redis-restore-result.json`을 씁니다.

`redisRestore` capability를 보고하지 않는 오래된 Guest는 runtime data restore를 완료할 수 없습니다.
Host는 Redis volume internals를 추정하지 말고 capability failure를 명시적으로 보고해야 합니다.

## Troubleshooting

### `redis-data` 누락으로 backup 생성 실패

증상:

```text
required runtime data backup artifact is missing id=redis-data path=/mnt/tirosh/backups/redis/<archive>.tar.gz
```

원인: Guest의 `redis-backup-result.json`은 guest mount namespace 기준 archive path
(`/mnt/tirosh/...`)를 보고합니다. Host backup store는 macOS filesystem을 읽으므로, archiving 전에 이
path를 명시적인 shared data directory contract를 통해 변환해야 합니다.

수정 방향: Redis archive를 `RuntimeDataBackupStore.createBackup`에 넘기기 전에
`/mnt/tirosh/<relative>`를 `<installed data directory>/<relative>`로 변환합니다.

예방 원칙: Host는 guest-reported path를 명시 mount contract를 통해서만 소비해야 합니다.
Guest absolute path를 Host path로 취급하거나 filename으로 equivalent location을 추정하면 안 됩니다.
