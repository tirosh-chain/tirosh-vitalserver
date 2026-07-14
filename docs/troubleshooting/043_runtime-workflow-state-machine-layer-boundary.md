# Runtime workflow state machine and layer boundary cleanup

> ID: TS-043
> Category: Architecture / Runtime workflow / macOS runtime
> Owner: macOS runtime architecture / RuntimeWorkflow
> Status: implemented

## Symptoms

- Install, uninstall, update, rollback, and guest operation order is visible in code, but the operation transition owner is not explicit enough.
- `Application/Usecase/Workflow` is now defined in `AGENTS.md`, but the macOS runtime project structure does not expose that layer as a separate target or top-level folder.
- Workflow-like types such as `RuntimeInstallWorkflow`, `RuntimeRollbackWorkflow`, `RuntimeGuestActivationWorkflow`, and `RuntimeDatastoreRepairWorkflow` live under `Sources/HostCLI/Runtime`, so the folder structure makes them look like CLI adapter code.
- `RuntimeUninstallRunner` still mixes sequencing, lifecycle state writes, side-effect calls, blocker construction, cleanup verification, and completion decisions in one HostCLI runtime file.
- `Sources/Core/Application` contains operation planning and runner code, so the name blurs `Domain/Core` and `Application/Workflow` responsibilities.
- At least one Presentation file directly imports `HostInfrastructure` and writes to the filesystem:
  - `Sources/MacRuntimeControlApp/Presentation/ViewModels/RuntimeHelperMessageLog.swift`

## Impact

- Future operation changes can accidentally put transition rules in adapters, shell entrypoints, or UI code.
- A blocked operation can be advanced by sequencing code instead of a central transition rule if tests do not cover the exact path.
- StateMachine invariants such as "files cannot be removed before explicit stopped state" are harder to audit because they are not centralized.
- Folder names do not fully teach new contributors where state transitions, orchestration, external reads/writes, and presentation formatting belong.
- TS-042 fixed the immediate install/uninstall state contract gap, but the broader operation workflow boundary remains a structural follow-up.

## Scope

TS-043 should go through the first real `RuntimeWorkflow` introduction, not a full migration of every runtime operation.

TS-043 is complete when:

- A `RuntimeWorkflow` target or top-level folder exists and its dependency direction is explicit.
- `RuntimeWorkflow` depends on `Contracts` and `Core`, and does not depend on `HostInfrastructure`, `HostCLI`, `MacHostRuntimeAdapter`, or UI targets.
- HostCLI uses `RuntimeWorkflow` as a composition/execution boundary instead of owning the operation workflow body.
- Uninstall is the first concrete operation moved under the new workflow boundary because TS-042 exposed the install/uninstall state contract gap.
- The uninstall workflow has a Core-owned transition policy or StateMachine and tests for its blocking invariants.
- The ambiguous `Sources/Core/Application` folder is removed by regrouping pure Core files into explicit folders such as `Plan`, `Preflight`, `Policy`, `StateMachine`, `Verification`, and `Document`.
- TS-042 behavior remains covered: fresh install preflight, uninstall readiness, cleanup artifact verification, receipt verification, and typed failure reporting must not regress.

Out of TS-043 scope:

- Moving every install, update, rollback, guest activation, datastore repair, and health workflow.
- Removing every Presentation-side infrastructure smell.
- Building resume/retry semantics beyond the state document and transition rules required for the first uninstall workflow.

## Cause

The current macOS runtime package has a useful target graph, but it does not fully match the layer boundaries now documented in `AGENTS.md`.

Confirmed structure that is already useful:

- `Sources/Contracts` defines shared explicit documents and state contracts.
- `Sources/Core` contains pure policies such as:
  - `RuntimeFreshInstallPreflightPolicy`
  - `RuntimeUninstallReadinessPolicy`
