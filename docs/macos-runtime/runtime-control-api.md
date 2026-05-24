# Runtime Control API

Runtime Control API는 PWA, native shell, remote control client가 공유할 runtime control boundary입니다. 현재 Swift `RuntimeControlAPI` target은 route/DTO, transport-independent router, SSE response model, macOS local loopback HTTP server를 둡니다. 이 문서는 PWA 착수 직전 기준으로 고정된 계약과 아직 구현이 남은 범위를 정리합니다.

OpenAPI contract는 [`runtime-control.openapi.json`](./runtime-control.openapi.json)에 둡니다. Swift test는 `RuntimeControlAPIEndpoint`와 OpenAPI path/method parity를 검증합니다.
배포 Swagger UI에서는 이 spec을 VitalServer API, Audit Proxy API와 함께 multi-spec catalog로 노출합니다.

## Target

| Target | 책임 |
|---|---|
| `RuntimeControl` | UI/usecase 관점의 typed protocol, DTO, enum, result model |
| `RuntimeControlAPI` | HTTP transport 관점의 route, request/response DTO, file reference abstraction, read-only/SSE router, local HTTP server |
| `MacHostRuntimeAdapter` | 현재 macOS local 구현. `RuntimeControlClient`와 `RuntimeHostClient`를 구현 |

## Local Server

macOS Helper app composition은 `distribution.profile=dev` build에서만 read-only Runtime Control API server를 조립합니다. Stable build는 아직 local API server를 시작하지 않습니다. Stable/PWA용 API는 pairing/session token 기반 auth 정책을 넣은 뒤 열어야 합니다.

| 항목 | 값 |
|---|---|
| Base URL | `http://127.0.0.1:18321` |
| Interface | loopback only |
| Auth header | `X-Runtime-Control-Token` |
| Dev-only transitional token | `vitalserver-helper-dev` |

Dev local server는 read-only runtime endpoint와 일부 host log endpoint를 구현합니다.

| Method | Path |
|---|---|
| `GET` | `/runtime/capabilities` |
| `GET` | `/runtime/status` |
| `GET` | `/runtime/status/stream` |
| `GET` | `/runtime/events` |
| `GET` | `/runtime/events/stream` |
| `POST` | `/runtime/health` |
| `GET` | `/runtime/settings` |
| `GET` | `/runtime/release` |
| `GET` | `/runtime/install` |
| `POST` | `/host/logs/read` |
| `GET` | `/host/logs/stream` |

나머지 write/admin/host affordance route는 계약에는 있지만 현재 router에서 `501 endpointNotImplemented`를 반환합니다.

`GET /runtime/events`는 운영 이력 조회용 query parameter를 지원합니다. 목표 구현은 SQLite read model을
우선 조회하고, DB가 없거나 손상된 경우 기존 `runtime-events.jsonl` fallback으로 응답하는 것입니다.

| Query | Meaning |
|---|---|
| `limit` | 반환할 event 수. 1-500, 기본 100 |
| `type` | `status-changed`, `health-observed`, `audit-proxy-observed` 같은 runtime event type |
| `since` | ISO-8601 timestamp lower bound |
| `cursor` | 이전 응답의 `nextCursor` 값을 그대로 전달하는 opaque pagination cursor |

내부 구현은 `RuntimeEventQuery` read model query로 변환되어 SQLite에 pushdown됩니다. Cursor는
내부적으로 `timestamp + id` 기준이며, API에는 opaque string으로만 노출합니다. Client는 cursor 값을
해석하지 않고 다음 페이지 조회 시 `cursor=<nextCursor>`로 다시 전달해야 합니다.

`GET /runtime/status/stream`은 long-lived SSE 연결입니다. 서버는 연결을 유지하고 runtime status가 바뀔 때
`runtime-status` frame을 보냅니다. 각 frame의 `id` 값은 `runtime-status`, `data` 값은 JSON encoded
`RuntimeStatus`입니다. 변경이 없으면 heartbeat comment를 보냅니다.

`GET /runtime/events/stream`은 client polling 없이 runtime event를 받기 위한 SSE contract입니다. 연결은
`Accept: text/event-stream`을 사용하고, 각 SSE frame의 `event` 값은 `RuntimeEventType`, `id` 값은
`RuntimeEventDocument.id`, `data` 값은 JSON encoded `RuntimeEventDocument`입니다. 서버는 연결을 유지하고
아직 전달하지 않은 새 event만 보냅니다. Client는 재연결 시 마지막으로 받은 event id를 `Last-Event-ID`
header로 전달할 수 있어야 합니다. 이 stream은 server에서 client로 보내는 단방향 status/progress/event
channel이며, command 전송용 양방향 WebSocket contract가 아닙니다.

`GET /host/logs/stream`은 long-lived SSE 연결입니다. 서버는 선택한 host log text가 바뀔 때 `runtime-log`
frame을 보냅니다. 각 frame의 `id` 값은 `runtime-log-<source>`, `data` 값은 JSON encoded
`RuntimeLogTextResponse`입니다. Query는 `source`, `lineLimit`, `helperMessage`를 지원합니다.

