# Recorder documentation map

이 디렉터리는 VitalServer가 VRecorder traffic을 받아 UI, Redis, recorder ingress로 연결하는 흐름을 정리합니다. 문서는 역할별 source of truth를 나눕니다.

## 읽는 순서

| 순서 | 문서 | 역할 |
|---|---|---|
| 1 | [Vital Recorder](vrecorder.md) | VRecorder가 upstream VitalServer와 맺는 Socket.IO protocol, `vrcode`, Web Monitoring 표시 기준 |
| 2 | [Redis 데이터 구조](redis-data-model.md) | upstream VitalServer가 `send_data` 처리 뒤 Redis에 남기는 key, TTL, relay scope |
| 3 | [VitalServer command audit](command-audit.md) | recorder ingress의 audit event, Redis IP rewrite, 운영 확인 |
| 4 | [Recorder ingress send_data spool/replay contract](send-data-spool-replay.md) | Issue #68의 `send_data` direct relay 차단, spool, replay, backpressure 계약 |

## 문서 책임

### `vrecorder.md`

VRecorder 호환 client가 어떤 event를 보내야 VitalServer에서 online으로 보이는지 설명합니다. `join_vr`, `send_data` payload shape, Network Settings, Web Monitoring UI 상태 기준이 이 문서의 책임입니다. recorder ingress 내부 구현이나 Redis relay 정책은 이 문서에서 정의하지 않습니다.

### `redis-data-model.md`

Upstream VitalServer가 Redis에 남기는 key model을 설명합니다. bed/recorder relationship, activity, waveform/trend frame, TTL, relay scope의 source of truth입니다. `send_data` 처리 비용이나 OOM 완화 전략은 [send-data-spool-replay.md](send-data-spool-replay.md)를 기준으로 봅니다.

### `command-audit.md`

Recorder ingress가 traffic을 관측해 audit event와 Redis IP rewrite 상태를 남기는 계약입니다. `join_vr`, `req_cmd`, command dispatch, audit sink, `/recorder-ingress/status` 운영 확인이 이 문서의 책임입니다. `send_data` spool/replay state machine은 링크만 두고 상세 계약을 중복 정의하지 않습니다.

### `send-data-spool-replay.md`

Issue #68의 본 해결 문서입니다. Upstream VitalServer의 `send_data` 처리 경로와 메모리 압력 원인, direct relay 차단, durable spool, replay worker, backpressure, state/failure/proof 계약을 정의합니다.

## 중복 방지 원칙

- VRecorder protocol은 `vrecorder.md`에 둡니다.
- Upstream Redis key model은 `redis-data-model.md`에 둡니다.
- Recorder ingress audit/IP rewrite 운영은 `command-audit.md`에 둡니다.
- `send_data` spool/replay mode, state, failure, backpressure, proof는 `send-data-spool-replay.md`에 둡니다.
- 다른 문서에서는 필요한 만큼 요약하고 authoritative 문서로 링크합니다.
