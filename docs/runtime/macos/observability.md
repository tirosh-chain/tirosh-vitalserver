# Runtime observability model

이 문서는 macOS VM runtime의 status, event, log, index 수집 책임을 정리합니다. 목표는 `runtime-status.json`, `runtime-events.jsonl`, SQLite read model, container logs, recorder ingress event가 서로 다른 용도로 존재하더라도 제품 관점에서 어디를 믿고, 어디를 API로 노출할지 명확하게 만드는 것입니다.

## 1. 현재 관찰된 파편화

Host Swift runtime 쪽은 타입과 계약이 비교적 명확합니다.

| 데이터 | 작성자 | 소비자 | 성격 |
|---|---|---|---|
| `status/runtime-status.json` | HostCLI workflow, watchdog | diagnostics, export, troubleshooting | Host diagnostics/status projection artifact |
| `status/runtime-progress.json` | HostCLI workflow | diagnostics, export, troubleshooting | Host workflow progress diagnostics/export artifact |
| `status/runtime-events.jsonl` | watchdog 관측 경로 | diagnostics, export, Runtime Control backing read | operational event diagnostics/backing artifact |
| `status/runtime-observability.sqlite` | host observability indexer | Runtime Control API | 조회용 read model/index; read failure remains explicit |
| `logs/command.log`, `logs/runtime/*` | HostCLI, launchd | Helper Logs, export logs | 진단용 raw log |

Guest/container 쪽은 목적이 다른 자료가 병렬로 있습니다.

| 데이터 | 작성자 | 소비자 | 성격 |
|---|---|---|---|
| `vm/data/run/runtime-observation.json` | guest `tirosh-runtime-observation` | host diagnostics, VM/resource status | guest OS/resource 스냅샷. Product service state SoT가 아님 |
| `vm/data/run/guest-observability/latest.json` | guest `tirosh-guest-observed` | Helper Logs, export logs | guest OS 진단 스냅샷 |
| `vm/data/run/guest-observability/snapshots/*` | guest `tirosh-guest-observe` | Helper Logs, export logs | phase별 one-shot 진단 |
| `vm/data/run/container-logs.log` | guest `tirosh-guest-container-logs` | Helper Logs, export logs | `docker compose logs --follow` 수집본 |
| `/var/log/vitalserver-audit/audit-events.log` | `vitalserver-recorder-ingress` | guest/operator diagnostics | command audit 원본 파일 로그 |
| `vm/data/run/recorder-ingress-failures/send-data-failures.jsonl` | `vitalserver-recorder-ingress` | guest/operator diagnostics | `send_data` spool/replay terminal failure evidence |
| `vm/data/run/recorder-ingress-raw/send-data-raw.jsonl` | `vitalserver-recorder-ingress` | `.vital` recovery source | `send_data` 원본 compressed payload append-only archive |
| recorder ingress stdout | `vitalserver-recorder-ingress` | container log collector | collector 호환 raw event log |
| Redis List `vitalserver:audit_events` | `vitalserver-recorder-ingress` | 운영 조회/디버깅 | Redis 3.2 호환 보조 조회 sink |
| `/recorder-ingress/status` | `vitalserver-recorder-ingress` | Guest Control API, operator | recorder ingress runtime counters |
| `/api/runtime/observations` | `vitaldb-observer` | Guest/Postgres read model writer | VitalDB recorder/bed/anomaly snapshot |
| vitaldb-observer stdout JSONL | `vitaldb-observer` | container log collector, operator diagnostics | observer collection/readiness diagnostic history |
| `/run/tirosh/status/redis-relay-status.json` | `vitalserver-redis-relay` | Guest Control API, operator diagnostics | relay process/progress/error snapshot |

파편화의 핵심은 container 쪽 raw log/event가 여러 sink에 흩어져 있고, 어떤 자료가 제품 API의 canonical source인지 명확하지 않다는 점입니다.

## 2. 책임 원칙

### 2-1. 각 app/container

각 app과 container는 자기 상태와 raw event만 기록합니다.

- `vitalserver-recorder-ingress`는 command audit event를 생성합니다.
- `vitaldb-observer`는 Redis와 proxy/access log를 읽어 VitalDB observation snapshot을 계산합니다.
- `vitalserver-redis-relay`는 source Redis 3.2의 allowlisted key를 외부 target Redis로 publish하고, publish 진행과 target 오류를 status payload로 기록합니다.
- guest `tirosh-runtime-observation`는 guest HTTP/resource snapshot을 생성합니다.
- guest `tirosh-guest-observed`는 Linux guest OS의 진단 snapshot을 생성합니다.
- compose service와 container는 stdout/stderr에 raw log를 남깁니다.
- upstream VitalServer app은 제품 runtime event를 직접 알 필요가 없습니다.

`vitaldb-observer` observation의 `readIssues`는 Redis audit event, proxy/access log, bed JSON처럼 source별 read/parse 문제가 있었음을 나타냅니다. 관련 `readIssues`가 있는 빈 `proxyConnections`, 빈 activity, 또는 부분 recorder/bed snapshot은 실제 관측값 0과 같은 의미가 아닙니다. 반복되는 audit event parse 실패는 실패 원인과 event count를 보존한 bounded summary로 보고하여, 같은 결함이 observation payload와 UI 메시지를 무한히 키우지 않게 합니다. Recorder activity의 `roomCount`는 해당 버킷에서 받은 `send_data` payload들의 room entry 합계입니다. 이는 고유 room 수나 현재 연결된 room 수가 아니므로 기본 UI 판단 지표로 노출하지 않습니다. 필요할 때 API/diagnostics contract에서만 확인합니다.

각 app은 제품 전체 상태를 판단하지 않습니다.

Redis Relay의 Docker health는 relay process와 status writer가 살아 있는지를 나타냅니다. Target Redis 인증, 네트워크, atomic publish 실패는 container liveness로 숨기지 않고 relay status document의 `state`, `lastErrorAt`, `lastError`, `lastSuccessAt`, `batches`, `totals`로 드러냅니다. Relay container는 `/run/tirosh/status/redis-relay-status.json`을 diagnostics artifact로 쓰고 같은 document를 `PUT /runtime/redis-relay/status` owner mutation으로 publish합니다. Guest Control API의 `GET /runtime/redis-relay/status`는 Guest/Postgres owner snapshot에서 relay status read state와 document를 명시적으로 노출합니다. Client는 `/runtime/redis-relay/status` resource로 이 결과를 직접 읽으며 Host `RuntimeStatus`는 Redis Relay 상태를 조립하지 않습니다. `settingsFingerprint`는 password를 포함하지 않는 설정 계약 hash이며, Helper UI가 표시하는 target/scope 설정과 guest relay process가 실제로 읽은 설정이 같은지 확인하는 단서입니다.

