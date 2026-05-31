# 032 macOS runtime 코드의 상태/관측 책임이 섞임

> ID: TS-032
> Category: Runtime health / Observability / Update
> Owner: macOS runtime
> Status: resolved

## Review Scope

2026-05-30 기준으로 `apps/vitalserver-macos-runtime/Sources` 전체 Swift target을 레이어별로 다시 검토했습니다.

검토 기준:

- `rg --files apps/vitalserver-macos-runtime/Sources -g '*.swift'`로 전체 Swift 파일 목록을 확정했습니다.
- `find ... wc -l` 기준으로 8개 target, 234개 Swift 파일, 34,748라인을 검토 범위로 잡았습니다.
- 모든 target에 대해 import graph, port protocol, optional/non-throwing read API, status/event/projection/query path, UI/API boundary 책임을 스캔했습니다.
- 고위험 파일은 라인 단위로 추가 확인했습니다. 특히 `RuntimeStatusWriter`, `RuntimeStatusReader`, `SQLiteRuntimeObservabilityStore`, `CompositeRuntimeEventRepository`, `RuntimeControlHTTPBoundary`, `MacRuntimeControlAPIHandler`, `RuntimeViewModel`, `RuntimeControlReadModels`, `RuntimeGuestGateway`, `RuntimeEventRepository`, `RuntimeStatusRepository`를 확인했습니다.

검토한 경계:

- `Contracts`: 25 files, 3,833 lines. Runtime/Guest/Update/VitalDB document/query contract
- `Core`: 30 files, 1,820 lines. update, health, guest operation evaluator, port protocol
- `HostInfrastructure`: 14 files, 2,293 lines. JSON/SQLite/file-system backed repository
- `HostCLI`: 78 files, 8,327 lines. install/update/rollback/repair/watchdog/runtime orchestration
- `MacHostRuntimeAdapter`: 16 files, 3,262 lines. Swift UI/API가 호출하는 host read/write adapter
- `RuntimeControl`: 7 files, 1,849 lines. Remote Console/Swift UI용 read model과 client contract
- `RuntimeControlAPI`: 9 files, 3,507 lines. HTTP boundary, request parsing, SSE
- `MacRuntimeControlApp`: 55 files, 9,826 lines. Swift UI composition, ViewModel, presentation policy

좋은 점:

- `Package.swift`의 기본 의존성 방향은 대체로 맞습니다. `Core`는 infrastructure를 직접 알지 않고, host 구현은 adapter/CLI 쪽에 있습니다.
- update, rollback, repair는 step executor/runner/use case 형태로 분리되어 테스트가 있습니다.
- guest result document는 `missing | loaded | failed`를 구분하는 방향으로 개선되어 있습니다.
- Runtime event, status, VitalDB observation contract가 typed document로 정리되어 있습니다.
- 최근 작업으로 상태 추정과 UI fallback 상당 부분이 제거되어 있습니다.

아직 남은 핵심 문제는 “레이어 역방향”보다 “역할 혼합”입니다. 특히 status, event, SQLite projection, read model, UI orchestration이 몇몇 타입 안에서 겹칩니다.

## File Classification

전체 파일은 target별로 확인했고, 조치가 필요한 파일은 아래처럼 분류합니다.

