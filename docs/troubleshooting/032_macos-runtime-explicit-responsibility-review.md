# 032 macOS runtime 코드의 상태/관측 책임이 섞임

> ID: TS-032
> Category: Runtime health / Observability / Update
> Owner: macOS runtime
> Status: active

## Review Scope

2026-05-30 기준으로 `apps/vitalserver-macos-runtime/Sources` 전체 Swift target을 레이어별로 다시 검토했습니다.

검토 기준:

- `rg --files apps/vitalserver-macos-runtime/Sources -g '*.swift'`로 전체 Swift 파일 목록을 확정했습니다.
- `find ... wc -l` 기준으로 8개 target, 206개 Swift 파일, 33,450라인을 검토 범위로 잡았습니다.
- 모든 target에 대해 import graph, port protocol, optional/non-throwing read API, status/event/projection/query path, UI/API boundary 책임을 스캔했습니다.
- 고위험 파일은 라인 단위로 추가 확인했습니다. 특히 `RuntimeStatusWriter`, `RuntimeStatusReader`, `SQLiteRuntimeObservabilityStore`, `CompositeRuntimeEventRepository`, `RuntimeControlHTTPBoundary`, `MacRuntimeControlAPIHandler`, `RuntimeViewModel`, `RuntimeControlReadModels`, `RuntimeGuestGateway`, `RuntimeEventRepository`, `RuntimeStatusRepository`를 확인했습니다.

검토한 경계:

- `Contracts`: 24 files, 3,764 lines. Runtime/Guest/Update/VitalDB document contract
- `Core`: 30 files, 1,887 lines. update, health, guest operation evaluator, port protocol
- `HostInfrastructure`: 10 files, 2,219 lines. JSON/SQLite/file-system backed repository
- `HostCLI`: 71 files, 7,939 lines. install/update/rollback/repair/watchdog/runtime orchestration
- `MacHostRuntimeAdapter`: 15 files, 3,050 lines. Swift UI/API가 호출하는 host read/write adapter
- `RuntimeControl`: 7 files, 1,807 lines. Remote Console/Swift UI용 read model과 client contract
- `RuntimeControlAPI`: 8 files, 3,497 lines. HTTP boundary, request parsing, SSE
- `MacRuntimeControlApp`: 41 files, 9,287 lines. Swift UI composition, ViewModel, presentation policy

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
| `Contracts` | 24 | Document contract 중심입니다. unknown enum/value 보존은 외부 contract 호환 목적이면 허용됩니다. 현재 구조적 조치 대상은 아닙니다. | Monitor |
| `Core/Application`, `Core/Guest`, `Core/Health` | 21 | 대부분 pure policy/evaluator입니다. 의존성 방향과 테스트 가능성은 좋습니다. | Monitor |
| `Core/Ports/RuntimeStatusRepository.swift` | 1 | `load() -> RuntimeStatusDocument?`가 missing과 read/decode failure를 접습니다. | P1 |
| `Core/Ports/RuntimeEventRepository.swift` | 1 | query/recent read failure를 contract로 표현하지 못합니다. | P1 |
| `Core/Ports/RuntimeGuestGateway.swift` | 1 | 명시 result API 옆에 optional convenience API가 남아 있습니다. | P1 |
| `Core/Ports/RuntimeStorageUsageProvider.swift` | 1 | `ResourceUsage?`가 not-found와 read failure를 구분하지 못합니다. 상태 핵심 경로보다는 낮은 우선순위입니다. | P3 |
| `Core/Ports` remaining files | 5 | command/file/timing/http/service port입니다. 현재 구조적 조치 대상은 아닙니다. | Monitor |
| `RuntimeControl/RuntimeControlReadModels.swift` | 1 | snapshot rolling activity가 history로 승격될 수 있습니다. | P1 |
| `RuntimeControl` remaining files | 6 | cursor codec, client contract, readiness/test model 중심입니다. 현재 구조적 조치 대상은 아닙니다. | Monitor |
| `HostInfrastructure/SQLiteRuntimeObservabilityStore.swift` | 1 | SQLite event index, VitalDB observation, recorder bucket, relationship projection이 한 타입에 집중되어 있습니다. 일부 public read API가 failure를 `[]`/`nil`로 숨깁니다. | P1 |
| `HostInfrastructure/CompositeRuntimeEventRepository.swift` | 1 | read path에서 JSONL→SQLite catchup/rebuild를 수행합니다. | P1 |
| `HostInfrastructure/JSONLRuntimeEventRepository.swift` | 1 | `all()`이 parse/read issue를 떨어뜨리고 event만 반환합니다. | P2 |
| `HostInfrastructure/JSONFileRuntimeStatusRepository.swift` | 1 | `loadResult()`는 좋지만 `RuntimeStatusRepository.load()` 구현이 optional contract를 계속 노출합니다. | P2 |
| `HostInfrastructure` remaining files | 6 | path/file/storage 구현입니다. 현재 큰 방향 문제는 없습니다. | Monitor |
| `MacHostRuntimeAdapter/RuntimeStatusReader.swift` | 1 | status document, launchd live diagnostics, event repository, VitalDB projection read를 함께 조립합니다. | P1 |
| `MacHostRuntimeAdapter/MacHostRuntimeClient.swift`, `MacHostRuntimeReadWorker.swift` | 2 | `RuntimeStatusReader`의 혼합 책임을 그대로 facade로 노출합니다. | P2 |
| `MacHostRuntimeAdapter/Testing/MacTestKitController.swift` | 1 | runtime status에서 testkit API base URL을 추론합니다. test tooling 한정이라 우선순위는 낮지만 명시 service endpoint로 바꾸는 편이 좋습니다. | P3 |
| `MacHostRuntimeAdapter` remaining files | 11 | command/log/export/settings/path adapter입니다. export/log collector는 명시 source list가 있어 현재 방향과 맞습니다. | Monitor |
| `HostCLI/RuntimeStatusWriter.swift` | 1 | status write와 VitalDB SQLite projection을 함께 수행합니다. | P1 |
| `HostCLI/RuntimeLifecycle+Support.swift` | 1 | best-effort event/status/projection helper가 집중되어 있고 status writer에 projection closure를 주입합니다. | P1 |
| `HostCLI/RuntimeLifecycle+Workflows.swift` | 1 | install/update/watchdog workflow가 status write, event record, projection side effect를 조합합니다. | P1 |
| `HostCLI/RuntimeHealthChecker.swift` | 1 | guest state/status observation read에서 optional convenience와 `try?`가 섞여 진단 상태를 약하게 만듭니다. | P2 |
| `HostCLI/RuntimeApplyBundleRunner.swift`, `RuntimeApplyBundleStepExecutor.swift`, `RuntimeBundleWorkflow.swift` | 3 | update runner/executor/workflow 분리는 방향이 맞습니다. 다만 progress/status write closure가 반복되어 orchestration abstraction을 더 명확히 할 여지가 있습니다. | P3 |
| `HostCLI` remaining files | 64 | CLI/VM/config/service/repair/rollback/log utility입니다. 현재 핵심 조치 대상은 status/projection/update orchestration 주변에 집중되어 있습니다. | Monitor |
| `RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift` | 1 | HTTP boundary가 overview read model 합성까지 수행합니다. | P2 |
| `RuntimeControlAPI/Boundary/RuntimeControlClientAPIReadHandler.swift` | 1 | handler contract가 optional observation을 노출합니다. observation unavailable/error 의미를 더 명시할 여지가 있습니다. | P3 |
| `RuntimeControlAPI` remaining files | 6 | endpoint routing, wire codec, local server, dev console입니다. 현재 큰 방향 문제는 없습니다. | Monitor |
| `MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModel.swift` | 1 | 화면 state, refresh orchestration, polling, command intent가 한 타입에 큽니다. | P1 |
| `MacRuntimeControlApp/Presentation/ViewModels/*` extensions | 5 | ViewModel의 책임을 파일로만 나눴고, orchestration 소유권은 여전히 ViewModel에 있습니다. | P2 |
| `MacRuntimeControlApp/Composition/MacRuntimeControlAPIHandler.swift` | 1 | API handler가 `Core`를 직접 import하고 remote console status를 합성합니다. | P2 |
| `MacRuntimeControlApp/Composition/AppConstants.swift` | 1 | 853라인의 UI text/constant 집합입니다. 기능 문제는 아니지만 screen/domain별 분리가 필요합니다. | P3 |
| `MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift` | 1 | chart/UI 구현이 큽니다. recorder chart 문제를 고친 뒤에도 rendering 책임이 한 파일에 집중되어 있습니다. | P3 |
| `MacRuntimeControlApp` remaining files | 32 | presentation view/policy/native shell/composition입니다. UI 계층의 `Core` 직접 의존 제거 이후 다시 확인합니다. | Monitor |

