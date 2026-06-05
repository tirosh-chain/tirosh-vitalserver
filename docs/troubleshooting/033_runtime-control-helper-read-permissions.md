# 033 Runtime Control Helper가 설정/로그/event를 읽지 못함

> ID: TS-033  
> Category: Runtime Control PWA / Observability  
> Owner: macOS runtime / packaging  
> Status: active

## Symptoms

VitalServer Helper 또는 Remote Console에서 아래 증상이 함께 나타납니다.

- Settings에 `guestRuntimeConfig: The file "runtime-config.json" couldn't be opened because you don't have permission to view it.`가 표시됩니다.
- Logs > Export logs가 실패합니다.
- Logs > Helper message가 최신 메시지만 보이고 이전 메시지는 사라집니다.
- Observability > Runtime Events가 `0 events` 또는 `No runtime events`로 표시됩니다.
- Recorders > Activity에 `attempt to write a readonly database`가 포함된 `Recorder activity history is incomplete`가 표시됩니다.

정상 상태라면 Settings는 guest runtime exposure 값을 읽고, Export logs는 host/guest diagnostic archive를 생성하며, Observability는 최근 watchdog/runtime command event를 표시해야 합니다.

## Impact

Runtime 자체가 곧바로 중단되는 증상은 아닐 수 있습니다. 다만 운영자가 runtime 상태를 확인하거나 support bundle을 만들 수 없고, 실제 event가 있음에도 Remote Console이 비어 보이므로 장애 원인 판단이 어려워집니다.

Settings의 read issue는 network exposure, Redis backup retention 같은 일부 값이 UI에서 stale/default처럼 보일 수 있습니다. Export logs 실패는 현장 로그 수집을 막습니다. Observability event 0건 표시는 runtime event persistence 실패와 runtime event read 실패를 구분하지 못하게 만듭니다.

## Cause

원인은 두 권한 경계가 섞인 것입니다.

첫 번째 원인은 guest deploy config의 역할 충돌입니다. `/Library/Application Support/TiroshVitalServer/vm/data/deploy/runtime-config.json`에는 `publicHost`, `publicPort`처럼 Helper가 읽어야 하는 설정과 `adminPassword` 같은 secret이 같이 들어갑니다. 설치/설정 flow는 이 파일을 쓴 뒤 `chmod 0600`으로 제한합니다.

```text
-rw------- root:wheel /Library/Application Support/TiroshVitalServer/vm/data/deploy/runtime-config.json
```

따라서 사용자 권한으로 실행되는 Helper는 이 파일을 읽지 못합니다. Settings는 이 read 실패를 `readIssues`로 노출합니다. Export logs도 같은 파일을 supplemental diagnostic item으로 복사하려다 실패할 수 있습니다.

두 번째 원인은 observability SQLite 조회가 pure read가 아니라는 점입니다. `/Library/Application Support/TiroshVitalServer/status/runtime-observability.sqlite`와 `runtime-events.jsonl`에 event가 있어도, Runtime Control API의 event query는 SQLite secondary index를 사용합니다. SQLite query path는 `initialize()`와 catch-up을 먼저 수행하면서 schema migration/index state write를 시도할 수 있습니다.

같은 DB를 사용하는 VitalDB observation/recorder activity/relationship 조회도 `initialize()`를 먼저 호출하면 read 요청이 schema write를 시도합니다. 사용자 권한 Helper가 root-owned DB 또는 status directory에 write할 수 없으면 SQLite가 `attempt to write a readonly database`를 반환합니다. 이 실패를 빈 event/activity list로 숨기면 실제 data가 있어도 Remote Console에는 0건 또는 불완전한 history처럼 보입니다.

세 번째 원인은 Helper message가 실제 로그가 아니라 UI state였다는 점입니다. macOS Helper의 `message` 값은 하나의 현재 상태 문자열이고, Remote Console은 `helperMessage=""`를 보내므로 이전 메시지를 조회할 source가 없었습니다. 따라서 Helper message를 Logs 탭에 노출하려면 host-visible append-only log file이 별도로 필요합니다.

## Checks

설정 파일 권한을 확인합니다.

```sh
stat -f '%Sp %Su:%Sg %N' \
  "/Library/Application Support/TiroshVitalServer/vm/data/deploy/runtime-config.json"
```

일반 사용자 권한으로 읽기 실패가 재현되는지 확인합니다.

```sh
head -c 20 \
  "/Library/Application Support/TiroshVitalServer/vm/data/deploy/runtime-config.json"
```

event가 실제로 기록되어 있는지 확인합니다.

```sh
wc -l \
  "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl"

sqlite3 \
  "/Library/Application Support/TiroshVitalServer/status/runtime-observability.sqlite" \
  'select count(*), min(timestamp), max(timestamp) from runtime_events; select count(*) from vitaldb_observation_snapshots; select count(*) from vitaldb_recorder_activity_buckets;'
```

SQLite가 사용자 권한에서 read-write 초기화에 실패하는지 확인합니다.

```sh
sqlite3 \
  "/Library/Application Support/TiroshVitalServer/status/runtime-observability.sqlite" \
  "INSERT OR IGNORE INTO runtime_event_index_state(key,value) VALUES ('permission_probe','0');"
```

`attempt to write a readonly database`가 나오면 Observability 0건은 event 미생성이 아니라 read path 권한 실패일 가능성이 큽니다.

