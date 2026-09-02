# Redis Relay

Redis Relay는 VitalServer 내부 Redis를 외부 network에 직접 열지 않고, Helper-managed runtime이
allowlisted Redis data를 외부 target Redis로 publish하는 계약입니다.

이 문서는 target Redis를 소비하는 외부 service가 무엇을 받아야 하고, 어떤 책임을 가져야 하는지
설명합니다. 특정 Tirosh 내부 구현에 묶인 문서가 아니라, Helper가 공개할 수 있는 generic external
Redis consumer contract입니다.

이 페이지는 외부 consumer용 공개 projection입니다. Relay 구현, 설정, Native 운영과 Protocol의
저장소 기준 문서는 각각 `docs/redis-relay/` 문서군에서 관리하며, 이 페이지에는 외부 consumer가
필요한 계약만 싣습니다.

## 1. 목적

### 1-1. 해결하는 문제

실시간 numeric, trend, waveform data는 HTTP API로 polling하기에 크고 빠르게 변합니다. 그러나
VitalServer raw Redis port를 VM 밖으로 열면 credential/session key, 운영 내부 state, 네트워크 보안
경계가 함께 노출될 수 있습니다.

Redis Relay는 VitalServer compose 내부의 source Redis를 read-only로 읽고, operator가 설정한 target
Redis에 필요한 key와 event만 publish합니다.

### 1-2. 아닌 것

- VitalServer 공식 API가 아닙니다.
- VitalServer raw Redis port를 외부에 공개하는 기능이 아닙니다.
- 특정 consumer 구현체 전용 계약이 아닙니다.
- decoded clinical data contract가 아닙니다. Relay payload는 source Redis payload를 보존한 원문
  snapshot입니다.

## 2. Runtime Flow

### 2-1. Source

Source Redis는 Helper-managed guest compose 내부 Redis입니다.

```text
redis://redis:6379/0
```

Relay container만 source Redis에 접근합니다. 외부 PC나 Kubernetes service는 source Redis에 직접
접속하지 않습니다.

### 2-2. Publisher

Publisher는 `vitalserver-redis-relay` container입니다.

Publisher는 source Redis에서 `SCAN`, `TYPE`, `PTTL`, `DUMP`를 사용해 allowlisted key snapshot을
읽습니다. Source Redis에는 write하지 않습니다.

### 2-3. Target

Target Redis는 Helper Advanced의 Redis relay 설정으로 지정합니다.

Target URL은 macOS Helper process 기준 주소가 아니라 guest relay container 기준 주소입니다. 예를 들어
Mac host에서 Redis를 `16381` port로 열고 shared NAT guest에서 접근한다면 보통 아래 주소를 사용합니다.

```text
redis://192.168.64.1:16381/0
```

## 3. Target Redis Output

### 3-1. Restored keys

Relay는 allowlisted source key를 target Redis에 아래 prefix로 restore합니다.

```text
vitalserver:<source-key>
```

예를 들어 source key가 `beds`이면 target key는 `vitalserver:beds`입니다.

### 3-2. Event stream

Relay는 target Redis stream에 metadata event를 publish합니다.

```text
vitalserver:relay:events
```

Consumer는 이 stream을 Redis Streams consumer group으로 읽고, event의 `target_key`를 다시 target
Redis에서 fetch합니다. Redis value 자체는 stream event에 넣지 않습니다.

### 3-3. Metadata keys

Relay는 publish idempotency와 change detection을 위해 아래 metadata key를 사용합니다.

| Key | 의미 |
|---|---|
| `vitalserver:relay:fingerprints` | target key별 source DUMP fingerprint |
| `vitalserver:relay:published` | publish dedupe key별 stream event id |

Consumer는 이 metadata를 자신의 processing state로 사용하지 않습니다. Consumer의 pending recovery,
DLQ, downstream idempotency state는 consumer가 별도로 소유합니다.

