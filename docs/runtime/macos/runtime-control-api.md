# Runtime Control API

Runtime Control API는 PWA, native shell, remote control client가 공유할 runtime control boundary입니다. 현재 Swift `RuntimeControlAPI` target은 route/DTO, transport-independent router, SSE response model, macOS local loopback HTTP server를 둡니다. 이 문서는 Helper app에 포함되는 Runtime Control PWA와 native UI가 공유하는 계약과 아직 구현이 남은 범위를 정리합니다.

공통 OpenAPI contract는 [`../runtime-control.openapi.json`](../runtime-control.openapi.json)에 둡니다. Swift test는 `RuntimeControlAPIEndpoint`와 OpenAPI path/method parity를 검증합니다. macOS 배포 Swagger UI에서는 이 spec을 기존 macOS catalog 경로로 복사해 VitalServer API, Recorder Ingress API와 함께 노출합니다.

## Target

| Target | 책임 |
|---|---|
| `RuntimeControl` | UI/usecase 관점의 typed protocol, DTO, enum, result model |
| `InboundAdapters` | HTTP transport 관점의 route, request/response DTO, SSE router, local HTTP server |
| `MacPlatformAgent` | macOS Platform owner/controller와 API handler 조립 |
| `MacPlatformAgentService` | launchd가 관리하는 headless API listener executable |
| `OutboundAdapters` | file/process/Guest Control client와 durable Platform repository |

## Local Server

launchd service `ai.tirosh.vitalserver.helper.platform-agent`가 Runtime Control API
server를 headless process로 조립합니다. Control Panel을 종료해도 API와 PWA는 계속
제공됩니다. `/platform/*`는 Platform Agent owner를, `/runtime/*`는 Runtime Controller
contract를 소비합니다. `/dev/runtime-control` 확인 화면은 dev profile 뒤에 두고,
Lab 기능은 `/runtime/lab/*` product API만 사용합니다. PWA는 static bundle에 API token을
넣지 않고 같은 loopback origin에서 발급한 browser session을 사용합니다.

| 항목 | 값 |
|---|---|
| Base URL | `http://127.0.0.1:18321` |
| Interface | loopback only |
| Auth header | `X-Runtime-Control-Token` |
| Automation token | `/Library/Application Support/VitalServerHelper/secrets/runtime-control-api-token`의 per-install root-owned secret |

Local server는 Runtime Control PWA static assets, read-only runtime endpoint, PWA overview, Redis backup 생성/조회, rollback backup 조회, 일부 host log endpoint를 구현합니다. Product build에서는 `apps/vitalserver-runtime-pwa/dist/` 결과물이 Helper app resource `Contents/Resources/runtime-control-pwa/`에 포함되고, local server가 아래 주소에서 제공합니다.

```text
http://127.0.0.1:18321/
```

PWA static file 요청은 token 없이 처리합니다. PWA는 같은 origin의
`POST /platform/browser-session`으로 `HttpOnly; SameSite=Strict` cookie를 받고,
cookie로 인증된 mutation은 정확히 같은 loopback origin을 다시 확인합니다. root-owned
automation token은 installer/acceptance처럼 browser 밖의 관리 도구만 사용합니다.
이것은 LAN 및 다른 browser origin을 막는 local-browser transport boundary이며, same-user
OS identity authorization을 대신하지는 않습니다. Platform Agent가 재기동되어 기존
cookie가 `401`로 거부되면 네이티브 및 PWA local-session client는 같은 loopback
origin에서 session을 한 번 다시 bootstrap하고 요청을 한 번 재전송합니다. 두 번째
실패는 숨기지 않고 명시적인 API 실패로 반환합니다. Advanced의 Recovery operations는
수동 `Reconnect Runtime Control`도 제공하며 automation token 자체는 회전하지 않습니다.

Capability는 owner별로 독립적으로 읽습니다. `GET /platform/capabilities`는 설치, update, Host service와 local file 같은 Platform Agent 기능을 제공하고, `GET /runtime/capabilities`는 Runtime Controller가 직접 보고한 `schemaVersion`과 capability identifier 목록을 그대로 제공합니다. PWA는 두 응답을 버튼 표시를 위해 함께 사용할 수 있지만 한 owner의 응답으로 다시 저장하거나 다른 owner의 상태에서 capability를 추론하지 않습니다.

Platform capability의 `canControlRuntimeServices`는 Host
maintenance actions such as settings activation, recovery, backup/restore, and
VM/proxy/watchdog lifecycle work를 제어합니다. Runtime product service 제어는
Runtime capability identifier `services:start`, `services:stop`,
`services:restart`가 모두 있을 때만 사용할 수 있습니다. Product Lab은
`lab:scenarios`, `lab:sessions:list`, `lab:recorders:start`,
`lab:recorders:stop` 등 Runtime Controller가 보고한 Lab capability를 사용합니다.