`distribution.profile`이 `dev`인 build에서는 macOS Helper가 실행 중일 때
`http://127.0.0.1:18321/dev/runtime-control`에서 브라우저용 Runtime Control API console을 열 수 있습니다.
Stable build는 local API server와 이 route를 제공하지 않습니다. 이 화면은 product PWA가 아니라 API/SSE
동작 확인용 loopback dev tool이며, status snapshot, status stream, event stream, log stream을 같은 origin에서 호출합니다.

## Route Scope

`RuntimeControlAPI`는 route를 두 scope로 나눕니다.

| Scope | Prefix | 의미 | PWA에서의 해석 |
|---|---|---|---|
| `runtimeControl` | `/runtime/*` | local/remote runtime control usecase | PWA가 우선 의존할 API surface |
| `hostAffordance` | `/host/*` | local file/log/update-bundle affordance | browser가 직접 수행하지 않고 native shell 또는 server endpoint로 재배치 |

## Runtime Routes

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/runtime/capabilities` | capability negotiation |
| `GET` | `/runtime/status` | runtime status read model |
| `GET` | `/runtime/status/stream` | SSE runtime status snapshot subscription |
| `GET` | `/runtime/events` | runtime status/progress event history |
| `GET` | `/runtime/events/stream` | SSE runtime status/progress event subscription |
| `POST` | `/runtime/health` | active health refresh |
| `GET` | `/runtime/settings` | current runtime settings |
| `PUT` | `/runtime/settings` | apply runtime settings |
| `GET` | `/runtime/release` | helper/release/component metadata |
| `GET` | `/runtime/install` | installed runtime paths and install metadata |
| `POST` | `/runtime/services/start` | start runtime services |
| `POST` | `/runtime/services/stop` | stop runtime services |
| `POST` | `/runtime/services/repair-proxy` | repair host proxy |
| `POST` | `/runtime/services/repair-datastore` | repair datastore |
| `POST` | `/runtime/uninstall` | uninstall runtime |

## Host Affordance Routes

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/host/backups` | list local backups |
| `POST` | `/host/logs/read` | read selected log text |
| `GET` | `/host/logs/stream` | SSE host log text snapshot subscription |
| `POST` | `/host/logs/export` | export local logs |
| `POST` | `/host/update-bundles/summary` | inspect selected update bundle |
| `POST` | `/host/update-bundles/verify` | verify selected update bundle |
| `POST` | `/host/update-bundles/apply` | apply selected update bundle |
| `POST` | `/host/backups/rollback` | rollback selected backup |
| `DELETE` | `/host/backups` | delete selected backup |

## Client Access Classification

`RuntimeControlAPIEndpoint`는 scope와 별도로 client access를 갖습니다. OpenAPI의 `x-runtime-control-access` 값은 Swift enum과 parity test로 검증합니다.

| Access | 의미 | 현재 route |
|---|---|---|
| `browserSafe` | 브라우저/PWA가 local Runtime Control server에 직접 호출 가능한 read-only runtime control | `GET /runtime/capabilities`, `GET /runtime/status`, `GET /runtime/status/stream`, `GET /runtime/events`, `GET /runtime/events/stream`, `POST /runtime/health`, `GET /runtime/settings`, `GET /runtime/release`, `GET /runtime/install` |
| `localServerMediated` | 브라우저가 직접 host resource를 만지지 않고 local server가 권한/파일/프로세스 작업을 중재해야 함 | runtime write/admin routes, backups list/delete/rollback, log read/stream, update bundle summary/verify/apply |
| `nativeShellOnly` | 브라우저 endpoint만으로는 UX나 보안 경계가 충분하지 않아 native shell mediation이 필요함 | `POST /host/logs/export` |

Portable `/runtime/*` route는 `RuntimeControlFileReference`를 사용하지 않습니다. 파일, update bundle, backup, log export destination처럼 host resource를 가리키는 값은 `/host/*` affordance에서만 `RuntimeControlFileReference`로 표현합니다.

## File Reference

PWA는 host local path를 직접 다룰 수 없습니다. 그래서 update bundle, backup, log export destination처럼 파일을 가리키는 값은 `RuntimeControlFileReference`로 표현합니다.

| Kind | 의미 |
|---|---|
| `localPath` | macOS SwiftUI/native shell 전환기에서 쓰는 local file path |
| `uploadedArtifact` | PWA/API server에 업로드된 artifact id |
| `remoteURL` | server가 가져올 수 있는 remote URL |

## Remaining Work

다음 Runtime Control API/PWA 단계에서는 아래를 구현합니다.

| 항목 | 내용 |
|---|---|
| event push subscription | 현재 long-lived SSE는 서버 내부 주기 관찰 기반입니다. file watcher 또는 repository-level publisher로 push latency를 더 줄입니다 |
| schema migration | SQLite schema version과 migration runner 확장 |
| HTTP client adapter | PWA/native shell이 사용할 generated/manual client |
| auth/session | 현재 dev token을 local pairing token, remote session, capability negotiation으로 교체 |
| progress client adapter | progress 전용 stream 또는 event stream 내 progress adapter |
| OpenAPI export | 현재 수동 OpenAPI 문서를 generated 또는 schema-test 강화 방식으로 전환 |
| host affordance implementation | `/host/*` write/update/backup route 구현과 native shell mediation 강화 |
