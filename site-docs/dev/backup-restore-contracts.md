# Backup/Restore 계약

이 문서는 Vital Server Helper의 backup/restore 구현 계약을 정리합니다.
Release `usage.md`는 운영자가 눌러야 하는 메뉴와 판단 순서를 다루고, 이 문서는 artifact 구성, data schema owner, backup-level restore compatibility, migration tool의 구현 기준을 다룹니다.

## 1. 제품 표면

| 제품 표면                                | 내부 operation                  | 사용 목적                                                                                |
| ---------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------- |
| VitalServer backup                       | `runtime-data-backup`           | Helper가 관리하는 runtime state와 Guest Redis data를 하나의 복구 단위로 backup/restore   |
| Automatic VitalServer backup             | Host launchd `automatic-backup` | Settings schedule에 따라 VitalServer backup을 자동 생성하고 보관 개수를 적용             |
| Redis-only recovery                      | Redis backup/restore request    | VM disk repair, uninstall, migration, 장애 분석처럼 Redis data만 분리해야 하는 고급 조치 |
| Existing VitalServer data import command | Troubleshooting Tools command   | 기존 VitalServer data directory를 Helper Redis-only import archive로 변환                |

일반 운영자는 VitalServer backup을 사용합니다. Redis-only recovery는 전체 runtime 상태를 되돌리는 기능이 아니라 Redis data만 바꾸는 repair 기능입니다.

자동 backup도 Redis-only archive가 아니라 VitalServer backup을 생성합니다. Host launchd job `ai.tirosh.vitalserver.helper.automatic-backup`이 Settings의 `automaticBackupEnabled`, `backupScheduleTimes`, `backupRetentionCount`를 source of truth로 사용합니다. Schedule은 macOS local time `HH:mm` 값이며, Helper app process가 실행 중인지에 의존하지 않아야 합니다.
Schedule time은 system timezone 기준으로 표시해야 하고, `03:15`, `15:15`처럼 24-hour `HH:mm` format만 허용합니다. 유효 범위는 `00:00`부터 `23:59`까지이며, 같은 schedule time을 중복 저장하면 안 됩니다.

Automatic backup command는 실행 시점에 runtime operation lease를 acquire합니다. 다른 mutating runtime operation이 active이면 실패 상태를 만들지 않고 해당 run을 skipped로 기록합니다.
Backup 생성 성공 후 `backups/vitalserver-helper` 아래의 오래된 VitalServer backup directory를 `backupRetentionCount`에 맞춰 제거합니다. Retention은 Redis-only archive에는 적용하지 않습니다.

## 2. Runtime Data Backup Artifact

VitalServer backup은 하나의 restore unit이지만 artifact마다 schema owner가 다릅니다.

| Artifact                         | Owner | Schema owner                                | Restore 대상                                     |
| -------------------------------- | ----- | ------------------------------------------- | ------------------------------------------------ |
| `redis-data`                     | Guest | VitalServer Redis key/value layout          | guest `redis-restore`를 통한 Redis Docker volume |
| `runtime-vm-config`              | Host  | VM runtime config contract                  | 설치된 VM config document                        |
| `guest-runtime-config`           | Host  | Guest deploy/runtime config contract        | 배포된 guest runtime config document             |
| `guest-runtime-settings`         | Host  | Runtime settings contract                   | runtime settings document                        |
| `proxy-launch-daemon-settings`   | Host  | macOS launchd plist contract                | proxy LaunchDaemon plist                         |
| `start-on-boot-state`            | Host  | `RuntimeDataBackupStartOnBootStateDocument` | launchctl enabled/disabled state                 |
| `runtime-status-document`        | Host  | Host diagnostics/status projection document | optional diagnostics/export context              |
| `runtime-events-document`        | Host  | Host runtime event JSONL contract           | optional diagnostics/export event history        |
| `runtime-observability-database` | Host  | SQLite observability projection schema      | optional diagnostics/migration projection snapshot |

Required recovery artifact는 Redis data, VM config, guest config, guest settings, proxy LaunchDaemon settings, start-on-boot state입니다. Status, events, observability SQLite는 optional diagnostics/export artifact입니다. Backup에 없으면 restore는 대체 current state를 만들지 않고 required artifact만 복원합니다. Restore된 status projection은 Runtime Control current `runtimeState`, `failureReasons`, active operation, workflow progress, service liveness, HTTP probe, VM IP, VM lifecycle, runtime version, latest backup owner가 아닙니다.

## 3. Compatibility Gate

Restore는 runtime destination에 artifact를 쓰기 전에 `RuntimeDataBackupManifest.restoreCompatibilityVersion`을 확인해야 합니다.