| Redis Relay state | 의미 |
|---|---|
| `disabled` | 설정에서 relay가 꺼져 있음. 장애가 아님 |
| `running` | 마지막 batch가 error 없이 완료됨 |
| `running_with_errors` | process는 살아 있고 일부 key publish가 실패함. `lastErrorSamples` 확인 |
| `relay_failed` | batch 실행 전후 target/source connection 같은 relay operation이 실패함 |
| `config_invalid` | relay TOML을 읽었지만 필수 설정이 없거나 값이 invalid |

`running_with_errors`는 VitalServer traffic path 장애로 해석하지 않습니다. Relay target으로 보내는 외부 data path의 degraded 상태입니다. Target Redis consumer가 event를 처리하지 못하는 문제도 Helper가 추측하지 않고 consumer 쪽 pending/DLQ/decoder 상태에서 확인합니다.

### 2-2. Guest collectors

Guest collector는 수집만 담당합니다.

- `tirosh-guest-container-logs`는 `docker compose logs --follow`를 공유 디렉터리로 복사합니다.
- `tirosh-guest-observed`는 `guest-observability/latest.json`, `history.jsonl`, `events.jsonl`을 공유 디렉터리에 씁니다.
- `tirosh-guest-observe <phase>`는 shutdown/update/repair 같은 전이 지점의 one-shot snapshot과 raw command report를 씁니다.
- `tirosh-guest-diagnostics`는 operator용 one-shot diagnostic report를 출력합니다.
- collector는 로그를 해석하거나 status/event로 승격하지 않습니다.
- `container-logs.log`는 진단용 raw log로 유지합니다.
- `guest-observability` 산출물은 진단/export 자료이며 update 성공/실패 판단의 contract가 아닙니다.

Guest observability는 Guest tools Python wheel package의 `observability` 서브패키지로 배포합니다.

- package source: `packages/vitalserver-guest-tools`
- staged wheel: `deploy/python-wheels/tirosh_vitalserver_guest_tools-*.whl`
- guest venv: `/opt/tirosh/guest-tools/venv`
- daemon entrypoint: `/usr/local/bin/tirosh-guest-observed`
- one-shot entrypoint: `/usr/local/bin/tirosh-guest-observe`
- container log entrypoint: `/usr/local/bin/tirosh-guest-container-logs`
- diagnostics entrypoint: `/usr/local/bin/tirosh-guest-diagnostics`
- guest tools config: `/etc/tirosh/guest-tools.toml`
- systemd units: `Support/Guest/systemd/tirosh-guest-observability.service`, `Support/Guest/systemd/tirosh-vitalserver-container-logs.service`

이 경계가 중요합니다. Guest가 자기 내부 상태를 명시적으로 관측하고 파일로 제공합니다. Host는 그 파일을 수집하고 export하지만, marker나 snapshot 내용을 근거로 guest state를 추정하거나 update flow를 성공으로 바꾸지 않습니다.

### 2-3. Host watchdog

Watchdog은 관측, 정규화, 판단의 중심입니다.

Watchdog 관측 대상:

- VM/proxy/watchdog launchd state
- VM IP
- Guest Control readiness
- host proxy readiness/liveness
- Redis UI / Swagger UI HTTP status
- rootfs/vm disk file state
- bootstrap result/log proof for diagnostics and smoke validation
- proxy port listener conflict
- active managed operation guard
- recorder ingress health/status
- Guest Control API VitalDB read model read state

Watchdog은 raw source를 제품 관점 current read model/event/diagnostics projection으로 정규화합니다.

- Current runtime observation는 explicit owner reads에서 조립하고, diagnostics/status projection만 `runtime-status.json`에 게시합니다.
- 상태 전이와 주요 관측 결과는 `runtime-events.jsonl`에 append-only로 기록합니다.
- 조회가 필요한 event/index row는 SQLite read model에도 best-effort로 반영합니다.
- VitalDB observation snapshot의 product read model은 Guest/Postgres가 소유합니다.
- Host `runtime-observability.sqlite`의 `vitaldb_*` namespace는 migration/diagnostics evidence로만 남깁니다.
- 자동 복구 판단도 watchdog에서 수행합니다.

`runtime-status.json`의 최신 상태 반영은 Host diagnostics/status projection
게시입니다. Runtime Control current read model은 이 파일을 읽지 않습니다.
runtimeState/failureReasons, Host service liveness, HTTP probe, VM IP, VM
lifecycle state/errors는 각각 explicit current owner reads, live launchd read,
explicit probe read, Guest address provider, VM lifecycle read에서 가져옵니다.
Workflow progress는 RuntimeStatus current read model에 포함하지 않고, operation
detail은 PlatformOperationState/operation lease/API owner 계약에서 읽습니다.

### 2-4. Status, event, recovery decision

Watchdog은 현재 상태 판단과 과거 이력 기록을 분리합니다.

| 구분 | 의미 | SoT/Owner | 사용처 |
|---|---|---|---|
| SoT | 각 owner가 작성한 원본 상태/로그 | host runtime, guest worker, launchd | watchdog 입력 |
| Status projection | Host diagnostics/status projection | `status/runtime-status.json` | diagnostics/export context; not current runtimeState/failureReasons owner |
| Current health | Runtime Control current read model | explicit current owner reads | Helper UI, Runtime Control API runtimeState/failureReasons input |
| Progress | Host workflow progress diagnostics/export artifact | `status/runtime-progress.json` | diagnostics/export and troubleshooting; not Runtime Control current read model or health owner |
| Active operation guard | recovery suppression에 필요한 현재 operation owner contract | Host operation lease | watchdog guard |
| Event | 의미 있는 상태 변화와 판단 이력 | Runtime Control `/runtime/events` API + `RuntimeEventHistory` read model contract | Observability, troubleshooting, API event history; JSONL/SQLite are backing artifact/index only and not current health/recovery state |
| Recovery decision | 이번 watchdog tick에서 어떤 action을 할지에 대한 일회성 판단 | `RuntimeWatchdogRecoveryPolicy` | skip/suppress/recover/action dispatch |

