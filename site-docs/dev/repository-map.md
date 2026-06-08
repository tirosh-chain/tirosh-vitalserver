# Repository Map

이 repository는 monorepo입니다. 각 package와 app은 역할 경계를 유지해야 합니다.
이 문서는 실행 단위, source layout, dependency direction을 함께 보는 지도입니다.

## 1. Runtime Units

| 서비스/패키지 | 공개 문서 노출 | 책임 |
|---|---|---|
| `apps/vitalserver` | Vital Server service | Vital Server integration wrapper와 runtime shim |
| `apps/vitalserver-macos-runtime` | Vital Server Helper | macOS Helper app, host runtime, VM orchestration, packaging |
| `apps/vitalserver-runtime-pwa` | Runtime Control UI | browser/PWA 기반 runtime control surface |
| `apps/vitaldb-observer` | Health Check 내부 collector | Redis/proxy 기반 recorder observation snapshot 생성 |
| `apps/vitalserver-audit-proxy` | command audit 기능 | VRecorder command/audit event sidecar |
| `packages/vitalserver-testkit` | 검증 도구 | simulated recorder, `.vital` upload, smoke/load validation |
| `packages/vitalserver-devtools` | dev 문서 중심 | build machine packaging, VM/update bundle tooling |
| `packages/vitalserver-guest-tools` | dev 문서 중심 | Linux guest-side runtime state, update, logs, repair commands |
| `infra/macos-nginx` | release installation에서 간접 설명 | Mac host proxy config and launchd template |

## 2. Top-Level Layout

| 경로 | 역할 |
|---|---|
| `apps/` | 실행 app, UI, runtime, observer, proxy |
| `packages/` | Python package 기반 devtools, guest tools, testkit |
| `infra/` | host proxy, swagger, deployment infrastructure |
| `config/` | build, packaging, testkit 설정 |
| `scripts/` | repository-level 운영/검증 script |
| `vendor/` | Vital Server source reference |
| `docs/` | 정식 문서 |
| `drafts/` | 정식 반영 전 문서 초안 |

## 3. Runtime Source Layout

`apps/vitalserver-macos-runtime/Sources`는 layer 이름이 책임 경계를 드러내야 합니다.

```text
Sources/
  Contracts/
    RuntimeControl/
    Shared/
  Domain/
    Models/
    Policies/
    StateMachines/
  Application/
    Ports/
    UseCases/
  Workflow/
  Adapters/
    Inbound/
    Outbound/
  Hosts/
    CLI/
    MacControlPanel/
  Bootstrap/
    Composition/
    DI/
  Errors/
```

Dev 배포판의 QA 기능은 test support가 아니라 product feature입니다. Production source에서
`Testing` 폴더명을 쓰지 않고, 기능 이름인 `TestKit` 또는 `DevConsole`로 드러냅니다.

```text
Contracts/RuntimeControl/TestKit/
Adapters/Inbound/RuntimeControlAPI/DevConsole/
Adapters/Inbound/RuntimeControlAPI/TestKit/
Adapters/Inbound/MacControlPanel/Presentation/TestKit/
Adapters/Outbound/MacRuntimeControlClient/TestKit/
```

Runtime Control API inbound adapter는 HTTP boundary, transport, dev UI, TestKit endpoint를
분리합니다. Dev Console HTML은 Swift responder에 inline하지 않고 target resource로 둡니다.
TestKit API는 router, endpoint catalog, request body DTO를 분리해서 라우터가 path catalog나
wire DTO 선언까지 소유하지 않게 합니다.

```text
Adapters/Inbound/RuntimeControlAPI/
  Boundary/
  Transport/
  DevConsole/
    RuntimeControlDevConsoleDocument.swift
    RuntimeControlDevConsole.html
  TestKit/
    RuntimeTestKitAPIRouter.swift
    RuntimeTestKitAPIEndpoint.swift
    RuntimeTestKitAPIRequests.swift
```

Mac Control Panel inbound adapter는 UI composition이라는 포괄 폴더에 상태/문구/설정을
섞어 두지 않습니다. UI copy와 표시 문자열은 Presentation 소유이고, generated release
metadata와 host-aware configuration limit은 각각 별도 소유자로 드러냅니다.

```text
Adapters/Inbound/MacControlPanel/
  Configuration/
  Generated/
  Presentation/
    Copy/
    Formatting/
    Policies/
    TestKit/
    ViewModels/
    Views/
```

