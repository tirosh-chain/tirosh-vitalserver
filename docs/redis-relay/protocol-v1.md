# Redis Relay Protocol v1

이 문서는 Redis Relay publisher와 Target Redis consumer 사이의 전송 계약입니다. Relay는
Source Redis payload를 decode하지 않고 Redis `DUMP` 형식으로 보존합니다. Consumer는 event를
받은 뒤 Target key를 조회하고 필요한 형식으로 decode하거나 변환합니다.

## 1. 목적과 보장 범위

### 1-1. 목적

Protocol v1은 다음 작업을 하나의 publish 단위로 묶습니다.

1. Source key snapshot을 Target key에 restore합니다.
2. Source payload fingerprint를 기록합니다.
3. 동일 publish의 dedupe state를 기록합니다.
4. `key_published` metadata event를 Redis Stream에 추가합니다.

### 1-2. 보장하지 않는 것

- Source Redis의 전체 keyspace 복제
- Source key가 삭제된 뒤의 복구
- Target consumer의 exactly-once 처리
- payload의 임상 의미 또는 decode schema
- consumer group, pending recovery, DLQ 운영

Protocol은 Target Redis publish의 원자성과 metadata를 제공하지만 durable source queue는
제공하지 않습니다.

## 2. Snapshot과 Target 데이터 모델

### 2-1. 읽기 순서

Relay batch는 Source Redis에서 다음 순서로 동작합니다.

1. `SCAN COUNT <scan_count>`로 key를 순회합니다.
2. deny policy와 선택된 scope allow policy를 적용합니다.
3. `TYPE`과 `PTTL`로 key type과 수명을 읽습니다.
4. `DUMP`로 Redis 직렬화 payload를 읽습니다.
5. 읽는 사이 key가 사라지면 `missing`으로 집계합니다.

Source Redis에는 write하지 않습니다.

### 2-2. Snapshot 구성

| 값 | 의미 |
|---|---|
| `key` | Source Redis key |
| `key_type` | `string`, `list`, `set`, `zset`, `hash`, `stream` 등 |
| `ttl_ms` | Target `RESTORE`에 사용할 TTL |
| `serialized_payload` | Source `DUMP` binary payload |

Payload는 HTTP/base64로 변환하지 않습니다. Redis의 binary serialization을 그대로 Target에
전달합니다.

### 2-3. Target Redis output

**Target key**

기본 Target key는 Source key 앞에 `vitalserver:`를 붙입니다.

```text
source: beds
target: vitalserver:beds
```

prefix는 `[publish].target_key_prefix`로 명시적으로 변경할 수 있습니다.

**Metadata key**

| 기본 key | 책임 |
|---|---|
| `vitalserver:relay:events` | Protocol v1 `key_published` event stream |
| `vitalserver:relay:fingerprints` | Target key별 Source payload fingerprint |
| `vitalserver:relay:published` | publish dedupe key별 stream event ID |

Consumer는 Relay metadata hash를 자신의 processing state로 사용하지 않습니다. Consumer의
offset, pending, retry, DLQ 상태는 consumer가 별도로 소유합니다.

## 3. Atomic publish와 event

### 3-1. Atomic 처리 순서

Target adapter는 하나의 Lua script 안에서 다음 작업을 수행합니다.

1. 기존 fingerprint와 새 fingerprint를 비교합니다.
2. payload가 바뀌었으면 Target key를 `RESTORE ... REPLACE`합니다.
3. fingerprint hash를 갱신합니다.
4. dedupe key가 이미 publish되었는지 확인합니다.
5. 새 publish이면 stream에 event를 추가하고 event ID를 dedupe hash에 기록합니다.

### 3-2. Publish 결과 상태

| 상태 | 의미 |
|---|---|
| `published` | 새 snapshot과 event가 기록됨 |
| `unchanged` | 기존 fingerprint와 같아 publish하지 않음 |
| `duplicate` | 같은 publish identity가 이미 기록됨 |

Consumer가 `key_published` event를 읽었다면 해당 publish transaction에서 Target key도 함께
기록되었다고 기대할 수 있습니다. 다만 TTL 때문에 consumer가 늦게 읽으면 key가 이미 만료될
수 있습니다. 이 경우를 빈 값으로 처리하지 말고 retry 또는 DLQ 대상으로 분류합니다.

### 3-3. `key_published` event

**Event identity**

Protocol v1의 event 이름은 `key_published` 하나입니다. Consumer는 다른 이름을 호환 alias로
추측하지 않습니다.

**Event fields**

