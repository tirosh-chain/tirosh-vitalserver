# Recorder observability persistence and API implementation plan

## 1. 문서 목적

이 문서는 Vital Recorder가 전송하는 관측 JSON을 VitalServer가 수락하고,
PostgreSQL에 보존하고, Recorder별 조회 모델로 투영해 Swift와 PWA에 제공하기
위한 전체 구현 계획입니다.

현재 recorder ingress에는 다음 다섯 POST endpoint와 PostgreSQL admission
store가 있습니다.

- `POST /api/v1/recorders/{vrcode}/observations`
- `POST /api/v1/recorders/{vrcode}/diagnostic-events`
- `POST /api/v1/recorders/{vrcode}/kernel-incidents`
- `POST /api/v1/recorders/{vrcode}/profiles`
- `POST /api/v1/recorders/{vrcode}/boot-events`

현재 구현은 HTTP framing, VRCODE path, `X-Device-ID`, 요청 크기 제한,
authoritative contract 검증, 모든 line disposition의 PostgreSQL 영속화와
Recorder별 current projection/read API를 제공합니다. Timeline/incident 전용
projection, retention release proof와 승인된 support expectation provider는
후속 범위입니다.

UI는 이 문서의 storage와 read contract가 완성된 뒤 설계합니다. Swift와 PWA는
Recorder 원본 JSON을 직접 해석하거나 missing state에서 장비 상태를 추정하지
않습니다.

## 2. 결정 요약

### 2-1. 엄격한 수신 계약과 느슨한 저장 모델을 함께 사용합니다

Recorder가 전송한 문서는 Recorder 저장소가 배포한 authoritative JSON Schema로
엄격하게 검증합니다. 검증을 통과한 문서는 payload 전체를 관계형 column으로
분해하지 않고 원본 JSONB로 저장합니다.

관계형 column으로 분리하는 값은 식별, 중복 제거, 순서, 시간 조회와 retention에
필요한 envelope field로 제한합니다.

- VRCODE
- event ID
- resource type
- schema version
- Observer device ID
- boot ID
- sequence
- device observed time
- server received time
- canonical content hash

온도, 메모리, storage, network, service, publisher와 kernel incident 세부값은
원본 JSONB에 보존합니다. 실제 제품 API가 반복해서 조회하는 값만 versioned
projection에 추가합니다.

### 2-2. 원본 evidence와 서버 판정을 분리합니다

Recorder는 observation, diagnostic event, kernel incident와 profile evidence를
제공합니다. VitalServer domain policy는 complete explicit input을 받아
report freshness, severity, 최근 재부팅과 active signal을 계산합니다.

Recorder가 다음과 같은 UI 판정을 POST하지 않습니다.

- Stable
- Needs attention
- Restarted recently
- Critical incident
- No health report

이 값들은 하나의 enum도 아닙니다. 조회 계약에서는 서로 다른 축으로
표현합니다.

```text
reportState = current | stale | missing | readFailed
severity = normal | warning | critical | unknown
recentRestart = null | explicit reboot evidence
signals = zero or more explicit signal documents
```

`missing`과 `readFailed`에서 severity를 정상으로 만들지 않습니다.
`restarted recently`는 health severity가 아니라 boot transition evidence입니다.

### 2-3. Profile은 별도 resource로 받고 current aggregate에서 연관을 보존합니다

Profile은 주기적인 health sample이 아닙니다. 장비에 설치된 software, 실제 수집
주기, 지원 capability와 관측 설정처럼 부팅 또는 설정 변경 때만 달라지는
정보입니다.

Recorder는 profile을 부팅 후와 profile content가 변경됐을 때 POST합니다.
Profile 원문 이력은 공통 event store에 저장합니다. Product read model은
Recorder당 한 행인 `recorder_observability.current`에 latest Profile과 현재
observation의 boot/device identity에 맞는 associated Profile을 함께 보존합니다.
Profile이 없거나 연관되지 않은 상태는 `profile_state`로 명시합니다.

### 2-4. PostgreSQL이 admission과 product read model의 Guest owner store입니다

PostgreSQL admission transaction이 성공한 뒤에만 `202 Accepted`를 반환합니다.
PostgreSQL을 쓸 수 없을 때 파일 저장을 성공 fallback으로 사용하지 않고
`503 Service Unavailable`을 반환합니다. Recorder publisher는 자신의 persistent
buffer에서 요청을 재시도합니다.

기존 NDJSON ledger는 명시적 migration input과 diagnostics artifact일 뿐,
PostgreSQL과 동시에 유지하는 두 번째 source of truth가 아닙니다.

### 2-5. POST 미지원 Recorder를 missing report로 판정하지 않습니다

Recorder/Observer 구버전은 observability POST 기능이 없을 수 있습니다. 보고가
없다는 사실만으로 지원 여부를 추정하지 않습니다. Product read contract는
지원 여부와 보고 상태를 독립 축으로 제공합니다.

```text
supportState = supported | unsupported | unknown
reportState = notEvaluated | awaitingFirstReport
            | current | stale | missing | readFailed
```

- accepted POST가 있으면 `supported`가 명시적으로 증명됩니다.
- deployment assignment, 승인된 version catalog 또는 manual evidence는
  `recorder_observability.expectations`가 소유합니다.
- expectation과 accepted POST가 모두 없으면 `unknown/notEvaluated`입니다.
- 명시적인 `unsupported` 장비는 `notEvaluated`이며 missing/stale 장애로
  표시하지 않습니다.
- 명시적인 `supported` expectation은 `expectedSince`부터 서버 설정의
  first-report grace period 동안 `awaitingFirstReport`입니다.
- grace period가 지난 뒤에만 `missing`으로 전이합니다.

Vital Recorder 앱 버전과 Observer producer 버전이 독립적으로 배포된다면 앱
버전만으로 support state를 만들지 않습니다. Version catalog는 두 artifact의
호환 관계가 release evidence로 고정된 경우에만 사용합니다.

## 3. 책임과 데이터 흐름

```text
Vital Recorder Observer
  -> application/x-ndjson POST
  -> recorder ingress request adapter
  -> authoritative schema validation
  -> admission transaction
     -> line disposition
     -> accepted JSONB event or quarantine
  -> 202 or request-level 4xx/503

PostgreSQL accepted event
  -> idempotent projection worker
  -> profile/current health/timeline/incident read models
  -> Guest Control read API
  -> Runtime Control proxy
  -> Swift / PWA
```

| 책임 | 소유자 |
|---|---|
| 장비 reading과 reading state 생성 | Recorder Observer |
| VRCODE 설정과 pinned identity 상태 | Recorder deployment |
| HTTP admission과 request/line disposition | recorder ingress |
| accepted 원문과 quarantine 영속화 | recorder ingress PostgreSQL adapter |
| report freshness, severity, boot transition policy | VitalServer domain/core |
| current/profile/timeline projection | projection workflow |
| product read response | Guest Control API |
| label, layout와 formatting | Swift/PWA presentation |

