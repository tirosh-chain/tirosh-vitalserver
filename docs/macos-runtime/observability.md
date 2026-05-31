# Runtime observability model

이 문서는 macOS VM runtime의 status, event, log, index 수집 책임을 정리합니다. 목표는
`runtime-status.json`, `runtime-events.jsonl`, SQLite read model, container logs, audit proxy event가
서로 다른 용도로 존재하더라도 제품 관점에서 어디를 믿고, 어디를 API로 노출할지 명확하게 만드는
것입니다.

## 현재 관찰된 파편화

Host Swift runtime 쪽은 타입과 계약이 비교적 명확합니다.

| 데이터 | 작성자 | 소비자 | 성격 |
|---|---|---|---|
| `status/runtime-status.json` | HostCLI workflow, watchdog | Helper UI, Runtime Control API, watchdog guard | 최신 상태 스냅샷 |
| `status/runtime-events.jsonl` | watchdog 관측 경로 | Runtime Control API | 상태 전이 이력 |
| `status/runtime-observability.sqlite` | host observability indexer | Runtime Control API | 조회용 read model/index |
| `logs/command.log`, `logs/runtime/*` | HostCLI, launchd | Helper Logs, export logs | 진단용 raw log |

Guest/container 쪽은 목적이 다른 자료가 병렬로 있습니다.

| 데이터 | 작성자 | 소비자 | 성격 |
|---|---|---|---|
| `vm/data/run/runtime-state.json` | guest `tirosh-runtime-state` | host `RuntimeHealthChecker`, Helper status | guest health/resource 스냅샷 |
| `vm/data/run/container-logs.log` | guest `tirosh-vitalserver-container-logs` | Helper Logs, export logs | `docker compose logs --follow` 수집본 |
| `/var/log/vitalserver-audit/audit-events.log` | `vitalserver-audit-proxy` | guest/operator diagnostics | command audit 원본 파일 로그 |
| audit proxy stdout | `vitalserver-audit-proxy` | container log collector | collector 호환 raw event log |
| Redis List `vitalserver:audit_events` | `vitalserver-audit-proxy` | 운영 조회/디버깅 | Redis 3.2 호환 보조 조회 sink |
| `/audit-proxy/status` | `vitalserver-audit-proxy` | watchdog 후보, operator | audit proxy runtime counters |
| `/api/v1/observations` | `vitaldb-observer` | guest `tirosh-runtime-state`, watchdog | VitalDB recorder/bed/anomaly snapshot |
| vitaldb-observer stdout JSONL | `vitaldb-observer` | container log collector, operator diagnostics | observer collection/readiness diagnostic history |

파편화의 핵심은 container 쪽 raw log/event가 여러 sink에 흩어져 있고, 어떤 자료가 제품 API의 canonical
source인지 명확하지 않다는 점입니다.

## 책임 원칙

### 각 app/container

각 app과 container는 자기 상태와 raw event만 기록합니다.

- `vitalserver-audit-proxy`는 command audit event를 생성합니다.
- `vitaldb-observer`는 Redis와 proxy/access log를 읽어 VitalDB observation snapshot을 계산합니다.
- guest `tirosh-runtime-state`는 guest HTTP/resource snapshot을 생성합니다.
- compose service와 container는 stdout/stderr에 raw log를 남깁니다.
- upstream VitalServer app은 제품 runtime event를 직접 알 필요가 없습니다.

각 app은 제품 전체 상태를 판단하지 않습니다.

### Guest collectors

Guest collector는 수집만 담당합니다.

- `tirosh-vitalserver-container-logs`는 `docker compose logs --follow`를 공유 디렉터리로 복사합니다.
- collector는 로그를 해석하거나 status/event로 승격하지 않습니다.
- `container-logs.log`는 진단용 raw log로 유지합니다.

### Host watchdog

Watchdog은 관측, 정규화, 판단의 중심입니다.

Watchdog 관측 대상:

- VM/proxy/watchdog launchd state
- VM IP
- guest `runtime-state.json`
- guest HTTP readiness
- host proxy readiness/liveness
- Redis UI / Swagger UI HTTP status
- rootfs/vm disk file state
- bootstrap result/log failure reason
- proxy port listener conflict
- active managed operation guard
- audit proxy health/status
- VitalDB observer snapshot

