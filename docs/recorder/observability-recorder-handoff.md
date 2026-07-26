# Recorder observability API and database handoff

> **문서 상태:** 이 문서는 초기 공동 설계와 합의 과정을 보존합니다. 다섯 POST,
> PostgreSQL admission/current/history query와 Swift/PWA presentation은 이후
> 구현됐으므로 현재 계약과 배포 판단은
> [Recorder observability 호환성과 배포 순서](observability-compatibility-and-rollout.md)를
> 먼저 확인합니다. 아래의 “제안”, “아직 구현되지 않음” 표현은 당시 설계
> checkpoint이며 현재 구현 상태를 뜻하지 않습니다.

## 1. 전달 목적

이 문서는 Vital Recorder 작업자가 다음 내용을 한 번에 확인하기 위한 협의
자료입니다.

- Recorder가 현재 보내는 세 observability POST의 목표 계약
- VitalServer가 수신 문서를 PostgreSQL에 어떻게 저장할 계획인지
- 추가로 제안하는 Recorder profile POST
- Recorder와 VitalServer가 각각 구현해야 하는 범위
- 구현 전에 함께 확정해야 할 항목

상세한 VitalServer 구현 단계는
[Recorder observability persistence and API implementation plan](observability-persistence-and-api-plan.md)을
참조합니다.

## 2. 현재 상태와 목표 상태

### 2-1. 현재 VitalServer에 들어간 범위

Recorder ingress에는 다음 endpoint의 초기 구현이 있습니다.

```text
POST /api/v1/recorders/{vrcode}/observations
POST /api/v1/recorders/{vrcode}/diagnostic-events
POST /api/v1/recorders/{vrcode}/kernel-incidents
```

현재 구현은 다음 범위를 제공합니다.

- `application/x-ndjson`
- `X-Device-ID`
- VRCODE path 검증
- 기본 5 MiB request limit
- accepted/duplicate/quarantined 분류의 기초
- 일별 NDJSON file ledger

하지만 아직 production 완료 상태가 아닙니다.

- Recorder authoritative JSON Schema 전체를 직접 사용하지 않습니다.
- nested payload 검증은 부분적입니다.
- duplicate line disposition이 모두 영속화되지 않습니다.
- accepted identity를 process memory에 올립니다.
- PostgreSQL event store와 read projection이 없습니다.
- profile endpoint가 없습니다.
- product read API가 없습니다.

따라서 Recorder 작업자는 기존 세 endpoint의 path와 document 의미는 유지하되,
VitalServer PostgreSQL cutover 및 contract digest가 확정되기 전까지 “서버 조회
저장소까지 완성됐다”고 가정하지 않습니다.

### 2-2. 목표 상태

```text
Recorder Observer
  -> NDJSON POST
  -> VitalServer authoritative schema validation
  -> PostgreSQL admission transaction
     -> request/line disposition
     -> accepted JSONB event or quarantine
  -> 202 Accepted
  -> asynchronous current/timeline projection
  -> Guest Control read API
  -> Swift/PWA
```

`202`는 모든 non-empty line이 `accepted`, `duplicate` 또는 `quarantined`로
PostgreSQL에 영속화됐다는 뜻입니다. Current health projection이나 UI 반영
완료를 뜻하지 않습니다.

## 3. 공통 POST 계약

### 3-1. Identity

| 값 | 의미 |
|---|---|
| path `{vrcode}` | 제조사가 발급한 Recorder identity |
| `X-Device-ID` | Observer deployment identity |
| body `deviceId` | 문서를 생성한 Observer deployment identity |

`X-Device-ID`와 body `deviceId`는 같아야 합니다. VRCODE와 device ID를 합치거나
서로 대신하지 않습니다.

현재 VRCODE와 device ID는 reported identity입니다. 이 값만으로 인증됐다고
표현하지 않습니다. 인증과 transport security는 별도 합의 항목입니다.

### 3-2. Delivery

- Content type: `application/x-ndjson`
- 한 non-empty line에 JSON object 한 건
- Delivery: at-least-once
- Idempotency identity: `(vrcode, eventId)`
- 같은 identity와 같은 canonical content: `duplicate`
- 같은 identity와 다른 content: `event_id_content_conflict` quarantine
- Schema invalid, device mismatch와 parse failure: 해당 line quarantine
- Mixed chunk: 모든 line disposition을 기록한 뒤 `202`

