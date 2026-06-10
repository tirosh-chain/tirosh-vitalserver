# Runtime Control API

Runtime Control API는 PWA, native shell, remote control client가 공유할 runtime control boundary입니다. 현재 Swift `RuntimeControlAPI` target은 route/DTO, transport-independent router, SSE response model, macOS local loopback HTTP server를 둡니다. 이 문서는 Helper app에 포함되는 Runtime Control PWA와 native UI가 공유하는 계약과 아직 구현이 남은 범위를 정리합니다.

OpenAPI contract는 [`runtime-control.openapi.json`](./runtime-control.openapi.json)에 둡니다. Swift test는 `RuntimeControlAPIEndpoint`와 OpenAPI path/method parity를 검증합니다.
배포 Swagger UI에서는 이 spec을 VitalServer API, Audit Proxy API와 함께 multi-spec catalog로 노출합니다.

## Target

| Target | 책임 |
|---|---|
| `RuntimeControl` | UI/usecase 관점의 typed protocol, DTO, enum, result model |
| `RuntimeControlAPI` | HTTP transport 관점의 route, request/response DTO, file reference abstraction, read-only/SSE router, local HTTP server |
| `MacHostRuntimeAdapter` | 현재 macOS local 구현. `RuntimeControlClient`와 `RuntimeHostClient`를 구현 |

## Local Server

macOS Helper app composition은 Runtime Control API server를 TestKit/dev console 노출 여부와 분리해서 조립합니다.
PWA가 사용할 `/runtime/*`, `/vitaldb/*`, `/host/*` API는 stable/dev profile 모두에서 같은 local server를 통해
제공될 수 있어야 합니다. `/dev/runtime-control` 확인 화면과 `/dev/testkit/*` route만 `distribution.profile=dev`
또는 test-enabled build 뒤에 둡니다. Stable/PWA용 인증은 현재 transitional token에서 pairing/session token
정책으로 교체해야 합니다.

| 항목 | 값 |
|---|---|
| Base URL | `http://127.0.0.1:18321` |
| Interface | loopback only |
| Auth header | `X-Runtime-Control-Token` |
| Transitional local token | `vitalserver-helper-dev` |

Local server는 Runtime Control PWA static assets, read-only runtime endpoint, PWA overview,
Redis backup 생성/조회, rollback backup 조회, 일부 host log endpoint를 구현합니다.
Product build에서는 `apps/vitalserver-runtime-pwa/dist/` 결과물이 Helper app resource
`Contents/Resources/runtime-control-pwa/`에 포함되고, local server가 아래 주소에서 제공합니다.

```text
http://127.0.0.1:18321/
```

PWA static file 요청은 token 없이 처리합니다. `/runtime/*`, `/vitaldb/*`, `/host/*`, `/dev/*` API 요청은
기존 Runtime Control API authorization 정책을 따릅니다.

`GET /runtime/capabilities`는 PWA route와 command availability의 source of truth입니다. TestKit 관련
`/dev/testkit/*` route는 test-enabled build에서만 노출되며, PWA는 `canUseTestTools=true`일 때만 Test
탭을 보여줍니다.

| Method | Path |
|---|---|
| `GET` | `/runtime/capabilities` |
| `GET` | `/runtime/overview` |
| `GET` | `/runtime/overview/stream` |
| `GET` | `/runtime/status` |
| `GET` | `/runtime/status/stream` |
| `GET` | `/runtime/events` |
| `GET` | `/runtime/events/stream` |
| `GET` | `/vitaldb/observations/latest` |
| `GET` | `/vitaldb/observations/stream` |
| `GET` | `/vitaldb/recorders` |
| `GET` | `/vitaldb/recorders/{vrcode}` |
| `GET` | `/vitaldb/recorders/{vrcode}/activity` |
| `GET` | `/vitaldb/beds` |
| `GET` | `/vitaldb/beds/{bedID}` |
| `GET` | `/vitaldb/relationships` |
| `POST` | `/runtime/health` |
| `GET` | `/runtime/settings` |
| `GET` | `/runtime/release` |
| `GET` | `/runtime/install` |
| `POST` | `/runtime/redis/backups` |
| `GET` | `/host/backups` |
| `GET` | `/host/backups/redis` |
| `POST` | `/host/logs/read` |
| `GET` | `/host/logs/stream` |

TestKit route와 browser 확인용 dev console은 test-enabled build에서만 노출됩니다.

## Status Vocabulary