Watchdog은 raw source를 제품 관점 status/event로 정규화합니다.

- 최신 상태는 `runtime-status.json`에 반영합니다.
- 상태 전이와 주요 관측 결과는 `runtime-events.jsonl`에 append-only로 기록합니다.
- 조회가 필요한 event/index row는 SQLite read model에도 best-effort로 반영합니다.
- VitalDB observation snapshot은 `runtime-observability.sqlite`의 `vitaldb_*` namespace에 저장합니다.
- 자동 복구 판단도 watchdog에서 수행합니다.

### Status, event, recovery decision

Watchdog은 현재 상태 판단과 과거 이력 기록을 분리합니다.

| 구분 | 의미 | SoT/Owner | 사용처 |
|---|---|---|---|
| SoT | 각 owner가 작성한 원본 상태/로그 | host runtime, guest worker, launchd | watchdog 입력 |
| Status | 현재 제품 상태를 정규화한 최신 snapshot | `status/runtime-status.json` | Helper UI, Runtime Control API, watchdog guard |
| Event | 의미 있는 상태 변화와 판단 이력 | `status/runtime-events.jsonl`, SQLite index | Observability, troubleshooting, API event history |
| Recovery decision | 이번 watchdog tick에서 어떤 action을 할지에 대한 일회성 판단 | `RuntimeWatchdogRecoveryPolicy` | skip/suppress/recover/action dispatch |

Watchdog은 event history로 복구 여부를 판단하지 않습니다. Event는 append-only history라 중복, 누락,
순서 문제가 생길 수 있기 때문입니다. 복구 판단은 현재 SoT를 읽어 만든 `RuntimeHealthSnapshot`과
active operation guard를 기준으로 합니다.

Recovery decision은 아래처럼 나뉩니다.

| Decision | Status/Event | Watchdog action |
|---|---|---|
| `healthy` | `healthy` status 기록 | action 없음 |
| protected operation | `watchdog-skipped` event 기록 | VM/proxy restart 금지 |
| `recoveryDisabled` | `degraded` status 기록 | action 없음 |
| `recoverySuppressed` | `critical` status + `recovery-suppressed` event 기록 | VM/proxy restart 금지 |
| `unrecoverable` | `critical` status 기록 | action 없음 |
| `recover` | `recovering` status + recovery event 기록 | policy가 허용한 service만 restart |

`recoverySuppressed`는 자동 재시작이 위험한 상태입니다. 예를 들어 launchd/kernel log에서
`storage device attachment is invalid`, `EXT4-fs error`, `Remounting filesystem read-only`,
`Input/output error`가 관측되면 VM disk/data 보존이 먼저 필요하므로 watchdog은 VM restart를 반복하지
않습니다.

### Runtime Control API

Runtime Control API는 정규화된 결과를 노출합니다.

- `GET /runtime/status`: 최신 runtime read model
- `GET /runtime/status/stream`: long-lived SSE status snapshot stream
- `GET /runtime/events`: SQLite read model을 우선 사용하고, 불가능하면 JSONL에서 읽은 최근 event history
  - `limit`: 1-500, 기본 100
  - `type`: event type filter
  - `since`: ISO-8601 timestamp lower bound
- `GET /runtime/events/stream`: long-lived SSE runtime event stream. `Last-Event-ID`로 reconnect cursor를 전달할 수 있음
- `GET /vitaldb/observations/latest`: 최신 VitalDB observation snapshot
- `GET /vitaldb/observations/stream`: long-lived SSE VitalDB observation snapshot stream
- raw log 조회는 `/host/logs/read` 계열 host affordance로 유지합니다.
- `GET /host/logs/stream`: long-lived SSE host log text stream. product runtime event stream과는 별도 host affordance입니다.

Container raw log나 Redis audit list를 API의 canonical source로 직접 노출하지 않습니다. 필요하면 별도
audit 조회 endpoint를 만들되, `runtime-events`와 같은 operational event stream과 분리합니다.

### SQLite read model

SQLite는 raw log의 대체물이 아니라 API 조회용 index/read model입니다.