Recorder publisher가 response를 받지 못하면 같은 event ID와 같은 document를
그대로 재시도해야 합니다. Retry 때 event timestamp나 optional field를
재생성하면 content conflict가 됩니다.

### 3-3. Request-level response

| HTTP | 의미 | Recorder 동작 |
|---|---|---|
| 202 | 모든 line disposition이 durable | 해당 chunk 완료 |
| 400 | header, VRCODE 또는 NDJSON framing invalid | 설정/producer 수정 |
| 404 | endpoint 또는 path invalid | endpoint 수정 |
| 413 | request 또는 line size limit 초과 | chunk size 수정 |
| 415 | content type invalid | header 수정 |
| 429 | ingress capacity 초과 | backoff 후 재시도 |
| 503 | PostgreSQL admission store unavailable | persistent buffer에서 재시도 |

영구 4xx를 같은 payload로 무한 재시도하지 않습니다. Connection error, 408, 429와
5xx는 publisher retry 대상입니다.

## 4. 기존 Recorder 문서

VitalServer는 Recorder 저장소가 소유한 다음 JSON Schema를 versioned artifact로
받아 그대로 검증할 계획입니다.

```text
contracts/observation/v1/observation.schema.json
contracts/observation/v1/log.schema.json
contracts/observation/v1/kernel-incident.schema.json
```

VitalServer는 이 nested contract를 별도로 손으로 재작성하지 않습니다. Artifact는
source commit과 각 file SHA-256 receipt를 포함해야 합니다. 배포된 v1 contract를
incompatible하게 변경하지 않고 새 contract version을 만듭니다.

Recorder가 이미 제공하는 정보는 다음과 같습니다.

| Resource | 주요 정보 |
|---|---|
| device-health | boot/sequence/uptime, NTP, system, memory, storage, Raspberry Pi, network, Recorder/publisher service와 read issues |
| diagnostic-log | power, thermal, storage, network, service lifecycle와 명시적 reboot evidence |
| kernel-incident | panic/Oops/watchdog/lockup summary와 pstore artifact metadata |

`Stable`, `Needs attention`, `Critical` 같은 판정은 Recorder document에 넣지
않습니다. VitalServer가 source event와 versioned policy로 계산합니다.

## 5. 제안 Profile API

### 5-1. 목적

Health observation에는 현재 장비 상태가 들어갑니다. 다음처럼 변경 주기가 느리고
health freshness를 해석하는 데 필요한 정보는 별도 profile로 보냅니다.

- Observer, Vital Recorder, OS/image와 kernel version
- 실제 health/power/telemetry interval
- 설치된 capability
- configured data path
- configured network interface와 serial device
- publisher persistent buffer limit
- pinned VRCODE state

### 5-2. 제안 endpoint

```text
POST /api/v1/recorders/{vrcode}/profiles
Content-Type: application/x-ndjson
X-Device-ID: <observer device id>
```

이 endpoint는 아직 구현 완료된 public contract가 아닙니다. Recorder와
VitalServer가 `profile.schema.json`, event identity와 digest 규칙을 합의한 후
구현합니다.

### 5-3. Profile emission

Profile은 다음 시점에 생성합니다.

- Observer가 부팅된 뒤 profile source를 읽었을 때
- 같은 boot에서 profile content가 변경됐을 때

주기적인 60초 health observation마다 반복 생성하지 않습니다.

```text
eventId = deviceId + ":" + bootId + ":profile:" + sequence
```

- Profile sequence는 boot마다 1부터 시작합니다.
- 같은 event retry는 같은 event ID와 같은 document를 사용합니다.
- 같은 boot에서 profile content가 변경되면 sequence를 증가시킵니다.
- 새 boot는 profile 내용이 같아도 새 boot ID와 sequence 1로 report합니다.

### 5-4. Profile document 초안

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
    "healthIntervalSeconds": 60,
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

Profile도 `ok`, `missing`, `invalid`, `failed`, `unsupported`의 typed reading
의미를 유지합니다. Version command가 실패했을 때 빈 문자열이나 알려진
version을 넣지 않습니다.

Body `identity.vrcode`는 path VRCODE와 같아야 합니다. Profile 장비 시각은
`ntpState` 없이 신뢰하지 않습니다.

`profileDigest`는 다음 field처럼 event마다 변하는 값을 제외한 canonical profile
content로 계산할 계획입니다.