VRCODE는 Recorder identity key입니다. `X-Device-ID`와 payload `deviceId`는
Observer deployment identity이며 서로 같아야 하지만 VRCODE를 대신하지
않습니다. 현재 평문 HTTP와 header만으로는 인증된 identity라고 표현할 수
없습니다. 인증 계층이 추가되기 전에는 binding state를 `reported`로 보존하고
`verified`로 승격하지 않습니다.

## 4. Recorder 입력 계약

### 4-1. 기존 v1 계약

VitalServer는 Recorder 저장소의 다음 artifact를 source commit과 SHA-256 receipt와
함께 vendor합니다.

- `contracts/observation/v1/observation.schema.json`
- `contracts/observation/v1/log.schema.json`
- `contracts/observation/v1/kernel-incident.schema.json`

VitalServer가 nested reading, enum과 payload field를 손으로 다시 구현하지
않습니다. JSON Schema 2020-12 validator가 pinned artifact를 읽습니다.
Incompatible contract 변경은 기존 v1 schema file을 바꾸지 않고 새 contract
version으로 배포합니다.

#### Device health observation

기본 60초 주기의 장비 상태입니다. 실제 interval은 Recorder 설정이 소유하며
서버는 profile이 제공한 값을 사용합니다.

- boot ID, sequence, uptime과 NTP state
- system load와 pressure
- memory, swap, OOM과 page-fault evidence
- root/data filesystem, read-only, inode와 block I/O
- Raspberry Pi temperature, voltage와 throttle flags
- network interface, Wi-Fi, USB와 error/drop counter
- Vital Recorder와 publisher service state와 restart counter
- publisher buffer 사용량
- 관련 systemd unit과 pstore state
- collector failure를 보존하는 read issues

#### Diagnostic event

상태 변화와 허용된 원문 evidence입니다. power loop는 기본 1초, platform loop는
기본 10초 주기로 조사하지만 모든 sample을 보내지 않고 최초 상태, 전환, 임계
구간 변경, counter 증가, 읽기 실패와 복구를 보냅니다.

#### Kernel incident

panic, Oops, watchdog와 lockup에 대한 bounded summary입니다. pstore 원문 file을
HTTP payload로 전송하지 않고 Recorder `/data` 보존 위치, 크기, hash와 제한된
excerpt를 전송합니다.

### 4-2. Recorder profile 계약

새 endpoint는 다음으로 정의합니다.

```text
POST /api/v1/recorders/{vrcode}/profiles
Content-Type: application/x-ndjson
X-Device-ID: <observer device id>
```

Profile도 at-least-once event이고 기존 endpoint와 동일한 line disposition,
content conflict와 request-level failure 규칙을 사용합니다.

권장 profile 문서는 다음 의미를 가집니다.

```json
{
  "schemaVersion": "v1",
  "kind": "recorder-profile",
  "eventId": "device-1:boot-a:profile:1",
  "profileDigest": "<sha256>",
  "deviceId": "device-1",
  "siteId": "site-a",
  "bootId": "boot-a",
  "sequence": 1,
  "deviceObservedAt": "2026-07-23T00:00:00Z",
  "ntpState": "unsynchronized",
  "identity": {
    "vrcode": "VRCODE-001",
    "vrcodeState": "ready"
  },
  "software": {
    "observerVersion": {"state": "ok", "value": "0.2.3"},
    "vitalRecorderVersion": {"state": "ok", "value": "1.18.43"},
    "osImageVersion": {"state": "ok", "value": "2026.07"},
    "kernelRelease": {"state": "ok", "value": "6.1.0-rpi"}
  },
  "collection": {
    "observationIntervalSeconds": 60,
    "powerIntervalSeconds": 1,
    "telemetryIntervalSeconds": 10
  },
  "capabilities": {
    "powerTelemetry": true,
    "platformTelemetry": true,
    "kernelIncidentCollection": true,
    "persistentPublisherBuffer": true,
    "vitalApplicationLogs": false
  },
  "configuration": {
    "dataPath": "/data",
    "networkInterfaces": ["eth0", "wlan0"],
    "serialDevices": []
  },
  "publishing": {
    "bufferLimitBytes": 67108864
  },
  "readIssues": []
}
```

위 JSON은 설명용 축약 예시입니다. 실제 admission의 source of truth는
`apps/vitalserver-recorder-ingress/contracts/recorder-observability/schemas/profile-v1.schema.json`
및 같은 manifest의 digest입니다. Recorder producer 변경은 이 artifact와 golden
document를 함께 갱신해야 합니다.

Profile에는 다음을 넣지 않습니다.

- Helper password, token, private key와 endpoint secret
- 환자 정보 또는 측정값
- server가 계산해야 하는 severity와 UI label
- Helper가 소유하는 received/indexed/upload 상태
- filename에서 추론한 bed 또는 Recorder identity

Profile `sequence`는 boot 안에서 1부터 증가합니다. 같은 profile retry는 같은
event ID와 content를 사용하고, 같은 boot에서 설정이 달라지면 sequence를
증가시켜 새 profile event를 만듭니다. 새 boot는 boot ID가 달라지므로 profile
내용이 같아도 새 부팅의 명시적 report로 남습니다.

`profileDigest`는 event ID, sequence와 장비 시각처럼 event마다 달라지는 field를
제외한 canonical profile content로 계산합니다. Body의
`identity.vrcode`는 path VRCODE와 같아야 합니다. `deviceObservedAt`은
`ntpState` 없이 신뢰하지 않으며 current profile 선택은 최신 health
observation과 같은 boot/device의 가장 큰 profile sequence를 우선합니다.

### 4-3. Profile과 분리할 후속 Recorder event

Recorder가 실제로 소유하고 명시적으로 제공할 수 있다면 recording/file
lifecycle은 별도 contract로 추가할 수 있습니다.

- local recording started/stopped
- `.vital` file finalized
- upload attempt started/failed
- client가 받은 upload response

이 정보는 profile에 넣지 않습니다. `uploadId`로 native upload admission과
연결하되 다음 owner state를 구분합니다.

- Recorder는 local file creation과 client attempt를 소유합니다.
- recorder ingress는 upload request 수신을 소유합니다.
- VitalServer file index는 최종 indexed evidence를 소유합니다.

동일한 `upload completed` boolean을 여러 owner가 덮어쓰지 않습니다. 이 계약은
profile과 observability storage를 완성한 뒤 별도 설계합니다.

## 5. PostgreSQL 모델

### 5-1. Schema와 role

기존 VitalDB read model table과 이름 및 migration을 섞지 않고 전용 schema를
사용합니다.