- raw log와 JSONL은 사람이 읽고 재구축할 수 있는 append-only source로 유지합니다.
- SQLite는 `limit`, `type`, `since`, cursor pagination 같은 조회를 빠르게 처리합니다.
- Runtime event write port와 history read port는 분리합니다. Write는 append-only recording이고, read는
  `RuntimeEventQuery`/`RuntimeEventPage` 기반 read model 조회입니다.
- API cursor는 내부 `RuntimeEventCursor(timestamp, id)`를 opaque `nextCursor` string으로 변환해
  노출합니다. Client는 값을 해석하지 않고 다음 `/runtime/events?cursor=...` 요청에 그대로 전달합니다.
- SQLite write 실패는 runtime 실패로 보지 않습니다. warning event 또는 diagnostics 대상으로만 둡니다.
- SQLite 파일은 삭제 가능해야 하고, raw log/JSONL에서 재구축할 수 있어야 합니다.
- local runtime 특성상 WAL mode를 사용하고, schema migration을 명시적으로 관리합니다.
- log export는 SQLite main DB뿐 아니라 `runtime-observability.sqlite-wal`,
  `runtime-observability.sqlite-shm`도 포함해야 합니다. WAL sidecar가 빠지면 최신 read model row가
  export에서 누락될 수 있습니다.

### Runtime event retention

`runtime-events.jsonl`은 runtime operational event의 1차 SoT입니다. 단일 파일이 무제한 커지면 export,
API fallback read, 파일 손상 영향 범위가 모두 커지므로 size 기반 rotation을 적용합니다.

- 현재 파일: `status/runtime-events.jsonl`
- rotated 파일: `status/runtime-events.jsonl.1`, `.2`, ...
- JSONL read path는 rotated 파일을 오래된 순서부터 읽고 마지막에 현재 파일을 읽습니다.
- SQLite read model은 조회용 index이므로 JSONL rotation이 있더라도 event SoT 역할을 대신하지 않습니다.
- log export는 현재 JSONL, rotated JSONL, SQLite main DB, SQLite WAL/SHM sidecar를 함께 포함해야 합니다.

## Target flow

```text
containers
  -> stdout/stderr
  -> raw audit file
  -> Redis audit list
  -> vitaldb-observer snapshot
  -> guest runtime-state.json

guest collectors
  -> container-logs.log

host watchdog
  -> observe guest state, host services, HTTP endpoints, audit proxy status, VitalDB snapshot
  -> normalize product status/events
  -> runtime-status.json
  -> runtime-events.jsonl
  -> runtime-observability.sqlite

Runtime Control API
  -> /runtime/status
  -> /runtime/events via SQLite first, JSONL fallback
  -> /vitaldb/observations/latest via SQLite
  -> /host/logs/read
```

## 수집 정보 지도

이 섹션은 runtime 주변의 collector가 어떤 정보를 읽고, 어디에 남기고, 어떤 용도로 쓰이는지 빠르게
파악하기 위한 inventory입니다. 상세 schema보다 책임과 흐름을 우선합니다.

### 한눈에 보는 수집 책임

| 수집자 | 주 책임 | 수집 성격 | 최종 SoT |
|---|---|---|---|
| `vitalserver-audit-proxy` | VRecorder/Web Monitoring command 흐름 추적 | event/history | audit file, Redis List |
| `vitaldb-observer` | Redis 기준 recorder/bed 상태 관측 | latest snapshot | runtime observability SQLite |
| guest runtime-state | VM 내부 상태 bridge | latest snapshot | runtime/watchdog |
| runtime/watchdog | 제품 health/status 판단 | normalized status/history | `runtime-status.json`, runtime observability SQLite |

### 어디에서 무엇을 읽는가

| Source | Reader | 읽는 정보 | 목적 |
|---|---|---|---|
| Socket.IO traffic | `vitalserver-audit-proxy` | `join_vr`, `send_data`, `req_cmd`, dispatch event | command trace |
| Redis | `vitaldb-observer` | recorder IP, last seen, version, bed, device/filter | VitalDB 상태 snapshot |
| proxy/access log | `vitaldb-observer` | remote IP, status, websocket handshake | proxy connection context |
| Linux guest OS | `tirosh-write-runtime-state` | VM IP, CPU, memory, disk, boot ID | guest runtime state |
| Docker Compose | `tirosh-write-runtime-state` | service state, health, uptime | container 상태/uptime |
| host launchd/files/HTTP | `RuntimeHealthChecker` | service state, files, proxy/guest HTTP | 제품 health 판단 |