| 필드 | 의미 |
|---|---|
| `schema_version` | Protocol schema version. 현재 `1` |
| `event` | Event name. 현재 `key_published` |
| `source_key` | Source Redis key |
| `target_key` | restored payload를 가진 Target Redis key |
| `key_type` | Source Redis key type |
| `ttl_ms` | Target restore에 사용한 TTL |
| `source_fingerprint` | Source DUMP payload의 SHA-256 |
| `dedupe_key` | 동일 snapshot publish를 식별하는 안정적인 key |
| `published_at` | Publisher가 기록한 UTC timestamp |
| `publisher` | Publisher ID. 기본 `vitalserver-helper-relay` |

Stream event는 metadata만 포함합니다. 실제 payload는 `target_key`에서 조회합니다.

### 3-4. TTL, 빈 값과 삭제

**TTL 보존**

Relay는 Source `PTTL`을 Target `RESTORE` semantics에 맞춰 전달합니다. 만료가 없는 key는
Target에서도 만료가 없는 값으로 restore합니다. Source를 읽는 동안 만료되거나 삭제된 key는
정상적인 빈 payload가 아니라 `missing`으로 집계합니다.

**Source 삭제**

Protocol v1은 Source key 삭제 event를 publish하지 않습니다. Target key는 자신의 TTL 또는 별도
consumer policy에 따라 정리됩니다. Source key가 TTL 없이 삭제된 경우 Target의 즉시 삭제 동기화는
Protocol v1의 보장 범위가 아닙니다.

### 3-5. Fingerprint와 dedupe

`source_fingerprint`는 Source `DUMP` payload의 SHA-256입니다. 같은 Target key에 같은 payload가
있으면 `unchanged`로 분류해 불필요한 restore와 event를 줄입니다.

Publish dedupe는 publisher가 같은 snapshot event를 반복 기록하는 것을 막습니다. 이것이 consumer의
exactly-once 처리를 보장하지는 않습니다. Consumer는 `dedupe_key` 또는 자신의 downstream
idempotency key로 중복 처리를 방지해야 합니다.

Relay settings fingerprint는 Protocol payload fingerprint와 다른 값입니다. Settings fingerprint는
endpoint의 비밀이 아닌 연결 정보, credential configured boolean, scope와 publish contract를
식별하며 credential 원문을 포함하지 않습니다.

## 4. 실패와 재시도

### 4-1. Source 실패

`TYPE`, `PTTL`, `DUMP` 등 Source snapshot 생성이 실패하면 해당 key를
`source_dump_failed`로 기록하고 batch의 다른 key를 계속 처리합니다.

### 4-2. Target 실패

Target의 atomic restore, fingerprint, dedupe 또는 event publish가 실패하면
`target_publish_failed`로 기록합니다. Socket close, timeout, Redis 응답 전 연결 실패는 bounded
exponential backoff로 재연결합니다. 재시도가 소진되면 성공으로 숨기지 않고 batch error로 남깁니다.

### 4-3. 장시간 장애

Target이 한 command retry window보다 오래 unavailable이어도 Relay process는 다음 loop를 계속
시도합니다. Target이 복구되면 그 시점에 Source에 남아 있는 허용 key를 다시 publish합니다.
장애 중 만료되거나 삭제된 Source key는 Relay만으로 복구할 수 없습니다.

## 5. Consumer 책임

### 5-1. 권장 흐름

1. `XGROUP CREATE vitalserver:relay:events <group> $ MKSTREAM`으로 group을 준비합니다.
2. `XREADGROUP`으로 새 event를 읽습니다.
3. `schema_version`과 `event`를 검증합니다.
4. `target_key`를 Target Redis에서 조회합니다.
5. payload를 decode하거나 downstream 형식으로 변환합니다.
6. downstream write를 idempotent하게 수행합니다.
7. 성공한 event만 `XACK`합니다.

### 5-2. 실패 처리

| 상황 | Consumer 처리 |
|---|---|
| Target payload missing | retry 또는 DLQ. empty success로 처리하지 않음 |
| Decode 실패 | event ID, Target key, error code를 보존하고 정책에 따라 retry/DLQ |
| Consumer crash | `XPENDING`, `XAUTOCLAIM` 또는 `XCLAIM`으로 복구 |
| Duplicate event | `dedupe_key`나 downstream idempotency key로 차단 |
| Downstream write 실패 | ACK하지 않고 retry하거나 DLQ로 이동 |

## 6. 버전 호환성

Consumer는 `schema_version`과 `event`를 명시적으로 검증합니다. v1에 필드를 추가할 때는 기존
필드 의미를 바꾸지 않는 additive change만 허용합니다. Event 이름, key 의미, atomicity 또는 필수
필드를 바꾸는 변경은 새 protocol version으로 정의해야 합니다.