Export logs가 중앙 로그 refresh에서 막히는지도 확인합니다.

```sh
touch \
  "/Library/Application Support/TiroshVitalServer/logs/guest/container-logs.log"
```

`Operation not permitted`가 나오면 사용자 권한 Helper가 root-owned central log를 갱신할 수 없는 상태입니다.

## Actions

현장 임시 조치와 제품 수정 방향을 분리합니다.

현장 임시 조치:

1. support bundle이 급하면 root 권한으로 필요한 로그와 status 파일을 직접 수집합니다.
2. `runtime-config.json`의 권한을 무작정 `644`로 풀지 않습니다. 현재 파일에는 `adminPassword`가 포함될 수 있습니다.
3. Observability 0건이면 JSONL/SQLite row count를 먼저 확인해 event 미생성인지 read 실패인지 구분합니다.

제품 수정 방향:

1. `runtime-config.json`에서 secret과 Helper-readable 설정을 분리합니다.
2. Helper가 읽는 Settings source는 secret-free read model이어야 합니다.
3. Export logs는 root-only supplemental file을 읽지 못해도 전체 export를 실패시키지 말고, manifest에 `sourcePresent=true`, `included=false`, `error=<reason>` 형태로 남깁니다. secret file은 redacted copy만 포함합니다.
4. Log collection refresh는 사용자 권한 Helper가 root-owned central logs를 touch/copy하지 않도록 privileged launcher에 위임하거나 read-only export path와 분리합니다.
5. SQLite runtime event/VitalDB observation/recorder activity/relationship query는 read-only connection/path를 제공해야 합니다. 조회 중 schema migration, catch-up, index state write를 시도하면 안 됩니다.
6. SQLite query 실패 시 JSONL primary fallback을 사용하거나, 최소한 `readError`를 API/UI에 노출합니다. 빈 event/activity list로 실패를 숨기면 안 됩니다.
7. Helper message는 UI state가 아니라 append-only helper message log를 source of truth로 읽습니다. 현재 UI message를 API request parameter로 재전송해 로그처럼 취급하지 않습니다.

## Prevention

설치물이 생성하는 host-visible 파일은 권한과 데이터 등급을 같이 설계해야 합니다.

- secret-bearing file: root-only, Helper 직접 read 금지
- Helper read model: secret-free, user-readable 또는 Helper-owned
- runtime write store: root/service-owned, read API는 read-only path 제공
- helper message log: Helper-owned append-only file, Logs 탭은 file tail만 표시
- support bundle: best-effort collection과 redaction manifest 제공

읽기 API에서 `initialize`, migration, catch-up, projection rebuild 같은 쓰기 작업을 암묵 수행하지 않습니다. 쓰기가 필요한 유지보수는 watchdog/launcher 같은 owner process가 수행하고, Helper/Remote Console read path는 실패를 명시적으로 드러냅니다.

## Operational Notes

이 증상은 Settings, Export logs, Observability가 동시에 깨져 보여도 하나의 단일 API 장애가 아닐 수 있습니다.

- Settings/Export logs는 `runtime-config.json`과 central log 권한 문제일 가능성이 큽니다.
- Observability 0건은 event 생성 실패보다 SQLite read path의 write 시도 및 실패 은닉을 먼저 의심합니다.
- `runtime-events.jsonl`과 `runtime-observability.sqlite`에 최근 event가 있으면 runtime watchdog/event recorder는 동작 중입니다.

## Related Cases

- `TS-026`: PWA가 Runtime Control API unreachable 표시
- `TS-030`: Runtime 상태를 Host/UI가 추정하거나 암묵 보정함
- `TS-031`: Recorder activity 그래프가 rolling window만 표시

## Follow-up

- 2026-05-30: VitalServer Helper 실행 중 Settings read issue, Export logs 실패, Observability event 0건 증상을 등록했습니다.
- 2026-05-30: 설치 경로에서 `runtime-config.json`이 `root:wheel 0600`임을 확인했습니다. 파일은 secret과 Helper-readable 설정을 동시에 포함합니다.
- 2026-05-30: `runtime-events.jsonl`과 `runtime-observability.sqlite`에는 최근 runtime event가 존재하므로 event 미생성이 아니라 read path 문제로 분리했습니다.
- 2026-05-30: 사용자 권한 SQLite write probe가 `attempt to write a readonly database`로 실패하는 것을 확인했습니다.
- 2026-05-30: Helper가 `runtime-settings.json` secret-free read model을 우선 읽도록 수정하고, install/configure/update migration이 이 파일을 생성하도록 보강했습니다.
- 2026-05-30: Export logs는 refresh/supplemental read 실패를 manifest issue로 기록하고 가능한 로그를 계속 export하도록 수정했습니다.
- 2026-05-30: SQLite event query 실패 시 JSONL primary event store로 fallback하도록 수정했습니다.
- 2026-05-31: Runtime Events뿐 아니라 Recorders/Activity/Relationships read path도 SQLite를 read-only로 열도록 hotfix 범위를 확장했습니다. Remote Console 조회는 projection catch-up, schema init, migration을 수행하지 않습니다.
- 2026-05-31: Helper message가 실제 로그로 남지 않고 현재 UI message 문자열만 표시하던 구조를 확인했습니다. `tirosh-vitalserver-helper-message.log` append-only source를 추가하고 Logs 탭/Export logs가 이 파일을 읽도록 수정했습니다.