Watchdog은 event history로 복구 여부를 판단하지 않습니다. Event는 append-only history라 중복, 누락, 순서 문제가 생길 수 있기 때문입니다. 복구 판단은 현재 SoT를 읽어 만든 `RuntimeHealthSnapshot`과 active operation guard를 기준으로 합니다.

Recovery decision은 아래처럼 나뉩니다.

| Decision | Status/Event | Watchdog action |
|---|---|---|
| `healthy` | `healthy` status 기록 | action 없음 |
| protected operation | `watchdog-skipped` event 기록 | VM/proxy restart 금지 |
| `recoveryDisabled` | `degraded` status 기록 | action 없음 |
| `recoverySuppressed` | `critical` status + `recovery-suppressed` event 기록 | VM/proxy restart 금지 |
| `unrecoverable` | `critical` status 기록 | action 없음 |
| `recover` | `recovering` status + recovery event 기록 | policy가 허용한 service만 restart |

`recoverySuppressed`는 자동 재시작이 위험한 상태입니다. 예를 들어 launchd/kernel log에서 `storage device attachment is invalid`, `EXT4-fs error`, `Remounting filesystem read-only`, `Input/output error`가 관측되면 VM disk/data 보존이 먼저 필요하므로 watchdog은 VM restart를 반복하지 않습니다.

### 2-5. Runtime Control API

Runtime Control API는 정규화된 결과를 노출합니다.

- `GET /runtime/status`: 최신 runtime read model
- `GET /runtime/status/stream`: long-lived SSE status snapshot stream
- `GET /runtime/events`: Runtime Control `RuntimeEventHistory` read model contract. Backing read failure must remain explicit as `readError`; `runtime-events.jsonl` is diagnostics/backing artifact, not a successful owner fallback.
  - `limit`: 1-500, 기본 100
  - `type`: event type filter
  - `since`: ISO-8601 timestamp lower bound
- `GET /runtime/vitaldb/observations/latest`: 최신 VitalDB observation snapshot
- `GET /runtime/vitaldb/observations/stream`: long-lived SSE VitalDB observation snapshot stream
- raw log 조회는 `/platform/logs/read` 계열 host affordance로 유지합니다.
- `GET /platform/logs/stream`: long-lived SSE host log text stream. product runtime event stream과는 별도 host affordance입니다.

Container raw log나 Redis audit list를 API의 canonical source로 직접 노출하지 않습니다. 필요하면 별도 audit 조회 endpoint를 만들되, `runtime-events`와 같은 operational event stream과 분리합니다.

### 2-6. SQLite read model

SQLite는 raw log의 대체물이 아니라 API 조회용 index/read model입니다.

- raw log와 JSONL은 사람이 읽고 재구축할 수 있는 append-only source로 유지합니다.
- SQLite는 `limit`, `type`, `since`, cursor pagination 같은 조회를 빠르게 처리합니다.
- Runtime event write port와 history read port는 분리합니다. Write는 append-only recording이고, read는 `RuntimeEventQuery`/`RuntimeEventPage` 기반 read model 조회입니다.
- API cursor는 내부 `RuntimeEventCursor(timestamp, id)`를 opaque `nextCursor` string으로 변환해 노출합니다. Client는 값을 해석하지 않고 다음 `/runtime/events?cursor=...` 요청에 그대로 전달합니다.
- SQLite write 실패는 runtime 실패로 보지 않습니다. warning event 또는 diagnostics 대상으로만 둡니다.
- SQLite 파일은 삭제 가능해야 하고, raw log/JSONL에서 재구축할 수 있어야 합니다.
- local runtime 특성상 WAL mode를 사용하고, schema migration을 명시적으로 관리합니다.
- log export는 SQLite main DB뿐 아니라 `runtime-observability.sqlite-wal`, `runtime-observability.sqlite-shm`도 포함해야 합니다. WAL sidecar가 빠지면 최신 read model row가 export에서 누락될 수 있습니다.

### 2-7. Runtime event retention

`runtime-events.jsonl`은 runtime operational event의 append diagnostics artifact입니다. Product consumers use the Runtime Control `/runtime/events` API contract and its typed `RuntimeEventHistory` read model; they do not treat the file path as the owner contract or successful fallback owner. 단일 파일이 무제한 커지면 export, diagnostics read, 파일 손상 영향 범위가 모두 커지므로 size 기반 rotation을 적용합니다.

- 현재 파일: `status/runtime-events.jsonl`
- rotated 파일: `status/runtime-events.jsonl.1`, `.2`, ...
- JSONL diagnostics read path가 사용되는 경우 rotated 파일을 오래된 순서부터 읽고 마지막에 현재 파일을 읽으며, read/decode failure는 `RuntimeEventHistory.readError`로 보존합니다.
- SQLite read model은 조회용 index이므로 JSONL rotation이 있더라도 current health/recovery owner 역할을 하지 않습니다.
- log export는 현재 JSONL, rotated JSONL, SQLite main DB, SQLite WAL/SHM sidecar를 함께 포함해야 합니다.

### 2-8. Runtime log archive retention

Runtime Control log collector는 central log를 날짜별 archive directory로 이동합니다. 관리 대상은 `/Library/Application Support/VitalServerHelper/logs/archive/YYYY-MM-DD` 형태의 직접 자식 directory입니다. 날짜 형식이 아닌 directory는 운영자가 둔 파일일 수 있으므로 자동 삭제하지 않고 size cap 계산에서도 제외합니다.

- 기본 보관 기간은 14일입니다.
- 설정 가능한 보관 기간은 1일 이상 30일 이하입니다.
- 관리 archive 총량 기본 cap은 1 GiB입니다.
- Settings의 `logArchiveRetentionDays`와 `logArchiveMaximumGiB`로 기간과 용량을 변경합니다. 이 값은 Host-owned `runtime-control-settings.json`에 저장되며 Guest runtime settings가 아닙니다.
- 기간 초과 archive를 먼저 삭제하고, 남은 관리 archive 총량이 cap을 넘으면 가장 오래된 날짜 directory부터 삭제합니다.
- retention days가 범위를 벗어나거나 maximum bytes가 0이면 collector는 fallback/clamp 없이 실패합니다.
- archive directory listing, managed archive size inspection, 삭제 실패는 명시 오류로 caller에 전달합니다.

## 3. Target flow