| Target | Files | Classification | Priority |
| --- | ---: | --- | --- |
| `Contracts` | 25 | Document/query contract 중심입니다. unknown enum/value 보존은 외부 contract 호환 목적이면 허용됩니다. 현재 구조적 조치 대상은 아닙니다. | Monitor |
| `Core/Application`, `Core/Guest`, `Core/Health` | 21 | 대부분 pure policy/evaluator입니다. 의존성 방향과 테스트 가능성은 좋습니다. | Monitor |
| `Core/Ports/RuntimeStatusRepository.swift` | 1 | `loadResult()`로 missing/read failure/loaded를 contract에 보존합니다. | Done |
| `Core/Ports/RuntimeEventRepository.swift` | 1 | `RuntimeEventRecording`을 write-only port로 분리하고 `RuntimeEventHistoryReading.query()`는 `RuntimeEventPage.readError`로 read failure를 contract에 보존합니다. `recent(limit:)`는 Core port contract에서 제거되어 concrete legacy/test convenience로만 남아 있습니다. | Done |
| `Core/Ports/RuntimeGuestGateway.swift` | 1 | optional convenience API를 제거하고 명시 result API만 남겼습니다. | Done |
| `Core/Ports/RuntimeStorageUsageProvider.swift` | 1 | `RuntimeStorageUsageResult`로 unavailable과 read failure를 구분합니다. | Done |
| `Core/Ports` remaining files | 5 | command/file/timing/http/service port입니다. 현재 구조적 조치 대상은 아닙니다. | Monitor |
| `RuntimeControl/RuntimeControlReadModels.swift` | 1 | recorder activity history는 explicit bucket projection이 있을 때만 생성됩니다. | Done |
| `RuntimeControl` remaining files | 6 | cursor codec, client contract, readiness/test model 중심입니다. 현재 구조적 조치 대상은 아닙니다. | Monitor |
| `HostInfrastructure/SQLiteRuntimeObservabilityStore.swift` | 1 | VitalDB consumer는 `SQLiteVitalDBObservationRepository` facade를 통해 read/write하고, event consumer는 `SQLiteRuntimeEventRepository`를 통해 접근합니다. relationship anomaly 판단은 `VitalDBRelationshipProjectionPlanner`로 분리했습니다. 저수준 SQLite prepare/bind/step helper는 `SQLiteRuntimeObservabilityDatabase`로 분리했고, store에는 SQLite state가 필요한 assignment/handoff projection만 남겼습니다. | Done |
| `HostInfrastructure/CompositeRuntimeEventRepository.swift` | 1 | query-time JSONL→SQLite catchup/rebuild를 제거했습니다. SQLite projection catchup은 `RuntimeEventSQLiteProjectionCatchUp`이 명시적으로 수행합니다. SQLite query unavailable 시 JSONL primary fallback은 TS-033 범위로 남겼습니다. | Done |
| `HostInfrastructure/JSONLRuntimeEventRepository.swift` | 1 | `query(_:)`는 parse/read issue를 `RuntimeEventPage.readError`로 보존합니다. Failure를 숨기던 `all()` convenience는 제거했고, bulk read consumer는 `allResult()`를 명시적으로 사용합니다. | Done |
| `HostInfrastructure/JSONFileRuntimeStatusRepository.swift` | 1 | `RuntimeStatusRepository.loadResult()` 구현으로 optional contract 노출을 제거했습니다. | Done |
| `HostInfrastructure` remaining files | 10 | path/file/storage 구현과 SQLite facade/helper입니다. 현재 큰 방향 문제는 없습니다. | Monitor |
| `MacHostRuntimeAdapter/RuntimeStatusReader.swift` | 1 | status document, guest state, live diagnostics assembly를 status/health status reader에 한정하고 event/VitalDB read는 `SystemRuntimeObservabilityReader`로 분리했습니다. | Done |
| `MacHostRuntimeAdapter/MacHostRuntimeClient.swift`, `MacHostRuntimeReadWorker.swift` | 2 | status reader와 observability reader를 별도 collaborator로 보유합니다. | Done |
| `MacHostRuntimeAdapter/Testing/MacTestKitController.swift` | 1 | TestKit API endpoint source를 configuration으로 명시하고 controller는 configured source를 resolve합니다. | Done |
| `MacHostRuntimeAdapter` remaining files | 11 | command/log/export/settings/path adapter입니다. export/log collector는 명시 source list가 있어 현재 방향과 맞습니다. | Monitor |
| `HostCLI/RuntimeStatusWriter.swift` | 1 | status document write만 수행하고 VitalDB projection은 `RuntimeVitalDBObservationProjector`가 담당합니다. | Done |
| `HostCLI/RuntimeLifecycle+Support.swift` | 1 | event document 조립/recording helper를 `RuntimeEventPublisher`로 분리했고 status write 후 observation projection은 `RuntimeObservedStatusPublisher`가 담당합니다. Lifecycle support는 collaborator 구성과 workflow-facing helper에 집중합니다. | Done |
| `HostCLI/RuntimeLifecycle+Workflows.swift` | 1 | observed event previous-status lookup과 event type policy를 `RuntimeObservedEventPublisher`로 분리했습니다. workflow composition의 status/progress writer, guest run directory, VM service, request id, polling sleep 반복은 named helper action으로 축소했습니다. | Done |
| `HostCLI/RuntimeHealthChecker.swift` | 1 | guest runtime state document read와 freshness 판정을 `RuntimeGuestRuntimeStateObservationReader`로 분리했습니다. Health checker는 fresh state만 health input에 사용하고 missing/read failure/stale 의미를 유지합니다. | Done |
| `HostCLI/RuntimeApplyBundleRunner.swift`, `RuntimeApplyBundleStepExecutor.swift`, `RuntimeBundleWorkflow.swift`, `RuntimeWorkflowStatusReporter.swift` | 4 | apply bundle runner의 status/progress publish와 best-effort logging을 `RuntimeWorkflowStatusReporter`로 분리했습니다. Bundle workflow는 named reporter를 주입하고, step executor는 step dispatch/payload 작업에 집중합니다. | Done |
| `HostCLI` remaining files | 64 | CLI/VM/config/service/repair/rollback/log utility입니다. 현재 핵심 조치 대상은 status/projection/update orchestration 주변에 집중되어 있습니다. | Monitor |
| `RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift` | 1 | overview read model 합성은 `RuntimeControlOverviewAssembler`로 분리했고 boundary는 route/query/response에 집중합니다. | Done |
| `RuntimeControlAPI/Boundary/RuntimeControlClientAPIReadHandler.swift` | 1 | API read handler contract가 `RuntimeVitalDBObservationSnapshot`을 반환하도록 변경했습니다. `/vitaldb/observations/latest`의 기존 document/null payload는 유지하되, overview에는 loaded/unavailable/failed와 readError metadata가 남습니다. | Done |
| `RuntimeControlAPI` remaining files | 6 | endpoint routing, wire codec, local server, dev console입니다. 현재 큰 방향 문제는 없습니다. | Monitor |
| `MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModel.swift` | 1 | snapshot source 선택, command action runner, observability refresh query/count/relationship orchestration, status/health refresh presentation 적용을 named helper로 분리했습니다. ViewModel은 사용자 intent, published state 적용, notification transition에 집중합니다. | Done |
| `MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModel+UpdateBundle.swift`, `RuntimeViewModelUpdateBundleVerifier.swift` | 2 | update bundle 검증 command result 포맷팅과 성공/실패 presentation 결정을 named verifier로 분리했습니다. extension은 selection/apply intent와 published state 반영에 집중합니다. | Done |
| `MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModel+Backups.swift`, `RuntimeViewModelBackupActionPlanner.swift` | 2 | rollback/delete backup의 selected path/root validation과 command action plan 생성을 named planner로 분리했습니다. extension은 권한 guard, command 실행, refresh transition에 집중합니다. | Done |
| `MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModel+Testing.swift`, `RuntimeViewModelTestKitStatePolicy.swift` | 2 | TestKit 시작/중지 가능 여부, selected/available bed 계산, 입력값 normalize, start request 생성을 named policy로 분리했습니다. extension은 사용자 action flow와 published state transition에 집중합니다. | Done |
| `MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModel+Navigation.swift`, `RuntimeViewModelNavigationCoordinator.swift` | 2 | 폴더 존재/생성/open과 URL resolution을 named coordinator로 분리했습니다. extension은 capability guard와 사용자 intent method에 집중합니다. | Done |
| `MacRuntimeControlApp/Presentation/ViewModels/*` remaining extensions | 1 | Logs/Export logs 권한 fallback은 TS-033에서 해결한 범위라 이번 TS-032 진행에서는 제외합니다. | Monitor |
| `MacRuntimeControlApp/Composition/MacRuntimeControlAPIHandler.swift`, `RuntimeControlStatusAnnotator.swift` | 2 | `Core` 직접 import는 제거했고, local Runtime Control server의 HTTP/startedAt status annotation을 named annotator로 분리했습니다. Handler는 API read/command delegation과 local settings side effect에 집중합니다. | Done |
| `MacRuntimeControlApp/Composition/AppConstants.swift`, `AppActionText.swift`, `AppPrimitiveConstants.swift`, `RuntimeSettingsLimits.swift`, `RuntimeServiceVersionConstants.swift` | 5 | settings limit, service version, action text, primitive/notification constants를 named extension 파일로 분리했습니다. `AppConstants.swift`는 product/label/status presentation text 중심으로 축소했습니다. | Done |
| `MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`, `RuntimeRecorderActivityChart.swift` | 2 | recorder activity chart rendering과 bucket aggregation을 `RuntimeRecorderActivityChart`/`RuntimeRecorderActivityChartDataBuilder`로 분리했습니다. Panel은 header/list/detail composition과 사용자 선택 state에 집중합니다. | Done |
| `MacRuntimeControlApp` remaining files | 36 | presentation view/policy/native shell/composition/helper입니다. UI 계층의 `Core` 직접 의존 제거 이후 다시 확인합니다. | Monitor |