## 4. Protocol v1 Event

### 4-1. Event name

Relay Protocol v1 event name은 아래 값입니다.

```text
key_published
```

### 4-2. Required fields

`vitalserver:relay:events` entry는 아래 field를 포함합니다.

| Field | 의미 |
|---|---|
| `schema_version` | protocol schema version. 현재 `1` |
| `event` | event name. 현재 `key_published` |
| `source_key` | source Redis key |
| `target_key` | target Redis key |
| `key_type` | source Redis key type |
| `ttl_ms` | source key PTTL. no-expiry는 `0` restore semantics로 publish |
| `source_fingerprint` | source DUMP payload SHA-256 |
| `dedupe_key` | 동일 source snapshot publish dedupe key |
| `published_at` | publisher가 event를 기록한 UTC timestamp |
| `publisher` | publisher id. 기본 `vitalserver-helper-relay` |

### 4-3. Atomicity

Publisher는 target key restore, fingerprint update, publish dedupe 기록, stream event publish를 하나의
Lua script 안에서 처리합니다.

Consumer는 `key_published` event를 읽었을 때 `target_key` payload가 이미 target Redis에 존재한다고
기대할 수 있습니다. 다만 target Redis TTL 때문에 consumer가 늦게 읽으면 payload가 만료될 수 있으므로,
missing payload는 정상 empty가 아니라 별도 failure/retry/DLQ 정책으로 다룹니다.

## 5. Responsibility Boundary

### 5-1. Helper owns

Helper와 `vitalserver-redis-relay`가 소유하는 책임은 아래입니다.

- source Redis read-only 접근
- allowlist/denylist policy
- target Redis connection 설정
- target key restore
- atomic publish
- publish progress/status document
- credential/session/auth key relay 차단

### 5-2. Consumer owns

Target-side consumer가 소유하는 책임은 아래입니다.

- Redis Streams consumer group 생성
- pending entry recovery
- decode 실패 DLQ
- duplicate event handling
- decoded event idempotency
- downstream database/message/callback write idempotency
- consumer-specific monitoring and alerting

Helper는 consumer group pending state를 추측하거나 복구하지 않습니다. Consumer가 어떤 sink를 쓰는지,
어떤 decode schema를 적용하는지, 어떤 retry policy를 쓰는지는 target-side system의 책임입니다.

## 6. Consumer Guidance

### 6-1. Recommended flow

Consumer는 아래 흐름을 권장합니다.

1. `XGROUP CREATE vitalserver:relay:events <group> $ MKSTREAM`으로 consumer group을 준비합니다.
2. `XREADGROUP GROUP <group> <consumer> STREAMS vitalserver:relay:events >`로 새 event를 읽습니다.
3. `event == key_published`인지 확인합니다.
4. `target_key`를 target Redis에서 fetch합니다.
5. payload를 decode하거나 downstream 형식으로 변환합니다.
6. downstream write를 idempotent하게 수행합니다.
7. 성공한 event만 `XACK`합니다.

### 6-2. Failure handling

Consumer는 happy path만 처리하면 안 됩니다.

| 상황 | 권장 처리 |
|---|---|
| target payload missing | retry 또는 DLQ. empty success로 처리하지 않음 |
| decode 실패 | 원본 event id, target key, error code를 DLQ에 기록 후 ack 여부를 policy로 결정 |
| consumer crash | `XPENDING`, `XAUTOCLAIM` 또는 `XCLAIM`으로 pending event 복구 |
| duplicate event | `dedupe_key` 또는 downstream idempotency key로 중복 처리 방지 |
| downstream write 실패 | ack하지 않고 retry하거나 DLQ로 이동 |

### 6-3. Event name policy

Protocol v1의 event name은 `key_published` 하나입니다. Consumer는 다른 event name을 호환 alias로
처리하지 않습니다. 새 event name이 필요하면 protocol version 또는 event contract를 명시적으로 변경합니다.