```text
schema: recorder_observability
writer role: recorder_observability_writer
reader role: recorder_observability_reader
```

recorder ingress writer는 admission table만 씁니다. Projection worker는 accepted
event를 읽고 projection table을 씁니다. Guest Control API는 projection을
read-only로 읽습니다.

현재 구현은 아래 네 물리 table을 사용합니다.

```text
recorder_observability.requests  = admission batch
recorder_observability.records   = accepted, duplicate, quarantine line evidence
recorder_observability.current   = Recorder current projection
recorder_observability.expectations = explicit support/deployment evidence
```

DDL의 source of truth는
`apps/vitalserver-postgres-migrator/migrations/versions/`입니다. Recorder ingress는
schema를 생성하거나 변경하지 않습니다.

아래 admission/accepted/quarantine 절은 물리 table을 추가로 뜻하지 않습니다.
`requests`와 `records` 안에서 보존되는 논리 상태를 설명합니다.

### 5-2. Admission batch

`admission_batches`는 HTTP 요청 단위 영수증입니다.

```text
request_id UUID primary key
resource_type
vrcode
request_device_id
source_ip
received_at
line_count
accepted_count
duplicate_count
quarantined_count
contract_version
contract_digest
```

### 5-3. Line disposition

`admission_records`는 비어 있지 않은 NDJSON line마다 한 행을 가집니다.

```text
request_id
line_number
disposition = accepted | duplicate | quarantined
claimed_event_id nullable
document_device_id nullable
content_hash
accepted_event_key nullable
quarantine_id nullable
failure_code nullable
failure_detail nullable
created_at
primary key (request_id, line_number)
```

Duplicate도 반드시 기록합니다. 모든 line disposition이 batch와 같은
transaction에서 commit된 뒤에만 `202`를 반환합니다.

### 5-4. Accepted event

`events`는 검증된 canonical event와 원본 JSONB를 저장합니다.

```text
event_key UUID primary key
vrcode
event_id
resource_type
schema_version
device_id
site_id nullable
boot_id nullable
sequence nullable
device_observed_at nullable
received_at
content_hash
document JSONB
unique (vrcode, event_id)
```

같은 `(vrcode,event_id)`와 같은 canonical content hash는 duplicate입니다.
같은 identity와 다른 hash는 `event_id_content_conflict` quarantine입니다.
Hash 규칙은 raw whitespace가 아니라 계약에서 고정한 canonical JSON 규칙을
사용합니다.

### 5-5. Quarantine

`quarantine_records`는 정상 event table과 분리합니다.

```text
quarantine_id UUID primary key
request_id
line_number
vrcode
resource_type
claimed_event_id nullable
request_device_id
document_device_id nullable
received_at
failure_code
failure_detail
raw_document TEXT
raw_bytes
raw_sha256
```

JSON parse failure도 저장할 수 있도록 원문은 JSONB가 아니라 bounded TEXT로
보존합니다. Request size limit과 line size limit을 모두 적용합니다.

### 5-6. Recorder current projection

`recorder_observability.current`는 Recorder당 한 행의 versioned JSONB
aggregate입니다.

```text
vrcode primary key
device_id
boot_id
profile_record_id nullable
health_record_id nullable
boot_record_id nullable
latest_received_at
report_state
severity
active_signal_count
recent_restart_at nullable
profile_state
projection_version
document JSONB
```

`document`는 accepted resource별 latest evidence와 Profile association을
보존합니다. Product summary는 이 aggregate와 완전한 정책 입력을 사용해
계산합니다. Profile이 없으면 기본 수집 주기를 추정하지 않고
`profileState=missing`과 `reportState=missing`을 제공합니다.

`severity`와 `active_signal_count`는 기존 projection column이지만 승인된
alarm/clearing 정책 전에는 UI health condition으로 사용하지 않습니다. 현재
사용자 계약은 `supportState`, `reportState`, `collectionState`,
`profileState`, `latestObservationReceivedAt`, `lastBootStartedAt`과
`readIssueCount`를 제공합니다.

### 5-7. Support expectation

`recorder_observability.expectations`는 accepted report가 아직 없는 Recorder의
지원 여부를 추정하지 않고 명시적으로 제공하는 owner table입니다.

```text
vrcode primary key
support_state = supported | unsupported
source = deployment_assignment | version_catalog | manual
recorder_version nullable
producer_version nullable
protocol_version nullable
catalog_revision nullable
expected_since nullable
evidence_document JSONB
updated_at
```

행이 없으면 `unknown`입니다. `supported`는 `expected_since`를 요구하며,
`unsupported`는 report freshness 평가 대상이 아닙니다.

### 5-8. Timeline과 incident projection

첫 persistence 단계에서는 만들지 않습니다. Current read API가 안정된 뒤 실제
query를 기준으로 추가합니다.

- `recorder_health_buckets`
- `recorder_boot_transitions`
- `recorder_incident_summaries`
- `projection_checkpoints`

Timeline은 처음에는 bucket identity와 metrics JSONB를 사용합니다. 온도 범위,
storage 부족과 publisher backlog처럼 반복되는 query가 확인되면 해당 JSON path만
typed column 또는 expression index로 승격합니다.

## 6. JSONB 인덱스 정책

기본 index는 JSON 구조와 무관한 identity와 시간 query를 우선합니다.

```sql
CREATE UNIQUE INDEX ON recorder_observability.events (vrcode, event_id);
CREATE INDEX ON recorder_observability.events (vrcode, received_at DESC);
CREATE INDEX ON recorder_observability.events (vrcode, boot_id, sequence);
CREATE INDEX ON recorder_observability.events (resource_type, received_at DESC);
```

Raw document containment과 JSONPath query가 제품 또는 운영 API에 실제로
필요해지면 GIN을 추가합니다.

```sql
CREATE INDEX recorder_observability_events_document_gin
ON recorder_observability.events
USING GIN (document jsonb_path_ops);
```

다음 원칙을 적용합니다.

- 단순히 JSONB가 있다는 이유로 모든 table에 GIN을 만들지 않습니다.
- `@>`, `@?`, `@@` query가 확인되면 `jsonb_path_ops`를 우선 검토합니다.
- key existence `?`, `?|`, `?&`가 필요하면 default `jsonb_ops`를 선택합니다.
- 숫자 범위와 정렬은 query expression과 일치하는 partial expression B-tree를
  사용합니다.
- GIN과 expression index의 write, disk와 vacuum 비용을 capacity test에서
  측정합니다.
- UI list와 detail은 raw event JSONPath search가 아니라 current projection을
  읽습니다.

## 7. Admission transaction과 응답

### 7-1. Request-level failure

다음 상태에서는 line admission을 시작하지 않습니다.