## Symptoms

macOS runtime 코드에서 상태, 이벤트, 관측 projection, UI/API read model의 책임이 일부 겹쳐 있습니다.

대표 증상:

- 상태를 쓰는 코드가 관측 데이터를 SQLite에 projection합니다.
- recorder history read model이 SQLite bucket projection이 없을 때 snapshot rolling activity를 history처럼 재사용할 수 있습니다.
- SQLite observability read 실패가 빈 배열로 바뀌는 public API가 남아 있습니다.
- recorder activity bucket 조회가 `VitalDBRecorderActivityBucketQuery`로 `vrcode`, `since`, `until`, `limit` 의도를 명시합니다.
- 상태 owner가 제공한 값과 consumer가 편의상 만든 값의 경계가 파일 단위로 바로 드러나지 않습니다.
- status read path가 `RuntimeStatusDocument`와 launchd live scan을 한 모델에 합칩니다.
- guest document gateway가 `missing`, `loaded`, `failed`를 제공하지만 convenience optional API가 다시 failure를 `nil`로 접습니다.
- Swift UI `RuntimeViewModel`이 상태 저장, command orchestration, polling, presentation message 갱신을 크게 함께 들고 있습니다.
- runtime event 조회가 SQLite query 전에 JSONL catchup을 수행하고, 실패하면 조회 경로 안에서 SQLite event index rebuild까지 시도합니다.
- `Core`의 repository/reader port 일부가 optional 또는 non-throwing read API라서 구현체가 read failure를 명시적으로 전달하기 어렵습니다.
- Runtime Control API boundary가 overview를 만들면서 `RuntimeStatus`에 `VitalDBObservation`을 다시 덮어씁니다.
- Swift UI target의 presentation/composition 코드가 `Core`를 직접 import합니다. 현재 동작상 문제는 아니지만 UI 계층이 domain port까지 직접 알고 있어 책임 경계가 흐려집니다.
- 일부 테스트가 현재 fallback 동작을 기대값으로 고정하고 있어, 명시적 계약으로 바꾸려면 테스트 의도도 함께 바꿔야 합니다.

## Impact

코드가 실행될 때는 동작해도 운영 장애 분석과 후속 기능 변경이 어려워집니다.

- 상태 기록 실패, 관측 projection 실패, 데이터 부재가 같은 화면 증상으로 보일 수 있습니다.
- update/watchdog/status 경로에 작은 조건이 계속 붙고, 방어로직이 분산됩니다.
- Remote Console과 Swift UI가 같은 domain concept을 서로 다른 방식으로 해석할 위험이 커집니다.
- 테스트가 “현재 구현 흐름”을 고정하고, “명시적 domain contract”를 검증하지 못할 수 있습니다.

## Cause

상태와 관측 데이터의 lifecycle이 충분히 분리되지 않았습니다.

현재 확인된 문제 패턴:

```text
status writer
  -> builds health snapshot
  -> writes RuntimeStatusDocument
  -> also projects VitalDB observation into SQLite
```

이 구조에서는 `RuntimeStatusWriter`가 status writer인지 observability projector인지 역할이 흐려집니다.

