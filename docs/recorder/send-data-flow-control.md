# Recorder ingress send_data flow control contract

이 문서는 Issue #68의 본 해결을 위한 recorder ingress `send_data` 수신 제어, durable spool, replay, backpressure 계약을 정의합니다. 목표는 upstream VitalServer를 수정하지 않고 recorder ingress가 `send_data`의 명시적 상태 소유자가 되는 것입니다.

## 1. 문제와 목표

### 1-1. 문제

VRecorder는 Socket.IO `send_data` event로 압축된 생체신호 payload를 지속 전송합니다. 현재 recorder ingress는 이 traffic을 관측하고 audit event를 남기지만, payload는 upstream VitalServer app으로 그대로 전달합니다.

장시간 또는 고부하 전송에서는 upstream app의 Node process memory가 증가하고, OOM 이후 502, stale runtime state, watchdog recovery 실패가 연쇄적으로 발생할 수 있습니다. upstream VitalServer 코드는 수정하지 않는 것이 원칙이므로, ingress 앞단에서 `send_data` 흐름을 흡수하고 통제해야 합니다.

### 1-2. Upstream `send_data` 처리 경로

Upstream VitalServer에서 `send_data`는 단순 relay event가 아닙니다. VRecorder가 보낸 payload 하나는 `vendor/vitalserver/vitalserver-old/service/app.js`의 Socket.IO handler를 통해 `monitor.send_data(io, payload)`로 들어가고, `service/include/monitor.js`에서 아래 작업을 수행합니다.

1. 압축된 Socket.IO payload를 `Buffer.from(payload, "binary")`로 메모리에 올립니다.
2. `zlib.inflateSync(...)`로 압축을 해제해 JSON string을 만듭니다.
3. control character와 `nan` 문자열을 정리한 뒤 `JSON.parse(...)`로 JS object graph를 만듭니다.
4. payload의 `vrcode`, `ver`, `rooms`를 읽고 `db.register_bed(vrcode, rooms)`를 실행합니다.
5. 각 room을 순회하면서 room name을 bed id로 hash하고, filter/hid/islinux 같은 보조 상태를 Redis에서 읽습니다.
6. room payload를 다시 `JSON.stringify`하고 `zlib.gzipSync(...)`로 압축해 UI bed room에 `recv_data`로 broadcast합니다.
7. `utime_*`, `vrver_*`, `devs_*`, `dtapp_*`, `filts_*`, `ptcon_*`, `dts_*`, `utimes`, `trend_*`, `dts_trend_result_*` 같은 Redis key와 sorted set을 갱신합니다.
8. filter 설정이 있는 bed는 과거 sample을 Redis에서 다시 읽고 `gunzipSync`, `JSON.parse`한 뒤 외부 filter service 호출과 filter result 저장을 수행할 수 있습니다.
9. trend summary를 계산해 Redis에 저장하고 오래된 score range를 정리합니다.

따라서 "처리 속도"는 하나의 함수 실행 시간이 아니라, 압축 해제, JSON parse, room/track 순회, Redis read/write, UI Socket.IO emit, filter/trend 계산을 모두 합친 처리량입니다.

메모리 압력도 한 곳에서만 생기지 않습니다.

- 압축 payload, inflate된 JSON string, parse된 JS object가 같은 이벤트 처리 중 동시에 존재합니다.
- room별 `JSON.stringify`, `gzipSync`, Socket.IO outgoing packet이 추가 buffer를 만듭니다.
- Redis write/read가 밀리면 Redis client command queue와 callback/Promise closure가 process 안에 남습니다.
- UI client 또는 upstream event loop가 느리면 Socket.IO/Engine.IO input/output buffer가 커질 수 있습니다.
- `inflateSync`, `gzipSync`, `gunzipSync`는 동기 zlib 작업이므로 그 시간 동안 event loop가 막히고, 새 `send_data` frame은 처리 대기열에 쌓일 수 있습니다.