```text
containers
  -> stdout/stderr
  -> raw audit file
  -> Redis audit list
  -> vitaldb-observer snapshot
  -> Guest/Postgres VitalDB read model
  -> Guest Control API /runtime/vitaldb/*

guest collectors
  -> container-logs.log

host watchdog
  -> observe guest diagnostics, host services, HTTP endpoints, Guest Control reads
  -> normalize product status/events
  -> runtime-status.json
  -> runtime-events.jsonl
  -> runtime-observability.sqlite

Runtime Control API
  -> /runtime/status
  -> /runtime/events via RuntimeEventHistory read model with readError on backing read failure
  -> /runtime/vitaldb/observations/latest via Guest Control API / Guest/Postgres read model
  -> /platform/logs/read
```

## 4. 수집 정보 지도

이 섹션은 runtime 주변의 collector가 어떤 정보를 읽고, 어디에 남기고, 어떤 용도로 쓰이는지 빠르게 파악하기 위한 inventory입니다. 상세 schema보다 책임과 흐름을 우선합니다.

### 4-1. 한눈에 보는 수집 책임

| 수집자 | 주 책임 | 수집 성격 | 최종 SoT |
|---|---|---|---|
| `vitalserver-recorder-ingress` | VRecorder/Web Monitoring command 흐름 추적 | event/history | audit file, Redis List |
| `vitaldb-observer` | Redis 기준 recorder/bed 상태 관측 | latest snapshot | Guest/Postgres VitalDB read model |
| guest runtime observation | VM 내부 관측 artifact | latest snapshot | Host diagnostics, VM/resource diagnostics |
| Guest Control API | product service status/operation 노출 | explicit read/operation | service control and liveness SoT |
| runtime/watchdog | Host/VM/proxy health 판단 | normalized status/history | live Host/Guest reads, operation lease, health snapshot inputs |

### 4-2. 어디에서 무엇을 읽는가

| Source | Reader | 읽는 정보 | 목적 |
|---|---|---|---|
| Socket.IO traffic | `vitalserver-recorder-ingress` | `join_vr`, `send_data`, `req_cmd`, dispatch event | command trace |
| Redis | `vitaldb-observer` | recorder IP, last seen, version, bed, device/filter | VitalDB 상태 snapshot |
| proxy/access log | `vitaldb-observer` | remote IP, status, websocket handshake | proxy connection context |
| Linux guest OS | `tirosh-write-runtime-observation` | VM IP, CPU, memory, disk, boot ID | guest diagnostics evidence |
| Docker Compose | Guest Control Compose adapter, diagnostics collectors | service state, health, uptime | Guest Control service status 또는 diagnostics evidence |
| host launchd/files/HTTP | `RuntimeHealthChecker` | service state, files, proxy/guest HTTP | 제품 health 판단 |

### 4-3. 무엇을 어디에 남기는가

| Output | Writer | 내용 | History | 용도 |
|---|---|---|---|---|
| audit file | `vitalserver-recorder-ingress` | command audit event | Yes | command 흐름 추적 |
| Redis List | `vitalserver-recorder-ingress` | command audit event | Yes, capped | 운영 조회/디버깅 |
| observer stdout | `vitaldb-observer` | 수집 성공/실패 summary | Yes, via container logs | 진단 |
| `runtime-observation.json` | guest runtime observation writer | VM/resource latest snapshot, diagnostics evidence | No | Host VM/resource diagnostics and export artifact |
| `runtime-status.json` | runtime/watchdog | Host diagnostics/status projection document | No | write-only diagnostics/export artifact; no product read-result state contract; not current runtimeState, failureReasons, active operation, progress, Host service liveness, HTTP probe, VM IP, VM lifecycle, proxy port, runtime version, or latest backup owner |
| `runtime-progress.json` | runtime workflow | Host workflow progress diagnostics/export artifact | No | write-only diagnostics/export artifact; no product read-result state contract; absence/read failure is not active operation, recovery, or health state |
| `runtime-events.jsonl` | runtime/watchdog | operational event diagnostics artifact | Yes, through `/runtime/events` read model with read issues preserved | operational history backing artifact, not current state |
| `runtime-observability.sqlite` | runtime/watchdog | event history index plus transitional VitalDB diagnostics projection | Yes, through explicit event/diagnostics readers | event history index and migration-only VitalDB read model until Guest/Postgres parity |

### 4-4. Recorder ingress 수집 정보

| 범주 | 수집 정보 | 저장 위치 |
|---|---|---|
| VRecorder join | `join_vr`, `vrcode`, selected IP, remote address | audit file, Redis List, stdout |
| VRecorder data | `send_data`, payload summary, bytes, vrcode, truncation | audit file, Redis List, stdout |
| Web Monitoring command | `req_cmd`, command job, target vrcode | audit file, Redis List, stdout |
| Server dispatch | `update`, `restart`, `reboot`, `edit_bed`, `edit_conf` 등 | audit file, Redis List, stdout |
| Proxy failure | upstream error/timeout | audit file, Redis List, stdout |
| Runtime metrics | active sockets, recorder connections, parse/write failures | `/recorder-ingress/status` |

### 4-5. VitalDB observer 수집 정보

| 범주 | Source | 수집 정보 | Output |
|---|---|---|---|
| Recorder | Redis `ip_*`, `utime_*`, `vrver_*`, `info_*`, `vrconf_*` | IP, last seen, version, info, config, online/stale | observation snapshot |
| Recorder activity | Redis List `vitalserver:audit_events` | recent `send_data` message count, bytes, room-count diagnostic, first/last activity, rates | observation snapshot |
| Bed | Redis `beds`, `beds:*`, `utime_<bed>`, `ptcon_<bed>` | bed name, vrcode, last seen, patient connected | observation snapshot |
| Device/filter | Redis `devs_*`, `filts_*` | raw device/filter value | observation snapshot |
| Proxy connection | optional access JSONL | remote address, URI, status, websocket handshake | observation snapshot |
| Anomaly | derived | stale recorder, duplicate IP, backend unavailable | observation snapshot |
| Diagnostics | collector process | collection count/duration/failure | stdout JSONL |

Recorder `online` and `stale` are explicit observer states. Consumers must not infer recorder state from activity graphs, anomaly text, last-seen age, or recorder ingress connection counts. If a recorder is reported as both `online` and `stale`, the read model presents it as `stale` because stale means the last known online state is no longer current enough for operator trust.

### 4-6. Runtime/watchdog 수집 정보