```text
RuntimeVitalRecorderHistory(observations:)
  -> activityBuckets == nil
  -> includeSnapshotActivity = true
  -> rolling activity snapshot becomes history
```

이 구조에서는 최신 rolling activity와 durable history의 경계가 생성자 overload에 숨어 있습니다.

```text
SQLiteRuntimeObservabilityStore.vitalDBRecorderActivityBuckets()
  -> try? load...
  -> [] on failure
```

이 구조에서는 “데이터가 없음”과 “읽기에 실패함”이 같은 값이 됩니다.

```text
SystemRuntimeStatusReader.loadBaseStatus()
  -> reads RuntimeStatusDocument
  -> falls back to launchdLoaded(...)
  -> returns one RuntimeStatus
```

이 구조에서는 status document가 제공한 상태와 Host가 즉시 관측한 service state가 같은 source처럼 보입니다.

```text
RuntimeGuestGateway.loadRuntimeStateDocument()
  -> missing | loaded | failed
RuntimeGuestGateway.loadRuntimeState()
  -> Document?
```

이 구조에서는 명시 result API를 만들어놓고도 consumer가 convenience optional API를 쓰면 read/decode failure가 다시 사라질 수 있습니다.

```text
RuntimeStatusRepository.load()
  -> RuntimeStatusDocument?

RuntimeEventHistoryReading.query()
  -> RuntimeEventPage
```

이 구조에서는 read failure를 port contract에서 표현하기 어려웠습니다. 현재 `RuntimeEventHistoryReading.query()`는 `RuntimeEventPage.readError`로 read issue를 전달하고, Runtime Control read model의 `RuntimeEventHistory.readError`까지 보존합니다. `recent(limit:)`와 일부 best-effort convenience는 write-side/legacy 경로에만 남아 있습니다.

수정 전 구조:

```text
CompositeRuntimeEventRepository.query()
  -> catchUpSecondaryIndexIfDue()
  -> primary JSONL all()
  -> secondary SQLite upsert()
  -> on failure, rebuild secondary index
  -> secondary query()
```

이 구조에서는 read path가 write path와 repair path를 수행했습니다. 현재는 `RuntimeEventSQLiteProjectionCatchUp`이 SQLite projection catchup/rebuild를 명시적으로 담당하고, repository query는 SQLite read와 TS-033 범위의 JSONL fallback만 수행합니다.

```text
RuntimeControlHTTPBoundary.makeOverview()
  -> loadStatus()
  -> loadVitalDBObservation()
  -> status.vitalDBObservation = vitalDBObservation ?? status.vitalDBObservation
```

이 구조에서는 API boundary가 transport/request boundary를 넘어 read model 합성 책임까지 수행합니다. overview assembler가 필요합니다.

```text
MacRuntimeControlApp
  -> RuntimeViewModel imports Core
  -> MacRuntimeControlAPIHandler imports Core
```

이 구조는 dependency 방향을 즉시 깨지는 않지만, UI/application composition이 domain port와 policy를 직접 참조하게 만듭니다. UI는 `RuntimeControl` read model과 `MacHostRuntimeAdapter` use case facade를 보는 쪽이 더 명시적입니다.

테스트에서도 같은 흐름이 고정되어 있습니다.

```text
RuntimeControlContractsTests.testVitalRecorderHistoryAggregatesByVrcode
  -> RuntimeVitalRecorderHistory(observations:)
  -> expects snapshot activity timeline

SQLiteRuntimeObservabilityStoreTests.testCompositeRepositoryRebuildsSQLiteIndexFromJSONLWhenDatabaseIsCorrupt
  -> query/recent triggers catchup and rebuild
```

이 테스트들은 나쁜 테스트가 아니라, 지금 구조가 실제로 그렇게 동작한다는 증거입니다. 다만 목표 원칙으로 가려면 기대값을 “fallback 유지”가 아니라 “명시 projection/use case”로 바꿔야 합니다.

## Checks

Swift runtime에서 같은 성격의 코드를 찾습니다.

```sh
rg -n "projectVitalDBObservation|activityBuckets == nil|includeSnapshotActivity" apps/vitalserver-macos-runtime/Sources
rg -n "try\\?.*loadVitalDB|\\?\\? \\[\\]|return \\[\\]" apps/vitalserver-macos-runtime/Sources/HostInfrastructure apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter
rg -n "loadBaseStatus\\(\\)|launchdLoaded\\(|ProcessRunner\\.run" apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter
rg -n "loadRuntimeState\\(\\)|loadBootstrapResult\\(\\)|loadUpdateActivationResult\\(\\)|loadUpdateShutdownResult\\(\\)|loadDatastoreRepairResult\\(\\)" apps/vitalserver-macos-runtime/Sources
rg -n "func load\\(\\) -> .*\\?|func query\\(_ query: RuntimeEventQuery\\) -> RuntimeEventPage|func recent\\(limit: Int\\) -> \\[RuntimeEventDocument\\]" apps/vitalserver-macos-runtime/Sources/Core apps/vitalserver-macos-runtime/Sources/HostInfrastructure
rg -n "@Published var|runClientAction|load.*Snapshot|try\\? await Task\\.sleep" apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/ViewModels
rg -n "catchUpSecondaryIndexIfDue|rebuild\\(from: primaryEvents\\)|func query\\(_ query: RuntimeEventQuery\\)" apps/vitalserver-macos-runtime/Sources/HostInfrastructure
rg -n "status\\.vitalDBObservation|makeOverview\\(|import Core" apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp
rg -n "RuntimeVitalRecorderHistory\\(observations:|RebuildsSQLiteIndexFromJSONL|CatchesUpSQLiteFromJSONL" apps/vitalserver-macos-runtime/Tests
rg -n "fallback|Fallback|legacy|Legacy|unknown|Unknown" apps/vitalserver-macos-runtime/Sources
```