- `Sources/HostInfrastructure` owns storage/repository/file infrastructure.
- `Sources/HostCLI` is the executable entrypoint for `vitalserver-vm`.
- `Sources/MacHostRuntimeAdapter` bridges the helper app and host runtime operations.
- `Sources/MacRuntimeControlApp/Presentation` contains UI-facing presentation code.

Confirmed weak points before TS-043:

- No `RuntimeWorkflow` or `Application` target exists between `Core` and `HostCLI`.
- Workflow files are physically under `HostCLI/Runtime`, so application orchestration and CLI adapter responsibilities are not separated by project structure.
- `RuntimeUninstallRunner` improved explicit state handling in TS-042, but its transition order is still inline rather than modeled by a StateMachine.
- `Core/Application` contains operation sequencing names under `Core`, which can confuse pure policy with workflow execution.
- Presentation has direct filesystem write behavior in `RuntimeHelperMessageLog.swift`; UI should request logging through a port or shell/adapter boundary instead.

## Checks

Use these checks before changing the folder structure. They identify misplaced imports and workflow files.

```sh
find apps/vitalserver-macos-runtime/Sources -maxdepth 2 -type d | sort

rg -n "struct .*Workflow|enum .*Workflow|class .*Workflow|struct .*Runner|StateMachine|Transition" \
  apps/vitalserver-macos-runtime/Sources/Core \
  apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime \
  apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter \
  apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation

rg -n "^import HostInfrastructure" \
  apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp \
  apps/vitalserver-macos-runtime/Sources/RuntimeControl \
  apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI \
  apps/vitalserver-macos-runtime/Sources/Core \
  apps/vitalserver-macos-runtime/Sources/Contracts

rg -n "FileManager|Process\\(|launchctl|pkgutil|lsof|runRequired|runProcess|removeItem|createDirectory" \
  apps/vitalserver-macos-runtime/Sources/Core \
  apps/vitalserver-macos-runtime/Sources/Contracts \
  apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation
```

Expected direction:

- `Contracts` may import Foundation and must not import product layers.
- `Core` may import `Contracts` and Foundation only when value types require it.
- `RuntimeWorkflow` should import `Contracts` and `Core`, not `HostInfrastructure`.
- `HostCLI`, adapters, infrastructure, and native shell may execute side effects and provide typed results inward.
- Presentation must not import `HostInfrastructure` or own filesystem/process side effects.

## Actions

1. Record the responsibility map before moving files.

   Classify each runtime file as one of:

   ```text
   Contract
   Core policy / StateMachine / invariant
   Application workflow / orchestration
   Port
   HostCLI composition
   Adapter / infrastructure effect
   Presentation formatting
   ```

2. Add a `RuntimeWorkflow` target or top-level folder.

   Target direction should be:

   ```text
   Contracts
   Core -> Contracts
   RuntimeWorkflow -> Contracts, Core
   HostInfrastructure -> Contracts, Core
   HostCLI -> Contracts, Core, RuntimeWorkflow, HostInfrastructure
   MacHostRuntimeAdapter -> Contracts, RuntimeControl, Core, HostInfrastructure
   MacRuntimeControlApp -> Contracts, RuntimeControl, RuntimeControlAPI, MacHostRuntimeAdapter
   ```

   `RuntimeWorkflow` must not import `HostInfrastructure`.

3. Introduce uninstall StateMachine first.

   Define in Core/Contracts:

   ```text
   RuntimeUninstallWorkflowState
   RuntimeUninstallWorkflowEvent
   RuntimeUninstallWorkflowCommand
   RuntimeUninstallTransitionPolicy
   RuntimeUninstallTransitionDecision -> persisted RuntimeUninstallState
   SQLite workflow operation state (`operation_type=uninstall`)
   ```

   Required invariants:

   - File removal cannot start without explicit stopped/read-safe service and VM process states.
   - `pidFileMissing`, `readFailed`, `permissionDenied`, `inspectFailed`, `forgetFailed`, and `unknown` cannot transition to `completed`.
   - `blocked` cannot clear without a new explicit observation/event.
   - Receipt forget success is not proof of receipt absence; receipt state must be observed.
   - Cleanup command success is not proof of artifact absence; artifact states must be observed.

