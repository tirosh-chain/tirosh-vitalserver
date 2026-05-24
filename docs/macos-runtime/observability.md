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

파편화의 핵심은 container 쪽 raw log/event가 여러 sink에 흩어져 있고, 어떤 자료가 제품 API의 canonical
source인지 명확하지 않다는 점입니다.

## 책임 원칙

### 각 app/container

각 app과 container는 자기 상태와 raw event만 기록합니다.

- `vitalserver-audit-proxy`는 command audit event를 생성합니다.
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

Watchdog은 raw source를 제품 관점 status/event로 정규화합니다.

- 최신 상태는 `runtime-status.json`에 반영합니다.
- 상태 전이와 주요 관측 결과는 `runtime-events.jsonl`에 append-only로 기록합니다.
- 조회가 필요한 event/index row는 SQLite read model에도 best-effort로 반영합니다.
- 자동 복구 판단도 watchdog에서 수행합니다.

### Runtime Control API

Runtime Control API는 정규화된 결과를 노출합니다.

- `GET /runtime/status`: 최신 runtime read model
- `GET /runtime/events`: SQLite read model을 우선 사용하고, 불가능하면 JSONL에서 읽은 최근 event history
  - `limit`: 1-500, 기본 100
  - `type`: event type filter
  - `since`: ISO-8601 timestamp lower bound
- raw log 조회는 `/host/logs/read` 계열 host affordance로 유지합니다.

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

## Target flow

```text
containers
  -> stdout/stderr
  -> raw audit file
  -> Redis audit list
  -> guest runtime-state.json

guest collectors
  -> container-logs.log

host watchdog
  -> observe guest state, host services, HTTP endpoints, audit proxy status
  -> normalize product status/events
  -> runtime-status.json
  -> runtime-events.jsonl
  -> runtime-observability.sqlite

Runtime Control API
  -> /runtime/status
  -> /runtime/events via SQLite first, JSONL fallback
  -> /host/logs/read
```

## Canonical source policy

| 질문 | Canonical source |
|---|---|
| 현재 runtime이 정상인가? | `runtime-status.json`, API `/runtime/status` |
| 언제 상태가 바뀌었나? | `runtime-observability.sqlite`, fallback `runtime-events.jsonl`, API `/runtime/events` |
| guest service가 살아 있나? | watchdog이 읽은 `runtime-state.json` + HTTP probe 결과 |
| container가 무슨 로그를 냈나? | `container-logs.log` |
| VRecorder command가 어떤 흐름으로 전달됐나? | audit proxy event log / Redis List |
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
| `recovery-triggered` | watchdog | recovery policy가 복구 작업을 시작함 |
| `recovery-completed` | watchdog | recovery 작업 후 runtime이 다시 관측됨 |
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

초기 구현은 `runtime_events`부터 시작했습니다. `container_log_index`와 `audit_event_index`는 raw log
retention/rotation 정책이 정리된 뒤 ingest합니다.

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
- Module uptime은 audit proxy process start time과 guest `docker inspect .State.StartedAt`에서
  계산한 container uptime을 사용합니다. 값이 없으면 unknown으로 표시하고 recovery 판단에는 쓰지 않습니다.