| HTTP | 의미 |
|---|---|
| 400 | required header, VRCODE 또는 NDJSON framing invalid |
| 404 | 지원하지 않는 path/resource |
| 413 | request 또는 line size limit 초과 |
| 415 | media type invalid |
| 429 | 명시적인 ingress capacity limit 초과 |
| 503 | PostgreSQL admission owner를 사용할 수 없음 |

### 7-2. Line-level disposition

JSON parse, schema validation, device ID mismatch와 content conflict는 해당 line의
quarantine입니다. Mixed chunk의 나머지 line을 계속 처리하고 모든 disposition을
한 transaction에 기록합니다.

`202` response는 다음 정보만 의미합니다.

```json
{
  "state": "admitted",
  "requestId": "...",
  "accepted": 2,
  "duplicates": 1,
  "quarantined": 1
}
```

이는 projection과 UI 반영 완료를 의미하지 않습니다. Projection backlog와
failure는 별도 owner status/read contract로 제공합니다.

## 8. Projection과 domain policy

Projection worker는 accepted event를 idempotent하게 처리합니다. Side effect와
retry는 workflow가 소유하고, 상태 판정은 pure domain policy가 소유합니다.

### 8-1. Profile projection

- 최신 health observation과 같은 device ID와 boot ID 안에서 profile sequence가
  가장 큰 event를 current 후보로 선택합니다.
- 같은 boot/profile sequence의 content conflict는 projection에서 해결하지 않고
  admission quarantine으로 남깁니다.
- current health와 다른 과거 boot의 profile이 늦게 도착해도 current profile을
  덮어쓰지 않습니다.
- device ID, boot ID와 generated time이 모순이면 projection failure evidence를
  남깁니다.
- missing profile은 observation interval 60초로 추정하지 않습니다.
- profile이 현재 observation과 다른 device ID를 보고하면 identity issue를
  노출하고 자동 결합하지 않습니다.

### 8-2. Health projection

Health freshness에는 다음 complete input이 필요합니다.

- latest observation server received time
- current server evaluation time
- profile의 configured health interval
- explicit stale tolerance policy
- profile availability/read state

판정 문서 예시는 다음과 같습니다.

```json
{
  "reportState": "current",
  "severity": "warning",
  "evaluatedAt": "2026-07-23T01:02:03Z",
  "policyVersion": "recorder-health/v1",
  "recentRestart": null,
  "signals": [
    {
      "code": "underVoltageNow",
      "severity": "warning",
      "sourceEventId": "device-1:boot-a:42"
    }
  ]
}
```

Signal은 source event ID와 reading path를 보존합니다. Diagnostic message pattern
하나만으로 근본 원인을 확정하지 않습니다.

### 8-3. Boot와 restart

- Linux reboot는 VRCODE 안에서 boot ID transition으로만 생성합니다.
- uptime 감소나 wall clock 변화만으로 reboot를 만들지 않습니다.
- 같은 boot의 Vital Recorder restart count 증가는 OS reboot와 별도 event입니다.
- device time이 불안정하면 같은 boot 순서는 sequence와 uptime을 사용하고,
  외부 시간은 server received time을 사용합니다.

## 9. Product read API

UI 구현 전에 다음 Guest Control read contract를 정의합니다.

### 9-1. Recorder list summary

기존 `GET /runtime/vitaldb/recorders`에는 목록에 필요한 작은 observability summary만
추가합니다.

```text
observability.supportState
observability.supportSource
observability.reportState
observability.expectedSince
observability.latestObservationReceivedAt
observability.collectionState
observability.profileState
observability.lastBootStartedAt
observability.readIssueCount
```

`notReported`는 support state가 아닙니다. 조회가 성공했지만 expectation과
accepted report가 모두 없는 Recorder는 `unknown/notEvaluated`로 표시합니다.

Guest/PostgreSQL read failure를 empty 또는 `No health report`로 바꾸지 않습니다.

### 9-2. Recorder observability detail

```text
GET /runtime/vitaldb/recorders/{vrcode}/observability
```

응답은 다음 owner read를 명시적으로 구분합니다.

- profile current read
- health current read
- recent restart evidence
- active signals
- read errors

### 9-3. Timeline과 incidents

```text
GET /runtime/vitaldb/recorders/{vrcode}/observability/timeline
GET /runtime/vitaldb/recorders/{vrcode}/observability/incidents
```

Timeline query는 `from`, `until`, `bucketSeconds`와 page/cursor를 요구합니다.
전체 raw history를 Swift나 브라우저로 보내지 않습니다. Incidents는 opaque cursor,
limit, type과 severity filter를 사용합니다.

## 10. Retention, backup과 운영

Retention은 raw payload, idempotency identity, quarantine, projection별로
분리합니다. 한 retention job이 서로 다른 state를 함께 삭제하지 않습니다.

| 데이터 | 초기 방향 |
|---|---|
| admission batch/line receipt | 운영 조사 기간 동안 보존 |
| accepted raw JSONB | 실제 payload 크기와 장비 수 capacity test 후 기간 확정 |
| event identity/content hash | producer retry horizon과 충돌 탐지 정책에 맞춰 raw보다 길게 보존 |
| quarantine raw | bounded 기간과 용량 제한 |
| profile current | Recorder deletion policy까지 |
| profile history | accepted event retention 적용 |
| health current | Recorder deletion policy까지 |
| timeline buckets | raw보다 긴 제품 조회 기간을 별도 설정 가능 |
| kernel incident summary | 일반 observation보다 긴 보존 정책 검토 |

Retention 값이 missing 또는 unreadable이면 disabled로 추정하지 않습니다. 설정
owner가 explicit unavailable/error를 보고하고 deletion job은 시작하지 않습니다.

Runtime backup은 새 PostgreSQL schema를 포함해야 합니다. Restore 후 admission
identity, accepted event, current projection과 projection checkpoint의 일관성을
검증합니다.

운영 status에는 최소한 다음을 제공합니다.

- 마지막 admission 성공/실패 시각
- resource별 accepted/duplicate/quarantined count
- PostgreSQL write failure
- projection pending count와 oldest pending age
- projection last success/failure
- quarantine retention 상태
- contract version과 digest

## 11. 기존 file ledger migration

기존 `ledger-YYYY-MM-DD.ndjson`은 다음 절차로 한 번만 가져옵니다.

1. 모든 segment와 SHA-256 manifest를 생성합니다.
2. batch와 record schema를 검증합니다.
3. accepted record는 `(vrcode,eventId)`와 canonical content hash로 import합니다.
4. 기존 conflict 또는 invalid ledger는 자동 성공 처리하지 않고 migration
   failure/quarantine report에 남깁니다.
5. imported segment, line range, count와 checksum receipt를 PostgreSQL에
   기록합니다.
6. import를 재실행해도 같은 receipt와 event가 중복 생성되지 않음을 검증합니다.
7. cutover 후 file ledger writer를 제거합니다.
8. 원본 ledger는 승인된 backup/diagnostics 위치로 이동한 뒤 retention 정책을
   적용합니다.

