# Runtime State Machine Traceability

이 문서는 runtime operation order가 중요한 흐름을 어떤 단위로 명세하고 검증할지 정리합니다.

목표는 구현 파일 목록을 설명하는 것이 아니라, 상태 전이가 있는 기능을 변경할 때 반드시 남겨야 하는 traceability 증거를 고정하는 것입니다. AGENTS.md 기준에 따라 state owner가 아닌 계층은 상태를 추론하지 않고, missing/invalid/failed/stale/zero/empty 의미를 서로 바꾸지 않습니다.

## Traceability Template

상태 전이를 갖는 흐름은 아래 항목을 문서와 테스트에서 추적할 수 있어야 합니다.

| 항목 | 의미 |
|---|---|
| Owner | state를 실제로 소유하고 기록하는 계층 또는 process |
| Consumers | state를 읽고 표시/판단하는 계층 |
| Persisted document | 재시작, 재시도, 진단에 필요한 state document |
| States | operation 또는 read model의 닫힌 상태 집합 |
| Events | state owner가 제공하거나 workflow가 명시적으로 생성하는 입력 |
| Guards | 전이를 허용하거나 차단하는 조건 |
| Commands/effects | Core policy가 반환하고 Workflow/Adapter가 실행하는 effect |
| Invariants | 어떤 경로에서도 깨지면 안 되는 조건 |
| Failure semantics | missing, invalid, failed, stale, unavailable, zero/empty 구분 |
| Verification | 상태 전이, boundary, adapter failure를 검증하는 테스트 |
| Diagnostics | operator가 실패 원인을 확인할 수 있는 event/log/export/API 위치 |

## Layer Rules

| Layer | 해야 하는 일 | 하지 말아야 하는 일 |
|---|---|---|
| `Contracts` | persisted state document, event, command/result DTO를 정의 | Host/Guest 내부 구현을 import |
| `Domain` | 최종 구조의 pure transition policy, guard, invariant를 계산 | filesystem/process/network/log 읽기 |
| `Core` | 전환기 legacy import compatibility shim을 제공 | policy/model/port ownership, filesystem/process/network/log 읽기 |
| `RuntimeWorkflow` | explicit state를 `Application/Ports`로 읽고 `Domain` decision을 실행 순서에 맞게 소비 | 상태를 absence/log/probe로 추론 |
| `HostInfrastructure` | host file/process/SQLite/shared directory read/write 결과를 typed result로 제공 | dependency failure를 empty/default success로 변환 |
| `RuntimeControlAPI` | transport response에서 read state/error semantics를 보존 | command/read failure를 성공 payload로 축소 |
| UI/PWA | explicit state를 표시하고 operator action을 요청 | domain state, recovery decision, operation transition 생성 |

## Current Traceability Map

| Flow | Current owner | Persisted/read document | Domain/Core policy | Workflow/API surface | Primary verification |
|---|---|---|---|---|---|
| Install | Host runtime | `RuntimeInstallStateDocument` | Domain `RuntimeInstallTransitionPolicy`, Domain `RuntimeOperationPlan` | `Workflow/RuntimeInstallLifecycle`, `HostCLI install` | `DomainRuntimeInstallTransitionPolicyTests`, `RuntimeInstallTransitionPolicyTests`, `RuntimeInstallWorkflowTests` |
| Uninstall | Host runtime | `RuntimeUninstallStateDocument` | Domain `RuntimeUninstallTransitionPolicy`, Domain `RuntimeUninstallReadinessPolicy` | `Workflow/RuntimeUninstallLifecycle`, `HostCLI uninstall` | `DomainRuntimeUninstallTransitionPolicyTests`, `RuntimeUninstallTransitionPolicyTests`, `RuntimeUninstallWorkflowTests` |
| Product update | Host updater + guest activation result | `runtime-status.json`, `activate-update.request`, `activate-update-result.json`, `runtime-version.json` | update preflight and compatibility policies | `apply-bundle`, `/host/update-bundles/*` | update preflight, bundle verifier, activation result tests |
| Watchdog recovery | Host watchdog | `runtime-status.json`, `runtime-events.jsonl`, health snapshot inputs | Domain `RuntimeWatchdogRecoveryPolicy`, health policies | Workflow `RuntimeWatchdogRunner`, `/runtime/status`, `/runtime/events` | recovery policy and observability tests |
| Guest operation result | Guest operation script | guest request/result JSON documents | guest activation/shutdown/datastore evaluators | Host guest gateway readers | guest evaluator and result gateway tests |
| Vital Recorder read model | VitalDB observer + host observability projection | latest observation snapshot, SQLite projection | recorder summary/history construction policy | `/vitaldb/recorders`, `/runtime/overview` | RuntimeControl contract tests, PWA schema tests |
| Log collection/export | Host log collector/exporter | raw logs, helper message log, JSONL, SQLite sidecars | no domain transition policy | `/host/logs/read`, `/host/logs/export` | log collector/exporter tests |