| 범주 | Source | 수집 정보 | Health 반영 |
|---|---|---|---|
| 설치 파일 | filesystem | VM binary, proxy runner, rootfs, VM disk | Yes |
| launchd | host service manager | VM/proxy/watchdog loaded state | Yes |
| HTTP | host/guest endpoints | host proxy, guest HTTP, recorder ingress | Yes |
| 부가 HTTP | Redis UI, Swagger UI | HTTP status | Display only |
| guest diagnostics artifact | `runtime-observation.json` | VM IP, resource, diagnostics evidence | No for product service liveness |
| Guest Control API | `/runtime/stack`, `/runtime/services/*` | product service list/status and operations | Yes |
| Guest/Postgres read models | `/runtime/vitaldb/*` | recorder/bed/activity/relationship snapshots | Yes |
| port conflict | `lsof` | proxy port listener | Yes |
| bootstrap | result/log | bootstrap failure reason | Yes |
| container logs | file metadata | present, size, updatedAt | Diagnostics |
| VitalDB observation | Guest/Postgres read model | recorder/bed/anomaly snapshot | Critical anomalies only |

### 4-7. 현재 파악된 갭

아래 항목은 수집 inventory를 정리하면서 확인한 구현/정책 갭입니다. 먼저 owner와 방향을 문서에 고정한 뒤 각 항목을 별도 수정으로 반영합니다.

| Gap | 의미 | 영향 | 수정 방향 | 우선순위 | 상태 |
|---|---|---|---|---|---|
| `vitalFilesDisk` host contract 누락 | guest writer는 `vitalFilesDisk`를 쓰지만 Swift `GuestRuntimeObservationDocument`가 읽지 않음 | vital files disk 사용량이 host/UI/API에 전달되지 않음 | `GuestRuntimeObservationDocument` decode와 RuntimeStatus `dataStorage` fallback 추가 | 높음 | 반영됨 |
| observer access log 연결 미정 | `vitaldb-observer`는 `VITALDB_OBSERVER_ACCESS_LOG_PATH`를 지원하지만 기본 compose env/volume이 없음 | 기본 실행에서 `proxyConnections`가 비어 있을 수 있음 | guest edge nginx JSONL access log를 `edge-logs` volume으로 observer에 read-only 연결 | 중간 | 반영됨 |
| VitalDB anomaly health 정책 미정 | anomaly는 저장/노출되지만 runtime degraded 판단에는 아직 미반영 | critical anomaly가 있어도 overall health가 healthy일 수 있음 | `critical` severity anomaly와 observer not-ready를 typed failure reason으로 승격 | 중간 | 반영됨 |
| Redis UI/Swagger health 정책 미정 | HTTP status는 수집하지만 failure reason으로 쓰지 않음 | 부가 UI 장애가 overall health에 반영되지 않음 | 부가 UI는 display-only로 유지하고 RuntimeHealthEvaluator test로 고정 | 낮음 | 반영됨 |
| compose service recovery 정책 미정 | service state/health/uptime은 수집하지만 recovery trigger와 직접 연결되지 않음 | 특정 container unhealthy를 자동 복구하지 않을 수 있음 | critical service unhealthy/exit 상태를 failure reason으로 승격하고 watchdog VM restart 계획에 반영 | 중간 | 반영됨 |
| observer diagnostic summary 보강 여지 | observer stdout summary에 online/stale count가 아직 없음 | 로그만 볼 때 recorder 상태 추적이 제한됨 | `onlineRecorderCount`, `staleRecorderCount` 추가 | 낮음 | 반영됨 |
| audit history와 runtime event 조회 경계 | command audit history와 runtime operational history는 분리되어 있음 | 사용자가 어떤 history를 어디서 봐야 하는지 헷갈릴 수 있음 | UI/API에서 audit history를 별도 surface로 제공할지 결정 | 낮음 | 정책 대기 |

## 5. Source of truth map

아래 표는 runtime, packaging, UI, API가 같은 값을 중복 소유하지 않도록 하기 위한 owner map입니다. 새 필드나 표시 항목을 추가할 때는 먼저 이 표의 SoT를 확인하고, 없는 영역이면 owner를 정한 뒤 구현합니다.

| 영역 | SoT | 생산자 | 소비자 | 비고 |
|---|---|---|---|---|
| Release metadata | `release.json` / `release-dev.json` | 개발자, release sync script | Swift generated release, vm-build, compose image sync | stable/dev release를 명시적으로 분리 |
| Runtime service catalog | `release*.json` | release config | UI, Runtime Control API, packaging | 화면에 표시되는 service name/version/image 기준 |
| VM/package build config | `vm-build.toml` | build config | `packages/vitalserver-devtools` | Docker image, guest deploy path, bundle 구성 기준 |
| Runtime health snapshot | runtime evaluator 결과 | watchdog/runtime | Runtime Control API, UI | 현재 runtime 상태 판단 기준 |
| Runtime event history | Runtime Control `/runtime/events` API + `RuntimeEventHistory` read model | watchdog/runtime | Runtime Control API, diagnostics | JSONL/SQLite는 backing diagnostics artifact/index이며 current health/recovery owner가 아님 |
| VitalDB observation latest/history | Guest/Postgres read model | Guest/Product runtime | Runtime Control API `/runtime/vitaldb/*`, UI/Lab 후보 | Host SQLite가 product SoT가 아님 |
| VitalDB raw observation | `vitaldb-observer` API snapshot | `vitaldb-observer` container | Guest/Postgres read model writer | stateless collector/producer |
| VitalDB observer diagnostic log | container stdout, `container-logs.log` | `vitaldb-observer` | operator diagnostics | raw diagnostic history, not canonical product history |
| Runtime observation artifact | guest `runtime-observation.json` | `tirosh-write-runtime-observation` | Host diagnostics, VM/resource status | VM 내부 진단 evidence를 host runtime support export로 전달하는 artifact |
| UI display policy | `RuntimeStatusDisplayPolicy`, `RuntimeEventDisplayPolicy` | macOS runtime app | macOS UI | View는 policy 결과를 렌더링만 함 |
| Runtime Control API contract | OpenAPI + Swift contracts | runtime control boundary | PWA, Swift UI, CLI, external product tools | 외부 연동 계약 SoT |
| Observer API contract | `docs/api/vitaldb-observer.openapi.yaml` | observer app | guest runtime observation writer, future tools | observer 내부 API 계약 |
| Testkit scenario config | `config/testkit.toml` | 개발자 | `scripts/test_vitalserver.py`, testkit | 테스트 실행 파라미터 SoT |