File write 실패 시 PostgreSQL로, PostgreSQL 실패 시 file로 전환하는 runtime
fallback은 두 owner를 만들기 때문에 사용하지 않습니다.

## 12. 단계별 구현

### 현재 구현 checkpoint

완료:

- authoritative v1 contract admission과 PostgreSQL durable disposition
- Profile/Observation/Boot current aggregate와 freshness policy
- support expectation schema와 first-report grace policy
- Ingress -> Guest Control -> Runtime Control summary contract
- Swift/PWA Recorder 목록 및 Detail의 support/report 표시

남음:

- deployment assignment 또는 승인된 version catalog가 expectation을 기록하는
  application workflow
- Profile/resource 세부 정보를 위한 작은 typed Detail DTO
- Timeline/incident bounded query와 projection
- PostgreSQL migration을 적용한 실제 DB 통합 검증
- capacity, retention, backup/restore와 release proof

### Phase 0. 계약과 ADR

- Recorder profile 목적, owner와 금지 field를 ADR로 확정합니다.
- Recorder v1 schema artifact 배포와 VitalServer vendoring receipt 형식을
  정의합니다.
- canonical JSON hash 규칙을 확정합니다.
- current POST의 partial hand-written validator와 duplicate non-persistence를
  known gap으로 기록합니다.

완료 조건:

- Recorder와 VitalServer가 같은 schema file/digest를 사용합니다.
- Profile schema와 event identity 규칙이 Recorder 저장소에서 승인됩니다.

### Phase 1. Authoritative validation

- JSON Schema 2020-12 validator를 recorder ingress에 추가합니다.
- 기존 hand-written nested validator를 제거합니다.
- OpenAPI에 각 NDJSON line의 authoritative item schema와 contract digest를
  연결합니다.
- observation, diagnostic, kernel incident golden document를 Recorder artifact에서
  가져와 contract test를 실행합니다.

완료 조건:

- malformed nested reading과 unknown field가 quarantine됩니다.
- valid Recorder golden documents가 세 endpoint에서 accepted됩니다.

### Phase 2. PostgreSQL admission

- schema migration과 전용 role을 추가합니다.
- batch, line disposition, accepted event와 quarantine repository port를
  구현합니다.
- 한 transaction으로 mixed chunk를 처리합니다.
- process memory의 전체 accepted identity map을 제거합니다.
- compose, health check, backup과 restore manifest에 dependency를 반영합니다.

완료 조건:

- process restart 후 duplicate가 duplicate로 남습니다.
- duplicate line도 durable record를 가집니다.
- event ID content conflict가 quarantine됩니다.
- commit 전 crash 또는 database failure는 `202`가 아니라 `503`입니다.

### Phase 3. Profile producer와 admission

Recorder 저장소:

- profile domain/document/schema를 구현합니다.
- boot/config change emission policy를 구현합니다.
- secret과 patient field 금지 test를 추가합니다.
- Fluent Bit profile input/output과 persistent cursor/buffer를 구성합니다.

VitalServer 저장소:

- `/profiles` admission을 추가합니다.
- profile current projector와 read repository를 구현합니다.

완료 조건:

- 동일 profile retry는 duplicate입니다.
- 같은 boot에서 설정 변경은 새 profile입니다.
- profile missing/invalid/read failure가 current health default로 바뀌지 않습니다.

### Phase 4. Health current projection

- profile과 latest observation을 complete input으로 받는 pure policy를
  구현합니다.
- report state, severity, recent restart와 signal contract를 정의합니다.
- projection checkpoint와 retry state를 영속화합니다.
- Guest Control observability detail endpoint를 추가합니다.

완료 조건:

- missing, stale, invalid와 dependency failure가 서로 다른 response입니다.
- projector 재실행 결과가 동일합니다.
- source event ID와 policy version을 통해 모든 판정을 추적할 수 있습니다.

### Phase 5. Timeline과 incident query

- 실제 UI query를 기준으로 bucket schema를 정의합니다.
- boot transition과 diagnostic/kernel incident projection을 추가합니다.
- 필요한 JSONB GIN 또는 expression index만 추가합니다.
- cursor pagination과 bounded response를 구현합니다.

완료 조건:

- 여러 boot의 uptime counter를 이어 붙이지 않습니다.
- time-unsynchronized 구간이 wall clock 기준으로 잘못 정렬되지 않습니다.
- 장기간 조회가 raw event 전체를 application memory에 materialize하지 않습니다.

### Phase 6. Swift/PWA

- Recorder 목록에 작은 observability summary를 추가합니다.
- Detail은 profile, current health, signals, timeline과 incidents를 lazy load합니다.
- Swift/PWA가 같은 generated API contract와 label policy를 사용합니다.
- UI가 severity, report state와 recent restart를 하나의 enum으로 재분류하지
  않습니다.

### Phase 7. Capacity, retention과 release proof

- 실제 Recorder observation 평균/p95/max JSON 크기를 측정합니다.
- 1, 10, 100 Recorder의 admission과 60일 상당 데이터를 시험합니다.
- GIN 유무에 따른 write latency, index 크기와 query latency를 비교합니다.
- retention, vacuum, backup/restore와 projection rebuild proof를 실행합니다.
- 반복 운영 실패를 troubleshooting 문서로 승격합니다.

## 13. 필수 테스트

### Contract

- 세 기존 v1 schema와 profile schema golden acceptance
- nested reading state/value/detail invariant
- unknown field, invalid enum, invalid timestamp와 wrong endpoint
- header/body device ID mismatch

### Admission

- accepted, duplicate, quarantine mixed chunk
- 같은 request 안의 duplicate
- process restart 뒤 duplicate
- same identity/different content conflict
- malformed JSON raw quarantine
- request/line size boundary
- PostgreSQL unavailable, timeout와 transaction rollback

### Projection

- out-of-order observation
- sequence gap
- boot transition
- same-boot Recorder service restart
- device clock rollback과 NTP unavailable
- profile missing, stale, changed와 device mismatch
- replay/rebuild idempotency

### API

- loaded empty와 read failure 구분
- current/stale/missing/readFailed 구분
- severity unknown 보존
- cursor와 bounded timeline
- PWA/Swift generated contract parity

### Operations

- migration import 재실행
- backup/restore
- retention dry-run과 explicit execution
- projector backlog/failure status
- 5 MiB request와 sustained Recorder load

## 14. 구현하지 않을 것

- Recorder 원본 payload의 모든 field를 관계형 column으로 정규화하지 않습니다.
- UI가 raw JSONB를 직접 검색하거나 domain state를 만들지 않습니다.
- profile 부재를 기본 60초 interval이나 알려진 version으로 채우지 않습니다.
- filename, IP, bed name으로 VRCODE identity를 만들지 않습니다.
- diagnostic message pattern만으로 reboot root cause를 확정하지 않습니다.
- PostgreSQL failure를 file fallback success로 숨기지 않습니다.
- 모든 JSONB path에 선제적으로 index를 만들지 않습니다.