### 무엇을 어디에 남기는가

| Output | Writer | 내용 | History | 용도 |
|---|---|---|---|---|
| audit file | `vitalserver-audit-proxy` | command audit event | Yes | command 흐름 추적 |
| Redis List | `vitalserver-audit-proxy` | command audit event | Yes, capped | 운영 조회/디버깅 |
| observer stdout | `vitaldb-observer` | 수집 성공/실패 summary | Yes, via container logs | 진단 |
| `runtime-state.json` | guest runtime-state | VM/container/observer latest snapshot | No | host로 전달 |
| `runtime-status.json` | runtime/watchdog | 최신 제품 상태 | No | UI/API latest status |
| `runtime-events.jsonl` | runtime/watchdog | 제품 상태 이벤트 | Yes | operational history |
| `runtime-observability.sqlite` | runtime/watchdog | event index, VitalDB observation history | Yes | Runtime Control API read model |

### Audit proxy 수집 정보

| 범주 | 수집 정보 | 저장 위치 |
|---|---|---|
| VRecorder join | `join_vr`, `vrcode`, selected IP, remote address | audit file, Redis List, stdout |
| VRecorder data | `send_data`, payload summary, bytes, vrcode, truncation | audit file, Redis List, stdout |
| Web Monitoring command | `req_cmd`, command job, target vrcode | audit file, Redis List, stdout |
| Server dispatch | `update`, `restart`, `reboot`, `edit_bed`, `edit_conf` 등 | audit file, Redis List, stdout |
| Proxy failure | upstream error/timeout | audit file, Redis List, stdout |
| Runtime metrics | active sockets, recorder connections, parse/write failures | `/audit-proxy/status` |

### VitalDB observer 수집 정보

| 범주 | Source | 수집 정보 | Output |
|---|---|---|---|
| Recorder | Redis `ip_*`, `utime_*`, `vrver_*`, `info_*`, `vrconf_*` | IP, last seen, version, info, config, online/stale | observation snapshot |
| Recorder activity | Redis List `vitalserver:audit_events` | recent `send_data` message count, bytes, rooms, first/last activity, rates | observation snapshot |
| Bed | Redis `beds`, `beds:*`, `utime_<bed>`, `ptcon_<bed>` | bed name, vrcode, last seen, patient connected | observation snapshot |
| Device/filter | Redis `devs_*`, `filts_*` | raw device/filter value | observation snapshot |
| Proxy connection | optional access JSONL | remote address, URI, status, websocket handshake | observation snapshot |
| Anomaly | derived | stale recorder, duplicate IP, backend unavailable | observation snapshot |
| Diagnostics | collector process | collection count/duration/failure | stdout JSONL |

### Runtime/watchdog 수집 정보

| 범주 | Source | 수집 정보 | Health 반영 |
|---|---|---|---|
| 설치 파일 | filesystem | VM binary, proxy runner, rootfs, VM disk | Yes |
| launchd | host service manager | VM/proxy/watchdog loaded state | Yes |
| HTTP | host/guest endpoints | host proxy, guest HTTP, audit proxy | Yes |
| 부가 HTTP | Redis UI, Swagger UI | HTTP status | Display only |
| guest state | `runtime-state.json` | VM IP, resource, compose services, observer snapshot | Yes for critical service/anomaly policy |
| port conflict | `lsof` | proxy port listener | Yes |
| bootstrap | result/log | bootstrap failure reason | Yes |
| container logs | file metadata | present, size, updatedAt | Diagnostics |
| VitalDB observation | guest state | recorder/bed/anomaly snapshot | Critical anomalies only |

### 현재 파악된 갭

아래 항목은 수집 inventory를 정리하면서 확인한 구현/정책 갭입니다. 먼저 owner와 방향을 문서에 고정한 뒤
각 항목을 별도 수정으로 반영합니다.