Runtime Control API는 wire payload에서 `runtimeInstalled`, `runtimeState`, `operation`, HTTP probe status처럼 도메인별 raw 값을 그대로 전달합니다. SwiftUI/PWA 표시 계층은 이 raw 값을 그대로 노출하지 않고 shared presentation vocabulary로 변환합니다.

| UI label | Source of truth | Display vocabulary |
|---|---|---|
| Runtime installation | `RuntimeStatus.runtimeInstalled` | `Installed`, `Not Installed` |
| Runtime state | `RuntimeStatus.runtimeState` | `Installing`, `Updating`, `Recovering`, `Healthy`, `Degraded`, `Critical`, `Unknown` |
| VM/proxy/watchdog/guest log sync/sleep prevention service | launchd loaded flags | `Running`, `Stopped` |
| VitalServer/Network access/Redis UI/Swagger UI | HTTP probe fields | `Reachable`, `Unreachable`, `Waiting` |
| Redis container health | guest compose observation | `Healthy`, `Unhealthy`, `Starting`, `Running`, `Stopped` |
| VitalDB recorder/bed status | VitalDB observation history | `Online`, `Stale`, `Offline`, `Not observed`, `Unknown` |
| Command/progress step | `RuntimeProgressDocument` | `Waiting`, `Running`, `Done`, `Failed`, `Skipped` |
| Planned or unsupported feature | capability/build profile | `Planned`, `Not Available` |

`Runtime installation` replaces the older UI wording `Helper runtime`. The value describes whether the installed VitalServer runtime components exist on the Mac, not whether the Helper app process itself is running.

`RuntimeVitalRecorderStatus.notObserved` and `RuntimeVitalBedStatus.notObserved` mean the recorder or bed is known from history but is absent from the latest VitalDB observation. It is distinct from `offline`, which requires the current owner observation to report the subject as present and not online.

`RuntimeVitalRecorderRecord.observationCount` and `RuntimeVitalBedRecord.observationCount` are support/debug metadata, not primary operator UI fields. They count how many stored VitalDB observation snapshots included the VRecorder or bed identity after same-snapshot duplicates were collapsed. `RuntimeVitalRecorderRecord.duplicateObservationCount` and `RuntimeVitalBedRecord.duplicateObservationCount` report the number of extra source records collapsed because they shared the same VRecorder or bed identity in a snapshot. `0` means no duplicate source records were collapsed for that identity.

`RuntimeVitalRecorderHistory.updatedAt` is displayed as `Data updated`. It is the latest VitalDB observation snapshot timestamp used to assemble the recorder/bed history response. It is distinct from each record's `lastSeenAt`, which comes from the recorder or bed activity source.

`RuntimeVitalRecorderRecord.latestAnomalyKind`, `latestAnomalySeverity`, `latestAnomalyMessage`, and `latestAnomalyObservedAt` describe the latest current anomaly for that VRecorder. The matching `RuntimeVitalBedRecord` fields describe the latest current anomaly for that bed. These fields remain null when there is no current anomaly.

`RuntimeVitalBedRecord.linkedRecorderStatus`, `linkedRecorderIP`, and `linkedRecorderLastSeenAt` are copied from the explicit VRecorder read model record linked by `vrcode`. They remain null when no linked VRecorder record is available; clients must not infer them from bed status.

`RuntimeStatus.sleepPreventionServiceLoaded` reports the optional host launchd service that keeps the Mac awake while VitalServer is running. It prevents idle system sleep so the host proxy, VM, and VRecorder TCP streams remain online, but it cannot prevent manual Sleep, lid close, shutdown, or managed power-policy sleep.

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
응답의 `matchingCount`는 `limit`을 적용하기 전 query 조건에 일치하는 전체 event 수입니다. UI는 이 값을
사용해 "50 shown · 183 matching"처럼 현재 표시 개수와 조회 조건에 맞는 전체 개수를 분리해서 보여줄 수
있습니다.

`GET /runtime/status/stream`은 long-lived SSE 연결입니다. 서버는 연결을 유지하고 runtime status가 바뀔 때
`runtime-status` frame을 보냅니다. 각 frame의 `id` 값은 `runtime-status`, `data` 값은 JSON encoded
`RuntimeStatus`입니다. 변경이 없으면 heartbeat comment를 보냅니다.

`RuntimeStatus.dataDirectoryStats`는 configured Vital files directory의 visible regular file count와
recursive size를 제공합니다. UI는 이를 Data directory path 옆의 보조 정보로 표시하며, volume-level
capacity 정보는 기존 `dataStorage`를 계속 사용합니다.

