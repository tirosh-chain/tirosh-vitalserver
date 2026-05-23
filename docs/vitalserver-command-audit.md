# VitalServer command audit

이 문서는 VitalServer 내부 Socket.IO lifecycle과 UI command audit event 계약을 정의합니다.

## 목적

Redis snapshot과 proxy log만으로는 `join_vr`, `send_data`, UI command 요청, 실제 VRecorder dispatch
시점을 정확히 추적하기 어렵습니다. VitalServer는 해당 시점에 audit event를 남기고, observer는 이
event를 읽어 command trace를 구성합니다.

Audit 실패는 VitalServer 기능 실패로 전파하지 않습니다. Redis 또는 HTTP sink가 실패해도 원래
Socket.IO handler는 계속 진행합니다.

## 저장 위치

기본 sink는 Redis List입니다.

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `VITALSERVER_AUDIT_ENABLED` | `1` | `0`이면 audit 기록을 비활성화 |
| `VITALSERVER_AUDIT_REDIS_LIST` | `vitalserver:audit_events` | audit JSON line을 `RPUSH`할 Redis List key |
| `VITALSERVER_AUDIT_REDIS_MAXLEN` | `10000` | `LTRIM`으로 유지할 최근 event 개수 |
| `VITALSERVER_AUDIT_HTTP_URL` | empty | 설정 시 같은 payload를 HTTP `POST`로 best-effort 전송 |

Redis는 현재 `3.2.12`로 pin되어 있으므로 Redis Stream을 기본값으로 쓰지 않습니다. Stream 기반
전달이 필요하면 Redis 5 이상으로 올린 뒤 별도 migration으로 다룹니다.

## 공통 schema

모든 event는 JSON object입니다.

```json
{
  "schema_version": 1,
  "source": "vitalserver",
  "event_type": "req_cmd",
  "ts": "2026-05-24T01:23:45.678Z",
  "ts_unix_ms": 1779585825678
}
```

## Event types

### `join_vr`

VRecorder가 Socket.IO `join_vr` event를 보낸 시점에 기록합니다.

```json
{
  "event_type": "join_vr",
  "vrcode": "VR001",
  "selected_ip": "172.31.0.152",
  "selected_source": "x-forwarded-for",
  "remote_address": "192.168.97.1",
  "trust_proxy": true,
  "socket_id": "abc123",
  "handshake_headers": {
    "x-forwarded-for": "172.31.0.152",
    "cookie": "[masked]"
  }
}
```

`VITALSERVER_TRUST_PROXY=1`일 때만 `x-forwarded-for`, `x-real-ip`, `forwarded`, `x-client-ip`
header를 IP 후보로 사용합니다. 그렇지 않으면 Socket.IO remote address를 사용합니다.

### `send_data`

VRecorder가 `send_data` payload를 보낸 시점에 기록합니다.

```json
{
  "event_type": "send_data",
  "vrcode": "VR001",
  "rooms_count": 4,
  "version": "2.3.4"
}
```

`rooms_count`는 decoded payload의 `rooms` object key 개수입니다.

### `req_cmd`

UI가 `req_cmd`를 요청한 시점에 기록합니다.

```json
{
  "event_type": "req_cmd",
  "socket_id": "abc123",
  "command_job": "restart_vr",
  "target_vrcode": "VR001",
  "payload": {
    "job": "restart_vr",
    "vrcode": "VR001"
  },
  "user": {
    "id": "admin",
    "name": "관리자",
    "admin_yn": "Y"
  }
}
```

### `command_dispatch`

VitalServer가 VRecorder room으로 실제 command event를 emit한 시점에 기록합니다.

```json
{
  "event_type": "command_dispatch",
  "socket_id": "abc123",
  "command_job": "restart_vr",
  "target_vrcode": "VR001",
  "dispatch_event": "restart"
}
```

현재 기록하는 dispatch event는 `update`, `del_bed`, `restart`, `reboot`, `add_event`, `edit_bed`,
`edit_conf`입니다.

## Masking

Audit payload는 key 이름 기준으로 민감 필드를 마스킹합니다. 아래 문자열이 포함된 key는 값 대신
`[masked]`를 기록합니다.

- `password`
- `passwd`
- `pw`
- `token`
- `secret`
- `authorization`
- `cookie`
- `session`
- `key`

문자열 값은 2000자를 초과하면 truncate합니다. 깊은 object는 depth 8에서 잘라 순환/대형 payload로
인한 audit 실패를 방지합니다.

## 읽기 예시

최근 event 확인:

```sh
docker compose exec redis redis-cli LRANGE vitalserver:audit_events -10 -1
```

비우기:

```sh
docker compose exec redis redis-cli DEL vitalserver:audit_events
```