즉 VRecorder 입력 속도가 이 전체 처리량보다 빠르면, 아직 처리되지 않은 payload와 처리 중간 객체가 upstream Node process memory에 누적됩니다. Issue #68은 이 upstream 내부 로직을 patch하지 않고, 앞단에서 `send_data` 유입을 명시적으로 소유하고 조절하는 문제입니다.

### 1-3. 해결 방향

Recorder ingress의 목표는 upstream 처리를 없애는 것이 아니라, upstream이 그 처리를 무제한 실시간 입력으로 받지 않게 만드는 것입니다. `spool_and_replay`에서는 client WebSocket frame 중 `send_data` text event와 binary attachment를 upstream direct relay에서 제거하고, 원본 payload를 durable spool에 기록한 뒤 replay worker가 설정된 interval, batch size, rate limit에 맞춰 upstream Socket.IO `send_data`로 재전송합니다.

이 구조에서 burst는 upstream Node heap이 아니라 Redis pending list로 이동합니다. pending list도 무제한 성공으로 취급하지 않고 `maxPendingItems`, `maxPendingBytes`, `maxPayloadBytes`를 넘으면 `spool_full`/`rejected` evidence로 노출합니다. 따라서 overload는 숨겨진 메모리 증가가 아니라, status와 test proof에서 확인 가능한 명시적 상태가 됩니다.

### 1-4. 목표

Recorder ingress는 `send_data`에 대해 아래 상태를 명시적으로 소유합니다.

- 수신 결과
- durable spool 기록 결과
- replay 진행 상태
- backpressure에 따른 reject/drop/dead-letter 결정
- upstream unavailable과 spool unavailable의 분리된 실패 의미

이 상태는 로그에서 추측하지 않습니다. recorder ingress status endpoint와 runtime health read model이 동일한 계약을 읽어야 합니다.

## 2. 책임 경계

### 2-1. Recorder ingress가 소유하는 책임

- VRecorder client의 `join_vr`와 `send_data` 흐름 관측
- `send_data` payload를 spool item으로 기록
- spool item을 upstream VitalServer로 통제된 속도로 replay
- spool/replay 상태와 실패 reason 노출
- recorder별 pending, lag, failure counter 노출
- upstream app OOM을 막기 위한 backpressure 적용

### 2-2. Recorder ingress가 소유하지 않는 책임

- upstream VitalServer Redis write의 domain 의미 변경
- bed online/offline domain 상태 생성
- waveform/trend payload 해석
- upstream app 코드 patch
- spool 실패를 성공으로 숨기는 fallback
- replay 성공을 VitalServer domain success로 확대 해석

Replay 성공은 "upstream으로 `send_data` 전달을 완료했다"는 뜻입니다. VitalServer가 내부 Redis key를 어떤 domain 상태로 만들었는지는 upstream의 책임입니다.

현재 replay adapter는 upstream VitalServer와 같은 Socket.IO v2 계열 client로 upstream app에 연결한 뒤 `send_data` event를 emit합니다. Ack를 요구하지 않는 upstream handler이므로, ingress의 replay 성공은 Socket.IO 연결과 emit 완료를 뜻합니다. upstream 내부 `monitor.send_data` 처리 결과를 ingress domain state로 추정하지 않습니다.

## 3. Ingress mode

`sendDataIngressModes`는 `apps/vitalserver-recorder-ingress/src/domain/send-data-ingress-contracts.ts`가 소유합니다.

| Mode | 의미 |
|---|---|
| `passthrough` | 현재 동작. `send_data`를 관측하고 upstream으로 바로 relay합니다. Phase 2/3 이전 또는 명시적 비활성화 상태입니다. |
| `mirror_spool` | Phase 3 동작. upstream relay는 유지하면서 `send_data`를 durable spool에도 기록합니다. 이 모드는 evidence와 spool 안정화용이며 upstream OOM을 구조적으로 막지는 않습니다. |
| `spool_only` | upstream direct relay를 끊고 `send_data`를 spool에만 기록합니다. Phase 4 cutover 검증과 안전한 rollout에 사용합니다. |
| `spool_and_replay` | `send_data`를 spool에 기록하고 replay worker가 upstream으로 재생합니다. Issue #68의 목표 운영 모드입니다. |