- event ID
- boot ID
- sequence
- device observed time
- NTP state

정확한 canonical JSON 규칙과 digest input은 구현 전에 두 저장소의 contract
test로 고정합니다.

### 5-5. Profile에 넣지 않을 정보

- Helper password, token, private key와 endpoint secret
- 환자 ID, 이름과 측정값
- VitalServer가 계산하는 health severity와 UI label
- Helper가 소유하는 received/indexed/upload 상태
- filename에서 추론한 bed 또는 Recorder identity
- diagnostic 원문 전체

## 6. VitalServer PostgreSQL schema

Recorder 팀이 PostgreSQL을 직접 쓰지는 않습니다. 그러나 retry, identity와
Profile lifecycle을 맞추려면 서버가 문서를 어떻게 저장하는지 알아야 합니다.

전용 schema를 사용할 계획입니다.

```text
PostgreSQL schema: recorder_observability
```

초기 물리 모델은 `requests`, `records`, `current` 세 table입니다. 아래
`admission_batches`, `admission_records`, `events`, `quarantine_records`는 논리적
역할을 설명하며 accepted/duplicate/quarantine evidence는 현재 `records`에
disposition으로 함께 저장합니다. PostgreSQL DDL은 중앙
`vitalserver-postgres-migrator`만 실행합니다.

### 6-1. `admission_batches`

HTTP request 단위 영수증입니다.

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

### 6-2. `admission_records`

각 non-empty NDJSON line의 최종 disposition입니다.

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

Duplicate도 행으로 남습니다. `202` 응답 전에 batch와 모든 line disposition이
같은 transaction으로 commit됩니다.

### 6-3. `events`

검증된 모든 resource의 공통 JSONB event store입니다.