| Method | Path |
|---|---|
| `GET` | `/platform/capabilities` |
| `GET` | `/runtime/capabilities` |
| `GET` | `/platform` |
| `GET` | `/platform/stream` |
| `GET` | `/platform/operations` |
| `GET` | `/runtime/stack` |
| `GET` | `/runtime/services` |
| `GET` | `/runtime/services/{service}/status` |
| `POST` | `/runtime/services/{service}/start` |
| `POST` | `/runtime/services/{service}/stop` |
| `POST` | `/runtime/services/{service}/restart` |
| `GET` | `/runtime/events` |
| `GET` | `/runtime/vitaldb/observations/latest` |
| `GET` | `/runtime/vitaldb/observations/stream` |
| `GET` | `/runtime/vitaldb/recorders` |
| `GET` | `/runtime/vitaldb/recorders/{vrcode}` |
| `GET` | `/runtime/vitaldb/recorders/{vrcode}/activity` |
| `POST` | `/runtime/vitaldb/recorders/{vrcode}/observability/expectation` |
| `GET` | `/runtime/vitaldb/beds` |
| `GET` | `/runtime/vitaldb/beds/{bedID}` |
| `GET` | `/runtime/vitaldb/relationships` |
| `GET` | `/runtime/lab/scenarios` |
| `GET` | `/runtime/lab/beds` |
| `GET` | `/runtime/lab/recorders` |
| `GET` | `/runtime/lab/sessions` |
| `POST` | `/runtime/lab/sessions` |
| `GET` | `/runtime/lab/sessions/{sessionId}` |
| `POST` | `/runtime/lab/sessions/{sessionId}/start` |
| `POST` | `/runtime/lab/sessions/{sessionId}/stop` |
| `POST` | `/runtime/lab/sessions/{sessionId}/finish` |
| `POST` | `/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start` |
| `POST` | `/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop` |
| `GET` | `/runtime/lab/vital-files` |
| `POST` | `/runtime/lab/vital-files/replay` |
| `POST` | `/runtime/lab/vital-files/upload` |
| `GET` | `/runtime/vitaldb/recorders/{vrcode}/vital-files` |
| `POST` | `/runtime/health` |
| `GET` | `/runtime/settings` |
| `GET` | `/platform/settings` |
| `PUT` | `/platform/settings` |
| `GET` | `/platform/release` |
| `GET` | `/platform/installation` |
| `POST` | `/platform/backups/redis` |
| `POST` | `/platform/backups/runtime-data` |
| `GET` | `/platform/backups` |
| `GET` | `/platform/backups/redis` |
| `GET` | `/platform/backups/runtime-data` |
| `POST` | `/platform/backups/runtime-data/restore` |
| `POST` | `/platform/logs/read` |
| `GET` | `/platform/logs/stream` |
| `GET` | `/platform/runtime-endpoint` |
| `PUT` | `/platform/runtime-endpoint` |
| `GET` | `/platform/runtime-provider` |
| `PUT` | `/platform/runtime-provider` |
| `POST` | `/platform/runtime-provider/start` |
| `POST` | `/platform/runtime-provider/stop` |
| `POST` | `/platform/runtime-provider/restart` |

Runtime Lab은 `/runtime/lab/*` product route로 노출됩니다. Legacy `/dev/testkit/*` Runtime Control routes are removed from the product API surface; browser diagnostics should use product Lab contracts or explicit More/Advanced diagnostics instead.

Automatic VitalServer backup은 별도 HTTP command route가 아니라 Settings contract로 제어됩니다. `automaticBackupEnabled`, `backupScheduleTimes`, `backupRetentionCount`를 저장하면 Host configure command가 macOS launchd job `ai.tirosh.vitalserver.helper.automatic-backup`을 갱신합니다. Job은 `runtime automatic-backup`을 실행하며, 생성 대상은 Redis-only archive가 아니라 VitalServer backup입니다.

Runtime log archive retention도 Settings contract로 제어됩니다. `logArchiveRetentionDays`와 `logArchiveMaximumGiB`는 Guest runtime settings가 아니라 Host-owned `/Library/Application Support/VitalServerHelper/runtime-control-settings.json`에 저장됩니다. 이 값은 central log collector가 `/Library/Application Support/VitalServerHelper/logs/archive/YYYY-MM-DD` 관리 archive directory를 prune할 때 사용하며, VM runtime restart requirement를 만들지 않습니다.

## Guest Product Service Control