`GET /runtime/overview`는 PWA status 화면용 aggregated read model입니다. 기존 raw endpoint의 SoT는 그대로
유지하면서 `RuntimeStatus`, `RuntimeSettings`, `RuntimeReleaseInfo`, `RuntimeInstallInfo`, 최신
`VitalDBObservationDocument`, 그리고 native Status 탭의 `Vital Recorder` 섹션과 같은 성격의
`RuntimeVitalRecorderSummary`를 한 payload로 제공합니다. `RuntimeVitalRecorderSummary`는
recorder 상태와 bed 상태를 `vitalDBObservation`에서만 읽습니다. audit-proxy 상태는 recorder 상태로 승격하지
않고, 현재 연결 수(`activeConnections`)만 제공합니다. audit-proxy status가 없으면 `activeConnections`는
생략되고, `vitalDBObservation`이 없으면 recorder/bed/anomaly count도 생략됩니다. 생략된 count는 관측된
`0`이 아니라 not-reported state입니다.

`GET /runtime/overview/stream`은 long-lived SSE 연결입니다. 서버는 overview payload가 바뀔 때
`runtime-overview` frame을 보냅니다. 각 frame의 `id` 값은 `runtime-overview`, `data` 값은 JSON encoded
`RuntimeControlOverview`입니다. PWA는 초기 화면을 `/runtime/overview`로 채우고 이후 이 stream으로 상태를
갱신할 수 있습니다.

`GET /runtime/events/stream`은 client polling 없이 runtime event를 받기 위한 SSE contract입니다. 연결은
`Accept: text/event-stream`을 사용하고, 각 SSE frame의 `event` 값은 `RuntimeEventType`, `id` 값은
`RuntimeEventDocument.id`, `data` 값은 JSON encoded `RuntimeEventDocument`입니다. 서버는 연결을 유지하고
아직 전달하지 않은 새 event만 보냅니다. Client는 재연결 시 마지막으로 받은 event id를 `Last-Event-ID`
header로 전달할 수 있어야 합니다. 이 stream은 server에서 client로 보내는 단방향 status/progress/event
channel이며, command 전송용 양방향 WebSocket contract가 아닙니다.

`GET /host/logs/stream`은 long-lived SSE 연결입니다. 서버는 선택한 host log text가 바뀔 때 `runtime-log`
frame을 보냅니다. 각 frame의 `id` 값은 `runtime-log-<source>`, `data` 값은 JSON encoded
`RuntimeLogTextResponse`입니다. Query는 `source`, `lineLimit`, `helperMessage`를 지원합니다.
`source=helperMessage`는 현재 UI message 값을 재전송하지 않고 host의 append-only
`tirosh-vitalserver-helper-message.log`를 읽습니다. `/host/logs/read` body는 `source`,
`helperMessage`, `lineLimit`를 모두 보내야 하며 legacy helper message 값이 없으면
`helperMessage: null`을 보냅니다. field absence와 explicit null/empty string은 다른 request state로
보존합니다.

`GET /vitaldb/observations/latest`는 watchdog/runtime observability SQLite에 저장된 최신
`VitalDBObservationDocument`를 반환합니다. 이 payload는 `vitaldb-observer` container가 계산한
recorder/bed/device/filter/proxy/anomaly snapshot과 최근 `send_data` 활동량 summary를 guest runtime-state
경로로 전달하고, watchdog이 runtime observability SoT에 저장한 결과입니다. `recorders[].activity`는
audit proxy Redis List에서 계산한 windowed metric이며 message count, byte count, room count, first/last
activity, 초당 message/byte rate를 포함합니다.
`readIssues`는 observer가 source를 읽거나 파싱하는 중 발견한 문제를 보존합니다. 관련 `readIssues`가 있는
빈 배열/빈 activity는 실제 관측값 0이 아니라 부분 관측 실패일 수 있습니다.

`GET /vitaldb/observations/stream`은 long-lived SSE 연결입니다. 서버는 최신 VitalDB observation payload가
바뀔 때 `vitaldb-observed` frame을 보냅니다. 각 frame의 `id` 값은 `vitaldb-observation`, `data` 값은
JSON encoded `RuntimeVitalDBObservationSnapshot`입니다. Stream payload는 `/runtime/overview`의
`vitalDBObservationSnapshot`과 같은 read state/readError contract를 유지합니다. 따라서 최신 observation이
없거나 read가 실패한 상태를 `null` observation으로만 축소하지 않습니다.

