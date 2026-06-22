# Recorder ingress send_data spool/replay contract

이 문서는 Issue #68의 본 해결을 위한 recorder ingress `send_data` 수신, 스풀, 재생 계약을 정의합니다.
목표는 upstream VitalServer를 수정하지 않고 recorder ingress가 `send_data`의 명시적 상태 소유자가 되는
것입니다.

## 1. 문제와 목표

### 1-1. 문제

VRecorder는 Socket.IO `send_data` event로 압축된 생체신호 payload를 지속 전송합니다. 현재 recorder
ingress는 이 traffic을 관측하고 audit event를 남기지만, payload는 upstream VitalServer app으로 그대로
전달합니다.

장시간 또는 고부하 전송에서는 upstream app의 Node process memory가 증가하고, OOM 이후 502, stale
runtime state, watchdog recovery 실패가 연쇄적으로 발생할 수 있습니다. upstream VitalServer 코드는
수정하지 않는 것이 원칙이므로, ingress 앞단에서 `send_data` 흐름을 흡수하고 통제해야 합니다.

### 1-2. 목표

Recorder ingress는 `send_data`에 대해 아래 상태를 명시적으로 소유합니다.

- 수신 결과
- durable spool 기록 결과
- replay 진행 상태
- backpressure에 따른 reject/drop/dead-letter 결정
- upstream unavailable과 spool unavailable의 분리된 실패 의미

이 상태는 로그에서 추측하지 않습니다. recorder ingress status endpoint와 runtime health read model이
동일한 계약을 읽어야 합니다.

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

Replay 성공은 "upstream으로 `send_data` 전달을 완료했다"는 뜻입니다. VitalServer가 내부 Redis key를
어떤 domain 상태로 만들었는지는 upstream의 책임입니다.

현재 replay adapter는 upstream VitalServer와 같은 Socket.IO v2 계열 client로 upstream app에 연결한 뒤
`send_data` event를 emit합니다. Ack를 요구하지 않는 upstream handler이므로, ingress의 replay 성공은
Socket.IO 연결과 emit 완료를 뜻합니다. upstream 내부 `monitor.send_data` 처리 결과를 ingress domain
state로 추정하지 않습니다.

## 3. Ingress mode

`sendDataIngressModes`는 `apps/vitalserver-recorder-ingress/src/domain/send-data-ingress-contracts.ts`가
소유합니다.

| Mode | 의미 |
|---|---|
| `passthrough` | 현재 동작. `send_data`를 관측하고 upstream으로 바로 relay합니다. Phase 2/3 이전 또는 명시적 비활성화 상태입니다. |
| `mirror_spool` | Phase 3 동작. upstream relay는 유지하면서 `send_data`를 durable spool에도 기록합니다. 이 모드는 evidence와 spool 안정화용이며 upstream OOM을 구조적으로 막지는 않습니다. |
| `spool_only` | upstream direct relay를 끊고 `send_data`를 spool에만 기록합니다. Phase 4 cutover 검증과 안전한 rollout에 사용합니다. |
| `spool_and_replay` | `send_data`를 spool에 기록하고 replay worker가 upstream으로 재생합니다. Issue #68의 목표 운영 모드입니다. |

Mode는 설정으로 명시되어야 합니다. 설정 누락, decode 실패, 저장소 연결 실패를 `passthrough` 성공으로
처리하지 않습니다.

`spool_and_replay`에서는 replay worker가 pending list에서 item을 claim해 in-flight list로 옮깁니다.
성공하면 replayed list, retry 한도 초과 또는 invalid payload는 dead-letter list로 이동합니다. 일시적인
upstream 실패는 `retryable_failed` 상태로 pending list에 다시 기록합니다.

`spool_only`와 `spool_and_replay`에서는 recorder ingress가 client WebSocket frame을 frame-level로 relay합니다.
Socket.IO `send_data` text event와 binary attachment는 upstream direct relay에서 제거하고, `join_vr`,
`req_cmd`, control frame 등 다른 frame은 계속 전달합니다.

## 4. 수신 결과

`sendDataIngressOutcomes`는 recorder ingress가 각 `send_data` 수신에 대해 기록해야 하는 결과입니다.

| Outcome | 의미 |
|---|---|
| `accepted` | ingress가 payload를 수신했고 spool 시도를 시작할 수 있습니다. |
| `spooled` | durable spool 기록이 완료되었습니다. |
| `rejected` | backpressure 정책으로 수신을 거부했습니다. |
| `invalid_payload` | Socket.IO event 또는 binary attachment를 spool item으로 만들 수 없습니다. |
| `spool_write_failed` | spool 저장소 쓰기가 실패했습니다. |