## 15. 후속 범위 실행 계획

이 절은 current summary 이후 작업을 두 workstream과 하나의 release
gate로 나눕니다. PostgreSQL backup이 Detail 코드 작성의 선행 조건은 아니지만,
전체 database backup/restore proof 없이는 새 schema를 포함한 정식 패키지를
배포하지 않습니다.

```text
Phase 0: explicit baseline
  |
  +-- Workstream A: Recorder product
  |     expectation owner
  |       -> typed Detail
  |       -> Swift/PWA lazy Detail
  |       -> bounded timeline/incidents
  |
  +-- Workstream B: Guest PostgreSQL platform
        full backup/restore
          -> capacity measurement
          -> owner-specific retention decision

Workstream A + Workstream B
  -> install/update/reboot/restore release gate
```

### 15-0. Phase 0: explicit baseline

구현을 시작하기 전에 다음 state를 read-only proof로 남깁니다.

- 설치 DB의 `alembic_version`
- `0002_observability_expectations` 적용 여부
- schema/table별 PostgreSQL estimated row count와 total/index size
- PostgreSQL volume과 현재 backup artifact 존재 여부
- Redis, PostgreSQL, `.vital` file과 recovery artifact의 현재 backup 포함/제외
- Guest observation writer, Product Lab과 Recorder Ingress의 write pause 방법
- Recorder deployment owner가 제공할 assignment document와 version evidence

이 proof 없이 migration file을 수정하거나 기존 설치가 clean이라고 가정하지
않습니다.

DB revision은 `public.alembic_version`을 명시적으로 읽고, schema readiness는
migrator와 각 repository의 startup verification으로 확인합니다. 별도 범용
inventory CLI를 제품 계약으로 두지 않습니다. PostgreSQL volume/backup
artifact, Redis와 `.vital` 파일은 서로 다른 owner state이므로 각 owner의
명시적인 계약으로 확인합니다.

Phase 0 결과로 다음 결정을 기록합니다.

1. `0002` 미적용이면 unreleased migration을 정리할지
2. `0002` 적용이면 additive migration을 만들지
3. 정식 backup에 포함되는 store와 명시적으로 제외되는 store
4. 첫 production rollout의 Recorder 수와 관측 주기

### 15-1. Workstream A1: support expectation owner와 command workflow

#### 결정

- 배포 assignment를 primary provider로 사용합니다.
- 승인된 version catalog는 Recorder 앱과 Observer producer의 결합 관계가
  release artifact와 digest로 고정된 경우에만 사용합니다.
- VitalDB 목록의 `version` 문자열 하나만으로 POST 지원 여부를 계산하지
  않습니다.
- accepted report는 계속 `supported`의 직접 증거입니다.
- provider도 accepted report도 없으면 `unknown/notEvaluated`입니다.
- manual 입력은 자동 판정 fallback이 아니라 actor와 reason을 요구하는 명시적
  command입니다.

#### 도메인 계약

```text
ExpectationCommand
  commandId
  vrcode
  expectedRevision
  action = set | clear
  supportState = supported | unsupported       # action=set only
  source = deployment_assignment | version_catalog | manual
  recorderVersion nullable
  producerVersion nullable
  protocolVersion nullable
  catalogRevision nullable
  expectedSince nullable                        # supported requires value
  evidenceDocument
  decidedAt

ExpectationDecision
  accepted | idempotent | revisionConflict | rejected
  currentRevision
  eventId nullable
  failure nullable
```

Domain/Core의 pure transition policy가 command, current revision과 invariant를
받아 event와 current projection command를 반환합니다. HTTP adapter나 repository가
revision 충돌, clear 또는 source precedence를 결정하지 않습니다.

#### PostgreSQL

current `0002` migration이 어떤 설치에도 적용되지 않았다는 proof가 있으면
unreleased migration을 수정합니다. 적용 이력이 있으면 기존 revision을 바꾸지
않고 새 migration을 추가합니다.

```text
recorder_observability.expectation_events
  event_id UUID primary key
  command_id UUID unique
  vrcode
  previous_revision
  revision
  action = set | clear
  support_state nullable
  source
  version/evidence fields
  decided_at
  received_at
  unique (vrcode, revision)

recorder_observability.expectations
  vrcode primary key
  revision
  lifecycle_state = active | cleared
  source_event_id unique
  support/version/evidence fields
  updated_at
```

`clear` event도 삭제하지 않습니다. current row의 `cleared` 상태는 repository가
domain expectation 부재로 전달하므로 제품 응답은 `unknown/notEvaluated`가
됩니다. DB row 부재, cleared, DB read failure는 repository result에서 서로
구분합니다.

#### API와 경계

1. recorder ingress application port에 expectation command를 추가합니다.
2. PostgreSQL adapter가 event append와 current CAS update를 한 transaction으로
   수행합니다.
3. ingress internal command endpoint를 추가합니다.
4. Guest Control adapter/usecase가 이 command를 명시적으로 전달합니다.
5. Runtime Control에는 authenticated admin/deployment endpoint만 노출합니다.
6. Recorder 사용자 화면에는 manual support editor를 넣지 않습니다. 필요하면
   Advanced 운영 화면에서만 별도 설계합니다.

Ingress control endpoint에는 별도 control credential을 사용합니다. credential이
missing/unreadable이면 command capability가 unavailable이어야 하며 일반
observability POST credential이나 빈 값으로 대체하지 않습니다.

#### 완료 조건

- 같은 `commandId` 재전송이 같은 receipt를 반환합니다.
- stale `expectedRevision`은 `409 revisionConflict`입니다.
- `supported`의 `expectedSince` 누락은 저장 전에 거절됩니다.
- `clear` 이후 read contract는 `unknown/notEvaluated`입니다.
- delayed old command가 새 assignment를 덮어쓰지 못합니다.
- DB transaction 실패는 success receipt를 만들지 않습니다.
- accepted POST가 존재하면 stale catalog보다 직접 evidence가 우선합니다.

### 15-2. Workstream A2: typed Recorder observability Detail

현재 ingress Detail의 raw `resources`는 내부 evidence이며 Swift/PWA contract로
전파하지 않습니다. Application query mapper가 다음 typed DTO를 만듭니다.

```text
RecorderObservabilityDetail
  state = loaded | notReported | unavailable
  vrcode
  support
    state, source, expectedSince
    recorderVersion, producerVersion, protocolVersion
  report
    state, receivedAt, deviceObservedAt
    collectionState, readIssueCount
  profile
    state = associated | unassociated | missing | invalid
    receivedAt, deviceId, bootId
    software
    collection intervals
    capabilities
  boot
    state
    bootId, startedAt, cleanShutdownAt
  readings
    temperature
    memory available/total
    root/data storage used
    Recorder service state
    publisher state and buffer usage
    network interface summaries
  readIssues
  readError
```