Mac Runtime Control outbound client는 host filesystem/process/network 상태를 읽고 쓰는
stateful boundary입니다. root에는 Swift 구현 파일을 직접 두지 않고 capability별 폴더만 둡니다.

```text
Adapters/Outbound/MacRuntimeControlClient/
  Backups/
  Client/
  Commands/
  Environment/
  Logs/
  Reads/
  Settings/
  TestKit/
```

Host CLI ProcessBoundary는 concrete process/filesystem effect와 workflow 실행 wiring을
소유합니다. 단일 `RuntimeLifecycle+Support` 또는 `RuntimeLifecycle+Workflows` 파일로
되돌리지 않고, lifecycle composition과 host support helper를 책임별 파일로 나눕니다.

```text
Hosts/CLI/ProcessBoundary/
  Lifecycle/
  Support/
```

## 4. Documentation Exposure

| 항목 | 문서 노출 | 설명 |
|---|---|---|
| Vital Server Helper | release | release 문서의 최상위 서비스명 |
| Health Check | release | Vital Server Helper가 제공하는 기능 |
| Runtime Control API | dev 중심 | public UI와 host runtime 사이의 계약 |
| Linux VM guest stack | dev 중심 | 동일 service appliance 운용환경 |
| wrapper/preload | dev 중심 | Vital Server integration layer |
| devtools | dev 중심 | packaging/build machine tooling |

## 5. Dependency Direction

Domain/Core는 Host, Guest, filesystem, network, logs, command output을 직접 읽지 않습니다.

Application/Usecase는 stateless입니다. 완전한 명시 입력과 port가 반환한 명시 상태를
받아 Domain/Core policy를 호출하고, 실행할 command/effect/event/state decision을
계산합니다. Usecase는 port bundle을 소유하거나 cache하지 않고, filesystem/process/network를
직접 읽지 않습니다.

Workflow는 stateful orchestration입니다. operation 진행 순서, progress, retry/wait loop,
runner 흐름, persisted workflow status를 연결합니다. Workflow는 Usecase를 호출해서 결정을
받고, domain policy를 직접 판단하거나 concrete Host effect를 직접 수행하지 않습니다.

Adapters/Host/Guest infrastructure는 외부 상태를 읽고 씁니다. 읽기 실패, 권한 실패,
decode 실패, dependency 실패는 명시적인 typed result로 inward layer에 전달합니다.

Presentation/UI는 명시 상태를 표시합니다. UI가 domain state를 추측하거나 복구하지 않습니다.

Bootstrap은 concrete dependency graph를 조립합니다. Bootstrap은 workflow/usecase를 실행하지
않고, process/filesystem/network/JSON read-write를 수행하지 않습니다. Bootstrap/Composition은
상수와 path composition만 둘 수 있고, concrete runner/effect composition은 Host process
boundary나 adapter에 둡니다.

## 6. Layer Responsibility Map

| Layer | Purity | State owner | Allowed fallback | 책임 |
|---|---|---|---|---|
| `Errors` | pure | 없음 | 없음 | 실패 의미, boundary/context/failure type을 명시 |
| `Contracts` | pure | 없음 | 없음 | state, event, command, document contract를 명시하고 missing/invalid/failed/stale/zero/empty를 보존 |
| `Domain` | pure | 없음 | 없음 | policy, guard, invariant, state-machine transition을 완전한 입력으로 계산 |
| `Application/UseCases` | stateless | 없음 | 없음 | explicit state를 받아 Domain policy를 호출하고 command/effect/event/state decision을 반환 |
| `Workflow` | stateful | workflow status/progress | reported degraded operation만 가능 | Usecase 호출 순서, wait/retry loop, progress, persisted workflow status를 관리 |
| `Adapters/Inbound` | stateful boundary | request/session/input boundary | display/input preset 수준만 가능 | CLI/API/UI 입력을 contract로 decode하고 출력/표시 형식으로 변환 |
| `Adapters/Outbound` | stateful boundary | filesystem/process/network/repository state | 명시 migration/documented config default만 가능 | 외부 상태를 읽고 쓰며 실패를 typed result로 보고 |
| `Bootstrap` | stateless assembly | 없음 | 없음 | concrete dependency graph, constants, path composition 조립 |
| `Hosts` | stateful process boundary | runtime/process/environment state | reported degraded operation만 가능 | process startup, host-owned effect closure, signal/process/filesystem boundary 연결 |

Fallback은 상태를 만들거나 실패를 성공으로 바꾸면 안 됩니다. read failure, permission
failure, decode failure, dependency failure, stale, missing은 각각 다른 의미로 유지해야 합니다.