```text
event_key UUID primary key
vrcode
event_id
resource_type = observation | diagnostic | kernelIncident | profile
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

Payload 전체를 관계형 column으로 정규화하지 않습니다. Identity, ordering과
시간 query에 필요한 envelope만 column으로 분리하고 Recorder document는
JSONB로 보존합니다.

기본 index는 다음 query를 지원합니다.

```text
unique (vrcode, event_id)
(vrcode, received_at desc)
(vrcode, boot_id, sequence)
(resource_type, received_at desc)
```

Raw JSON containment/JSONPath 검색이 실제로 필요해지면 `document
jsonb_path_ops` GIN을 추가합니다. 숫자 범위 query는 확인된 JSON path에만
expression B-tree를 추가합니다.

### 6-4. `quarantine_records`

Parse 또는 contract validation에 실패한 원문입니다.

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

Parse할 수 없는 JSON도 있으므로 raw document는 bounded TEXT입니다.

### 6-5. `recorder_profile_current`

Recorder별 현재 profile 한 행입니다.

```text
vrcode primary key
source_event_key unique
source_event_id
profile_digest
device_id
boot_id
sequence
device_observed_at
received_at
projection_version
projected_at
document JSONB
```

과거 profile은 `events`에 남으므로 별도의 profile history table을 중복 생성하지
않습니다.

Current profile은 latest health observation과 같은 device/boot의 가장 큰 profile
sequence로 선택합니다. 과거 boot profile이 network delay 때문에 늦게 도착해도
current profile을 덮어쓰지 않습니다.

### 6-6. `recorder_health_current`

Recorder list와 detail을 위한 현재 health read model입니다.

```text
vrcode primary key
source_event_key unique
device_id
boot_id
sequence
latest_received_at
report_state = current | stale | missing | readFailed
severity = normal | warning | critical | unknown
active_signal_count
recent_restart_at nullable
profile_state
profile_event_key nullable
policy_version
projection_version
projected_at
document JSONB
```

목록에서 반복해서 사용하는 state와 time은 typed column으로 저장합니다. 상세
signal, reading state/value/detail과 evidence reference는 JSONB document에
저장합니다.

### 6-7. 후속 projection

다음 table은 처음부터 만들지 않고 timeline/incident read API가 확정된 뒤
추가합니다.

```text
recorder_health_buckets
recorder_boot_transitions
recorder_incident_summaries
projection_checkpoints
```

장기 graph에서 반복 집계하는 온도, storage 사용률과 buffer ratio는 typed
numeric column을 사용하고 드문 세부 metric만 JSONB에 둡니다.

## 7. Recorder 구현 영향

### 7-1. 유지해야 하는 것

- VRCODE와 device ID 역할 분리
- boot ID별 monotonic sequence
- retry 시 immutable event
- reading state/value/detail 의미
- persistent journal cursor와 publisher buffer
- endpoint별 독립 input/cursor/output

### 7-2. 추가할 것

- Profile domain/document/JSON Schema
- Profile sequence state
- Profile digest 생성
- boot/config change detection
- Profile journal tag와 Fluent Bit input/output
- Profile golden document와 invalid document contract test
- VitalServer pinned schema artifact manifest

### 7-3. 추가하지 않을 것

- VitalServer DB column에 맞춘 Recorder payload flattening
- UI health condition 계산
- server received time 생성
- upload indexed 상태 추정
- transport failure를 empty/success profile로 변환

## 8. 역할 분담

| 작업 | Recorder 저장소 | VitalServer 저장소 |
|---|---:|---:|
| 기존 세 v1 schema owner | Owner | Pinned consumer |
| Profile schema/document | Owner | Pinned consumer |
| event ID와 profile digest 생성 | Owner | Validator |
| NDJSON persistent delivery | Owner | Receiver |
| HTTP request/line disposition | Consumer | Owner |
| PostgreSQL admission | 없음 | Owner |
| quarantine 보존/조회 | 없음 | Owner |
| profile current 선택 | Evidence producer | Owner |
| health severity/restart policy | Evidence producer | Owner |
| Swift/PWA read model | 없음 | Owner |

## 9. 구현 전 합의가 필요한 항목

다음 항목을 확정한 뒤 Profile 구현을 시작합니다.

1. Profile contract version 표기: `v1` 또는 별도 namespace
2. Profile sequence state file의 위치, owner와 corruption 처리
3. `profileDigest` canonicalization과 제외 field
4. Vital Recorder version을 읽는 authoritative source
5. OS/image version을 읽는 authoritative source
6. Capability enum과 boolean field 목록
7. Network/serial configuration에 민감한 정보가 포함되는지
8. Profile request/line 최대 크기
9. Profile schema artifact 배포와 receipt 형식
10. VRCODE별 authentication 또는 trusted-network-only 운영 범위

미확정 항목을 default로 추정해서 구현하지 않습니다.

## 10. 권장 구현 순서

### Recorder와 VitalServer 공동

1. 기존 세 v1 schema artifact와 digest 전달 방식을 고정합니다.
2. Profile schema, event ID, sequence와 digest 규칙을 확정합니다.
3. 양쪽에서 같은 golden documents를 사용하는 contract test를 만듭니다.

### VitalServer 우선

1. Existing endpoint를 authoritative schema validator로 전환합니다.
2. PostgreSQL admission과 모든 line disposition을 구현합니다.
3. Process-memory accepted identity map과 runtime file ledger writer를 제거합니다.

### Recorder와 VitalServer Profile

1. Recorder가 Profile producer와 persistent delivery를 구현합니다.
2. VitalServer가 `/profiles`와 `recorder_profile_current` projection을 구현합니다.
3. Retry, config change, late previous-boot profile을 함께 검증합니다.

### 그 다음

1. `recorder_health_current`와 Guest Control detail API를 구현합니다.
2. 실제 query를 기준으로 timeline/incident projection을 추가합니다.
3. 마지막으로 Swift/PWA를 구현합니다.

## 11. 공동 acceptance scenario

최소한 다음 시나리오를 두 저장소의 release proof로 사용합니다.

1. Recorder가 boot profile sequence 1을 보냅니다.
2. VitalServer가 accepted event와 current profile을 저장합니다.
3. Response loss 뒤 같은 profile을 다시 보내 duplicate가 됩니다.
4. 같은 boot에서 collection interval이 변경되고 profile sequence 2가 accepted됩니다.
5. device-health observation이 새 interval을 사용해 current로 평가됩니다.
6. 새 boot의 profile sequence 1과 observation이 도착하고 reboot evidence가
   생성됩니다.
7. 이전 boot에서 지연된 profile이 뒤늦게 도착하지만 current profile은
   바뀌지 않습니다.
8. 같은 event ID의 다른 body는 quarantine됩니다.
9. PostgreSQL을 사용할 수 없으면 `503`이고 Recorder buffer가 event를
   보존합니다.
10. 복구 후 retry가 accepted 또는 duplicate로 수렴합니다.
