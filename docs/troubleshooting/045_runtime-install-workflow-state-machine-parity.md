# Runtime install workflow state machine parity

> ID: TS-045
> Category: Runtime workflow / Install / StateMachine
> Owner: macOS runtime architecture / RuntimeWorkflow
> Status: implemented

## Symptoms

- Install has Core preflight and operation plan tests, but it does not have an install workflow state machine equivalent to uninstall.
- Install execution still lives mainly in HostCLI runner and step executor code.
- Install step execution can be tested, but transition policy, command emission, command consumption, persisted install state, and phase blockers are not explicit.
- Install completion is derived from runner completion instead of a state transition that proves the required observations for the selected install mode.
- Install dependencies are grouped as broad HostCLI operations, not as explicit state readers, side-effect executors, state writers, and diagnostics ports.

## Cause

TS-042 and TS-044 tightened uninstall state ownership first because reinstall cleanup was blocked by ambiguous uninstall state. That left install with a partial structure:

- Core owns fresh install preflight policy and install step ordering.
- HostCLI owns settings loading, step execution, status writes, progress writes, filesystem writes, process execution, and launchd operations.
- RuntimeWorkflow has no install orchestration layer.

The result is a layer gap. Install has explicit preflight state, but no explicit operation state machine.

## Completion Criteria

TS-045 is complete when:

- Contracts define a persisted install state document that preserves started, blocked, failed, provisioned, completed, and step states distinctly.
- Core defines install workflow states, events, commands/effects, blockers, transition decisions, and invariants.
- RuntimeWorkflow contains install orchestration with explicit reader, effect, writer, and diagnostics ports.
- RuntimeWorkflow consumes Core commands before executing install side effects.
- HostCLI becomes the composition root for install external reads/writes/effects.
- Full install cannot complete healthy before required install steps and health verification complete.
- Install provision can finish as provisioned/degraded without claiming full health.
- Fresh install preflight blockers stop side effects before install files or services are changed.
- Settings read/decode failure, invalid settings, present artifacts, package receipts, loaded services, proxy port conflicts, and unknown states remain explicit blockers or failures.
- Focused Core and RuntimeWorkflow tests cover transition blockers, command consumption, phase order, provision behavior, and failure state persistence.

## Fix Direction

Refactor in this order:

1. Add focused Core tests for install transition blockers and mode completion rules.
2. Add `RuntimeInstallStateDocument` and install operation state values to Contracts.
3. Add Core install transition policy.
4. Add `RuntimeWorkflow/Install` with generic settings handling so HostCLI-specific `InstallSettings` does not leak inward.
5. Group install dependencies into explicit RuntimeWorkflow ports:
   - state readers
   - effects
   - state writer
   - diagnostics/logging
6. Rewire HostCLI install entrypoints through the new RuntimeWorkflow install runner.
7. Keep step side-effect implementations in HostCLI adapters or helpers.
8. Preserve existing `install` and `install-provision` operator behavior.

## Implementation Result

- Contracts now define `RuntimeInstallStateDocument`, `RuntimeInstallState`, and `RuntimeInstallMode`.
- `RuntimeFileNames` and `InstalledRuntimePaths` expose a dedicated `/private/tmp/tirosh-vitalserver-install-state.json` state path.
- Core now defines install workflow state, event, command, transition decision, and transition policy types.
- Core validates install mode/plan invariants:
  - full install must include `wait-install-runtime-health`
  - install provision must not claim runtime health
- RuntimeWorkflow now contains `RuntimeWorkflow/Install/RuntimeInstallWorkflow`.
- RuntimeWorkflow install dependencies are grouped into:
  - `RuntimeInstallStateReaders`
  - `RuntimeInstallEffects`
  - `RuntimeInstallStateWriter`
  - `RuntimeInstallDiagnostics`
- RuntimeWorkflow install orchestration consumes Core commands before side effects run.
- Fresh install preflight blockers stop install side effects before any step executes.
- Settings load failure and step failure persist explicit failed install state and write critical status best-effort.
- Full install reaches `completed` only after the full install plan, including health wait, succeeds.
- Install provision reaches `provisioned` with degraded completion status and does not execute the health wait step.
- HostCLI now composes the install workflow through RuntimeWorkflow and keeps step side effects in HostCLI helpers.
- The legacy HostCLI `RuntimeInstallRunner` was removed.

## Verification

- `swift test --filter 'RuntimeInstallTransitionPolicyTests|RuntimeInstallWorkflowTests'`
- `swift test --filter 'RuntimeInstallTransitionPolicyTests|RuntimeInstallWorkflowTests|RuntimeInstallStateStoreTests|RuntimeInstallStepExecutorTests|RuntimeFreshInstallPreflightPolicyTests|RuntimeFreshInstallPreflightRunnerTests|InstalledRuntimePathsTests|RuntimeLifecycleProgressEventTests|RuntimeLifecycleCommandTests'`
- `swift test --filter 'ContractsTests|CoreTests|RuntimeWorkflowTests|HostInfrastructureTests|HostCLITests'`
- `uv run pytest packages/vitalserver-devtools/tests/unit/test_packaging_templates.py`
- `bash -n apps/vitalserver-macos-runtime/Support/Packaging/preinstall`
- `bash -n apps/vitalserver-macos-runtime/Support/Packaging/postinstall.template`
- `swift test --filter 'RuntimeControlAPITests.RuntimeControlAPITests/testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents'`

Known suite signal:

- Full `swift test` still exits non-zero with xctest signal 11 when the full suite reaches `RuntimeControlAPITests.RuntimeControlAPITests/testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents`.
- The same test passes when executed in isolation, matching the existing full-suite signal observed before TS-045.

## Prevention

- Install must not infer clean state from absent logs, package script success, old command output, or missing state documents.
- Preflight failure, settings failure, dependency failure, and step failure must not become default success.
- HostCLI may read Host state, but it must pass explicit typed state into Core/RuntimeWorkflow.
- RuntimeWorkflow must not execute side effects unless Core has returned the matching command.
- Full install and install provision must remain different operation meanings in code and persisted state.

## Related Cases

- `TS-042`: Host install/uninstall state 계약 부족으로 cleanup/reinstall이 막힘
- `TS-043`: Runtime workflow StateMachine과 계층 경계 정리가 필요함
- `TS-044`: Runtime uninstall workflow가 phase와 command 계약을 읽기 어렵게 섞음