`GET /runtime/overview`는 `vitalDBObservationSnapshot`에 최신 observation read 상태를 함께 싣습니다.
`state`는 `loaded`, `unavailable`, `failed` 중 하나이며, `observation`이 `null`일 때 단순 미관측인지
read failure인지 구분하기 위한 API-facing metadata입니다. `/vitaldb/observations/latest` 자체는 기존
호환성을 위해 `VitalDBObservationDocument` 또는 `null` payload를 유지합니다.
최신 observation 선택 정책은 명시적입니다. reader는 guest `runtime-state.json`의 current observation을
가장 신선한 source로 우선하고, 없으면 `runtime-status.json`의 current observation을 사용하며, 둘 다 없을
때만 `runtime-observability.sqlite` projection의 latest snapshot을 사용합니다. current source read issue는
projection fallback을 쓰더라도 `readError`에 보존합니다. durable history/relationship/activity read model은
SQLite projection을 source로 유지합니다.

`GET /vitaldb/recorders`는 runtime observability SQLite에 저장된 VitalDB observation snapshot들을
`vrcode` 기준으로 집계한 `RuntimeVitalRecorderHistory`를 반환합니다. `vrcode`는 recorder identity key이며,
IP는 마지막 관측 주소일 뿐 identity로 쓰지 않습니다. 이 read model은 접속했었던 VRecorder 목록, last IP,
version, bed, first/last seen, latest status, current anomaly count, `activityTimeline`을 PWA/SwiftUI가
바로 표시할 수 있게 정리한 결과입니다. `activityTimeline`은 snapshot history에서 vrcode별
`recorders[].activity`를 시간순으로 모은 recorder activity point list입니다. 각 point는 해당 시각의
message count, byte count, room count를 담아 활동 차트를 그리기 위한 값입니다.
`activityHistory.source`는 `sqliteProjection`, `unavailable`, `notProvided` 중 하나입니다.
`sqliteProjection`의 empty timeline은 activity bucket projection을 읽었지만 해당 recorder activity가
없었다는 뜻이고, `notProvided`는 caller가 activity projection을 제공하지 않은 construction path입니다.
`readError`가 있으면 observation/current/activity projection read가 실패해 `recorders`, `beds`,
`activityHistory`가 incomplete일 수 있습니다. 이 상태는 관측된 recorder가 없다는 의미와 구분해야 합니다.

`GET /vitaldb/recorders/{vrcode}`는 같은 history read model에서 특정 `vrcode`의 recorder record 하나를
반환합니다. 관측 이력이 없으면 `null`을 반환합니다.

`GET /vitaldb/recorders/{vrcode}/activity`는 recorder activity chart용 lazy window read model입니다.
Query는 `bucketSeconds=60|300`, `period=last15Minutes|lastHour|last6Hours|last12Hours|all`,
`pageIndex=<non-negative integer>`를 지원합니다. `period=all`일 때 page 하나는 12시간이며,
`pageIndex`가 없으면 최신 page를 반환합니다. 서버는 SQLite에서 해당 `vrcode`의 first/latest bucket
boundary를 먼저 읽고, 선택된 window의 `since/until` 범위만 조회합니다. UI는 응답의 `page.count`,
`page.index`, `page.windowStartedAt`, `page.windowEndedAt`, `buckets`만 표시하고 전체 history gap을
브라우저나 SwiftUI 메모리에서 materialize하면 안 됩니다.

`RuntimeVitalRecorderActivityWindow.state`는 `loaded`, `empty`, `invalidRequest`, `readFailed` 중
하나입니다. `empty`는 read가 성공했지만 해당 recorder/window에 activity bucket이 없다는 뜻이며,
`readFailed`와 구분해야 합니다. `invalidRequest`는 query contract 위반입니다. Missing bucket은 선택된
window 안에서만 zero-count display bucket으로 채울 수 있고, window 밖의 missing history를 activity state로
추정하지 않습니다.

`GET /vitaldb/beds`는 runtime observability SQLite에 저장된 VitalDB observation snapshot들을 `bedID`
기준으로 집계한 `RuntimeVitalBedRecord` 배열을 반환합니다. Bed 탭/PWA는 recorder history payload에
포함된 `beds` 필드에 의존하지 않고 이 route를 우선 사용합니다. `GET /vitaldb/beds/{bedID}`는 특정
bed record 하나를 반환하고, 관측 이력이 없으면 `null`을 반환합니다.

`GET /vitaldb/relationships`는 bed/VRecorder assignment와 relationship event projection을 반환합니다.
`readError`가 있으면 assignment projection 또는 relationship event projection 일부가 실패한 상태이며,
empty `assignments`/`events`를 정상적인 무관측 상태로 해석하면 안 됩니다.