4. Introduce `RuntimeUninstallWorkflow` under `RuntimeWorkflow`.

   The workflow should:

   - consume explicit Host state through injected ports/closures
   - call the Core transition policy or StateMachine
   - execute returned commands through ports
   - create explicit events from command results
   - persist operation state through an injected writer
   - avoid direct filesystem, process, launchd, pkgutil, or shell reads

5. Refactor `RuntimeUninstallRunner` without changing external behavior.

   First make the existing runner delegate transition decisions to the StateMachine. Then separate workflow orchestration from HostCLI composition. Keep the TS-042 tests green while adding transition tests.

6. Shrink HostCLI for uninstall to command parsing and composition.

   `RuntimeLifecycle+Support.swift` and `RuntimeLifecycle+Workflows.swift` can remain composition roots. They should wire state readers, effect executors, and state writers into `RuntimeUninstallWorkflow`; they should not own uninstall transition rules.

7. Add boundary and transition tests.

   Required tests:

   - `RuntimeWorkflow` imports only `Contracts` and `Core`
   - invalid uninstall transitions are blocked
   - file removal command is not emitted without explicit stopped/read-safe states
   - `pidFileMissing`, `readFailed`, `permissionDenied`, `inspectFailed`, `forgetFailed`, and `unknown` do not reach `completed`
   - receipt command success must be followed by explicit receipt absence before completion
   - cleanup command success must be followed by explicit artifact absence before completion
   - HostCLI composition still wires the same uninstall behavior

8. Update tests and documentation with the new workflow boundary.

## Implementation Result

Implemented on `feature/issue-44`.

- Added a `RuntimeWorkflow` Swift target between `Core` and `HostCLI`.
- `RuntimeWorkflow` depends on `Contracts` and `Core` only.
- `HostCLI` now depends on `RuntimeWorkflow` and wires uninstall dependencies from the composition root.
- Moved uninstall workflow body out of `HostCLI/Runtime/RuntimeUninstallRunner.swift` into:
  - `Sources/RuntimeWorkflow/Uninstall/RuntimeUninstallWorkflow.swift`
- Added a Core-owned uninstall transition policy:
  - `Sources/Core/StateMachine/RuntimeUninstallTransitionPolicy.swift`
- The uninstall transition policy defines:
  - `RuntimeUninstallWorkflowState`
  - `RuntimeUninstallWorkflowEvent`
  - `RuntimeUninstallWorkflowCommand`
  - `RuntimeUninstallTransitionDecision`
  - `RuntimeUninstallTransitionError`
- The uninstall workflow now delegates blocking transition decisions to Core policy for:
  - start state persistence
  - Redis backup request and completion
  - runtime stop request
  - stop-state verification before file removal
  - cleanup artifact verification before receipt forget
  - receipt forget failure
  - receipt absence verification before completion
- Uninstall workflow tests now live under `RuntimeWorkflowTests`, not `HostCLITests`.
- Added RuntimeWorkflow boundary tests that:
  - reject imports from outer layers such as `HostInfrastructure`, `HostCLI`, `MacHostRuntimeAdapter`, `MacRuntimeControlApp`, `RuntimeControl`, and `RuntimeControlAPI`
  - reject the ambiguous `Sources/Core/Application` folder and require explicit Core responsibility folders
- TS-042 behavior remains covered by existing and moved tests for explicit stopped state, cleanup artifact blockers, receipt forget blockers, and completion gating.
- Removed the ambiguous `Sources/Core/Application` folder. Pure Core files are now grouped by responsibility:
  - `Sources/Core/Plan`
  - `Sources/Core/Preflight`
  - `Sources/Core/Policy`
  - `Sources/Core/StateMachine`
  - `Sources/Core/Verification`
  - `Sources/Core/Document`

Verification:

- `swift test --filter 'RuntimeUninstallTransitionPolicyTests|RuntimeWorkflowBoundaryTests|RuntimeUninstallWorkflowTests|RuntimeLifecycleCommandTests'`
- `swift test --filter 'ContractsTests|CoreTests|RuntimeWorkflowTests|HostInfrastructureTests|HostCLITests'`
- `swift test --filter 'RuntimeControlAPITests.RuntimeControlAPITests/testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents'`
- `uv run pytest packages/vitalserver-devtools/tests/unit/test_packaging_templates.py`
- `bash -n apps/vitalserver-macos-runtime/Support/Packaging/preinstall`
- `bash -n apps/vitalserver-macos-runtime/Support/Packaging/postinstall.template`
- `git diff --check`

Known test-suite note:

- Full `swift test` still exits with xctest signal 11 when it reaches `RuntimeControlAPITests.RuntimeControlAPITests/testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents`.
- The same RuntimeControl API stream test passes in isolation, and the TS-043 affected target range passes separately.

## Deferred Follow-up

After TS-043 introduces the first workflow boundary, follow-up work can move the remaining operations one at a time:

- Move install workflow after replacing `HostInfrastructure` path types with workflow DTOs or ports.
- Move update bundle, rollback, guest activation, datastore repair, and health workflows after uninstall/install.
- Revisit `RuntimeOperationPlanRunner` if it starts owning effects rather than executing injected step callbacks; at that point it should move from `Core/Plan` into `RuntimeWorkflow`.
- Remove Presentation filesystem ownership by moving `RuntimeHelperMessageLog` file writes behind `NativeShell`, `MacHostRuntimeAdapter`, or a dedicated logging port.
- Add automated import-boundary checks if SwiftPM target dependencies are not enough to prevent regressions.

## Prevention

- Operation order that matters must define state, event, guard, command/effect, invariant, and persisted document before changing side-effect code.
- Core StateMachines must be pure and must not read Host, Guest, filesystem, process, network, logs, or command output state.
- Workflow code may sequence steps, but it must consume explicit state through ports and must not infer state.
- Adapters must return typed state/failure contracts instead of collapsing dependency failure into success.
- Folder/target names should make layer responsibility visible without needing to inspect every file.

## Operational Notes

- This is a structural follow-up to TS-042, not a replacement for TS-042.
- TS-042 is considered implemented for the Host install/uninstall state contract gap.
- TS-043 is implemented for the first `RuntimeWorkflow` boundary and uninstall workflow transition ownership.
- TS-043 also removes the ambiguous `Core/Application` physical folder; Core now uses explicit responsibility folders.
- TS-043 does not require every workflow to move. Broad workflow migration should be done as follow-up work after the first boundary is proven.
- For future workflow migrations, add StateMachine tests first, refactor one operation in place, then move the workflow layer after behavior is pinned.

## Related Cases

- `TS-032`: macOS runtime 코드의 상태/관측 책임이 섞임
- `TS-039`: AGENTS.md 상태/실패 fallback 감사
- `TS-042`: Host install/uninstall state 계약 부족으로 cleanup/reinstall이 막힘

## Follow-up

- 2026-06-02: `AGENTS.md`에 Layer Boundaries를 추가한 뒤 현재 macOS runtime folder/target structure를 점검했다. 큰 target 경계는 존재하지만 `RuntimeWorkflow` 계층과 StateMachine 전이 소유자는 아직 물리적으로 분리되지 않았다.
- 2026-06-02: TS-043 scope was narrowed to introducing the first `RuntimeWorkflow` boundary through uninstall workflow. Full install/update/rollback/guest/UI cleanup remains follow-up work.
- 2026-06-02: Implemented the first `RuntimeWorkflow` target and moved uninstall workflow under it with Core transition policy tests and RuntimeWorkflow import-boundary tests.
- 2026-06-02: Removed `Sources/Core/Application` and regrouped Core files under `Plan`, `Preflight`, `Policy`, `StateMachine`, `Verification`, and `Document` so folder structure matches the documented layer boundary.