핵심 원칙은 `vitaldb-observer`가 관측을 생산하지만 최종 관측 상태의 owner는 아니라는 점입니다. v2 VitalDB observation SoT는 Guest/Postgres read model이며 Host는 Guest Control API를 소비합니다. UI나 Runtime Control API는 observer container, guest `runtime-observation.json`, Host `runtime-status.json`의 embedded observation을 직접 신뢰하지 않습니다. Remote Console의 Observability anomaly detail은 `RuntimeVitalDBObservationSnapshot`을 기준으로 표시합니다. Snapshot `failed`/`unavailable`은 stale status 값으로 대체하지 않고 read issue 또는 unavailable state로 노출해야 합니다. Host SQLite projection은 transitional diagnostics 또는 migration evidence로만 남고, current product health/read model의 canonical source가 아닙니다. Guest VitalDB read model provider가 구성된 live path에서는 Host SQLite projection을 최신 observation snapshot fallback으로도 사용하지 않습니다. Recorder/bed live history는 Guest VitalDB read model provider가 없으면 explicit `readFailed`/read issue로 남겨야 하며, latest observation provider나 Host projection을 recorder/bed state fallback으로 사용하지 않습니다.

## 6. Canonical source policy

| 질문 | Canonical source |
|---|---|
| 현재 runtime이 정상인가? | API `/runtime/status` read model assembled from explicit owner reads |
| 언제 상태가 바뀌었나? | Runtime Control API `/runtime/events` (`RuntimeEventHistory`), with JSONL/SQLite backing artifacts preserving read issues |
| guest service가 살아 있나? | Guest Control API `GET /runtime/stack` |
| container가 무슨 로그를 냈나? | `container-logs.log` |
| VRecorder command가 어떤 흐름으로 전달됐나? | recorder ingress event log / Redis List |
| VRecorder/bed/anomaly 최신 관측 결과는? | Guest/Postgres read model, Guest Control API, Runtime Control API `RuntimeVitalDBObservationSnapshot` |
| 장애 원인을 제품 상태로 볼 수 있나? | watchdog이 정규화한 `failureReasons`와 runtime event |

## 7. Event taxonomy

### 7-1. Event Classes

Runtime event와 command audit event는 분리합니다.

| 종류 | 목적 | 예 |
|---|---|---|
| runtime operational event | 제품 runtime 상태 전이와 복구 판단 추적 | `status-changed`, `progress-updated`, `health-observed` |
| command audit event | VRecorder/Web Monitoring command 추적 | `join_vr`, `send_data`, `req_cmd`, `command_dispatch` |
| raw log | 사람이 보는 진단 정보 | compose logs, launchd logs, proxy logs |

Raw proxy log rows can explain why a previous request failed, but they do not own current backend availability state. VitalDB observer keeps parsed proxy connections as diagnostic evidence only. Current runtime failure reasons must be derived from explicit status/probe contracts owned by watchdog/runtime and guest runtime observation, not from historical log rows.

### 7-2. Ownership Boundary

Runtime operational event는 watchdog이 생성합니다. Command audit event는 recorder ingress가 생성하고 watchdog은 필요한 경우 요약 상태만 관측합니다.

Runtime operational event type은 API와 JSONL의 public contract입니다.

### 7-3. Runtime Operational Event Types

| Event type | Owner | Meaning |
|---|---|---|
| `status-changed` | watchdog | runtime 상태가 이전 관측값과 달라짐 |
| `progress-updated` | host runtime | install/update/rollback 같은 workflow 진행 상태 변경 |
| `health-observed` | watchdog | health snapshot이 수집됨 |
| `container-observed` | watchdog | container log/status 관측값이 수집됨 |
| `recorder-ingress-observed` | watchdog | recorder ingress status/counter 관측값이 수집됨 |
| `vitaldb-observed` | watchdog | Guest/Postgres VitalDB read model read가 수집됨 |
| `vitaldb-observer-unhealthy` | watchdog | Guest Control VitalDB read 또는 observer readiness가 실패함 |
| `vitaldb-anomaly-detected` | watchdog | Guest/Postgres read model이 recorder/bed/proxy anomaly를 보고함 |
| `recovery-triggered` | watchdog | recovery policy가 복구 작업을 시작함 |
| `recovery-completed` | watchdog | recovery 작업 후 runtime이 다시 관측됨 |
| `watchdog-skipped` | watchdog | protected/grace 상태라 recovery를 건너뜀 |
| `recovery-planned` | watchdog | Host recovery policy가 VM restart, proxy restart 같은 platform 복구 action 계획을 생성함 |
| `recovery-suppressed` | watchdog | disk/filesystem 보호 등으로 자동 recovery를 금지함 |
| `service-restart-dispatched` | watchdog | VM/proxy/guest-log-sync 같은 Host-owned service restart 명령을 보냄 |
| `runtime-command-started` | host runtime | start/stop/configure/update 등 host command 시작 |
| `runtime-command-completed` | host runtime | host command 성공 종료 |
| `runtime-command-failed` | host runtime | host command 실패 종료 |

새 이벤트는 raw source 이름이 아니라 제품 운영 의미를 기준으로 추가합니다.

## 8. SQLite schema plan

초기 SQLite schema는 조회 가치가 있는 metadata와 원본 payload를 함께 보관합니다. 큰 raw log body를 무조건 DB에 복사하지 않고, 필요하면 raw file 위치와 offset을 index합니다.

```sql
runtime_events (
  id text primary key,
  timestamp text not null,
  source text not null,
  event_type text not null,
  status text,
  previous_status text,
  operation text,
  message text,
  runtime_version text,
  payload_json text not null
);

vitaldb_observation_snapshots (
  observed_at text primary key,
  ready integer not null,
  recorder_count integer not null,
  anomaly_count integer not null,
  payload_json text not null
);

vitaldb_bed_assignments (
  id text primary key,
  bed_id text not null,
  bed_name text,
  vrcode text not null,
  started_at text not null,
  ended_at text,
  last_seen_at text,
  last_observed_at text not null,
  status text not null,
  patient_connected integer,
  observation_count integer not null
);

vitaldb_relationship_events (
  id text primary key,
  observed_at text not null,
  event_type text not null,
  severity text not null,
  bed_id text,
  bed_name text,
  vrcode text,
  previous_vrcode text,
  previous_bed_id text,
  message text not null
);

runtime_observations (
  id text primary key,
  timestamp text not null,
  kind text not null,
  status text,
  payload_json text not null
);

container_log_index (
  id integer primary key autoincrement,
  timestamp text,
  service text,
  level text,
  message text,
  raw_file text not null,
  raw_offset integer,
  raw_length integer
);

audit_event_index (
  id text primary key,
  timestamp text not null,
  event_type text not null,
  command text,
  request_id text,
  recorder_id text,
  payload_json text not null
);
```