각 reading은 `state`, nullable `value`, nullable `detail`, source timestamp를
가집니다. `missing`, `invalid`, `failed`, `unsupported`를 `0`, `false` 또는
정상으로 바꾸지 않습니다. Observer가 제공한 memory/storage/buffer reading은
그 상태와 값을 그대로 typed mapper에 전달하며, 누락된 분자나 분모를 UI가
추정해 percentage로 만들지 않습니다.

구현 순서:

1. ingress domain mapper와 golden contract test
2. ingress typed Detail query endpoint
3. Guest adapter의 strict decoder
4. Runtime Guest gateway/provider와
   `GET /runtime/vitaldb/recorders/{vrcode}/observability`
5. Runtime OpenAPI 및 generated TypeScript
6. PWA query key/hook와 선택된 Recorder 기준 lazy load
7. Swift async detail provider와 선택된 Recorder 기준 lazy load

Detail 실패는 Recorder 목록 전체를 실패시키지 않고 해당 section의
`unavailable/readFailed`로 남깁니다. 목록 summary와 Detail의 support/report
field가 다르면 contract mismatch로 표시하고 UI가 하나를 임의 선택하지 않습니다.

#### 완료 조건

- raw JSONB field가 Runtime public response에 노출되지 않습니다.
- Profile association 실패와 Profile 부재가 구분됩니다.
- PWA/Swift가 같은 fixture에서 같은 label과 값 상태를 표시합니다.
- Detail을 열기 전에는 Detail 요청이 발생하지 않습니다.
- Recorder 선택 변경 시 이전 Recorder 응답을 새 Recorder에 표시하지 않습니다.

PWA/Swift lazy Detail은 별도 commit으로 분리하되 A2 public contract가 확정된
직후 수행합니다.

2026-07-24 기준 1~7단계 public contract와 lazy presentation은
구현되었습니다. Ingress는 내부
aggregate JSONB를 typed DTO로 투영하고, Guest strict decoder와 Runtime Guest
gateway/Runtime Control GET route가 같은 계약을 사용합니다. 서로 다른 boot의
start/shutdown evidence는 합치지 않으며 저장 projection의
`latest_unassociated`는 공개 계약의 `unassociated`로 정규화합니다. PWA와
Swift는 Recorder가 선택되기 전에는 Detail을 읽지 않고, vrcode별 결과를
분리해 이전 Recorder 응답을 현재 선택에 표시하지 않습니다. 목록 summary와
Detail의 support/report가 다르면 mismatch를 명시적으로 표시합니다.

### 15-3. Workstream A3: bounded timeline과 incident query

초기에는 새 시계열 table을 선제적으로 만들지 않습니다.
`recorder_observability.records_history_idx`와 accepted JSONB evidence를 사용해
query proof를 먼저 만듭니다.

```text
GET /runtime/vitaldb/recorders/{vrcode}/observability/timeline
  from, until, bucketSeconds

GET /runtime/vitaldb/recorders/{vrcode}/observability/incidents
  from, until, type, cursor, limit
```

- `from`, `until`과 최대 window를 필수 검증합니다.
- `bucketSeconds`는 server가 허용한 enum만 받습니다.
- PostgreSQL `date_bin`과 explicit JSON reading state로 집계합니다.
- temperature, memory availability, root/data used percent와 publisher buffer
  사용량처럼 직접 설명 가능한 값만 1차 chart metric으로 제공합니다.
- `Stable`, `Critical` 같은 condition은 승인된 threshold/clearing policy 전에는
  만들지 않습니다.
- device time이 trusted인 row와 server receipt time을 섞지 않고 time basis를
  response metadata로 제공합니다.
- incident cursor는 `(received_at, record_id)` opaque encoding을 사용합니다.

Explain analyze 결과나 payload 크기가 목표를 넘을 때만 bucket/incident
projection migration을 추가합니다. GIN index도 실제 JSON containment query가
확정된 path에만 만듭니다.

2026-07-24 기준 1차 bounded query가 구현되었습니다. 별도 timeline/incident
table 없이 accepted `records`와 기존 history index를 사용하며, timeline은
최대 24시간과 `300|900|3600`초 bucket, incident는 최대 30일과 100개 page로
제한합니다. 모든 시간축은 `receivedAt`이고 incident cursor는
`(received_at, record_id)`를 opaque하게 인코딩합니다. 활성 expectation이
`unsupported`이고 해당 구간의 accepted observation도 없으면
`state=unsupported`를 반환하며, expectation이나 report가 없는 경우의
`notReported`와 분리합니다. accepted observation은 support의 직접 evidence라서
같은 구간에 row가 있으면 expectation보다 우선해 `supported/loaded`입니다.

Guest와 Runtime Control은 query를 재검증하고 결과 state를 그대로 전달합니다.
PWA Recorder Detail은 Recorder를 선택한 뒤에만 24시간/15분 timeline과 최근
20개 incident를 lazy read합니다. 현재 chart는 직접 설명 가능한 root/data
storage percent만 표시하며 condition label이나 임계값을 추론하지 않습니다.
Swift와 다른 client도 동일한 Runtime Control endpoint를 사용할 수 있습니다.

#### 완료 조건

- 한 Recorder 24시간 기본 window가 bounded row/payload 제한 안에 들어옵니다.
- 여러 boot의 uptime/counter를 이어 붙이지 않습니다.
- unsupported/notReported Recorder는 빈 성공 chart가 아니라 명시적 상태를
  반환합니다.
- cursor 재요청에서 누락과 중복이 없습니다.

### 15-4. Workstream B1: VitalServer PostgreSQL 전체 backup/restore

이 단계는 Recorder observability 전용 기능이 아니라 Guest platform 공통
maintenance 범위입니다. 현재 PostgreSQL에는 다음 owner schema가 함께 있습니다.

```text
vitaldb_read_model
  observation_snapshots
  recorder_activity_buckets
  relationship_history_snapshots
  entity_visibility

product_lab
  sessions
  beds
  recorders

recorder_observability
  requests
  records
  current
  expectations / expectation_events

public
  alembic_version
```

Retention보다 전체 database backup을 먼저 구현합니다. 현재 Redis-only
maintenance operation을 PostgreSQL 성공으로 간주하지 않습니다. Schema별
부분 dump를 기본 backup으로 사용하지 않고 한 database snapshot으로 owner
schema와 migration revision의 일관성을 유지합니다.

```text
PostgreSQLBackupManifest
  schemaVersion
  databaseName
  serverVersion
  alembicRevision
  createdAt
  dumpFormat
  dumpFile
  dumpSha256
  dumpSizeBytes
```