| Gap | 의미 | 영향 | 수정 방향 | 우선순위 | 상태 |
|---|---|---|---|---|---|
| `vitalFilesDisk` host contract 누락 | guest writer는 `vitalFilesDisk`를 쓰지만 Swift `GuestRuntimeStateDocument`가 읽지 않음 | vital files disk 사용량이 host/UI/API에 전달되지 않음 | `GuestRuntimeStateDocument` decode와 RuntimeStatus `dataStorage` fallback 추가 | 높음 | 반영됨 |
| observer access log 연결 미정 | `vitaldb-observer`는 `VITALDB_OBSERVER_ACCESS_LOG_PATH`를 지원하지만 기본 compose env/volume이 없음 | 기본 실행에서 `proxyConnections`가 비어 있을 수 있음 | guest edge nginx JSONL access log를 `edge-logs` volume으로 observer에 read-only 연결 | 중간 | 반영됨 |
| VitalDB anomaly health 정책 미정 | anomaly는 저장/노출되지만 runtime degraded 판단에는 아직 미반영 | critical anomaly가 있어도 overall health가 healthy일 수 있음 | `critical` severity anomaly와 observer not-ready를 typed failure reason으로 승격 | 중간 | 반영됨 |
| Redis UI/Swagger health 정책 미정 | HTTP status는 수집하지만 failure reason으로 쓰지 않음 | 부가 UI 장애가 overall health에 반영되지 않음 | 부가 UI는 display-only로 유지하고 RuntimeHealthEvaluator test로 고정 | 낮음 | 반영됨 |
| compose service recovery 정책 미정 | service state/health/uptime은 수집하지만 recovery trigger와 직접 연결되지 않음 | 특정 container unhealthy를 자동 복구하지 않을 수 있음 | critical service unhealthy/exit 상태를 failure reason으로 승격하고 watchdog VM restart 계획에 반영 | 중간 | 반영됨 |
| observer diagnostic summary 보강 여지 | observer stdout summary에 online/stale count가 아직 없음 | 로그만 볼 때 recorder 상태 추적이 제한됨 | `onlineRecorderCount`, `staleRecorderCount` 추가 | 낮음 | 반영됨 |
| audit history와 runtime event 조회 경계 | command audit history와 runtime operational history는 분리되어 있음 | 사용자가 어떤 history를 어디서 봐야 하는지 헷갈릴 수 있음 | UI/API에서 audit history를 별도 surface로 제공할지 결정 | 낮음 | 정책 대기 |

## Source of truth map

아래 표는 runtime, packaging, UI, API가 같은 값을 중복 소유하지 않도록 하기 위한 owner map입니다.
새 필드나 표시 항목을 추가할 때는 먼저 이 표의 SoT를 확인하고, 없는 영역이면 owner를 정한 뒤
구현합니다.

| 영역 | SoT | 생산자 | 소비자 | 비고 |
|---|---|---|---|---|
| Release metadata | `release.json` / `release-dev.json` | 개발자, release sync script | Swift generated release, vm-build, compose image sync | stable/dev release를 명시적으로 분리 |
| Runtime service catalog | `release*.json` | release config | UI, Runtime Control API, packaging | 화면에 표시되는 service name/version/image 기준 |
| VM/package build config | `vm-build.toml` | build config | `packages/vitalserver-devtools` | Docker image, guest deploy path, bundle 구성 기준 |
| Runtime health snapshot | runtime evaluator 결과 | watchdog/runtime | Runtime Control API, UI | 현재 runtime 상태 판단 기준 |
| Runtime event log | `runtime-observability.sqlite`, fallback `runtime-events.jsonl` | watchdog/runtime | Runtime Control API, diagnostics | 이벤트 조회와 이력 추적 기준 |
| VitalDB observation latest/history | `runtime-observability.sqlite` | watchdog/runtime | Runtime Control API `/vitaldb/*`, UI/Test 탭 후보 | `vitaldb-observer`가 직접 SoT가 아님 |
| VitalDB raw observation | `vitaldb-observer` API snapshot | `vitaldb-observer` container | guest state writer | stateless collector/producer |
| VitalDB observer diagnostic log | container stdout, `container-logs.log` | `vitaldb-observer` | operator diagnostics | raw diagnostic history, not canonical product history |
| Runtime state bridge | guest `runtime-state.json` | `tirosh-write-runtime-state` | watchdog/runtime | VM 내부 상태를 host runtime으로 전달하는 bridge |
| UI display policy | `RuntimeStatusDisplayPolicy`, `RuntimeEventDisplayPolicy` | macOS runtime app | macOS UI | View는 policy 결과를 렌더링만 함 |
| Runtime Control API contract | OpenAPI + Swift contracts | runtime control boundary | client/UI/testkit/external tools | 외부 연동 계약 SoT |
| Observer API contract | `docs/openapi/vitaldb-observer.openapi.yaml` | observer app | guest state writer, future tools | observer 내부 API 계약 |
| Testkit scenario config | `config/testkit.toml` | 개발자 | `scripts/test_vitalserver.py`, testkit | 테스트 실행 파라미터 SoT |