`distribution.profile`이 `dev`인 build에서는 macOS Helper가 실행 중일 때
`http://127.0.0.1:18321/dev/runtime-control`에서 브라우저용 Runtime Control API console을 열 수 있습니다.
Stable build는 local API server는 유지하되 이 dev console route는 제공하지 않습니다. 이 화면은 product PWA가 아니라 API/SSE
동작 확인용 loopback dev tool이며, status snapshot, status stream, event stream, log stream을 같은 origin에서 호출합니다.

## Route Scope

`RuntimeControlAPI`는 route를 두 scope로 나눕니다.

| Scope | Prefix | 의미 | PWA에서의 해석 |
|---|---|---|---|
| `runtimeControl` | `/runtime/*`, `/vitaldb/*` | local/remote runtime control usecase | PWA가 우선 의존할 API surface |
| `hostAffordance` | `/host/*` | local file/log/update-bundle affordance | browser가 직접 수행하지 않고 native shell 또는 server endpoint로 재배치 |

## Runtime Routes

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/runtime/capabilities` | capability negotiation |
| `GET` | `/runtime/overview` | PWA status screen aggregate read model |
| `GET` | `/runtime/overview/stream` | SSE PWA status screen aggregate subscription |
| `GET` | `/runtime/status` | runtime status read model |
| `GET` | `/runtime/status/stream` | SSE runtime status snapshot subscription |
| `GET` | `/runtime/events` | runtime status/progress event history |
| `GET` | `/runtime/events/stream` | SSE runtime status/progress event subscription |
| `GET` | `/vitaldb/observations/latest` | latest VitalDB recorder/bed/anomaly observation snapshot |
| `GET` | `/vitaldb/observations/stream` | SSE VitalDB observation snapshot subscription |
| `GET` | `/vitaldb/recorders` | VRecorder history aggregated by vrcode |
| `GET` | `/vitaldb/recorders/{vrcode}` | one VRecorder history record by vrcode |
| `GET` | `/vitaldb/recorders/{vrcode}/activity` | lazy VRecorder activity chart window |
| `GET` | `/vitaldb/beds` | bed history aggregated by bedID |
| `GET` | `/vitaldb/beds/{bedID}` | one bed history record by bedID |
| `GET` | `/vitaldb/relationships` | VRecorder-bed assignment and relationship event history |
| `POST` | `/runtime/health` | active health refresh |
| `GET` | `/runtime/settings` | current runtime settings |
| `PUT` | `/runtime/settings` | apply runtime settings |
| `GET` | `/runtime/release` | helper/release/component metadata |
| `GET` | `/runtime/install` | installed runtime paths and install metadata |
| `POST` | `/runtime/services/start` | start runtime services |
| `POST` | `/runtime/services/stop` | stop runtime services |
| `POST` | `/runtime/services/repair-runtime` | repair VM, guest log sync, host proxy, and watchdog services |
| `POST` | `/runtime/services/repair-proxy` | repair host proxy |
| `POST` | `/runtime/services/repair-datastore` | repair datastore |
| `POST` | `/runtime/services/repair-vm-disk` | archive and recreate the mutable VM disk from the installed base image |
| `POST` | `/runtime/redis/backups` | create recoverable Redis backup |
| `POST` | `/runtime/uninstall` | uninstall runtime |

## Host Affordance Routes

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/host/backups` | list local backups |
| `GET` | `/host/backups/redis` | list local Redis backups |
| `POST` | `/host/backups/redis/restore` | restore selected Redis backup, planned |
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
| `browserSafe` | 브라우저/PWA가 local Runtime Control server에 직접 호출 가능한 read-only runtime control | `GET /runtime/capabilities`, `GET /runtime/overview`, `GET /runtime/overview/stream`, `GET /runtime/status`, `GET /runtime/status/stream`, `GET /runtime/events`, `GET /runtime/events/stream`, `GET /vitaldb/observations/latest`, `GET /vitaldb/observations/stream`, `GET /vitaldb/recorders`, `GET /vitaldb/recorders/{vrcode}`, `GET /vitaldb/beds`, `GET /vitaldb/beds/{bedID}`, `GET /vitaldb/relationships`, `POST /runtime/health`, `GET /runtime/settings`, `GET /runtime/release`, `GET /runtime/install` |
| `localServerMediated` | 브라우저가 직접 host resource를 만지지 않고 local server가 권한/파일/프로세스 작업을 중재해야 함 | runtime write/admin routes, Redis backup create/list/restore, backups list/delete/rollback, log read/stream, update bundle summary/verify/apply |
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
