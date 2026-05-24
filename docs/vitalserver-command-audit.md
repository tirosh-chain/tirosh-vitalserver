# VitalServer command audit

VitalServer command audit은 upstream VitalServer 코드를 수정하지 않고 Socket.IO lifecycle과 UI command
event를 추적하기 위한 proxy 계층입니다.

## 위치

1차 구현은 `vitalserver-audit-proxy`를 VitalServer app 앞에 둡니다.

```text
host nginx
  -> guest nginx
  -> vitalserver-audit-proxy
  -> upstream VitalServer app
```

장기적으로는 guest nginx와 audit proxy를 하나의 edge proxy로 합칠 수 있습니다. 다만 제품 관점에서는
먼저 audit proxy를 안정화한 뒤, nginx가 맡고 있는 Redis UI, Swagger UI, health, header policy,
WebSocket upgrade routing을 단계적으로 이전해야 합니다.

## 책임

- `join_vr` event audit
- `join_vr` 시점의 selected IP/source 계산
- Redis `ip_<vrcode>` best-effort 보정 저장
- `send_data` event audit
- `req_cmd` event audit
- server -> VRecorder command dispatch event audit
- audit Redis List sink
- proxy health/status endpoint 제공

Audit 실패는 VitalServer 기능 실패로 전파하지 않습니다.

## 환경변수

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `AUDIT_PROXY_PORT` | `8080` | audit proxy listen port |
| `AUDIT_PROXY_UPSTREAM_HOST` | `app` | upstream VitalServer host |
| `AUDIT_PROXY_UPSTREAM_PORT` | `80` | upstream VitalServer port |
| `VITALSERVER_REDIS_HOST` | `redis` | Redis host |
| `VITALSERVER_REDIS_PORT` | `6379` | Redis port |
| `VITALSERVER_TRUST_PROXY` | `1` | forwarding header 신뢰 여부 |
| `VITALSERVER_AUDIT_ENABLED` | `1` | `0`이면 audit write 비활성화 |
| `VITALSERVER_AUDIT_REDIS_LIST` | `vitalserver:audit_events` | audit event Redis List key |
| `VITALSERVER_AUDIT_REDIS_MAXLEN` | `10000` | Redis List 유지 길이 |
| `VITALSERVER_AUDIT_FILE_ENABLED` | `1` | `0`이면 audit file log 비활성화 |
| `VITALSERVER_AUDIT_LOG_PATH` | `/var/log/vitalserver-audit/audit-events.log` | append-only audit log path |
| `VITALSERVER_AUDIT_LOG_FORMAT` | `json` | `json` 또는 `logfmt` |
| `VITALSERVER_AUDIT_STDOUT_ENABLED` | `1` | `0`이면 container log collector용 stdout audit log 비활성화 |
| `VITALSERVER_AUDIT_STDOUT_FORMAT` | `VITALSERVER_AUDIT_LOG_FORMAT` | stdout audit log format. `json` 또는 `logfmt` |
| `AUDIT_PROXY_IP_WRITE_DELAY_MS` | `250` | upstream `join_vr` 처리 뒤 `ip_<vrcode>` 보정 write 지연 |
| `AUDIT_PROXY_UPSTREAM_TIMEOUT_MS` | `30000` | upstream VitalServer 응답 대기 timeout |

Audit event는 기본적으로 파일 로그와 Redis List에 함께 기록합니다. 파일 로그는 Docker named volume
`audit-logs`에 저장되므로 컨테이너 재시작 후에도 유지됩니다. 같은 event를 stdout에도 기록하므로
guest의 `tirosh-vitalserver-container-logs` collector가 `docker compose logs --follow`로 수집하는
`container-logs.log`에도 포함됩니다. Redis는 현재 `3.2.12`로 pin되어 있으므로 Redis Stream 대신 Redis
List를 보조 조회 sink로 사용합니다.

## Event schema

코드 기준 event 계약은 `apps/vitalserver-audit-proxy/src/domain/audit-event-contracts.js`에 모읍니다. 새 audit event를
추가할 때는 먼저 이 파일에 event type, Socket.IO event name, JSDoc payload contract를 추가합니다.

Audit proxy 코드는 작은 DDD 경계로 구성합니다.

- `src/domain`: VitalServer Socket.IO event 이름, audit event 계약, command payload 해석, `send_data` 요약 규칙
- `src/application`: Socket.IO audit 유스케이스와 도메인 흐름
- `src/infrastructure`: HTTP/WebSocket proxy, Redis audit sink, Redis VRecorder identity store
- `src/observability`: runtime metric 수집과 status snapshot

공통 필드:

```json
{
  "schema_version": 1,
  "source": "vitalserver-audit-proxy",
  "event_type": "join_vr",
  "ts": "2026-05-24T00:00:00.000Z",
  "ts_unix_ms": 1779552000000
}
```

### `join_vr`

```json
{
  "event_type": "join_vr",
  "vrcode": "VR001",
  "selected_ip": "172.31.0.152",
  "selected_source": "x-forwarded-for",
  "remote_address": "172.18.0.1",
  "trust_proxy": true
}
```

### `send_data`

`send_data` payload는 compressed/binary string입니다. Proxy는 원본 body를 streaming으로 upstream에
전달하면서 audit용 mirror buffer만 별도로 보관합니다. 가능한 경우 payload를 inflate해서 `vrcode`,
`version`, `rooms_count`를 기록하고, decode에 실패하면 size와 decode error만 기록합니다.

```json
{
  "event_type": "send_data",
  "payload_summary": {
    "payload_type": "string",
    "bytes": 12345,
    "vrcode": "VR001",
    "version": "2.3.4",
    "rooms_count": 4
  }
}
```

### `req_cmd`

```json
{
  "event_type": "req_cmd",
  "command_job": "restart_vr",
  "target_vrcode": "VR001",
  "payload": {
    "job": "restart_vr",
    "vrcode": "VR001"
  }
}
```

### `command_dispatch`

```json
{
  "event_type": "command_dispatch",
  "dispatch_event": "restart"
}
```

현재 dispatch event는 `update`, `del_bed`, `restart`, `reboot`, `add_event`, `edit_bed`, `edit_conf`를
기록합니다.

## 운영 확인

로컬 문법/단위 테스트:

```sh
npm --prefix apps/vitalserver-audit-proxy run check
npm --prefix apps/vitalserver-audit-proxy test
```

최근 audit event:

```sh
docker compose exec redis redis-cli LRANGE vitalserver:audit_events -10 -1
```

파일 audit log:

```sh
docker compose exec audit-proxy tail -n 20 /var/log/vitalserver-audit/audit-events.log
VITALSERVER_AUDIT_LOG_FORMAT=logfmt docker compose up -d audit-proxy
```

proxy 상태:

```sh
curl http://localhost:18080/audit-proxy/status
```

`/audit-proxy/status`는 현재 WebSocket 수, 관측한 Socket.IO event 수, parse 실패 수, Redis write 실패
수를 반환합니다.

## 제품 관점 판단

edge proxy를 하나만 유지하는 방향은 가능합니다. 단, 단일 edge proxy가 되려면 아래 기능이 모두
제품 기능으로 검증돼야 합니다.

- HTTP reverse proxy
- WebSocket upgrade proxy
- Socket.IO polling proxy
- Redis UI/Swagger UI route
- health/readiness endpoint
- `X-Forwarded-*` overwrite policy
- audit 실패 격리
- access/audit log 분리
- update/rollback 시 설정 호환성

따라서 #28에서는 audit proxy를 app 앞단에 추가하고, guest nginx 제거는 별도 단계에서 진행합니다.