핵심 원칙은 `vitaldb-observer`가 관측을 생산하지만 최종 관측 상태의 owner는 아니라는 점입니다.
최종 VitalDB observation SoT는 watchdog/runtime이 저장하는 `runtime-observability.sqlite`입니다.
UI나 Runtime Control API는 observer container를 직접 신뢰하지 않고 runtime 계층의 저장 결과를 기준으로
응답합니다.
Remote Console의 Observability anomaly detail은 `RuntimeVitalDBObservationSnapshot`을 기준으로
표시합니다. Snapshot `failed`/`unavailable`은 stale `runtime-status.json` 값으로 대체하지 않고
read issue 또는 unavailable state로 노출해야 합니다. Status summary는 status document의
`vitalDBObservation`을 표시할 수 있지만, anomaly detail의 대체 source가 되면 안 됩니다.

## Canonical source policy

| 질문 | Canonical source |
|---|---|
| 현재 runtime이 정상인가? | `runtime-status.json`, API `/runtime/status` |
| 언제 상태가 바뀌었나? | `runtime-observability.sqlite`, fallback `runtime-events.jsonl`, API `/runtime/events` |
| guest service가 살아 있나? | watchdog이 읽은 `runtime-state.json` + HTTP probe 결과 |
| container가 무슨 로그를 냈나? | `container-logs.log` |
| VRecorder command가 어떤 흐름으로 전달됐나? | audit proxy event log / Redis List |
| VRecorder/bed/anomaly 최신 관측 결과는? | `runtime-observability.sqlite`, API `RuntimeVitalDBObservationSnapshot` |
| 장애 원인을 제품 상태로 볼 수 있나? | watchdog이 정규화한 `failureReasons`와 runtime event |

## Event taxonomy

Runtime event와 command audit event는 분리합니다.

| 종류 | 목적 | 예 |
|---|---|---|
| runtime operational event | 제품 runtime 상태 전이와 복구 판단 추적 | `status-changed`, `progress-updated`, `health-observed` |
| command audit event | VRecorder/Web Monitoring command 추적 | `join_vr`, `send_data`, `req_cmd`, `command_dispatch` |
| raw log | 사람이 보는 진단 정보 | compose logs, launchd logs, proxy logs |

Runtime operational event는 watchdog이 생성합니다. Command audit event는 audit proxy가 생성하고 watchdog은
필요한 경우 요약 상태만 관측합니다.

Runtime operational event type은 API와 JSONL의 public contract입니다.

| Event type | Owner | Meaning |
|---|---|---|
| `status-changed` | watchdog | runtime 상태가 이전 관측값과 달라짐 |
| `progress-updated` | host runtime | install/update/rollback 같은 workflow 진행 상태 변경 |
| `health-observed` | watchdog | health snapshot이 수집됨 |
| `container-observed` | watchdog | container log/status 관측값이 수집됨 |
| `audit-proxy-observed` | watchdog | audit proxy status/counter 관측값이 수집됨 |
| `vitaldb-observed` | watchdog | VitalDB observer snapshot이 수집됨 |
| `vitaldb-observer-unhealthy` | watchdog | VitalDB observer 조회 또는 readiness가 실패함 |
| `vitaldb-anomaly-detected` | watchdog | VitalDB observer가 recorder/bed/proxy anomaly를 계산함 |
| `recovery-triggered` | watchdog | recovery policy가 복구 작업을 시작함 |
| `recovery-completed` | watchdog | recovery 작업 후 runtime이 다시 관측됨 |
| `watchdog-skipped` | watchdog | protected/grace 상태라 recovery를 건너뜀 |
| `recovery-planned` | watchdog | recovery policy가 service restart 계획을 생성함 |
| `recovery-suppressed` | watchdog | disk/filesystem 보호 등으로 자동 recovery를 금지함 |
| `service-restart-dispatched` | watchdog | VM/proxy/guest-log-sync service restart 명령을 보냄 |
| `runtime-command-started` | host runtime | start/stop/configure/update 등 host command 시작 |
| `runtime-command-completed` | host runtime | host command 성공 종료 |
| `runtime-command-failed` | host runtime | host command 실패 종료 |