- Guest maintenance adapter가 `pg_dump --format=custom`을 실행합니다.
- dump와 manifest를 같은 managed backup directory에 저장합니다.
- manifest/dump write, checksum 또는 `pg_dump` 실패는 operation failure입니다.
- restore는 maintenance state에서만 수행합니다.
- restore 동안 Guest observation writer, Product Lab과 Recorder Ingress writer를
  정지하거나 명시적인 maintenance write barrier에 진입시킵니다.
- `pg_restore` 전 manifest, checksum, 고정 database name과 migration revision을
  검증합니다.
- restore 후 migrator, schema readiness와 representative read proof를
  실행한 뒤에만 completed로 전이합니다.
- update, repair와 uninstall 보존 workflow가 PostgreSQL backup receipt를
  명시적으로 요구하도록 확장합니다.

백업 실패 시 Redis backup이나 기존 volume이 있다는 이유로 PostgreSQL backup
성공으로 진행하지 않습니다. Redis와 PostgreSQL은 서로 다른 owner store이므로
각각의 receipt를 유지합니다.

#### 구현 checkpoint

현재 Guest Control의 PostgreSQL backup/restore operation, custom dump
manifest/checksum 검증, restore write barrier, Host VitalServer backup의 required
`postgres-database` artifact와 compatibility version 2까지 구현되었습니다.
통합 backup의 최종 package 검증 후 그 operation이 만든 Redis/PostgreSQL
maintenance archive를 삭제하고, cleanup 실패는 최종 backup을 보존한
`completedWithCleanupFailure`로 보고합니다.
제품 restore는 PostgreSQL 복원에 `restartRuntime=false`를 명시하고 Redis
복원이 끝날 때까지 writer를 재기동하지 않습니다.
Update shutdown은 Redis와 PostgreSQL receipt가 모두 있어야
`poweroff-ready`로 승인되며, standard uninstall과 VM disk repair의 보존
작업도 Redis-only가 아니라 VitalServer backup을 생성합니다. VM disk repair의
backup은 기존 disk archive가 별도로 남기 때문에 명시적인 best-effort
degraded operation으로 유지합니다.

`make runtime/proof/postgres-restore`는 실제 Guest Compose/PostgreSQL에서
migration, 대표 데이터 write, custom dump, 새 database restore, owner schema별
representative read equality를 검증합니다. 별도 diagnostics inventory와 통합
backup 중간 archive retention은 축소 범위에서 제품 기능으로 만들지 않습니다.
용량 측정과 사용자가 직접 생성한 standalone maintenance backup 보관 정책은
실제 운영 필요가 확인될 때 별도 결정합니다.

Redis와 PostgreSQL snapshot은 각각 내부적으로 일관되지만 서로 다른 시점에
순차 생성됩니다. 현재 구현은 cross-datastore distributed transaction을
제공하거나 주장하지 않습니다.

#### 완료 조건

- VitalDB history/visibility, Product Lab session/bed/recorder와 Recorder
  observability evidence/current/expectation이 모두 restore됩니다.
- checksum mismatch와 incompatible revision이 restore 전에 중단됩니다.
- restore 실패가 기존 DB를 부분 성공 상태로 표시하지 않습니다.
- 새 VM에서 backup restore 후 각 schema의 representative read가 동일합니다.

### 15-5. Workstream B2: capacity 측정과 owner별 retention/rebuild

먼저 schema/table별 row 증가량, 평균/p95 document 크기, index 비율과 대표 query
latency를 측정합니다. 측정 결과가 retention 필요성을 증명한 resource에만
정책을 추가합니다.

하나의 공통 TTL로 전체 PostgreSQL을 정리하지 않습니다. 각 schema owner가
자신의 삭제 의미와 rebuild 조건을 정의합니다.

- `vitaldb_read_model`: observation/relationship snapshot과 activity bucket 기간
- `product_lab`: 일반 TTL 없음, 명시적인 session/bed/recorder 삭제만 적용
- `recorder_observability`: accepted/duplicate/quarantine evidence와 current
  source 보호

실제 row 증가량, payload 크기와 제품 조회 기간을 측정한 뒤 owner별 설정 값을
확정합니다.

```text
RetentionPolicy
  owner
  resource
  retentionDays or retainForever
  batchSize
  dryRun

RetentionRun
  runId
  policyReceipt
  state
  candidate/removed/blocked counts
  oldest/newest boundary
  failure
```

- 설정 missing/decode failure는 disabled가 아니라 unavailable입니다.
- dry-run과 execute를 별도 command로 둡니다.
- current source record, duplicate pointer 대상과 projection pending/failed row는
  삭제 대상에서 제외합니다.
- 삭제 순서와 foreign-key blocker를 domain plan으로 먼저 계산합니다.
- expectation audit event는 별도 승인 없이 일반 observation retention과 함께
  삭제하지 않습니다.
- Product Lab current state는 observability evidence retention job이 접근하지
  않습니다.
- rebuild는 accepted evidence, projection version과 checkpoint를 명시적으로
  입력받습니다.

#### 완료 조건

- dry-run count와 실제 삭제 count가 설명 가능합니다.
- 같은 retention run 재실행이 안전합니다.
- current projection을 재생성할 source가 사라지지 않습니다.
- retention 도중 실패가 성공이나 zero removal로 기록되지 않습니다.

### 15-6. Release gate: proof와 cutover

필수 proof:

1. 빈 PostgreSQL에서 전체 Alembic upgrade
2. 기존 revision에서 upgrade 후 데이터 보존
3. expectation set/idempotent/conflict/clear
4. observation/profile/boot out-of-order projection
5. actual PostgreSQL summary/Detail/timeline integration (integration DB 필요)
6. PWA/Swift generated contract parity
7. 전체 PostgreSQL backup -> 새 DB restore -> schema별 read equality
8. clean install, in-place update와 재부팅 후 read equality
9. 1/10/100 Recorder sustained admission과 query latency
10. DMG distribution review와 runtime smoke

권장 commit 단위:

1. Phase 0 installed-state/capacity baseline 문서와 proof tool
2. PostgreSQL backup domain/workflow와 manifest
3. PostgreSQL restore workflow, Guest/Host maintenance integration과 restore proof
4. expectation event/current migration과 pure transition policy
5. expectation command workflow, internal adapter와 Guest/Runtime forwarding
6. typed Detail backend와 public Runtime contract
7. PWA/Swift lazy Detail
8. bounded timeline/incidents — 구현됨, actual PostgreSQL integration proof 남음
9. schema별 capacity report와 retention decision
10. 필요성이 증명된 owner의 retention/rebuild
11. install/update/reboot release proof와 troubleshooting

각 commit은 해당 계층의 focused test와 contract 문서를 함께 포함합니다.