`accepted`와 `spooled`는 같은 의미가 아닙니다. `accepted` 이후 write가 실패하면
`spool_write_failed`로 남아야 하고, 성공처럼 집계하지 않습니다.

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

Payload는 waveform/trend domain으로 해석하지 않습니다. spool은 upstream `send_data` replay를 위한 opaque
payload 보존이 목적입니다.

## 6. Spool item state

| State | 의미 |
|---|---|
| `pending` | durable spool에 저장되었고 replay 대기 중입니다. |
| `in_flight` | replay worker가 upstream 전달을 시도 중입니다. |
| `replayed` | upstream 전달이 완료된 terminal state입니다. |
| `retryable_failed` | upstream 또는 일시적 의존성 실패로 retry 대상입니다. |
| `dead_lettered` | 더 이상 retry하지 않는 terminal state입니다. |

Terminal state는 `replayed`, `dead_lettered`뿐입니다. `retryable_failed`는 실패 evidence이지만, 아직
회복 가능한 pending work입니다.

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

이 reason들은 서로 대체하지 않습니다. 예를 들어 upstream down 상태에서 spool write가 성공했다면
`spool_write_failed`가 아니라 replay failure로 남아야 합니다.

## 8. Backpressure policy

Phase 3/4의 기본 정책은 아래와 같습니다.

| 조건 | Action | 이유 |
|---|---|---|
| spool depth와 byte limit 안쪽 | `accept` | 정상 수신 |
| spool 저장소 unavailable | `reject` | 저장 없이 성공 처리하지 않음 |
| spool full | `reject` | `mirror_spool`에서는 spool 기록 거부 evidence로 남기고, Phase 4 cutover 이후에는 upstream 유입 차단에 사용 |
| 운영자가 dead-letter oldest 정책을 명시한 경우 | `dead_letter_oldest` | 자동 drop이 아니라 명시 설정으로만 허용 |

기본값은 안전해야 합니다. 누락된 설정은 무제한 수신이나 silent drop이 아니라 명시적인 unavailable/error로
보고해야 합니다.

## 9. Status contract

Recorder ingress `/recorder-ingress/status`는 Phase 3/4에서 아래 optional object를 채워야 합니다.

- `spool`: 전체 spool 상태
- `replay`: 전체 replay 상태
- `recorders[].spool`: recorder별 spool 상태
- `recorders[].replay`: recorder별 replay 상태

OpenAPI 초안은 `docs/api/recorder-ingress.openapi.yaml`에 둡니다. Phase 2에서는 optional field로 남기고,
Phase 3/4에서 구현된 뒤 runtime contract와 health policy의 required read model로 승격합니다.

## 10. Phase completion proof

### Phase 3 proof

- text `send_data`가 `spooled`로 기록됨
- binary attachment `send_data`가 `spooled`로 기록됨
- Redis write 실패가 `spool_write_failed`로 남음
- mirror spool limit 초과가 `rejected`와 `spool_full` evidence로 남음
- audit 실패와 spool 실패가 다른 counter로 남음

Phase 3의 `mirror_spool`은 upstream WebSocket pipe를 끊지 않습니다. 따라서 `rejected`는 네트워크
수신 거부가 아니라 spool 기록 거부 evidence입니다. upstream direct `send_data` 유입 차단은 Phase 4의
`spool_only`/`spool_and_replay` frame-level relay에서 수행합니다.

### Phase 4 proof

- `pending` item이 replay 성공 뒤 `replayed`가 됨
- upstream down은 `retryable_failed`와 `upstream_unavailable`로 남음
- payload invalid는 retry하지 않고 `dead_lettered`가 됨
- replay rate limit이 적용됨
- replay lag가 status에 드러남
- `spool_only`에서 client `send_data` frame이 upstream으로 direct relay되지 않음
- `mirror_spool`에서 client `send_data` frame이 기존처럼 upstream으로 direct relay됨

Phase 4의 implementation proof는 replay worker/storage transition 단위 테스트와 local fake upstream을
사용한 recorder ingress WebSocket relay integration test로 검증합니다.

Compose 환경 proof는 Swift/macOS runtime build 전에 실행합니다. 이 proof는 실제 Compose의
`recorder-ingress`, upstream `app`, `redis`, testkit Socket.IO client를 함께 사용해 `spool_and_replay`
경로를 확인합니다.

```sh
make testkit/recorder-ingress/replay
```

성공 조건은 testkit stream이 보낸 `send_data` 수만큼 recorder ingress status의 `spooledEvents`와
`replayedEvents`가 증가하고, Redis `dead_letter` list가 비어 있는 것입니다. Swift `dist/dmg/*` build는
이 compose proof 이후 guest packaging과 VM compile 경로를 검증하는 단계로 둡니다.

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