초기 구현은 `runtime_events`, `vitaldb_observation_snapshots`, `vitaldb_bed_assignments`, `vitaldb_relationship_events`부터 시작했습니다. Bed/VRecorder 관계 read model은 observation snapshot append 시점에 projection합니다. Guest/Postgres에 저장된 snapshot row는 relationship projection을 재생성하는 canonical evidence이고, raw observer endpoint, Host `runtime-observation.json`, Host `runtime-status.json`, Host SQLite projection은 relationship owner가 아닙니다. assignment/event table은 삭제 후 Guest/Postgres snapshot history에서 다시 만들 수 있는 derived read model입니다. `container_log_index`와 `audit_event_index`는 raw log retention/rotation 정책이 정리된 뒤 ingest합니다.

## 9. VitalDB observer policy

`vitaldb-observer`는 별도 container이지만 SQLite owner는 아닙니다.

| 책임 | Owner |
|---|---|
| Redis read-only 수집 | `vitaldb-observer` |
| proxy/access log 파싱 | `vitaldb-observer` |
| recorder/bed/anomaly 계산 | `vitaldb-observer` |
| collection/readiness diagnostic stdout 로그 | `vitaldb-observer` |
| observation history/read model 저장 | Guest/Postgres read model |
| bed/VRecorder assignment projection | Guest/Postgres read model |
| Helper/PWA 조회 API | Runtime Control API가 Guest/Product API를 소비 |

이 구조는 수집/계산 장애를 traffic path와 Host watchdog core loop에서 분리하면서도, 제품이 보는 최종 관측 SoT를 Guest/Postgres read model로 유지하기 위한 결정입니다. Observer container는 자체 SQLite를 갖지 않고 `/api/runtime/observations` snapshot을 제공합니다. Guest writer가 이 snapshot을 Postgres read model에 저장하고, Runtime Control API는 Guest/Product API를 소비합니다. Host `runtime-observability.sqlite`는 transitional diagnostics 또는 migration evidence로만 남아야 하며 product read source로 승격하면 안 됩니다. Observer stdout JSONL은 `server_started`, `readiness_failed`, `observation_collected`, `observation_failed` 같은 진단 이벤트만 남깁니다. 이 로그는 raw history이고, Runtime Control API가 보는 canonical observation history는 아닙니다.

### 9-1. External Redis relay

외부 consumer가 VitalServer host 밖의 다른 PC나 Kubernetes cluster에서 실행되는 배포에서도 raw Redis port를 VM 밖으로 열지 않습니다. 실시간/대용량 numeric, trend, waveform relay는 observer API가 아니라 별도 relay container가 담당합니다. Relay는 VitalServer compose 내부에서 source Redis 3.2를 읽고, Helper Advanced 설정에 명시된 target Redis 8.x endpoint로 publish합니다.

| 항목 | 계약 |
|---|---|
| Source | internal `redis://redis:6379/0` |
| Target | Helper Advanced Redis relay setting |
| Owner | `vitalserver-redis-relay` |
| Control | Helper Advanced setting -> runtime relay TOML + secret file |
| Payload | allowlisted Redis key의 binary `DUMP` payload |
| Write direction | source read-only, target write-only |

Relay는 source Redis에서 `SCAN`, `TYPE`, `PTTL`, `DUMP`를 사용합니다. Target Redis에는 VitalServer Redis Relay Protocol v1로 key restore, fingerprint update, publish dedupe, `key_published` stream event를 한 Lua script 안에서 atomic하게 기록합니다. Credential/session/auth 계열 key는 항상 denylist로 제외합니다. `.vital`과 비슷한 수준의 복원이 필요하면 `vital_reconstruction` preset을 사용해 waveform/trend payload와 bed/recorder/device context key를 함께 publish합니다.

운영 원칙:

- Raw Redis port를 외부 network에 publish하지 않습니다.
- Helper Advanced에서 target Redis 설정이 없으면 relay는 disabled 상태입니다.
- target URL은 macOS Helper process 기준이 아니라 relay container/guest runtime 기준 주소입니다. Mac host에서 publish한 Redis를 shared NAT guest에서 바라볼 때는 보통 `redis://192.168.64.1:<port>/<db>` 형태를 사용합니다.
- Helper는 `/mnt/tirosh/deploy/redis-relay-config/redis-relay.toml`과 `/mnt/tirosh/deploy/redis-relay-secrets/redis-relay-target-password`를 생성합니다.
- relay container는 위 파일을 각각 `/run/tirosh/config/redis-relay.toml`, `/run/tirosh/secrets/redis-relay-target-password`로 read-only mount해서 읽습니다.
- target password는 settings/read model/TOML에 원문으로 저장하지 않고 secret file로 전달합니다.
- Runtime Control settings/read model에는 password 원문 대신 `passwordConfigured`만 노출합니다.
- relay 장애는 VitalServer traffic path 장애로 승격하지 않고 relay degraded/status로 보고합니다.
- relay container는 `/run/tirosh/status/redis-relay-status.json`을 diagnostic artifact로 publish하고, 같은 document를 `PUT /runtime/redis-relay/status` owner mutation으로 Guest Control API에 보냅니다. `GET /runtime/redis-relay/status`는 Guest/Postgres owner snapshot을 읽어 `loaded`, `invalidResponse`, `readFailed`를 구분해 노출합니다. Runtime surface의 `/runtime/redis-relay/status`는 이 read result를 그대로 전달하며 Host `RuntimeStatus`나 shared status file을 current product state로 사용하지 않습니다.
- relay container는 publisher입니다. Target Redis consumer group pending recovery, DLQ, decode idempotency, downstream 재처리는 target 쪽 consumer가 소유합니다.
- target Redis 수신 계약과 consumer 권장 흐름은 site dev 문서의 `Redis Relay`를 기준으로 봅니다.
- `running_with_errors`는 부분 성공 상태입니다. 현재 batch의 실패 원인은 status JSON의 `lastErrorSamples`에서 key/stage/code/errorType/message로 확인합니다.
- relay publish error code는 machine-readable 계약입니다. `source_dump_failed`는 source key metadata 또는 `DUMP` 실패, `target_publish_failed`는 target Redis의 atomic restore/fingerprint/dedupe/event publish 실패를 의미합니다.
- relay preset은 코드의 domain policy가 소유하며 UI는 regex를 만들지 않습니다.

