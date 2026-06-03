# Runtime uninstall workflow phase and command readability cleanup

> ID: TS-044
> Category: Runtime workflow / Readability / StateMachine
> Owner: macOS runtime architecture / RuntimeWorkflow
> Status: implemented

## Symptoms

- `RuntimeUninstallWorkflow` has a clear target boundary, but the main workflow body is still hard to read.
- `RuntimeUninstallWorkflow.run()` mixes state transitions, persistence, side-effect execution, file preservation, removal, cleanup verification, receipt forget, receipt verification, and diagnostics in one long function.
- The Core transition policy returns `RuntimeUninstallWorkflowCommand`, but the workflow does not consistently consume commands as an execution contract.
- The workflow constructor receives many closures directly, so readers must inspect every argument to understand which dependencies are state readers, effects, writers, or diagnostics.
- Removal diagnostics can hide a directory-read failure by using best-effort reading without an explicit failure log.

## Cause

TS-043 introduced the correct layer boundary first. That made the target/folder structure readable, but it intentionally preserved much of the old uninstall flow shape to avoid changing behavior too broadly in the same step.

The remaining issue is now inside the `RuntimeWorkflow` layer:

- Workflow phase ownership is implicit.
- Command ownership is split between Core decisions and handwritten workflow sequencing.
- Dependency roles are not grouped.
- Some diagnostic failures are not visible enough for operators or future maintainers.

## Completion Criteria

TS-044 is complete when:

- `RuntimeUninstallWorkflow` dependencies are grouped by role:
  - state readers
  - side-effect executors
  - state writer
  - diagnostics/logging
- `RuntimeUninstallWorkflow.run()` reads as a short phase sequence.
- Each phase takes an explicit current workflow state or decision and returns the next explicit state or decision.
- Core `RuntimeUninstallWorkflowCommand` values are validated and consumed by the workflow before executing side effects.
- Failure states such as `pidFileMissing`, `readFailed`, `permissionDenied`, `inspectFailed`, `forgetFailed`, and `unknown` are tested so they cannot reach `completed`.
- Diagnostic read failures are explicitly logged instead of being silently ignored.
- TS-043 behavior remains intact for install/uninstall state contracts, cleanup verification, receipt verification, and standard uninstall data preservation.

## Fix Direction

Refactor in this order:

1. Add focused tests for failure-state blockers and diagnostic read failures.
2. Group workflow dependencies into explicit port structs.
3. Add a small command assertion/execution contract in `RuntimeUninstallWorkflow`.
4. Split `run()` into phase methods:

   ```text
   start
   backupIfNeeded
   stopAndVerifyRuntime
   removeFilesAndVerifyCleanup
   forgetReceiptsAndVerifyAbsence
   complete
   ```

5. Keep side-effect implementations injected from HostCLI composition.
6. Keep Core pure: Core still receives explicit state and returns decisions only.

## Implementation Result

- `RuntimeUninstallWorkflow` dependencies are grouped into explicit reader, effect, writer, and diagnostics port structs.
- `RuntimeUninstallWorkflow.run()` now reads as phase sequencing:
  - `start`
  - `backupIfNeeded`
  - `stopAndVerifyRuntime`
  - `removeFilesAndVerifyCleanup`
  - `forgetReceiptsAndVerifyAbsence`
  - `complete`
- Each phase receives the current explicit state or transition decision and returns the next explicit state or decision.
- Core transition decisions are enforced through a workflow command requirement before side effects run.
- Start/persist events no longer re-emit already-approved commands. Commands are emitted by state-observation decisions, then consumed by RuntimeWorkflow.
- Diagnostic directory-read failures are logged explicitly instead of being silently ignored.
- HostCLI remains the composition root for external reads, writes, effects, and diagnostics.

## Install Parity Review

TS-044 completed the uninstall workflow cleanup. At the time of this review, the same structure had not yet been applied to install.

Current install coverage:

- Fresh install preflight is represented in Core by `RuntimeFreshInstallPreflightPolicy`.
- Install step order is represented in Core by `RuntimeOperationPlan`.
- HostCLI has runner and step executor tests for install/provision step execution.
- `preinstall` calls explicit fresh install preflight instead of probing package state directly.
- `postinstall` calls `runtime install-provision` and uses `runtime uninstall --clean` for failed fresh-install cleanup.

Findings:

- `RuntimeWorkflow` currently contains only uninstall workflow code. There is no `RuntimeWorkflow/Install` equivalent.
- Install has no `RuntimeInstallTransitionPolicy`, `RuntimeInstallWorkflowState`, `RuntimeInstallWorkflowEvent`, `RuntimeInstallWorkflowCommand`, or transition decision type.
- Install execution still lives in `HostCLI/RuntimeInstallWorkflow`, `RuntimeInstallRunner`, and `RuntimeInstallStepExecutor`.
- Install tests verify plan execution and step dispatch, but they do not verify state-machine transitions, command emission/consumption, persisted install state, or observed-state blockers at each phase.
- Install dependency roles are grouped as broad HostCLI operations, not as explicit state readers, side-effect executors, state writer, and diagnostics ports.
- Install reaches final status through runner completion rather than through an explicit state transition that proves required install observations.

Install was brought to uninstall parity in `TS-045`. The implementation pass used this checklist:

1. Define Core install state machine types:
   - states
   - events
   - commands/effects
   - blockers
   - persisted install state document
2. Move install orchestration into `RuntimeWorkflow/Install`.
3. Group install dependencies by role:
   - state readers
   - side-effect executors
   - state writer
   - diagnostics/logging
4. Make each install phase consume Core commands before executing effects.
5. Require explicit owner-provided observations before advancing through risky boundaries:
   - settings loaded/defaulted/invalid/read failed
   - install artifacts absent/present/inspect failed
   - package receipts absent/present/read failed
   - service state not loaded/loaded/read failed/permission denied
   - VM disk/rootfs availability
   - launchd start result
   - runtime health result
6. Add focused tests equivalent to uninstall:
   - Core transition table tests
   - blocking state tests
   - command emission/consumption tests
   - RuntimeWorkflow phase order tests
   - diagnostic failure visibility tests
   - install-provision path tests that do not claim full health

This follow-up must preserve the TS-042 rule: install must not guess clean state from absence, logs, package script success, or stale command output.

## Verification

- `swift test --filter 'RuntimeUninstallTransitionPolicyTests|RuntimeWorkflowBoundaryTests|RuntimeUninstallWorkflowTests|RuntimeLifecycleCommandTests'`
- `swift test --filter 'ContractsTests|CoreTests|RuntimeWorkflowTests|HostInfrastructureTests|HostCLITests'`
- `uv run pytest packages/vitalserver-devtools/tests/unit/test_packaging_templates.py`
- `bash -n apps/vitalserver-macos-runtime/Support/Packaging/preinstall`
- `bash -n apps/vitalserver-macos-runtime/Support/Packaging/postinstall.template`
- `swift test --filter 'RuntimeControlAPITests.RuntimeControlAPITests/testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents'`

Known suite signal:

- Full `swift test` still exits non-zero when the full suite reaches `RuntimeControlAPITests.RuntimeControlAPITests/testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents`.
- The same test passes when executed in isolation, matching the existing full-suite signal observed before TS-044.

## Prevention

- New workflow code should not start as one large `run()` body.
- If Core returns commands, RuntimeWorkflow must either consume those commands or not expose commands at all.
- Dependency constructor parameters must make role boundaries visible.
- Diagnostic failures must be visible, even when the diagnostic path is degraded and does not change the primary operation result.

## Related Cases

- `TS-042`: Host install/uninstall state 계약 부족으로 cleanup/reinstall이 막힘
- `TS-043`: Runtime workflow StateMachine과 계층 경계 정리가 필요함
