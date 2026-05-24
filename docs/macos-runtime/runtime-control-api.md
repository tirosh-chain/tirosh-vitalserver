# Runtime Control API

Runtime Control API는 PWA, native shell, remote control client가 공유할 runtime control boundary입니다. 현재 branch는 Swift `RuntimeControlAPI` target에 route/DTO, transport-independent router, macOS local loopback HTTP server skeleton을 둡니다. 이 문서는 PWA 착수 직전 기준으로 어떤 계약이 고정됐고, 무엇이 다음 단계에서 구현될지 정리합니다.

OpenAPI contract는 [`runtime-control.openapi.json`](./runtime-control.openapi.json)에 둡니다. Swift test는 `RuntimeControlAPIEndpoint`와 OpenAPI path/method parity를 검증합니다.
배포 Swagger UI에서는 이 spec을 VitalServer API, Audit Proxy API와 함께 multi-spec catalog로 노출합니다.

## Target

| Target | 책임 |
|---|---|
| `RuntimeControl` | UI/usecase 관점의 typed protocol, DTO, enum, result model |
| `RuntimeControlAPI` | HTTP transport 관점의 route, request/response DTO, file reference abstraction, read-only router, local HTTP server skeleton |
| `MacHostRuntimeAdapter` | 현재 macOS local 구현. `RuntimeControlClient`와 `RuntimeHostClient`를 구현 |

## Local Server

macOS Helper app composition은 read-only Runtime Control API server를 조립합니다.

| 항목 | 값 |
|---|---|
| Base URL | `http://127.0.0.1:18321` |
| Interface | loopback only |
| Auth header | `X-Runtime-Control-Token` |
| Transitional dev token | `vitalserver-helper-dev` |

현재 local server는 아래 endpoint만 구현합니다.

| Method | Path |
|---|---|
| `GET` | `/runtime/capabilities` |
| `GET` | `/runtime/status` |
| `GET` | `/runtime/events` |
| `POST` | `/runtime/health` |
| `GET` | `/runtime/settings` |
| `GET` | `/runtime/release` |
| `GET` | `/runtime/install` |

나머지 route는 계약에는 있지만 현재 read-only router에서 `501 endpointNotImplemented`를 반환합니다.

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
| `GET` | `/runtime/events` | runtime status/progress event history |
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
| `browserSafe` | 브라우저/PWA가 local Runtime Control server에 직접 호출 가능한 read-only runtime control | `GET /runtime/capabilities`, `GET /runtime/status`, `GET /runtime/events`, `POST /runtime/health`, `GET /runtime/settings`, `GET /runtime/release`, `GET /runtime/install` |
| `localServerMediated` | 브라우저가 직접 host resource를 만지지 않고 local server가 권한/파일/프로세스 작업을 중재해야 함 | runtime write/admin routes, backups list/delete/rollback, log read, update bundle summary/verify/apply |
| `nativeShellOnly` | 브라우저 endpoint만으로는 UX나 보안 경계가 충분하지 않아 native shell mediation이 필요함 | `POST /host/logs/export` |

Portable `/runtime/*` route는 `RuntimeControlFileReference`를 사용하지 않습니다. 파일, update bundle, backup, log export destination처럼 host resource를 가리키는 값은 `/host/*` affordance에서만 `RuntimeControlFileReference`로 표현합니다.

## File Reference

PWA는 host local path를 직접 다룰 수 없습니다. 그래서 update bundle, backup, log export destination처럼 파일을 가리키는 값은 `RuntimeControlFileReference`로 표현합니다.

| Kind | 의미 |
|---|---|
| `localPath` | macOS SwiftUI/native shell 전환기에서 쓰는 local file path |
| `uploadedArtifact` | PWA/API server에 업로드된 artifact id |
| `remoteURL` | server가 가져올 수 있는 remote URL |

## Next Issue

다음 Runtime Control API 단계에서는 아래를 구현합니다.

| 항목 | 내용 |
|---|---|
| observability SQLite read model | `/runtime/events` query를 위해 `runtime-observability.sqlite` 우선 조회 추가 |
| JSONL fallback | SQLite unavailable 시 기존 `runtime-events.jsonl` 조회로 degrade |
| event push subscription | polling 없이 event stream을 받기 위한 SSE/WebSocket 또는 native bridge contract |
| schema migration | SQLite schema version과 migration runner 확장 |
| HTTP client adapter | PWA/native shell이 사용할 generated/manual client |
| auth/session | 현재 dev token을 local pairing token, remote session, capability negotiation으로 교체 |
| streaming | progress/log SSE 또는 동등한 event stream |
| OpenAPI export | 현재 수동 OpenAPI 문서를 generated 또는 schema-test 강화 방식으로 전환 |
| host affordance | `/host/*` route를 browser-safe/local-server-mediated/native-shell-only로 분류 |