## Symptoms

macOS runtime 코드에서 상태, 이벤트, 관측 projection, UI/API read model의 책임이 일부 겹쳐 있습니다.

대표 증상:

- 상태를 쓰는 코드가 관측 데이터를 SQLite에 projection합니다.
- recorder history read model이 SQLite bucket projection이 없을 때 snapshot rolling activity를 history처럼 재사용할 수 있습니다.
- SQLite observability read 실패가 빈 배열로 바뀌는 public API가 남아 있습니다.
- recorder activity bucket 조회가 `limit`만 받고 `vrcode`, `since`, `until` 같은 조회 의도를 SQL에 명시하지 않습니다.
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

이 구조에서는 read failure를 port contract에서 표현하기 어렵습니다. 구현체가 내부적으로 실패를 `nil`, `[]`, stale page로 숨기기 쉬운 모양입니다.

```text
CompositeRuntimeEventRepository.query()
  -> catchUpSecondaryIndexIfDue()
  -> primary JSONL all()
  -> secondary SQLite upsert()
  -> on failure, rebuild secondary index
  -> secondary query()
```

이 구조에서는 read path가 write path와 repair path를 수행합니다. JSONL이 SoT이고 SQLite가 조회 projection인 방향은 맞지만, catchup/rebuild는 명시 projector 책임이어야 합니다.

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
5. Activity bucket 조회는 `vrcode`, `since`, `until`, `limit`을 명시한 query object로 바꿉니다.
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
   - query는 SQLite read만 수행하고, projection 상태/오류는 별도 event/status로 남김

5. `SystemRuntimeStatusReader` 분리
   - `RuntimeStatusDocumentReader`: document만 읽음
   - `RuntimeLiveDiagnosticsReader`: launchd/curl/data directory 같은 live diagnostics만 읽음
   - `RuntimeStatusAssembler`: 둘을 명시 source로 합성

6. `RuntimeViewModel` 다이어트
   - command flow/polling/use case orchestration을 coordinator로 분리
   - ViewModel은 화면 state와 사용자 intent delegation만 유지

7. Core read port contract 정리
   - `RuntimeStatusRepository.load() -> RuntimeStatusDocument?`를 `loadResult()` 또는 throwing API로 변경
   - `RuntimeEventHistoryReading.query()`는 read failure를 표현할 수 있게 변경
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