레이어 방향은 `Package.swift`와 import graph로 확인합니다.

```sh
sed -n '1,220p' apps/vitalserver-macos-runtime/Package.swift
rg -n "import (HostInfrastructure|MacHostRuntimeAdapter|HostCLI|RuntimeControlAPI|MacRuntimeControlApp|Core|Contracts|RuntimeControl)" apps/vitalserver-macos-runtime/Sources
```

## Actions

수정 방향:

1. Status writer는 status document만 씁니다.
2. VitalDB observation projection은 별도 projector/use case가 명시적으로 수행합니다.
3. Recorder activity history는 SQLite bucket projection만 사용합니다. Snapshot rolling activity fallback은 제거하거나 이름으로 위험을 드러냅니다.
4. SQLite observability read API는 throwing API를 기본으로 사용합니다. Best-effort reader는 public domain read path에서 제거합니다.
5. Activity bucket 조회는 `vrcode`, `since`, `until`, `limit`을 명시한 query object를 사용합니다.
6. Host/UI consumer는 누락, invalid, read failure를 서로 다른 값으로 유지합니다.
7. `loadBaseStatus`는 status document reader와 live diagnostics reader를 분리합니다.
8. `RuntimeGuestGateway`의 optional convenience API는 제거하거나 진단/테스트 외부에서 쓰지 못하게 합니다.
9. Swift UI `RuntimeViewModel`은 화면 state holder와 use case orchestration을 분리합니다.
10. Runtime event JSONL→SQLite catchup은 query path에서 분리해 explicit projection/catchup use case로 이동합니다.
11. fallback 동작을 고정한 테스트는 명시 contract 테스트로 바꿉니다.
12. Core read port는 `nil`/`[]`로 실패를 접지 말고 result 또는 throwing contract를 제공합니다.
13. Runtime Control overview 합성은 HTTP boundary 밖의 named assembler/use case로 이동합니다.
14. `MacRuntimeControlApp` presentation 계층의 `Core` 직접 import를 제거하고, adapter/read model facade를 통해 의존성을 고정합니다.

우선순위:

1. `RuntimeStatusWriter`에서 VitalDB projection 제거
   - 새 타입: `RuntimeVitalDBObservationProjector`
   - 호출 위치: watchdog/health/status workflow에서 status write와 별도 단계로 명시
   - 테스트: status writer가 status만 쓰는지, projector 실패가 status write 성공/실패와 섞이지 않는지 검증

2. `RuntimeVitalRecorderHistory(observations:)` fallback 제거
   - recorder/bed 상태 요약과 activity history 생성 책임을 분리
   - activity history는 `activityBuckets` 없는 생성 경로에서 빈 값 또는 unavailable로 유지
   - 테스트: snapshot activity가 history로 승격되지 않음을 검증

3. SQLite observability read API 정리
   - `vitalDBObservations`, `vitalDBRecorderActivityBuckets`, `vitalDBBedAssignments`, `vitalDBRelationshipEvents`의 best-effort public API 제거 또는 `bestEffort...`로 격하
   - production read path는 throwing API만 사용
   - read failure는 API response metadata에 남김

4. Runtime event catchup 분리
   - `CompositeRuntimeEventRepository.query()`에서 catchup/rebuild 제거
   - 명시 use case: `RuntimeEventSQLiteProjectionCatchUp`
   - query는 SQLite read만 수행하고, SQLite query unavailable 시 JSONL primary fallback은 TS-033 권한 fallback 범위로 유지

5. `SystemRuntimeStatusReader` 분리
   - `RuntimeStatusDocumentReader`: document만 읽음
   - `RuntimeLiveDiagnosticsReader`: launchd/curl/data directory 같은 live diagnostics만 읽음
   - `RuntimeStatusAssembler`: 둘을 명시 source로 합성

6. `RuntimeViewModel` 다이어트
   - command flow/polling/use case orchestration을 coordinator로 분리
   - ViewModel은 화면 state와 사용자 intent delegation만 유지

7. Core read port contract 정리
   - `RuntimeStatusRepository.load() -> RuntimeStatusDocument?`를 `loadResult()` 또는 throwing API로 변경
   - `RuntimeEventHistoryReading.query()`는 `RuntimeEventPage.readError`로 read failure를 표현
   - infrastructure의 best-effort 동작은 이름에 `BestEffort`를 붙여 운영성 없는 경로로 격리

8. Runtime Control API overview assembler 분리
   - `RuntimeControlHTTPBoundary`는 route, query parsing, response encoding만 담당
   - status와 VitalDB observation의 합성 정책은 `RuntimeControlOverviewAssembler` 같은 named type으로 이동

9. UI target dependency 정리
   - `RuntimeViewModel`이 `Core`를 직접 import하지 않도록 필요한 query/value type을 `RuntimeControl` 또는 adapter facade로 이동
   - `MacRuntimeControlAPIHandler`도 API handler 역할만 남기고 Core 세부 type 의존은 handler input/output contract로 제한

## Prevention

새 코드 리뷰 기준:

- Writer 이름을 가진 타입은 다른 projection/write side effect를 갖지 않습니다.
- `init` overload가 domain meaning을 바꾸면 안 됩니다.
- `[]`, `nil`, `"Unknown"`은 표시 값일 수 있지만 read failure의 대체값이면 안 됩니다.
- Query API는 consumer가 원하는 범위와 owner를 명시합니다.
- Snapshot, event, status, projection은 서로 다른 lifecycle입니다. 하나의 lifecycle 실패가 다른 lifecycle 성공처럼 숨으면 안 됩니다.
- Convenience API가 명시 result type의 의미를 지우면 제거합니다.
- Port contract는 read failure를 표현할 수 있어야 합니다. 구현체에서 `nil`/`[]`로 실패를 숨기는 구조는 만들지 않습니다.
- ViewModel은 UI state와 command flow를 모두 소유하지 않습니다. 반복되는 command/polling 흐름은 named coordinator/use case로 분리합니다.
- Read path는 projection catchup/rebuild를 수행하지 않습니다. Projection은 명시적인 writer/catchup 책임으로 둡니다.
- HTTP boundary는 request/response boundary입니다. Read model 합성 정책은 named assembler/use case가 담당합니다.
- UI target은 domain policy/port를 직접 보지 않습니다. UI는 presentation model과 application facade를 통해 domain 의미를 읽습니다.
- 테스트명은 구현 수단보다 domain contract를 말해야 합니다. “query가 rebuild한다”보다 “projection catchup use case가 SQLite index를 회복한다”가 맞습니다.

## Related Cases

- `TS-030`: Runtime 상태를 Host/UI가 추정하거나 암묵 보정함
- `TS-031`: Recorder activity 그래프가 rolling window만 표시함

## Follow-up