Runtime v2 exposes product service status and start/stop/restart through Guest Control API. Runtime Control API is the Host-facing consumer boundary; clients must not read Guest Compose files or infer product service state from `runtime-observation.json`.

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/runtime/stack` | read the Runtime Controller-owned product service stack status document |
| `GET` | `/runtime/services` | list Guest-owned product services available for control |
| `GET` | `/runtime/services/{service}/status` | read one Guest product service status document |
| `POST` | `/runtime/services/{service}/start` | request start of one Guest product service and return the persisted operation document |
| `POST` | `/runtime/services/{service}/stop` | request stop of one Guest product service and return the persisted operation document |
| `POST` | `/runtime/services/{service}/restart` | request restart of one Guest product service and return the persisted operation document |

`RuntimeStatus` does not carry Guest service lists, statuses, resources, probe errors, CPU, memory, or system disk usage. Clients read `/runtime/stack` and `/runtime/services/{service}/resource` directly and preserve each owner resource's loaded, failed, and unavailable meanings. A failed owner read must not be converted to an empty list or reconstructed from Host status.

Whole-stack runtime start/stop is not exposed through Runtime Control HTTP API.
`vitalserver-vm runtime start-services` and `vitalserver-vm runtime stop-services`
remain native Host maintenance commands for Host launchd runtime services such
as VM, host proxy, guest log sync, and watchdog. Product service control must
use `/runtime/services/*` so the Guest remains the service owner and the
Host remains an API consumer.

## VitalDB Read Models

Runtime VitalDB read models are exposed to local automation through Guest
Control API. These commands print the Guest contract JSON and do not read Host
SQLite, `runtime-observation.json`, `runtime-status.json`, logs, or recorder-ingress
diagnostics directly.

| Command | 계약 |
|---|---|
| `vitalserver-vm runtime vitaldb-observation [--guest-control-url <url>]` | read the latest Guest-owned VitalDB observation document |
| `vitalserver-vm runtime vitaldb-recorders [--guest-control-url <url>]` | read the Guest-owned VitalDB recorder read model |
| `vitalserver-vm runtime vitaldb-beds [--guest-control-url <url>]` | read the Guest-owned VitalDB bed read model |
| `vitalserver-vm runtime vitaldb-relationships [--guest-control-url <url>]` | read the Guest-owned VitalDB relationship history read model |

## Product Lab

Runtime Lab is the product-facing boundary for virtual recorder scenarios and `.vital` replay. It replaces the idea that sample playback belongs to a dev-only TestKit API. The Host-facing API calls Guest Control `/runtime/lab/*`, and Guest Control may mediate simulator/TestKit internals as product implementation details without exposing them as Runtime Control API routes.

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/runtime/lab/scenarios` | list product lab scenarios available for virtual recorder sessions |
| `GET` | `/runtime/lab/beds` | list Product Lab bed read model |
| `GET` | `/runtime/lab/recorders` | list Product Lab recorder read model with execution send state |
| `GET` | `/runtime/lab/sessions` | list persisted Product Lab sessions so a client can discover sessions it did not create locally |
| `POST` | `/runtime/lab/sessions` | create a Product Lab virtual recorder session |
| `GET` | `/runtime/lab/sessions/{sessionId}` | read one Product Lab session state |
| `POST` | `/runtime/lab/sessions/{sessionId}/start` | start one Product Lab session |
| `POST` | `/runtime/lab/sessions/{sessionId}/stop` | pause one Product Lab session without finalizing archives |
| `POST` | `/runtime/lab/sessions/{sessionId}/finish` | finish one Product Lab session and request durable `.vital` archive upload |
| `POST` | `/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start` | start one recorder owned by a running session |
| `POST` | `/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop` | stop one recorder owned by a running session |
| `GET` | `/runtime/lab/vital-files` | list VitalServer-indexed `.vital` files available for Product Lab replay |
| `POST` | `/runtime/lab/vital-files/replay` | create a virtual recorder session from a configured `.vital` file path |
| `POST` | `/runtime/lab/vital-files/upload` | upload N Host-selected `.vital` files through VitalServer API and verify their file-list index entries |
| `GET` | `/runtime/vitaldb/recorders/{vrcode}/vital-files` | lazily read native Recorder uploads and cold-path recovery artifacts attributed to one Recorder; Product Lab files are excluded |

`RuntimeLabScenarioList.state`, `RuntimeLabSessionList.state`, `RuntimeLabSessionResponse.state`, and `RuntimeLabRecorderResponse.state` preserve `loaded`, `failed`, and `unavailable` as different meanings. The API must not convert a missing Lab backend, Product Lab HTTP failure, or invalid Lab response into an empty scenario/session list or a successful stopped session. Recorder commands require an explicitly running session and a recorder whose `sessionId` matches the path session; the UI must not infer either relationship from labels or IDs. Command-style Lab requests also preserve the Guest operation id when Guest Control accepts the command.

The common Lab presentation is split into three explicit areas on Swift and PWA clients: `New scenario session`, persisted `Sessions`, and `Selected session`. Creating a session refreshes the collection and selects the returned session. The selected session owns whole-session Start/Stop controls and its filtered recorder rows own per-recorder Start/Stop controls. An unavailable or failed collection remains visible as a read state and must not be replaced with a locally remembered session.

The runtime CLI exposes the same Product Lab boundary for local automation and field diagnostics. CLI commands call Guest Control API and print the returned contract JSON; they do not inspect Lab files, TestKit files, or container internals directly.

| Command | 계약 |
|---|---|
| `vitalserver-vm runtime lab-scenarios [--guest-control-url <url>]` | list Product Lab scenarios |
| `vitalserver-vm runtime lab-beds [--guest-control-url <url>]` | list Product Lab bed read model |
| `vitalserver-vm runtime lab-recorders [--guest-control-url <url>]` | list Product Lab recorder read model with execution send state |
| `vitalserver-vm runtime lab-session-create <scenario-id> [--name <name>] [--recorder-count <count>] [--target-url <url>] [--guest-control-url <url>]` | create a virtual recorder session |
| `vitalserver-vm runtime lab-session-get <session-id> [--guest-control-url <url>]` | read one Lab session |
| `vitalserver-vm runtime lab-session-start <session-id> [--guest-control-url <url>]` | start one Lab session |
| `vitalserver-vm runtime lab-session-stop <session-id> [--guest-control-url <url>]` | stop one Lab session |
| `vitalserver-vm runtime lab-vital-replay <vital-file-path> [--session-name <name>] [--target-url <url>] [--guest-control-url <url>]` | create a `.vital` replay session |

## Status Vocabulary

Runtime Control API는 wire payload에서 `runtimeInstallationState`, `runtimeState`, `operation`, HTTP probe status처럼 도메인별 raw 값을 그대로 전달합니다. SwiftUI/PWA 표시 계층은 이 raw 값을 그대로 노출하지 않고 shared presentation vocabulary로 변환합니다. `runtimeInstalled`는 호환/display hint로만 남으며 설치 상태의 source of truth가 아닙니다.

| UI label | Source of truth | Display vocabulary |
|---|---|---|
| Runtime installation | `RuntimeStatus.runtimeInstallationState` | `Executable`, `Present but not executable`, `Missing`, `Inspect failed`, `Unknown` |
| Runtime state | `RuntimeStatus.runtimeState` | `Installing`, `Initializing`, `Updating`, `Recovering`, `Healthy`, `Degraded`, `Critical`, `Unknown` |
| VM/proxy/watchdog/guest log sync/sleep prevention service | launchd loaded flags | `Running`, `Stopped` |
| VitalServer/Network access | explicit HTTP probe fields where the platform provides them | `Reachable`, `Unreachable`, `Waiting` |
| Redis UI/Swagger UI | Runtime product service resource and observed stack state | service resource/stack vocabulary; no separate inferred probe row |
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

`GET /runtime/events`는 Runtime Controller가 소유한 product operation 이력을 반환합니다. 각 event는 `operationId`, `operationService`, `operationCommand`, `operationState`와 explicit nullable `failure`를 포함합니다. Host JSONL·SQLite event store는 이 API의 source나 fallback이 아닙니다.

| Query | Meaning |
|---|---|
| `limit` | 반환할 event 수. 1-500, 기본 100 |
| `type` | `operation-accepted`, `operation-running`, `operation-completed`, `operation-failed`, `operation-cancelled`, `operation-interrupted` 중 하나 |
| `since` | explicit `Z` 또는 numeric UTC offset을 포함한 ISO-8601 timestamp lower bound. timezone 없는 값은 `400` |
| `cursor` | 이전 응답의 `nextCursor` 값을 그대로 전달하는 opaque pagination cursor |

Runtime Controller는 query를 Guest-local SQLite control ledger의 immutable operation-event 기록에 전달합니다. Cursor는 opaque string으로만 노출하며 client는 해석하지 않습니다. `nextCursor`와 `matchingCount`는 값이 없을 때도 JSON `null`로 명시됩니다. 응답의 `matchingCount`는 provider가 계산하지 못한 경우 `null`이지 `0`이 아닙니다. `nextCursor`가 있거나 `matchingCount`가 `null`이면 client는 현재 page 수를 전체 수로 표시하면 안 됩니다. Guest ledger dependency를 읽을 수 없으면 endpoint는 Guest의 failure message와 `guestControlUnavailable` code를 보존한 `503`을 반환하며 Host JSONL·SQLite diagnostics를 fallback으로 사용하지 않습니다. Controller restart로 결과를 알 수 없어진 명령은 `operation-interrupted` event와 `controllerRestarted` failure로 남습니다.

`GET /runtime/status/stream`은 long-lived SSE 연결입니다. 서버는 연결을 유지하고 runtime status가 바뀔 때 `runtime-status` frame을 보냅니다. 각 frame의 `id` 값은 `runtime-status`, `data` 값은 JSON encoded `RuntimeStatus`입니다. 변경이 없으면 heartbeat comment를 보냅니다.

`RuntimeStatus.dataDirectoryStats`는 configured Vital files directory의 visible regular file count와 recursive size를 제공합니다. UI는 이를 Data directory path 옆의 보조 정보로 표시하며, volume-level capacity 정보는 기존 `dataStorage`를 계속 사용합니다.

PWA는 Platform과 product 상태를 하나의 Host aggregate에서 읽지 않습니다. `/platform`, `/runtime/stack`, `/runtime/settings`, `/runtime/vitaldb/*`를 독립적으로 읽고 화면에서만 조합합니다. `/runtime/overview`와 `/runtime/overview/stream`은 v2에서 제거했습니다.

`GET /platform/logs/stream`은 long-lived SSE 연결입니다. 서버는 선택한 host log text가 바뀔 때 `runtime-log` frame을 보냅니다. 각 frame의 `id` 값은 `runtime-log-<source>`, `data` 값은 JSON encoded `RuntimeLogTextResponse`입니다. Query는 `source`, `lineLimit`, `helperMessage`를 지원합니다. `source=helperMessage`는 현재 UI message 값을 재전송하지 않고 host의 append-only `tirosh-vitalserver-helper-message.log`를 읽습니다. `/platform/logs/read` body는 `source`, `helperMessage`, `lineLimit`를 모두 보내야 하며 legacy helper message 값이 없으면 `helperMessage: null`을 보냅니다. field absence와 explicit null/empty string은 다른 request state로 보존합니다.

`GET /runtime/vitaldb/observations/latest`는 최신 `RuntimeVitalDBObservationSnapshot`을 반환하는 Runtime Control API 표면입니다. 응답은 `state`, `observation`, `readError` 세 필드를 항상 포함하며 nullable 값도 생략하지 않고 JSON `null`로 전달합니다. v2 TO-BE에서는 이 read가 Host 파일이나 Host SQLite projection에서 오지 않고 Guest/Product API의 `GET /runtime/vitaldb/observations/latest`를 소비해야 합니다. Guest endpoint는 `state`, `observation`, `readError`를 보존하며, default Guest composition은 `PostgresVitalDBReadModelRepository`를 통해 `vitaldb_observation_snapshots` JSONB read model을 읽습니다. Guest `tirosh-runtime-observation` writer는 VitalDB Observer의 explicit observation document를 수집한 뒤 이 Postgres read model에 저장합니다. Read model adapter가 없거나 table이 비어 있으면 빈 성공이나 inferred empty observation 대신 `state=unavailable`, `observation=null`을 반환합니다. Host `runtime-observability.sqlite` projection은 명시 diagnostics/migration mode에서만 읽을 수 있으며, guest `runtime-observation.json`이나 Host `runtime-status.json`의 embedded current observation은 product read source로 사용하지 않습니다.

`GET /runtime/vitaldb/observations/stream`은 long-lived SSE 연결입니다. 서버는 최신 VitalDB observation snapshot이 바뀔 때 `vitaldb-observed` frame을 보냅니다. 각 frame은 `RuntimeVitalDBObservationSnapshot.state`, `observation`, `readError`를 그대로 보존하므로 unavailable과 failed를 `null` observation으로 축소하지 않습니다.

`GET /platform/operations`는 operation 상태 전용 read model입니다. API owner가 `activeOperation`을 확정해서 제공하며, clients는 install/lease/status 하위 필드를 다시 조합해 active operation을 추론하지 않습니다. 이 read는 `RuntimeStatus`를 입력으로 받거나 먼저 읽지 않습니다. Install operation state는 `RuntimeStatus`가 아니라 operation-state owner의 `install.state=loaded|unavailable|failed`로 노출해, UI가 missing document와 failed read를 `nil` 값으로 추론하지 않게 합니다. `loaded`만 install state document를 포함하고, `failed`는 `readError`를 보존합니다. `unavailable`은 읽을 문서가 없거나 아직 operation state owner가 제공한 상태가 없다는 의미이며 empty/success로 해석하면 안 됩니다. Install state document는 install detail artifact이고 active operation owner가 아닙니다. `activeOperation`은 explicit operation lease/API owner가 제공한 operation에서만 나와야 합니다.

같은 resource의 `lease`는 Platform operation owner가 제공한 lease 상태를 `lease.state=loaded|unavailable|failed|stale`로 노출합니다. macOS 구현은 Host `runtime-state.sqlite.runtime_operation_lease` repository를 CLI workflow와 Runtime Control API가 함께 사용합니다. API의 `RuntimeControlOperationLeaseController`는 이 repository를 read/mutation resource로 노출할 뿐, UI process memory가 owner가 아닙니다. Runtime Control read path는 `PlatformOperationStateResourceReading`과 read-only `RuntimeOperationLeaseReading` contract만 소비합니다. missing lease는 `unavailable`, owner read failure는 `failed`, `expiresAt`이 현재 Platform 시각보다 과거인 lease는 `stale`입니다. `stale`은 stale lease row와 `staleReason`을 함께 보존하며, UI는 stale lease를 active operation success나 empty state로 바꾸면 안 됩니다.

Platform operation lease mutation은 Platform affordance API로 분리합니다. `POST /platform/operations/lease/acquire`, `POST /platform/operations/lease/heartbeat`, `POST /platform/operations/lease/release`는 durable operation owner에 위임하는 API입니다. 이 API는 product status를 조립하지 않고 active operation ownership의 mutation boundary만 제공합니다. CLI workflow는 같은 owner repository를 직접 사용하므로 headless install/update가 UI나 HTTP listener의 선행 실행에 의존하지 않습니다. API read/mutation과 CLI workflow 사이의 동시성은 SQLite immediate transaction, revision guard, WAL, bounded busy timeout으로 보호합니다.

Runtime endpoint도 Platform affordance API owner로 승격합니다. `GET /platform/runtime-endpoint`는 `loaded|missing|unavailable|failed`를 구분하는 `RuntimeGuestAddressResourceState`를 반환하고, `PUT /platform/runtime-endpoint`는 명시적인 address를 owner mutation boundary에 기록합니다. macOS 구현은 `runtime-state.sqlite.runtime_endpoint`를 durable owner로 사용하고 `RuntimeControlGuestAddressController`는 같은 repository를 API로 노출합니다. Host proxy는 bootstrap `vm-ip` evidence를 읽어 SQLite owner에 transaction으로 publish한 뒤 직접 HTTP readiness를 검증합니다. lifecycle/status/command consumers는 `SQLiteRuntimeGuestAddressResourceStore` 또는 API resource를 읽으며 UI listener가 없어도 동작합니다. endpoint JSON, `runtime-status.json`, `runtime-observation.json`은 current endpoint owner가 아닙니다.

Runtime Provider lifecycle도 Platform owner resource로 승격합니다. `GET /platform/runtime-provider`은 `loaded|missing|unavailable|failed`를 구분하는 resource state를 반환하고, `PUT /platform/runtime-provider`은 명시적인 lifecycle document를 mutation boundary에 기록합니다. macOS에서는 VM launcher가 API 서버보다 먼저 시작될 수 있으므로 `runtime-state.sqlite.vm_lifecycle`과 `SQLiteRuntimeVMLifecycleResourceStore`가 durable state를 소유합니다. Launcher, delegate, watchdog과 stop workflow는 이 repository port에 직접 쓰고, `RuntimeControlVMLifecycleController`와 API는 같은 repository를 읽고 씁니다. 따라서 UI/API process가 실행되지 않은 installed boot에서도 provider가 자신의 state를 게시할 수 있으며 API 재시작 뒤에도 state가 사라지지 않습니다. `runtime-status.json`은 fallback source가 아니고, SQLite row missing, invalid field, open/integrity/read failure는 각각 explicit resource state로 남습니다. Golden-rootfs 빌드 VM의 별도 compile-proof lifecycle 파일은 installed runtime owner와 다른 빌드 계약입니다.

Provider `start|stop|restart` command는 Platform effect와 Provider state를 합치지 않습니다. macOS는 launchd service command, Windows는 SCM, Linux는 systemd D-Bus를 사용하고 command 응답은 effect의 `completed|failed`와 당시 Provider lifecycle resource를 별도 필드로 반환합니다. service-manager command가 완료돼도 lifecycle을 `running`으로 만들지 않으며 실제 Provider가 기록한 문서만 표시합니다. 해당 Platform control 자체가 없거나 launcher가 실행 불가하면 `501`을 반환하고, preflight·effect·lifecycle read 실패는 원인과 resource state를 보존한 typed `failed` 응답으로 `503`을 반환합니다. nullable wire field는 생략하지 않고 JSON `null`로 보냅니다.

`GET /runtime/vitaldb/recorders`는 `vrcode` 기준으로 집계한 `RuntimeVitalRecorderHistory`를 반환합니다. `vrcode`는 recorder identity key이며, IP는 마지막 관측 주소일 뿐 identity로 쓰지 않습니다. Live v2 path는 Guest/Product API의 `GET /runtime/vitaldb/recorders`와 `GET /runtime/vitaldb/beds`를 우선 소비하며, Guest read가 unavailable/failed이면 Host SQLite observation snapshot을 recorder/bed product state로 읽거나 승격하지 않습니다. Guest endpoint는 `state`, `recorders`, `observedAt`, `ready`, `recorderOnlineThresholdSeconds`, `readError`를 보존하며, default Guest composition은 `PostgresVitalDBReadModelRepository`를 통해 최신 `vitaldb_observation_snapshots` JSONB read model의 `recorders` 배열과 observation metadata를 읽습니다. Empty `recorders`는 loaded empty collection이고, adapter 없음, empty table, dependency failure, malformed collection은 다른 read state로 보존해야 합니다. Host는 `ready`나 recorder stale threshold를 추정하지 않고 Guest가 제공한 값을 사용합니다. Guest VitalDB read model provider가 구성되지 않았거나 읽을 수 없으면 recorder history는 explicit read failure/unavailable state를 보존해야 하며, `/runtime/vitaldb/observations/latest`, guest `runtime-observation.json`, Host `runtime-status.json`, Host SQLite projection을 recorder/bed fallback으로 사용하지 않습니다. Recorder-ingress status는 explicit diagnostics/counter read로 보존할 수 있지만, ingress-only recorder를 product recorder로 생성하거나 Guest/Postgres가 제공한 recorder online/stale/lastSeen/IP state를 덮어쓰면 안 됩니다. `activityTimeline`은 snapshot history에서 vrcode별 `recorders[].activity`를 시간순으로 모은 recorder activity point list입니다. 각 point는 해당 시각의 message count, byte count, room count를 담아 활동 차트를 그리기 위한 값입니다. `activityHistory.source`는 `readModelProjection`, `unavailable`, `notProvided` 중 하나입니다. `readModelProjection`의 empty timeline은 Guest/Postgres read model projection을 읽었지만 해당 recorder activity가 없었다는 뜻이고, `notProvided`는 caller가 activity projection을 제공하지 않은 construction path입니다. `readError`가 있으면 Guest read 또는 activity projection read가 실패해 `recorders`, `beds`, `activityHistory`가 incomplete일 수 있습니다. 이 상태는 관측된 recorder가 없다는 의미와 구분해야 합니다.

`GET /runtime/vitaldb/recorders/{vrcode}`는 같은 history read model에서 특정 `vrcode`의 recorder record 하나를 반환합니다. 관측 이력이 없으면 `null`을 반환합니다.

`GET /runtime/vitaldb/recorders/{vrcode}/activity`는 recorder activity chart용 lazy window read model입니다. Query는 `bucketSeconds=60|300`, `period=last15Minutes|lastHour|last6Hours|last12Hours|all`, `pageIndex=<non-negative integer>`를 지원합니다. `period=all`일 때 page 하나는 12시간이며, `pageIndex`가 없으면 최신 page를 반환합니다. Runtime v2 server는 Guest Control API의 `GET /runtime/vitaldb/recorders/{vrcode}/activity`를 소비하고, Guest/Postgres read model에서 해당 `vrcode`의 first/latest bucket boundary와 선택된 window의 `since/until` 범위만 조회합니다. Host SQLite projection은 Guest provider가 없는 transitional diagnostics path일 뿐 product state owner가 아닙니다. UI는 응답의 `page.count`, `page.index`, `page.windowStartedAt`, `page.windowEndedAt`, `buckets`만 표시하고 전체 history gap을 브라우저나 SwiftUI 메모리에서 materialize하면 안 됩니다.

`POST /runtime/vitaldb/recorders/{vrcode}/observability/expectation`은 운영자
control plane의 명시적 command 경로입니다. Runtime Control은 body의 `vrcode`가
path와 같은지 확인한 뒤 Guest Control로 전달하고, Guest는 별도 내부 bearer
credential로 recorder-ingress를 호출합니다. recorder-ingress가
`expectation_events` journal과 current projection을 revision compare-and-set으로
갱신합니다. 응답의 `accepted`, `idempotent`, `revisionConflict`, `rejected`는
각각 200, 200, 409, 422로 보존됩니다. Guest, credential, PostgreSQL 실패는
503이며 disabled나 성공으로 바꾸지 않습니다.

`RuntimeVitalRecorderActivityWindow.state`는 `loaded`, `empty`, `invalidRequest`, `readFailed` 중 하나입니다. `empty`는 read가 성공했지만 해당 recorder/window에 activity bucket이 없다는 뜻이며, `readFailed`와 구분해야 합니다. `invalidRequest`는 query contract 위반입니다. Missing bucket은 선택된 window 안에서만 zero-count display bucket으로 채울 수 있고, window 밖의 missing history를 activity state로 추정하지 않습니다.

`GET /runtime/vitaldb/beds`는 `bedID` 기준으로 집계한 `RuntimeVitalBedRecord` 배열을 반환합니다. Bed 탭/PWA는 recorder history payload에 포함된 `beds` 필드에 의존하지 않고 이 route를 우선 사용합니다. Live v2 path는 Guest/Product API의 `GET /runtime/vitaldb/beds`를 우선 소비하며, Guest read가 unavailable/failed이면 Host SQLite observation snapshot을 bed product state로 승격하지 않습니다. Guest endpoint는 `state`, `beds`, `observedAt`, `ready`, `recorderOnlineThresholdSeconds`, `readError`를 보존하며, loaded empty beds와 read-model unavailable/failed/invalid 상태를 구분합니다. Host는 recorder read와 bed read의 metadata가 일치할 때만 하나의 current observation으로 조립하고, 불일치하면 explicit read issue로 남깁니다. `GET /runtime/vitaldb/beds/{bedID}`는 특정 bed record 하나를 반환하고, 관측 이력이 없으면 `null`을 반환합니다.

`GET /runtime/vitaldb/relationships`는 bed/VRecorder assignment와 relationship event history를 반환합니다. Live v2 path는 Guest/Product API의 `GET /runtime/vitaldb/relationships`를 소비하며, Host SQLite relationship projection을 product state로 승격하지 않습니다. Guest endpoint는 `state`, `assignments`, 최신순 `events`, `eventTotalCount`, `eventLimit`, `readError`를 보존하고, default Guest composition은 `PostgresVitalDBReadModelRepository`를 통해 `vitaldb_relationship_history_snapshots` JSONB read model을 읽습니다. Guest `tirosh-runtime-observation` writer는 최신 VitalDB observation의 explicit bed-vrcode 관계와 이전 Guest/Postgres relationship snapshot을 domain policy에 넘겨 다음 relationship history snapshot을 저장합니다. Projection document v2는 현재 지속 중인 relationship issue를 `activeIssueIDs`로 명시적으로 소유합니다. `duplicateAssignment`, `unlinkedBed`, `unlinkedRecorder`, `staleLink`는 매 observation의 상태 sample이 아니라 issue 발생 전이에서만 event로 추가되고, 해소 후 같은 issue가 재발하면 새 event가 됩니다. `handoff`는 assignment 전이 자체이므로 발생할 때마다 기록합니다. 기존 projectionVersion 없는 문서는 첫 v2 projection에서 반복 condition event를 issue identity별 첫 발생 한 건으로 축약하는 explicit migration을 거칩니다. Guest API의 `eventLimit` 기본값은 100이고 허용 범위는 1...500이며, 전체 건수는 `eventTotalCount`로 별도 보고합니다. Empty previous history는 schema가 존재하고 snapshot row가 없을 때의 초기 상태일 뿐이며, invalid previous document나 dependency failure는 성공으로 변환하지 않습니다. Observer read issue가 있으면 `partiallyLoaded`와 explicit `readError`로 보존합니다. Read model adapter가 없거나 table이 비어 있으면 empty success 대신 `state=unavailable`과 explicit `readError`를 반환합니다. Transitional projection tests can still exercise the SQLite relationship assembler directly, but live Runtime Control consumers should treat Guest/Postgres as the relationship owner. `readError`가 있으면 assignment/history read가 실패했거나 부분 로드된 상태이며, empty `assignments`/`events`를 정상적인 무관측 상태로 해석하면 안 됩니다.

`distribution.profile`이 `dev`인 build에서는 macOS Helper가 실행 중일 때 `http://127.0.0.1:18321/dev/runtime-control`에서 브라우저용 Runtime Control API console을 열 수 있습니다. Stable build는 local API server는 유지하되 이 dev console route는 제공하지 않습니다. 이 화면은 product PWA가 아니라 API 동작 확인용 loopback dev tool이며, owner별 snapshot과 Platform/VitalDB/log stream을 같은 origin에서 호출합니다.

## Route Scope

`RuntimeControlAPI`는 route를 두 scope로 나눕니다.

| Scope | Prefix | 의미 | PWA에서의 해석 |
|---|---|---|---|
| `runtimeControl` | `/runtime/*`, `/runtime/vitaldb/*` | local/remote runtime control usecase | PWA가 우선 의존할 API surface |
| `platformAffordance` | `/host/*` | local file/log/update-bundle affordance | browser가 직접 수행하지 않고 native shell 또는 server endpoint로 재배치 |

## Runtime Routes

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/runtime/capabilities` | capability negotiation |
| `GET` | `/runtime/status` | runtime status read model |
| `GET` | `/runtime/status/stream` | SSE runtime status snapshot subscription |
| `GET` | `/platform/operations` | explicit runtime operation state read model |
| `GET` | `/runtime/stack` | Runtime Controller product service stack status |
| `GET` | `/runtime/services` | Guest product service list through Guest Control API |
| `GET` | `/runtime/services/{service}/status` | Guest product service status through Guest Control API |
| `GET` | `/runtime/redis-relay/status` | Guest/Postgres-owned Redis Relay status read result |
| `POST` | `/runtime/services/{service}/start` | Guest product service start through Guest Control API |
| `POST` | `/runtime/services/{service}/stop` | Guest product service stop through Guest Control API |
| `POST` | `/runtime/services/{service}/restart` | Guest product service restart through Guest Control API |
| `GET` | `/runtime/events` | Guest Runtime Controller operation event history |
| `GET` | `/runtime/vitaldb/observations/latest` | latest VitalDB recorder/bed/anomaly observation snapshot |
| `GET` | `/runtime/vitaldb/observations/stream` | SSE VitalDB observation snapshot subscription |
| `GET` | `/runtime/vitaldb/recorders` | VRecorder history aggregated by vrcode |
| `GET` | `/runtime/vitaldb/recorders/{vrcode}` | one VRecorder history record by vrcode |
| `GET` | `/runtime/vitaldb/recorders/{vrcode}/activity` | lazy VRecorder activity chart window |
| `GET` | `/runtime/vitaldb/beds` | bed history aggregated by bedID |
| `GET` | `/runtime/vitaldb/beds/{bedID}` | one bed history record by bedID |
| `GET` | `/runtime/vitaldb/relationships` | Guest/Postgres-owned VRecorder-bed assignment and relationship event history |
| `GET` | `/runtime/lab/scenarios` | Product Lab scenario list |
| `GET` | `/runtime/lab/beds` | Product Lab bed read model |
| `GET` | `/runtime/lab/recorders` | Product Lab recorder read model |
| `GET` | `/runtime/lab/sessions` | persisted Product Lab session list |
| `POST` | `/runtime/lab/sessions` | create Product Lab virtual recorder session |
| `GET` | `/runtime/lab/sessions/{sessionId}` | Product Lab session state |
| `POST` | `/runtime/lab/sessions/{sessionId}/start` | start Product Lab session |
| `POST` | `/runtime/lab/sessions/{sessionId}/stop` | pause Product Lab session without finalizing archives |
| `POST` | `/runtime/lab/sessions/{sessionId}/finish` | terminally finish Product Lab session and upload finalized archives |
| `POST` | `/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start` | start one session-owned recorder |
| `POST` | `/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop` | stop one session-owned recorder |
| `GET` | `/runtime/lab/vital-files` | VitalServer-indexed `.vital` files available for Product Lab replay |
| `POST` | `/runtime/lab/vital-files/replay` | create Product Lab `.vital` replay session |
| `POST` | `/runtime/lab/vital-files/upload` | prevalidate repeated multipart `files`, upload each through VitalServer `/upload`, and verify `/api/filelist`; report partial completion explicitly |
| `POST` | `/runtime/health` | active health refresh |
| `GET` | `/runtime/settings` | current runtime settings |
| `PUT` | `/runtime/settings` | apply runtime settings |
| `POST` | `/runtime/admin-password` | replace the Runtime administrator password without exposing a read contract |
| `GET` | `/platform/settings` | read Platform Agent-owned Host resources, network, filesystem, boot, recovery, backup, and log-retention settings without exposing Runtime credentials |
| `PUT` | `/platform/settings` | apply the mutable Host settings through the Platform Agent; a failed/incomplete current owner read blocks apply |
| `GET` | `/platform/release` | helper/release/component metadata |
| `GET` | `/platform/installation` | installed runtime paths and install metadata |
| `GET` | `/runtime/stack` | read the Runtime Controller-owned service stack status |
| `GET` | `/runtime/services` | list Guest-owned compose services |
| `GET` | `/runtime/services/{service}/status` | read one Guest-owned service status through Guest Control API |
| `GET` | `/runtime/redis-relay/status` | read Redis Relay status directly from the Runtime owner resource without `RuntimeStatus` aggregation |
| `GET` | `/runtime/redis-relay/settings` | read Runtime-owned Relay settings with only `passwordConfigured` secret state |
| `PUT` | `/runtime/redis-relay/settings` | preserve, replace, or explicitly clear the Relay secret and reconcile Compose |
| `POST` | `/runtime/services/{service}/start` | start one Guest-owned service through Guest Control API |
| `POST` | `/runtime/services/{service}/stop` | stop one Guest-owned service through Guest Control API |
| `POST` | `/runtime/services/{service}/restart` | restart one Guest-owned service through Guest Control API |
| `POST` | `/platform/services/repair` | macOS platform-maintenance extension for VM, guest-log-sync, host-proxy, and watchdog repair; not a common PWA action |
| `POST` | `/platform/proxy/repair` | macOS platform-maintenance extension for host proxy repair; not a common PWA action |
| `POST` | `/runtime/maintenance/datastore/repair` | request Guest-owned datastore repair; returns `202 Accepted` with a persisted `RuntimeGuestControlServiceOperation` |
| `POST` | `/platform/runtime-provider/disk/repair` | macOS platform-maintenance extension that archives and recreates the mutable VM disk; not a common PWA action |
| `POST` | `/platform/backups/redis` | create advanced Redis-only repair backup |
| `POST` | `/platform/backups/runtime-data` | create user-facing VitalServer backup containing Host runtime state and Redis data |
| `POST` | `/platform/uninstall` | uninstall runtime |

## Host Affordance Routes

| Method | Path | 계약 |
|---|---|---|
| `GET` | `/platform/backups` | list local backups |
| `GET` | `/platform/backups/redis` | list local Redis-only repair backups |
| `POST` | `/platform/backups/redis/restore` | restore selected Redis-only repair backup |
| `GET` | `/platform/backups/runtime-data` | list local VitalServer backups |
| `POST` | `/platform/backups/runtime-data/restore` | restore selected VitalServer backup |
| `POST` | `/platform/logs/read` | read selected log text |
| `GET` | `/platform/logs/stream` | SSE host log text snapshot subscription |
| `POST` | `/platform/logs/export` | export local logs |
| `POST` | `/platform/update-bundles/summary` | inspect selected update bundle |
| `POST` | `/platform/update-bundles/verify` | verify selected update bundle |
| `POST` | `/platform/update-bundles/apply` | apply selected update bundle |
| `POST` | `/platform/operations/lease/acquire` | acquire Host operation lease through `RuntimeOperationLeaseOwner` |
| `POST` | `/platform/operations/lease/heartbeat` | heartbeat Host operation lease through `RuntimeOperationLeaseOwner` |
| `POST` | `/platform/operations/lease/release` | release Host operation lease through `RuntimeOperationLeaseOwner` |
| `GET` | `/platform/runtime-endpoint` | read Host Guest address resource state |
| `PUT` | `/platform/runtime-endpoint` | update Host Guest address resource through owner mutation boundary |
| `GET` | `/platform/runtime-provider` | read Host VM lifecycle resource state |
| `PUT` | `/platform/runtime-provider` | update Host VM lifecycle resource through owner mutation boundary |
| `POST` | `/platform/runtime-provider/start` | request Runtime Provider service start and return effect plus lifecycle separately |
| `POST` | `/platform/runtime-provider/stop` | request Runtime Provider service stop and return effect plus lifecycle separately |
| `POST` | `/platform/runtime-provider/restart` | request ordered Provider stop/start without inferring readiness |
| `POST` | `/platform/backups/rollback` | rollback selected backup |
| `DELETE` | `/platform/backups` | delete selected backup |

Host backup list routes must preserve filesystem read state. A missing managed
backup directory, permission failure, path inspection failure, or unexpected
path state is not an empty backup list; it must surface as a typed host
affordance read failure. An empty list is reserved for a readable managed
backup directory that contains no matching backup artifacts.

### Common PWA maintenance boundary

The common PWA does not expose the macOS-only proxy-repair or VM-disk-repair
routes above. They are optional platform-maintenance extensions, not a portable
Runtime Controller contract; a future Windows or Linux implementation may use
a different native workflow or omit the extension entirely. `localServerMediated`
means that a supported platform UI can ask its local server to perform an
explicit privileged action. It does not make every mediated route a common PWA
control.

Datastore repair is different: its execution and operation state are owned by
the Guest Runtime Controller. If `GET /runtime/capabilities` advertises
`maintenance:datastore-repair:create`, the PWA may call
`POST /runtime/maintenance/datastore/repair` and must handle the `202`
persisted Guest operation, including an explicit failed state. If the capability
is absent, the PWA shows the action as unavailable and makes no speculative
request. Runtime Provider restart remains the portable Platform lifecycle
action when the corresponding Platform capability permits it.

## Client Access Classification

`RuntimeControlAPIEndpoint`는 scope와 별도로 client access를 갖습니다. OpenAPI의 `x-runtime-control-access` 값은 Swift enum과 parity test로 검증합니다.

| Access | 의미 | 현재 route |
|---|---|---|
| `browserSafe` | 브라우저/PWA가 local Runtime Control server에 직접 호출 가능한 read-only runtime control | `GET /platform`, `GET /platform/stream`, `GET /runtime/capabilities`, `GET /platform/operations`, `GET /runtime/stack`, `GET /runtime/services`, `GET /runtime/services/{service}/status`, `GET /runtime/events`, `GET /runtime/vitaldb/observations/latest`, `GET /runtime/vitaldb/observations/stream`, `GET /runtime/vitaldb/recorders`, `GET /runtime/vitaldb/recorders/{vrcode}`, `GET /runtime/vitaldb/recorders/{vrcode}/activity`, `GET /runtime/vitaldb/beds`, `GET /runtime/vitaldb/beds/{bedID}`, `GET /runtime/vitaldb/relationships`, `GET /runtime/lab/scenarios`, `GET /runtime/lab/beds`, `GET /runtime/lab/recorders`, `GET /runtime/lab/sessions`, `GET /runtime/lab/sessions/{sessionId}`, `GET /runtime/lab/vital-files`, `POST /platform/health`, `GET /runtime/settings`, `GET /platform/settings`, `GET /platform/release`, `GET /platform/installation` |
| `localServerMediated` | 브라우저가 직접 host resource를 만지지 않고 local server가 권한/파일/프로세스 작업을 중재해야 함 | runtime write/admin routes, `PUT /platform/settings`, Product Lab session commands, Product Lab `replay` and `upload`, Redis backup create/list/restore, backups list/delete/rollback, log read/stream, update bundle summary/verify/apply |
| `nativeShellOnly` | 브라우저 endpoint만으로는 UX나 보안 경계가 충분하지 않아 native shell mediation이 필요함 | `POST /platform/logs/export` |

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