Mode는 설정으로 명시되어야 합니다. 설정 누락, decode 실패, 저장소 연결 실패를 `passthrough` 성공으로 처리하지 않습니다.

`spool_and_replay`에서는 replay worker가 pending list에서 item을 claim해 in-flight list로 옮깁니다. 성공하면 replayed list, retry 한도 초과 또는 invalid payload는 dead-letter list로 이동합니다. 일시적인 upstream 실패는 `retryable_failed` 상태로 pending list에 다시 기록합니다.

`spool_only`와 `spool_and_replay`에서는 recorder ingress가 client WebSocket frame을 frame-level로 relay합니다. Socket.IO `send_data` text event와 binary attachment는 upstream direct relay에서 제거하고, `join_vr`, `req_cmd`, control frame 등 다른 frame은 계속 전달합니다.

### 3-1. Runtime 설정

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `RECORDER_INGRESS_SEND_DATA_MODE` | `mirror_spool` | `passthrough`, `mirror_spool`, `spool_only`, `spool_and_replay` 중 하나 |
| `RECORDER_INGRESS_SEND_DATA_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:pending` | durable `send_data` spool Redis List key |
| `RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:in_flight` | replay worker가 claim한 item의 in-flight Redis List key |
| `RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:replayed` | replay 완료 item Redis List key |
| `RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:dead_letter` | retry하지 않는 dead-letter item Redis List key |
| `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS` | `10000` | pending spool item limit |
| `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES` | `536870912` | pending spool byte limit |
| `RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES` | `10485760` | 단일 `send_data` payload spool limit |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED` | mode 기반 | 빈 값이면 `spool_and_replay`에서 활성화, 그 외 mode에서 비활성화 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS` | `1000` | replay worker tick interval |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE` | `1` | worker tick마다 처리할 최대 item 수 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_ATTEMPTS` | `3` | retry 후 dead-letter로 전환할 최대 replay 시도 수 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND` | `1` | worker tick에서 적용하는 replay rate limit |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_TARGET_TIMEOUT_MS` | `5000` | upstream Socket.IO replay 연결 timeout |

Replay 처리량은 `intervalMs`, `batchSize`, `rateLimitPerSecond`를 함께 봐야 합니다. worker는 tick마다 `min(batchSize, rateLimitPerSecond)`개까지 처리하므로, rate limit만 높이고 batch size를 기본값 `1`로 두면 실제 처리량은 tick interval에 의해 제한됩니다.

## 4. 수신 결과

`sendDataIngressOutcomes`는 recorder ingress가 각 `send_data` 수신에 대해 기록해야 하는 결과입니다.

| Outcome | 의미 |
|---|---|
| `accepted` | ingress가 payload를 수신했고 spool 시도를 시작할 수 있습니다. |
| `spooled` | durable spool 기록이 완료되었습니다. |
| `rejected` | backpressure 정책으로 수신을 거부했습니다. |
| `invalid_payload` | Socket.IO event 또는 binary attachment를 spool item으로 만들 수 없습니다. |
| `spool_write_failed` | spool 저장소 쓰기가 실패했습니다. |

`accepted`와 `spooled`는 같은 의미가 아닙니다. `accepted` 이후 write가 실패하면 `spool_write_failed`로 남아야 하고, 성공처럼 집계하지 않습니다.

## 5. Spool item schema

Phase 3 구현은 최소한 아래 필드를 가진 item을 durable storage에 기록해야 합니다.

```json
{
  "schemaVersion": 1,
  "id": "senddata_01J...",
  "state": "pending",
  "vrcode": "VR001",
  "connectionId": "connection-1",
  "requestId": "request-1",
  "receivedAt": "2026-06-22T09:00:00.000Z",
  "payloadEncoding": "binary",
  "payloadBytes": 12345,
  "payload": "<opaque payload bytes or storage reference>",
  "attemptCount": 0,
  "lastAttemptAt": null,
  "lastFailure": null
}
```