- 2026-05-30: Swift runtime 리뷰에서 `RuntimeStatusWriter`가 status write와 VitalDB observation projection을 함께 수행하는 구조를 확인했습니다.
- 2026-05-30: `RuntimeVitalRecorderHistory(observations:)`가 SQLite projection 없이 snapshot rolling activity를 history로 사용할 수 있는 fallback 경로를 확인했습니다.
- 2026-05-30: `SQLiteRuntimeObservabilityStore`에 throwing read API와 별도로 failure를 `[]`로 숨기는 public best-effort reader가 남아 있음을 확인했습니다.
- 2026-05-30: recorder activity bucket 조회가 explicit query 없이 generic `limit` 기반으로 동작하는 것을 확인했습니다.
- 2026-05-30: `SystemRuntimeStatusReader.loadBaseStatus`가 status document 값과 launchd live scan 값을 같은 `RuntimeStatus`로 합치는 구조를 확인했습니다.
- 2026-05-30: `RuntimeGuestGateway`의 `loadRuntimeState()` 등 optional convenience API가 `missing`과 `failed`를 다시 합칠 수 있음을 확인했습니다.
- 2026-05-30: `RuntimeViewModel`이 다수의 `@Published` state, command 실행, polling, status/event/recorder refresh orchestration을 한 타입에서 처리하는 구조를 확인했습니다.
- 2026-05-30: `CompositeRuntimeEventRepository.query()`가 read path에서 SQLite event index catchup/rebuild를 수행하는 구조를 확인했습니다.
- 2026-05-30: 테스트 중 일부가 snapshot activity fallback과 query-triggered SQLite rebuild를 현재 기대 동작으로 고정하고 있음을 확인했습니다.
- 2026-05-30: 전체 Swift source 범위를 8개 target, 206개 파일, 33,450라인으로 확정하고 target별 import graph와 상태/이벤트/관측/query 경로를 재검토했습니다.
- 2026-05-30: `RuntimeStatusRepository.load()`와 `RuntimeEventHistoryReading.query()` 같은 Core read port가 read failure를 contract로 표현하지 못하는 구조를 확인했습니다.
- 2026-05-30: `RuntimeControlHTTPBoundary.makeOverview()`가 status와 VitalDB observation을 직접 합성하며 boundary 책임을 넘어서는 구조를 확인했습니다.
- 2026-05-30: `MacRuntimeControlApp`의 ViewModel/API handler가 `Core`를 직접 import해 UI/application composition의 의존성 경계가 느슨해진 것을 확인했습니다.
- 2026-05-30: `RuntimeStatusWriter`에서 VitalDB SQLite projection side effect를 제거하고 `RuntimeVitalDBObservationProjector`로 분리했습니다. Status write는 status document만 쓰고, lifecycle이 반환된 snapshot의 observation projection을 명시적으로 호출합니다.
- 2026-05-30: `RuntimeVitalRecorderHistory(observations:)`가 snapshot rolling activity를 history timeline으로 승격하지 않도록 수정했습니다. Recorder activity timeline은 SQLite projection bucket이 명시적으로 전달될 때만 채웁니다.
- 2026-05-30: `SQLiteRuntimeObservabilityStore`의 VitalDB read API를 throwing `load...` 중심으로 정리하고, 실패를 숨기는 호출은 `bestEffort...` 이름으로만 남겼습니다.
- 2026-05-30: `SystemRuntimeStatusReader.loadBaseStatus()` 내부의 status document read, guest state read, launchd live diagnostics, base status assembly를 private reader/diagnostics/assembler 타입으로 분리했습니다.
- 2026-05-30: Runtime Control overview 합성을 `RuntimeControlOverviewAssembler`로 분리하고, HTTP boundary는 route/stream response에서 assembler를 호출하도록 정리했습니다.
- 2026-05-30: `RuntimeStatusRepository` Core port에서 optional `load()`를 제거하고 `loadResult()`를 contract로 승격했습니다. `RuntimeStatusReporter.writeProgress`와 watchdog active operation guard가 missing과 read failure를 구분합니다.
- 2026-05-30: `RuntimeGuestGateway`의 optional convenience API를 제거하고 document result API만 남겼습니다. `RuntimeHealthChecker`는 guest runtime state read failure를 `guestRuntimeStateInvalid`로 보존합니다.
- 2026-05-30: `RuntimeEventQuery`, `RuntimeEventCursor`, `RuntimeEventPage`를 `Core` port 파일에서 `Contracts`로 이동했습니다. `RuntimeControl`, `RuntimeControlAPI`, `MacRuntimeControlApp` source target의 `Core` 직접 import와 RuntimeControl/RuntimeControlAPI target의 `Core` dependency를 제거했습니다.
- 2026-05-30: `RuntimeViewModelSnapshotLoader`를 추가해 ViewModel 내부의 readWorker/controlClient/localAPISettings snapshot source 선택 책임을 분리했습니다. ViewModel은 refresh orchestration과 화면 state update만 수행하고, snapshot read source fallback은 named loader가 담당합니다.
- 2026-05-30: `RuntimeStorageUsageProviding.storageUsage`를 optional `ResourceUsage?`에서 `RuntimeStorageUsageResult`로 변경했습니다. `SystemRuntimeStatusReader`는 storage usage read failure를 `RuntimeStatus.dataStorageError`에 보존하고, 성공 시 error를 지웁니다.
- 2026-05-30: `MacTestKitControllerConfiguration`에 `MacTestKitAPIEndpointSource`를 추가했습니다. TestKit API endpoint는 explicit URL 또는 runtime status VM IP source 중 하나로 선언되며, controller는 endpoint source와 health check를 주입받아 상태 조회와 API reachability 확인을 분리합니다.
- 2026-05-30: `RuntimeViewModelCommandActionRunner`를 추가해 command action 실행, busy/message 전환, command log refresh, operation progress polling, process result formatting을 ViewModel 밖으로 분리했습니다. ViewModel은 사용자 intent와 presentation state sink 역할로 축소됩니다.
- 2026-05-30: `VitalDBRecorderActivityBucketQuery`를 추가해 recorder activity bucket 조회에서 recorder owner와 time range, limit을 SQL predicate로 명시했습니다. 기존 generic `limit` 중심 조회보다 projection read 의도가 드러납니다.
- 2026-05-30: `RuntimeVitalRelationshipHistory.readError`를 추가하고 `SystemRuntimeObservabilityReader.loadVitalDBRelationships()`가 assignment/event projection read 실패를 빈 relationship 목록으로만 숨기지 않도록 변경했습니다. Recorders/Beds relationship 패널도 read issue를 표시합니다.
- 2026-05-30: `RuntimeStatusReading`에서 event/VitalDB 관측 read API를 분리해 `RuntimeObservabilityReading`을 추가했습니다. `MacHostRuntimeClient`와 `MacHostRuntimeReadWorker`는 status reader와 observability reader를 별도 collaborator로 보유합니다.
- 2026-05-30: `SystemRuntimeObservabilityReader`로 runtime event/VitalDB projection read 구현을 분리했습니다. `SystemRuntimeStatusReader`는 status/health status 구성만 담당하고, facade/read worker는 두 reader를 각각 주입받습니다.
- 2026-05-30: `RuntimeEventFactory`를 추가해 lifecycle support가 `RuntimeEventDocument` 필드를 직접 조립하지 않도록 했습니다. `RuntimeObservedStatusPublisher`도 추가해 status write 후 VitalDB observation projection 정책을 named collaborator로 분리했습니다.
- 2026-05-30: `RuntimeObservedEventPublisher`와 `RuntimeObservedEventTypePolicy`를 추가했습니다. `RuntimeLifecycle+Workflows`는 더 이상 observed event의 previous status 조회나 VM/domain event type 판정을 직접 수행하지 않습니다.
- 2026-05-30: `RuntimeEventSQLiteProjectionCatchUp`을 추가하고 `CompositeRuntimeEventRepository.query()`에서 JSONL→SQLite catchup/rebuild side effect를 제거했습니다. 기존 query-triggered rebuild 테스트는 explicit projection catchup contract 테스트로 변경했습니다.
- 2026-05-30: `RuntimeViewModelObservabilityRefresher`를 추가해 runtime event query/count/container observation 선택과 VitalDB recorder/relationship refresh orchestration을 ViewModel 밖으로 분리했습니다. ViewModel은 refresh 결과를 화면 state에 적용하는 쪽으로 축소했습니다.
- 2026-05-30: `RuntimeEventPage.readError`와 `RuntimeEventHistory.readError`를 추가해 SQLite/JSONL runtime event read issue를 빈 이벤트 목록이나 `matchingCount == nil` sentinel로만 숨기지 않도록 했습니다. JSONL fallback은 TS-033 범위로 유지하되, fallback 발생 원인은 UI/API read model에 보존됩니다.
- 2026-05-30: `SQLiteVitalDBObservationRepository`를 추가해 VitalDB observation snapshot/activity/relationship consumer가 `SQLiteRuntimeObservabilityStore`를 직접 잡지 않도록 했습니다. event path는 `SQLiteRuntimeEventRepository`, VitalDB path는 새 repository facade로 분리됩니다.
- 2026-05-30: `VitalDBRelationshipProjectionPlanner`를 추가해 unlinked bed/recorder, duplicate assignment, stale link 같은 현재 observation 기반 relationship anomaly 판단을 SQLite SQL writer 밖으로 분리했습니다. 기존 assignment/handoff projection은 SQLite state가 필요해 store에 남겼습니다.
- 2026-05-30: `RuntimeObservationRecorder`가 `RuntimeEventRepository` 전체가 아니라 write-only `RuntimeEventRecording` port에만 의존하도록 축소했습니다. `RuntimeEventRepository` protocol에서도 failure를 숨기는 `recent(limit:)` convenience를 제거해 event recording path와 query/read path를 분리했습니다.
- 2026-05-30: `RuntimeGuestRuntimeStateObservationReader`를 추가해 guest runtime state document load result와 freshness 판정을 `RuntimeHealthChecker.snapshot()` 밖으로 분리했습니다. Health checker는 reader가 제공하는 loaded/fresh/present/failure metadata를 health input에 조립합니다.
- 2026-05-30: `JSONLRuntimeEventRepository.all()`을 제거했습니다. JSONL bulk read가 필요한 projection/test path는 `allResult()`를 사용해 parse/read issue를 명시적으로 확인합니다.
- 2026-05-30: `RuntimeEventPublisher`를 추가해 observed/status-document/document/command/progress/lifecycle event 생성과 recording을 lifecycle support 밖으로 분리했습니다. `RuntimeLifecycle+Support`는 event publisher를 구성하고 workflow-facing 호출만 위임합니다.
- 2026-05-30: `SQLiteRuntimeObservabilityDatabase`를 추가해 SQLite prepare/bind/step, scalar/count/row query helper를 `SQLiteRuntimeObservabilityStore` 밖으로 분리했습니다. Store는 runtime event/VitalDB query 조립과 SQLite state가 필요한 assignment/handoff projection 로직에 집중합니다.
- 2026-05-30: `RuntimeLifecycle+Workflows`의 반복 closure를 `runtimeStatusWriterAction`, `runtimeProgressWriterAction`, guest run directory/VM service/request id/polling sleep helper로 모았습니다. Workflow composition은 collaborator wiring과 workflow-specific action만 남기도록 축소했습니다.
- 2026-05-30: `RuntimeViewModelStatusRefresher`를 추가해 status/health snapshot load, status display message, file-backed update operation presentation, command operation detail 계산을 ViewModel 밖으로 분리했습니다. ViewModel은 refresh 결과를 published state에 적용하고 health notification transition만 호출합니다.
- 2026-05-30: `RuntimeViewModelUpdateBundleVerifier`를 추가해 update bundle 검증 command result의 성공/실패 presentation formatting을 ViewModel extension에서 분리했습니다. TS-033의 Logs/Export logs 권한 fallback 변경은 TS-032 진행 범위에서 제외했습니다.
- 2026-05-30: `RuntimeViewModelBackupActionPlanner`를 추가해 rollback/delete backup의 selected path, backups root, managed backup validation을 ViewModel extension에서 분리했습니다. Backups extension은 권한 guard, command 실행, 성공 후 refresh transition만 유지합니다.
- 2026-05-30: `RuntimeViewModelTestKitStatePolicy`를 추가해 TestKit start/stop/reset/delete 가능 여부와 bed selection, operator input normalization, start request 생성을 ViewModel extension에서 분리했습니다. Testing extension은 session action과 refresh transition만 유지합니다.
- 2026-05-30: `RuntimeViewModelNavigationCoordinator`를 추가해 폴더 생성/open과 web URL resolution을 ViewModel extension에서 분리했습니다. Navigation extension은 local capability guard와 사용자 intent delegation만 유지합니다.
- 2026-05-30: `RuntimeVitalDBObservationSnapshot`을 추가하고 `RuntimeControlAPIReadHandler`가 optional observation 대신 explicit read state를 반환하도록 변경했습니다. 기존 `/vitaldb/observations/latest` payload는 호환성을 유지하되, `/runtime/overview`는 `vitalDBObservationSnapshot.state/readError`로 unavailable과 failure를 구분합니다.
- 2026-05-30: `RuntimeControlStatusAnnotator`를 추가해 `MacRuntimeControlAPIHandler`의 remote console HTTP/startedAt status annotation을 분리했습니다. Handler는 local API read/command delegation과 settings 적용 side effect에 집중합니다.
- 2026-05-30: `RuntimeWorkflowStatusReporter`를 추가해 apply bundle workflow의 status/progress publish와 best-effort failure logging을 runner 밖으로 분리했습니다. `RuntimeApplyBundleRunner`는 update flow와 rollback decision에 집중하고, `RuntimeBundleWorkflow`는 reporter wiring만 담당합니다.
- 2026-05-30: `AppConstants`의 settings limit, service version, action text, primitive/notification 그룹을 별도 extension 파일로 분리했습니다. 거대한 constants 파일은 product/label/status text 중심으로 축소하고 domain별 상수 소유권을 드러냈습니다.
- 2026-05-30: `RuntimeRecorderActivityChart`와 `RuntimeRecorderActivityChartDataBuilder`를 추가해 recorder activity chart 렌더링과 bucket aggregation을 `RuntimeRecordersPanel` 밖으로 분리했습니다. Panel은 recorder list/detail 화면 조립에 집중합니다.
- 2026-05-30: latest VitalDB observation read path도 `RuntimeVitalDBObservationSnapshot`을 직접 반환하도록 변경했습니다. SQLite read failure가 optional `nil`로 접히지 않고 `.failed(readError:)`로 Runtime Control API까지 보존됩니다.