## Required Flow Details

### Install

Owner:

- Host runtime owns install operation state.
- HostCLI is composition root, not transition owner.

Invariants:

- Fresh install preflight blockers stop side effects before install files or services are changed.
- Full install cannot complete before required install steps and health verification complete.
- Install provision can finish as provisioned/degraded, but must not claim runtime health.
- Settings read/decode failure, invalid settings, existing artifacts, receipt state, service state, proxy port conflict, and unknown state remain blockers or failures.

Diagnostics:

- Install state document.
- command log.
- runtime status/progress event. `RuntimeStepExecutionEvent` is a shared `Contracts` value, not a `Core`-owned transition rule.
- package preinstall/postinstall logs.

### Uninstall

Owner:

- Host runtime owns uninstall operation state.
- Domain transition policy owns the phase/command rules. `Core` exposes compatibility aliases during migration.

Invariants:

- File removal cannot start without explicit stopped/read-safe service and VM process state.
- `pidFileMissing`, `readFailed`, `permissionDenied`, `inspectFailed`, `forgetFailed`, and `unknown` cannot transition to completed.
- Receipt forget success is not proof of receipt absence; receipt state must be observed.
- Cleanup command success is not proof of artifact absence; artifact states must be observed.

Diagnostics:

- Uninstall state document.
- command log.
- runtime event history.
- cleanup verification blockers.

### Product Update

Owner:

- Domain owns bundle verification policy. Workflow owns bundle materialization, verification, staging, host artifact replacement order, rollback decision, and status write sequencing. Host adapters supply concrete filesystem/process effects.
- Guest activation script owns guest activation result document.

States:

- verifying
- staged
- backup-created
- host-artifacts-applied
- guest-activation-requested
- guest-activation-completed
- health-verified
- committed
- rollback-running
- failed

Invariants:

- Bundle verification must pass before staging or replacing artifacts.
- `manifest.json`, `checksums.txt`, and artifact sha256/size mismatches block apply.
- `activate-update-result.json` must match the active request id before guest activation is accepted.
- Update/rollback is a protected operation; watchdog must not restart VM/proxy during the protected window.
- Rollback must preserve mutable runtime data.

Diagnostics:

- update command log.
- `runtime-status.json` operation/progress.
- `activate-update.request`.
- `activate-update-result.json`.
- managed backup metadata.
- runtime events.

### Watchdog Recovery

Owner:

- Host watchdog owns normalized product status, event emission, and recovery decision for each tick.

States/decisions:

- healthy
- protected operation skipped
- recovery disabled
- recovery suppressed
- unrecoverable
- recover

Invariants:

- Recovery does not use event history as decision input.
- Recovery consumes current explicit health snapshot and active operation guard.
- Storage corruption, readonly disk, invalid VM disk attachment, and destructive-risk signals suppress automatic VM restart.
- Missing, failed, stale, and unavailable health inputs remain visible in status/event diagnostics.

Diagnostics:

- `runtime-status.json`.
- `runtime-events.jsonl`.
- watchdog log.
- runtime observability SQLite.
- log export bundle.

### Vital Recorder Read Model

Owner:

- `vitaldb-observer` owns Redis/proxy/access-log observation snapshot.
- Host observability projection owns SQLite read model.
- Runtime Control owns API response shape.

Invariants:

- Recorder online/stale/notObserved state is derived from explicit observation fields and thresholds, not UI timers.
- Activity read failure is not empty activity.
- `readIssues` and projection `readError` remain visible.
- Summary counts come from provider read model, not UI recomputation when provider summary exists.
- Anomaly count without anomaly detail is incomplete operator state and must be exposed as a read issue or detail list.

Diagnostics:

- `/vitaldb/recorders`.
- `/runtime/overview`.
- `/runtime/events`.
- vitaldb-observer stdout/container logs.
- runtime observability SQLite.

### Log Collection And Export

Owner:

- Host log collector/exporter owns what source files are read and copied.
- UI/PWA owns source selection and rendering only.

Invariants:

- Log read permission failure is not empty log text.
- Missing source is distinct from empty source.
- Export failure must include the failed source/destination reason.
- Export includes JSONL event history and SQLite WAL/SHM sidecars when present.

Diagnostics:

- `/host/logs/read`.
- `/host/logs/export`.
- helper message log.
- command log.
- exported bundle manifest.

## Completion Evidence For New Changes

Any future state-machine or operation-order change should include:

1. Contract or state document update when state crosses a process/layer boundary.
2. Core transition or policy test for blocked and allowed transitions.
3. Workflow test proving side effects are executed only after Core returns commands.
4. Adapter/repository test for missing, permission denied, decode failure, dependency failure, and observed empty/zero.
5. Runtime Control API/PWA schema test when the state is exposed to Remote Console.
6. Troubleshooting or architecture doc update when the change clarifies an operational rule.