### 5-1. Required semantics

| Field | 의미 |
|---|---|
| `schemaVersion` | item decode 계약 버전 |
| `id` | replay idempotency와 diagnostics를 위한 고유 ID |
| `state` | spool item state |
| `vrcode` | recorder identity. payload에서 얻지 못하면 `join_vr` context 값을 사용합니다. 둘 다 없으면 invalid입니다. |
| `connectionId` / `requestId` | ingress 관측 correlation |
| `receivedAt` | ingress 수신 시각 |
| `payloadEncoding` | `string`, `binary`, 또는 이후 확장된 명시적 encoding |
| `payloadBytes` | 원본 compressed payload byte length |
| `payload` | upstream replay에 필요한 원본 payload 또는 그 저장소 참조 |
| `attemptCount` | replay 시도 횟수 |
| `lastAttemptAt` | 마지막 replay 시도 시각 |
| `lastFailure` | 마지막 실패 reason/message/time |

Payload는 waveform/trend domain으로 해석하지 않습니다. spool은 upstream `send_data` replay를 위한 opaque payload 보존이 목적입니다.

## 6. Spool item state

| State | 의미 |
|---|---|
| `pending` | durable spool에 저장되었고 replay 대기 중입니다. |
| `in_flight` | replay worker가 upstream 전달을 시도 중입니다. |
| `replayed` | upstream 전달이 완료된 terminal state입니다. |
| `retryable_failed` | upstream 또는 일시적 의존성 실패로 retry 대상입니다. |
| `dead_lettered` | 더 이상 retry하지 않는 terminal state입니다. |

Terminal state는 `replayed`, `dead_lettered`뿐입니다. `retryable_failed`는 실패 evidence이지만, 아직 회복 가능한 pending work입니다.

## 7. Failure reason

| Reason | 의미 |
|---|---|
| `invalid_payload` | payload를 spool item으로 만들 수 없음 |
| `spool_unavailable` | spool 저장소가 준비되지 않음 |
| `spool_full` | backpressure limit 초과 |
| `spool_write_failed` | spool write 명령 실패 |
| `upstream_unavailable` | upstream app에 접속할 수 없음 |
| `upstream_timeout` | upstream 응답 또는 Socket.IO ack 대기 timeout |
| `upstream_rejected` | upstream이 명시적으로 거부 또는 오류 응답 |
| `replay_session_unavailable` | replay에 필요한 Socket.IO session/context를 만들 수 없음 |

이 reason들은 서로 대체하지 않습니다. 예를 들어 upstream down 상태에서 spool write가 성공했다면 `spool_write_failed`가 아니라 replay failure로 남아야 합니다.

## 8. Backpressure policy

Phase 3/4의 기본 정책은 아래와 같습니다.

| 조건 | Action | 이유 |
|---|---|---|
| spool depth와 byte limit 안쪽 | `accept` | 정상 수신 |
| spool 저장소 unavailable | `reject` | 저장 없이 성공 처리하지 않음 |
| spool full | `reject` | `mirror_spool`에서는 spool 기록 거부 evidence로 남기고, Phase 4 cutover 이후에는 upstream 유입 차단에 사용 |
| 운영자가 dead-letter oldest 정책을 명시한 경우 | `dead_letter_oldest` | 자동 drop이 아니라 명시 설정으로만 허용 |

기본값은 안전해야 합니다. 누락된 설정은 무제한 수신이나 silent drop이 아니라 명시적인 unavailable/error로 보고해야 합니다.

## 9. Status contract

Recorder ingress `/recorder-ingress/status`는 Phase 3/4에서 아래 optional object를 채워야 합니다.

- `spool`: 전체 spool 상태
- `replay`: 전체 replay 상태
- `recorders[].spool`: recorder별 spool 상태
- `recorders[].replay`: recorder별 replay 상태