## 10. 정리 단계

### 10-1. 현재 책임 고정

- `RuntimeStatusReporter`는 diagnostics/export status projection과 workflow progress artifact를 별도로 기록합니다.
- watchdog이 `runtime-events.jsonl`을 기록합니다.
- `GET /runtime/events`는 정규화된 runtime event만 반환합니다.
- recorder ingress는 raw audit event를 계속 파일/stdout/Redis에 남깁니다.

### 10-2. explicit recorder-ingress read model

Swift 쪽은 `RuntimeContainerObservation` read model을 사용하지 않습니다.
recorder-ingress 상태는 Guest Control API `GET /runtime/recorder-ingress/status`
결과를 `RuntimeRecorderIngressStatusReadResult`로 전달합니다.

현재 포함 항목:

- Guest Control API `GET /runtime/recorder-ingress/status` read 결과
- recorder ingress status counter snapshot

이 모델은 Guest Control API가 제공한 explicit read 결과입니다. Helper UI는 `RuntimeRecorderIngressStatusReadResult`를 그대로 받아 read state와 recorder-ingress counter를 표시할 수 있지만, 접근 실패를 service liveness나 product recovery state로 추정하지 않습니다. audit write failure counter는 관측값으로 보존하지만 즉시 runtime recovery 실패로 판단하지 않습니다. Recorder-ingress counter는 active connection 보조 정보와 diagnostics evidence이며, ingress-only recorder를 product recorder로 생성하거나 Guest/Postgres read model의 recorder online/stale/lastSeen/IP state를 수정하는 source가 아닙니다.

남은 후보:

- recorder-ingress status read의 terminal failure count를 diagnostics event로 정규화
- recorder-ingress status read 실패가 장시간 지속될 때 support warning으로 표시

### 10-3. recorder ingress status를 Guest Control read로 관측

watchdog과 health checker는 Host proxy를 직접 curl하지 않고 Guest Control API `GET /runtime/recorder-ingress/status`를 소비합니다. Guest가 container network 안에서 recorder-ingress status endpoint를 읽고, Host는 그 read document를 diagnostics evidence로 보존합니다.

현재 판단:

- Guest Control recorder-ingress read 실패는 `RuntimeRecorderIngressStatusReadResult.readError`에 보존
- recorder-ingress read 실패 자체로 product service liveness를 추정하지 않음

향후 판단 후보:

- Socket.IO parse failure가 급증하는지
- Redis/file/stdout audit write failure가 발생하는지
- active WebSocket 수가 비정상적으로 고정되어 있는지

장애로 판단되면 current `failureReasons`는 explicit owner reads에서 조립하고, operational history는 `/runtime/events` API로 조회할 수 있도록 runtime event artifact/index에 제품 용어로 기록합니다.

### 10-4. SQLite read model 도입

SQLite read model을 도입합니다.

- `HostInfrastructure`에 `SQLiteRuntimeObservabilityStore`를 추가했습니다.
- `RuntimeEventRepository`는 JSONL append를 durable diagnostics artifact로 기록하고 SQLite append를 best-effort index로 수행하는 composite repository로 확장했습니다.
- `/runtime/events` read path는 SQLite index를 우선 사용하고 실패 시 JSONL diagnostics artifact로 fallback하되 read issue를 `RuntimeEventHistory.readError`로 보존합니다.
- `RuntimeEventQuery`, `RuntimeEventCursor`, `RuntimeEventPage`를 Core boundary에 두고 SQLite query로 `limit`, `type`, `since`, cursor 조건을 pushdown합니다.
- `/runtime/events` response는 다음 페이지가 있을 때 `nextCursor`를 반환하고, request는 `cursor` query parameter로 이를 받습니다. Wire cursor는 opaque string입니다.
- schema version/migration table을 추가했습니다.
- DB 손상 또는 삭제 시 runtime 동작은 계속되고, `/runtime/events` 조회 시 JSONL에서 SQLite index를 best-effort로 재구축합니다. 깨진 JSONL line은 건너뜁니다.

### 10-5. 추가 API 검토

기본 API는 runtime operational event만 제공합니다.

필요하면 아래 endpoint를 별도로 검토합니다.

- `GET /runtime/audit-events`
- `GET /runtime/container-observations`
- `GET /runtime/log-sources`

단, raw audit event와 raw container log를 `/runtime/events`에 섞지 않습니다.

## 11. 유지보수 기준

- 새 container나 sidecar를 추가하면 먼저 “raw 상태를 어디에 남길지”를 정합니다.
- 제품 상태 판단은 watchdog으로 올립니다.
- API는 raw source가 아니라 SQLite/JSONL 기반 정규화 read model을 기본으로 제공합니다.
- raw log는 export/debug 대상이고, operational event는 API/자동화 대상입니다.
- 같은 event를 여러 sink에 남길 수는 있지만, canonical source와 sink 목적을 문서에 명시합니다.
- Swagger UI는 단일 화면에서 VitalServer, Runtime Control API, Recorder Ingress API spec을 선택하는 multi-spec catalog로 제공합니다. Recorder Ingress spec은 raw proxy traffic이 아니라 `/recorder-ingress/health`, `/recorder-ingress/status` 같은 sidecar 운영 endpoint만 문서화합니다.
- Helper Status 화면은 현재 runtime snapshot을 보여주고, Events 화면은 `RuntimeEventHistory` 기반의 status/event history를 보여줍니다. VRecorder 접속 수와 recorder별 snapshot은 Guest Control API `GET /runtime/recorder-ingress/status`가 제공하는 explicit `RuntimeRecorderIngressStatusReadResult`로 전달합니다. `containerObservation.recorderIngressStatus`는 current product display source가 아닙니다.
- Helper UI의 상태 문구, severity, service 행 구성, HTTP 상태 표시, uptime formatting은 SwiftUI view가 아니라 `RuntimeStatusDisplayPolicy`와 `RuntimeEventDisplayPolicy`가 소유합니다. View는 policy output을 렌더링만 하며, 새 상태/행/표시 규칙을 추가할 때는 먼저 해당 policy를 수정합니다.
- Product service uptime은 Guest Control API가 명시적으로 제공할 때만 표시합니다. Guest `docker inspect .State.StartedAt`나 compose observation에서 Host가 uptime을 재구성하지 않습니다.