Restore compatibility version은 backup unit 전체의 restore 계약입니다. 제품 `runtimeVersion`과 같은 의미가 아니고, artifact마다 따로 관리하는 schema version도 아닙니다.
Product version은 운영자 context를 위해 기록하지만, restore는 product version, filename, artifact 존재 여부, checksum 성공만으로 compatibility를 추정하면 안 됩니다.

Restore는 아래 경우 backup을 거부합니다.

- `restoreCompatibilityVersion`이 없음
- 현재 Helper가 선언된 compatibility version을 지원하지 않음
- manifest schema, product, artifact identity validation 실패
- required artifact state, path, size, checksum validation 실패

오래된 backup을 지원해야 한다면 restore가 파일을 쓰기 전에 명시 migration을 구현해야 합니다. Restore flow는 artifact 일부를 적용한 뒤 나중에 다른 artifact가 incompatible하다는 사실을 발견하면 안 됩니다.

이 문서가 도입된 compatibility baseline 이전 backup은 지원하지 않습니다. Legacy runtime-data backup kind/path/manifest를 추정해서 읽는 fallback을 추가하지 않습니다. 이후 버전에서 하위호환이 필요하면 새 baseline의 `restoreCompatibilityVersion`을 기준으로 명시 migration을 작성합니다.

## 4. Compatibility Version을 올리는 기준

이전 backup을 현재 runtime이 migration 없이 안전하게 restore할 수 없으면
`RuntimeDataBackupCompatibility.currentRestoreCompatibilityVersion`을 올립니다.

대표적인 bump 기준은 아래와 같습니다.

- 현재 VitalServer가 old Redis data를 읽을 수 없을 정도로 Redis key/value layout이 변경됨
- VM config, guest runtime config, guest runtime settings에서 required field가 제거되거나 의미가 변경됨
- start-on-boot service label 또는 launchd plist 의미가 호환되지 않게 변경됨
- `runtime-observability.sqlite` schema 변경으로 restored snapshot이 현재 read-only query path에서
  안전하지 않거나 읽을 수 없음

명시적인 missing-state 처리로 복원 가능한 additive optional field 때문에 compatibility version을 올리면 안 됩니다. Missing, invalid, failed, stale, zero, empty는 서로 다른 의미로 유지해야 합니다.

## 5. Redis-only와 Existing Data Import

Redis-only backup/restore는 Guest-owned 작업입니다. Host는 archive를 staging하거나 선택하고, typed request를 쓰고, typed result를 기다린 뒤 capability/read failure를 명시적으로 보고합니다.
Host는 filename, log, Docker volume path로 Redis 내부 상태를 추정하지 않습니다.

DMG Troubleshooting Tools의 existing VitalServer data import command는 기존 VitalServer Redis data를 migration하기 위한 helper입니다. 이 command는 기존 VitalServer data directory를 입력받아 Helper import용 `redis-upstream-import.tar.gz`를 만듭니다.

Command는 archive를 만들기 전에 bundled Redis tooling으로 `SAVE`를 실행할 수 있습니다. `SAVE`는 Redis를 중지하지 않지만 `dump.rdb`를 쓰는 동안 Redis를 잠깐 block할 수 있습니다. 자동 refresh를 기다리되 무기한 대기하면 안 됩니다. Command는 기본 15초 timeout 안에 SAVE가 끝나지 않으면 실패로 중단하고 helper process를 종료합니다.
자동 refresh를 건너뛰면 운영자는 data directory를 선택하기 전에 기존 VitalServer Redis에서 `SAVE`/`BGSAVE`를 실행하거나 Redis를 중지해 `dump.rdb`가 최신인지 확인해야 합니다.

생성된 data import archive는 Advanced -> Recovery operations -> Redis-only recovery -> Import Backups로 가져온 뒤 Restore Redis-only Backup으로 복원합니다.

Troubleshooting Tools command log는 현재 사용자 temp directory에 남깁니다.

| Command                          | Log                                            |
| -------------------------------- | ---------------------------------------------- |
| Reset for Reinstall              | `tirosh-vitalserver-reset-for-reinstall.log`   |
| Existing VitalServer data import | `tirosh-vitalserver-upstream-redis-backup.log` |

## 6. 문서화 규칙

Backup/restore 동작이 바뀌면 아래 문서를 함께 갱신합니다.

- release usage 문서: 운영자가 보는 메뉴, 결과, 실패 안내
- 이 dev 계약 문서: schema owner, compatibility, migration 의미

반복되는 restore failure는 symptom, cause, fix direction, prevention을 갖춘 troubleshooting 문서로
승격합니다. Restore 실패가 UI progress/message에 표시되지 않는 failure pattern은
[TS-079](https://github.com/tirosh-chain/tirosh-vitalserver/blob/main/docs/troubleshooting/079_runtime-data-restore-silent-failure.md)에 기록합니다.