OpenAPI 초안은 `docs/api/recorder-ingress.openapi.yaml`에 둡니다. Phase 2에서는 optional field로 남기고, Phase 3/4에서 구현된 뒤 runtime contract와 health policy의 required read model로 승격합니다.

## 10. Phase completion proof

### Phase 3 proof

- text `send_data`가 `spooled`로 기록됨
- binary attachment `send_data`가 `spooled`로 기록됨
- Redis write 실패가 `spool_write_failed`로 남음
- mirror spool limit 초과가 `rejected`와 `spool_full` evidence로 남음
- audit 실패와 spool 실패가 다른 counter로 남음

Phase 3의 `mirror_spool`은 upstream WebSocket pipe를 끊지 않습니다. 따라서 `rejected`는 네트워크 수신 거부가 아니라 spool 기록 거부 evidence입니다. upstream direct `send_data` 유입 차단은 Phase 4의 `spool_only`/`spool_and_replay` frame-level relay에서 수행합니다.

### Phase 4 proof

- `pending` item이 replay 성공 뒤 `replayed`가 됨
- upstream down은 `retryable_failed`와 `upstream_unavailable`로 남음
- payload invalid는 retry하지 않고 `dead_lettered`가 됨
- replay rate limit이 적용됨
- replay lag가 status에 드러남
- `spool_only`에서 client `send_data` frame이 upstream으로 direct relay되지 않음
- `mirror_spool`에서 client `send_data` frame이 기존처럼 upstream으로 direct relay됨

Phase 4의 implementation proof는 replay worker/storage transition 단위 테스트와 local fake upstream을 사용한 recorder ingress WebSocket relay integration test로 검증합니다.

Compose 환경 proof는 Swift/macOS runtime build 전에 실행합니다. 이 proof는 실제 Compose의 `recorder-ingress`, upstream `app`, `redis`, testkit Socket.IO client를 함께 사용해 `spool_and_replay` 경로를 확인합니다.

```sh
make testkit/recorder-ingress/replay
```

성공 조건은 testkit stream이 보낸 `send_data` 수만큼 이번 실행의 recorder ingress status delta에서 `sendDataEventsObserved`, `spooledEvents`, `replayedEvents`가 증가하고, `pending`/`in_flight` 상태가 비어 있으며 Redis `dead_letter` list가 비어 있는 것입니다. Swift `dist/dmg/*` build는 이 compose proof 이후 guest packaging과 VM compile 경로를 검증하는 단계로 둡니다.

### Phase 5 proof

- runtime이 recorder ingress status read failure, invalid response, spool failure, replay lag를 구분함
- missing/invalid/failed/stale 상태가 같은 degraded label로만 합쳐지지 않음
- health event에 failing reason과 artifact path가 남음

### Phase 6 proof

- 장시간 load에서 app container `oomKilled=false`
- app restart count 증가 없음
- recorder ingress spool depth가 회복 가능 범위
- replay lag가 부하 종료 후 감소
- stale runtime cascade가 재현되지 않음

Compose load proof는 정상 부하와 backpressure를 분리해서 실행합니다.

```sh
make testkit/recorder-ingress/load
make testkit/recorder-ingress/backpressure
```

`testkit/recorder-ingress/load`는 `spool_and_replay`에서 5 recorder x 100 `send_data`를 보내고, 이번 실행의 observed/spooled/replayed delta, Redis `dead_letter` 부재, replay lag, app container `oomKilled=false`, restart count 불변을 확인합니다. 이 proof는 replay interval/rate/batch를 함께 명시해 load 종료 후 pending spool이 drain 되는지 확인합니다.

`testkit/recorder-ingress/backpressure`는 의도적으로 `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS=1`과 낮은 replay rate를 사용해 `rejectedEvents` delta가 증가하는지 확인합니다. 이 proof의 성공은 모든 event가 replay되는 것이 아니라, recorder ingress가 overload를 숨기지 않고 `spool_full` 계열 rejection evidence로 노출한다는 뜻입니다.