새 이벤트는 raw source 이름이 아니라 제품 운영 의미를 기준으로 추가합니다.

## SQLite schema plan

초기 SQLite schema는 조회 가치가 있는 metadata와 원본 payload를 함께 보관합니다. 큰 raw log body를
무조건 DB에 복사하지 않고, 필요하면 raw file 위치와 offset을 index합니다.

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

초기 구현은 `runtime_events`, `vitaldb_observation_snapshots`,
`vitaldb_bed_assignments`, `vitaldb_relationship_events`부터 시작했습니다.
Bed/VRecorder 관계 read model은 observation snapshot append 시점에 projection합니다. 원본 snapshot은
canonical source로 유지하고, assignment/event table은 삭제 후 snapshot history에서 다시 만들 수 있는
derived read model입니다.
`container_log_index`와 `audit_event_index`는 raw log retention/rotation 정책이 정리된 뒤 ingest합니다.

## VitalDB observer policy

`vitaldb-observer`는 별도 container이지만 SQLite owner는 아닙니다.

| 책임 | Owner |
|---|---|
| Redis read-only 수집 | `vitaldb-observer` |
| proxy/access log 파싱 | `vitaldb-observer` |
| recorder/bed/anomaly 계산 | `vitaldb-observer` |
| collection/readiness diagnostic stdout 로그 | `vitaldb-observer` |
| observation history/read model 저장 | watchdog/runtime observability SQLite |
| bed/VRecorder assignment projection | watchdog/runtime observability SQLite |
| Helper/PWA 조회 API | Runtime Control API |

이 구조는 수집/계산 장애를 traffic path와 watchdog core loop에서 분리하면서도, 제품이 보는 최종 관측
SoT를 `runtime-observability.sqlite`로 유지하기 위한 결정입니다. Observer container는 자체 SQLite를
갖지 않고 `/api/v1/observations` snapshot을 제공합니다. Guest `tirosh-runtime-state`가 이 snapshot을
`runtime-state.json`에 포함시키고, watchdog은 status/event/SQLite 경로로 정규화합니다.
Observer stdout JSONL은 `server_started`, `readiness_failed`, `observation_collected`,
`observation_failed` 같은 진단 이벤트만 남깁니다. 이 로그는 raw history이고, Runtime Control API가
보는 canonical observation history는 아닙니다.

## 정리 단계

### 1단계: 현재 책임 고정

- `RuntimeStatusReporter`는 최신 status/progress 문서만 기록합니다.
- watchdog이 `runtime-events.jsonl`을 기록합니다.
- `GET /runtime/events`는 정규화된 runtime event만 반환합니다.
- audit proxy는 raw audit event를 계속 파일/stdout/Redis에 남깁니다.

### 2단계: container observation 모델 추가

Swift 쪽에 `RuntimeContainerObservation` read model을 추가합니다.

현재 포함 항목:

- audit proxy `/audit-proxy/status` HTTP 관측 결과
- audit proxy `/audit-proxy/status` counter snapshot
- `runtime-state.json` 내부 `updatedAt`
- `runtime-state.json` 파일 수정 시각
- `container-logs.log` 존재 여부
- `container-logs.log` byte size
- `container-logs.log` 파일 수정 시각
- guest `docker compose ps --format json`에서 정규화한 compose service summary

이 모델은 watchdog의 관측 입력입니다. Helper UI에 그대로 노출하기보다는 `runtime-status`와
`runtime-events`로 정규화합니다. 현재는 audit proxy status endpoint 접근 실패만
`audit-proxy-http-<status>` failure reason으로 승격합니다. audit write failure counter는 관측값으로
보존하지만 즉시 runtime recovery 실패로 판단하지 않습니다.

남은 후보:

- `runtime-state.json` updated age를 failure policy에 반영
- `container-logs.log` updated age를 warning policy에 반영
- compose service health summary를 recovery trigger와 연결

### 3단계: audit proxy status를 watchdog 관측 대상에 편입

watchdog이 host proxy를 통해 `/audit-proxy/status`를 읽습니다.

현재 판단:

- `/audit-proxy/status`를 읽을 수 없으면 `audit-proxy-http-failed` failure reason 기록

향후 판단 후보:

- Socket.IO parse failure가 급증하는지
- Redis/file/stdout audit write failure가 발생하는지
- active WebSocket 수가 비정상적으로 고정되어 있는지

장애로 판단되면 `failureReasons`와 `runtime-events.jsonl`에 제품 용어로 기록합니다.

### 4단계: API 확장 여부 결정

SQLite read model을 도입합니다.

- `HostInfrastructure`에 `SQLiteRuntimeObservabilityStore`를 추가했습니다.
- `RuntimeEventRepository`는 JSONL append를 canonical source로 유지하고 SQLite append를 best-effort로
  수행하는 composite repository로 확장했습니다.
- `/runtime/events` read path는 SQLite를 우선 사용하고 실패 시 기존 JSONL repository로 fallback합니다.
- `RuntimeEventQuery`, `RuntimeEventCursor`, `RuntimeEventPage`를 Core boundary에 두고 SQLite query로
  `limit`, `type`, `since`, cursor 조건을 pushdown합니다.
- `/runtime/events` response는 다음 페이지가 있을 때 `nextCursor`를 반환하고, request는 `cursor`
  query parameter로 이를 받습니다. Wire cursor는 opaque string입니다.
- schema version/migration table을 추가했습니다.
- DB 손상 또는 삭제 시 runtime 동작은 계속되고, `/runtime/events` 조회 시 JSONL에서 SQLite index를
  best-effort로 재구축합니다. 깨진 JSONL line은 건너뜁니다.

### 5단계: API 확장 여부 결정

기본 API는 runtime operational event만 제공합니다.

필요하면 아래 endpoint를 별도로 검토합니다.

- `GET /runtime/audit-events`
- `GET /runtime/container-observations`
- `GET /runtime/log-sources`

단, raw audit event와 raw container log를 `/runtime/events`에 섞지 않습니다.

## 유지보수 기준

- 새 container나 sidecar를 추가하면 먼저 “raw 상태를 어디에 남길지”를 정합니다.
- 제품 상태 판단은 watchdog으로 올립니다.
- API는 raw source가 아니라 SQLite/JSONL 기반 정규화 read model을 기본으로 제공합니다.
- raw log는 export/debug 대상이고, operational event는 API/자동화 대상입니다.
- 같은 event를 여러 sink에 남길 수는 있지만, canonical source와 sink 목적을 문서에 명시합니다.
- Swagger UI는 단일 화면에서 VitalServer, Runtime Control API, Audit Proxy API spec을 선택하는
  multi-spec catalog로 제공합니다. Audit Proxy spec은 raw proxy traffic이 아니라
  `/audit-proxy/health`, `/audit-proxy/status` 같은 sidecar 운영 endpoint만 문서화합니다.
- Helper Status 화면은 현재 runtime snapshot을 보여주고, Events 화면은 `RuntimeEventHistory` 기반의
  status/event history를 보여줍니다. VRecorder 접속 수와 recorder별 snapshot은 audit proxy
  `/audit-proxy/status`에서 수집해 `containerObservation.auditProxyStatus`로 전달합니다.
- Helper UI의 상태 문구, severity, service 행 구성, HTTP 상태 표시, uptime formatting은 SwiftUI view가
  아니라 `RuntimeStatusDisplayPolicy`와 `RuntimeEventDisplayPolicy`가 소유합니다. View는 policy output을
  렌더링만 하며, 새 상태/행/표시 규칙을 추가할 때는 먼저 해당 policy를 수정합니다.
- Service uptime은 audit proxy process start time과 guest `docker inspect .State.StartedAt`에서
  계산한 uptime을 사용하며, Helper Status/Advanced 화면의 상태 값 옆에 inline으로 표시합니다.
  값이 없으면 표시하지 않고 recovery 판단에는 쓰지 않습니다.
