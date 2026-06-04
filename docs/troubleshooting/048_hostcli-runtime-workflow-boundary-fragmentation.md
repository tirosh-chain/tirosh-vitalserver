# HostCLI runtime workflow boundary fragmentation

> ID: TS-048  
> Category: Architecture / Runtime workflow / macOS runtime  
> Owner: macOS runtime application layer  
> Status: active

## Symptoms

- Runtime service restart, pkg install, update, rollback, repair, and health wait changes frequently touch many files across `Core`, `RuntimeWorkflow`, `HostCLI`, UI, tests, and docs.
- A small operational rule change, such as requiring `guest-log-sync` after runtime restart, needs edits in service policy, service controller, lifecycle workflow, install/update/rollback/repair paths, status document building, UI labels, and multiple tests.
- HostCLI runtime files still contain a mixture of command entrypoint composition, application usecase orchestration, workflow sequencing, launchd/process/filesystem effects, and status reporting.
- Release issues appear as different symptoms, but often share the same structural cause: an operation does not have one explicit owner for required state, effects, and completion criteria.
- The codebase has useful targets and policies, but contributors still need to inspect several layers to answer simple questions such as "who owns restarting this service?" or "what proves this workflow is complete?"

## Impact

- Changes have a wide blast radius and are hard to review.
- Release hardening becomes reactive because every field failure can require a new cross-layer patch.
- Race conditions are easier to introduce when lifecycle state, launchd state, VM state, disk state, and UI status are coordinated from multiple places.
- Recovery and update behavior can look correct in one path while another path misses the same required side effect.
- Tests tend to verify the latest bug path instead of enforcing a stable architectural contract.

## Cause

TS-043 introduced a useful `RuntimeWorkflow` boundary, but the current runtime implementation still lacks a stable application structure above the pure domain policies.

The current weak point is not "missing services objects." The weak point is that the responsibilities below are not consistently represented as separate, named layers:

```text
Bootstrap / composition root
  Wires concrete adapters and usecases.

Interface adapters
  Own launchd, process, filesystem, pkgutil, VM runner, guest HTTP, and log effects.

Application usecases
  Own one user-visible operation contract such as install, update, repair, uninstall,
  service restart, service health refresh, or disk repair.

Workflow
  Own operation order, persisted operation state, progress events, and completion gates.

Domain / Core
  Own pure policies, state machines, transition guards, invariants, and decisions.

Contracts
  Own explicit documents, commands, events, state values, and failure shapes.
```

When these roles are mixed inside `HostCLI/Runtime`, the code can still work, but the architecture stops localizing change. A new operational requirement then spreads through multiple workflow branches instead of being added to one usecase contract and one domain decision point.

## Checks

Use these checks before and during the refactor.

```sh
rg -n "RuntimeLifecycle|RuntimeServiceController|RuntimeServiceRestartPolicy|waitForHealth|restart.*Service|launchctl|pkgutil|FileManager|Process\\(" \
  apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime \
  apps/vitalserver-macos-runtime/Sources/RuntimeWorkflow \
  apps/vitalserver-macos-runtime/Sources/Core

rg -n "struct .*UseCase|final class .*UseCase|protocol .*Port|Workflow|TransitionPolicy|StateMachine" \
  apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime \
  apps/vitalserver-macos-runtime/Sources/RuntimeWorkflow \
  apps/vitalserver-macos-runtime/Sources/Core

rg -n "^import HostInfrastructure|^import HostCLI|^import MacHostRuntimeAdapter|^import MacRuntimeControlApp" \
  apps/vitalserver-macos-runtime/Sources/Core \
  apps/vitalserver-macos-runtime/Sources/RuntimeWorkflow
```

Review smell:

- `HostCLI` decides operation transitions instead of delegating to Core or RuntimeWorkflow.
- A workflow calls `launchctl`, `pkgutil`, `FileManager`, or process APIs directly instead of using an injected port.
- UI or status builders infer service state instead of formatting explicit provider state.
- One required runtime service is listed in more than one unrelated place without a single policy or contract explaining why.
- A successful command result is treated as proof of final state without a follow-up explicit observation.

## Actions

Proceed in small, behavior-preserving slices. Do not start with a broad folder rewrite.

1. Define the runtime application map.

   Record each operation as a usecase with an owner, input contract, output contract, required ports, workflow state, and completion condition.

   Initial usecases:

   ```text
   InstallRuntimeUseCase
   ApplyRuntimeUpdateUseCase
   RollbackRuntimeUpdateUseCase
   RepairRuntimeDatastoreUseCase
   RepairRuntimeVMDiskUseCase
   ControlRuntimeServicesUseCase
   RefreshRuntimeHealthUseCase
   UninstallRuntimeUseCase
   ```

2. Stabilize service lifecycle first.

   Service lifecycle has caused repeated release-facing symptoms and is narrow enough to extract safely.

   Target shape:

   ```text
   Core
     RuntimeServiceRestartPolicy
     RuntimeRequiredServicePolicy

   RuntimeWorkflow / Application
     ControlRuntimeServicesUseCase
     RuntimeServiceLifecycleWorkflow
     RuntimeServiceLifecyclePorts

   HostCLI / adapters
     LaunchdRuntimeServiceAdapter
     RuntimeServiceStatusReader
     RuntimeLifecycle command composition
   ```

   The usecase should own "what operation is being requested." Core policy should own "which services are required." Adapters should own "how launchd is called."

3. Move completion gates into workflow contracts.

   Every operation that stops, starts, updates, repairs, or removes runtime state must name the explicit observations required before completion.

   Examples:

   - service restart is complete only after required services are explicitly observed loaded or running
   - update stop phase is complete only after VM lifecycle is explicitly stopped, not merely after a stop command returns
   - disk repair is complete only after repair result and disk attachability are explicitly observed
   - uninstall cleanup is complete only after artifacts and receipts are explicitly observed absent

4. Shrink `RuntimeLifecycle`.

   Keep it as a composition facade and command-facing coordinator. It may wire dependencies and call usecases. It should not own transition rules, completion gates, or direct external effects.

5. Add boundary tests before moving more behavior.

   Required tests:

   - `Core` does not import outer layers.
   - `RuntimeWorkflow` does not import host infrastructure, UI, or CLI layers.
   - usecases expose explicit input/output contracts.
   - required service policy has one tested source of truth.
   - command success cannot be used as final state without explicit observation where the operation depends on external state.

6. Migrate one operation at a time.

   Recommended order:

   ```text
   ControlRuntimeServicesUseCase
   RefreshRuntimeHealthUseCase
   RepairRuntimeVMDiskUseCase
   ApplyRuntimeUpdateUseCase
   RollbackRuntimeUpdateUseCase
   InstallRuntimeUseCase
   UninstallRuntimeUseCase
   ```

   This order starts with the current service-status failures, then moves toward higher-risk update and disk behavior.

## Prevention

- New runtime behavior must enter through a named usecase, not through scattered HostCLI conditionals.
- A usecase must declare required ports and completion observations before implementation.
- Domain decisions must remain pure and testable.
- Adapters must return explicit typed results and failures; they must not convert dependency failure into empty/default success.
- UI must display explicit state and must not create operational state.
- Important release failures must add or update a troubleshooting entry with symptom, cause, fix direction, and prevention rule.

## Related Cases

- `TS-030`: Runtime state inference
- `TS-032`: macOS runtime explicit responsibility review
- `TS-039`: AGENTS.md fallback audit
- `TS-043`: RuntimeWorkflow target and layer boundary cleanup
- `TS-045`: Runtime install workflow state machine parity
- `TS-047`: Guest log sync service remains stopped after runtime restart

## Follow-up

- 2026-06-04: Created after repeated install, update, power-off, disk repair, launchd, and guest log sync failures showed that the remaining issue is structural fragmentation around HostCLI runtime workflows, not a single missing branch.
- 2026-06-05: Started Slice 1 for service lifecycle stabilization. Added the `Application` target with `ControlRuntimeServicesUseCase` and service lifecycle ports, moved service lifecycle command sequencing into `RuntimeWorkflow/ServiceLifecycle`, and introduced `RuntimeRequiredServicePolicy` as the required-service source of truth. HostCLI now wires concrete launchd/status observations into the workflow, while the workflow requires explicit service loaded/stopped observations before reporting service start/repair/stop completion. TS-048 remains active; next slice is runtime health refresh boundary cleanup.
- 2026-06-05: Completed Slice 2 for runtime health refresh. Added `RefreshRuntimeHealthUseCase` and `RuntimeWorkflow/HealthRefresh` so health snapshot classification, status message selection, and observed-event message selection no longer live in HostCLI. HostCLI now prints command output, maps explicit workflow health failures to the CLI error, and keeps Host-owned snapshot/status/event adapters wired at the boundary. Moved `RuntimeFailureReasonText` into Core so health workflows share one tested formatter. TS-048 remains active; next slice is health wait workflow boundary cleanup.
- 2026-06-05: Completed Slice 3 for runtime health wait. Added `WaitForRuntimeHealthUseCase` and `RuntimeWorkflow/HealthWait` so required service observations, wait polling, progress status, early failure, timeout, and healthy completion logging are no longer owned by HostCLI. HostCLI now wires launchd state, snapshots, status best-effort writes, sleep, and logging at the adapter boundary, then maps explicit workflow operation failure to the CLI runtime health failure. TS-048 remains active; next slice should target VM disk repair or update stop completion gates.
- 2026-06-05: Completed Slice 4 for VM disk repair. Moved VM disk repair orchestration into `RuntimeWorkflow/VMDiskRepair`, with HostCLI now providing command paths and concrete filesystem/process/service/status adapters at composition time. Added a replacement disk completion gate so repair does not restart services unless the replacement VM disk is explicitly present and at least the expected target size. TS-048 remains active; next slice should target update stop completion gates.
- 2026-06-05: Completed Slice 5 for apply-bundle step execution. Moved `RuntimeApplyBundleStepExecutor` into `RuntimeWorkflow/ApplyBundle`, so update stop sequencing, rootfs replacement, artifact/migration dispatch, service restart, activation, and health-wait step routing are no longer owned by HostCLI. Added workflow tests that keep direct stop distinct from guest-poweroff stop and prove guest shutdown preparation is cleared even when the observed VM stop gate fails. TS-048 remains active; next slice should target the broader apply-bundle workflow facade or rollback step execution.
- 2026-06-05: Completed Slice 6 for rollback step execution. Moved `RuntimeRollbackStepExecutor` into `RuntimeWorkflow/Rollback`, so rollback stop, rootfs restore, runtime-version restore, artifact restore, service restart, and health-wait step routing no longer depend on HostCLI types. Added RuntimeWorkflow tests that preserve artifact restore order, keep missing backup rootfs as an explicit failure, and reject non-rollback steps at the workflow boundary. TS-048 remains active; next slice should target the broader rollback workflow facade or rollback preflight boundary cleanup.
- 2026-06-05: Completed Slice 7 for rollback plan execution. Moved `RuntimeRollbackRunner` into `RuntimeWorkflow/Rollback`, so rollback plan selection, started/completed/failed progress events, recovering/healthy status writes, and preserved VM disk logging are no longer owned by HostCLI. Kept CLI command parsing outside RuntimeWorkflow by making the runner generic over the command input and requiring explicit preflight preparation through a port. TS-048 remains active; next slice should target rollback preflight or the broader rollback workflow facade.
- 2026-06-05: Completed Slice 8 for rollback preflight. Moved `BackupManifest` and `RuntimeRollbackCommand` into `Contracts`, then moved `RuntimeRollbackPreflightRunner` into `RuntimeWorkflow/Rollback`. Rollback backup selection, manifest-declared rootfs restore detection, missing backup directory failure, missing backup rootfs failure, and explicit restart policy capture are now workflow-level behavior with HostCLI supplying filesystem and manifest loading adapters. TS-048 remains active; next slice should target the rollback workflow facade.
- 2026-06-05: Completed Slice 9 for the rollback workflow facade. Moved `RuntimeRollbackWorkflow`, context, and operations into `RuntimeWorkflow/Rollback`, with HostCLI now only composing filesystem, launchd, service, status, and backup adapters. Added workflow-level integration tests for manifest loading, restart policy capture, rollback plan execution, step adapter dispatch, and missing manifest failure before side effects. Centralized rollback file names in `RuntimeFileNames`. TS-048 remains active; next slice should target the apply-bundle workflow facade or update preflight boundary.
- 2026-06-05: Completed Slice 10 for apply-bundle plan execution. Moved `RuntimeApplyBundleRunner` and `RuntimeWorkflowStatusReporter` into `RuntimeWorkflow`, so apply plan execution, progress publication, preflight failure status, rollback/degraded/critical handling, best-effort service restart after rollback failure, and cleanup best-effort logging are workflow-level behavior. HostCLI still owns bundle verification, staging, update preflight adapters, and concrete status/progress writers. TS-048 remains active; next slice should target apply-bundle preflight or the broader bundle workflow facade.
- 2026-06-05: Completed Slice 11 for apply-bundle preflight. Moved `RuntimeApplyBundlePreflightRunner` into `RuntimeWorkflow/ApplyBundle` and moved `RuntimeGuestCapabilityRequirement` into `Contracts`. Apply update staging input, manifest loading, compatibility checks, rootfs replacement detection, storage requirement calculation, explicit restart policy capture, guest disk-health gate, guest capability gates, and managed backup creation are now workflow-level behavior with HostCLI supplying concrete file, storage, health, guest, and backup adapters. TS-048 remains active; next slice should target the broader apply-bundle workflow facade.
- 2026-06-05: Completed Slice 12 for the apply-bundle workflow facade. Added `RuntimeApplyBundleWorkflow` in `RuntimeWorkflow/ApplyBundle` so apply log preparation, runner/preflight/step-executor composition, rollback/service/status wiring, and final mutable VM disk preservation logging are owned by the workflow boundary. HostCLI now delegates apply to that workflow and only supplies bundle staging/verification helpers plus concrete filesystem, service, guest, status, and artifact adapters. TS-048 remains active; next slice should separate bundle verification/staging or move the install workflow boundary.
- 2026-06-05: Completed Slice 13 for apply-bundle migration execution. Moved `RuntimeMigrationRunner` into `RuntimeWorkflow/ApplyBundle`, so migration ordering, executable-file gating, migration execution dispatch, and empty migration logging are no longer HostCLI-owned. HostCLI now supplies executable checks and command execution ports, while the workflow reports a typed workflow failure when a manifest-declared migration is not executable. TS-048 remains active; next slice should target artifact replacement or install step execution.
- 2026-06-05: Completed Slice 14 for apply-bundle artifact replacement. Moved `RuntimeArtifactReplacer` and artifact replacement destination/rule contracts into `RuntimeWorkflow/ApplyBundle`, so artifact payload validation, tar entry safety checks, replacement/extraction order, cleanup logging, and unsupported artifact failures are workflow-level behavior. HostCLI now supplies product-specific roots, runtime-tool allowlists, tar command, filesystem, and process ports explicitly. TS-048 remains active; next slice should target bundle verification/staging or install step execution.
- 2026-06-05: Completed Slice 15 for install step execution. Moved `RuntimeInstallStepExecutor` into `RuntimeWorkflow/Install` as a generic workflow step dispatcher, so install plan step routing and unsupported install-step failure no longer depend on HostCLI. HostCLI keeps ownership of concrete `InstallSettings` loading and maps those settings to an explicit `RuntimeServiceRestartPolicy` through the composition boundary. TS-048 remains active; next slice should target install directory/runtime effects or bundle verification/staging.
- 2026-06-05: Completed Slice 16 for guest update activation. Moved `RuntimeGuestActivationRunner` and `RuntimeGuestActivationWorkflow` into `RuntimeWorkflow/GuestActivation`, so guest deploy detection, activation request preparation, VM service start gate, result waiting, progress reporting, and activation failure mapping are no longer HostCLI-owned. HostCLI now supplies guest gateway effects, service observations, timestamps, status writers, polling sleep, and the activation wait timeout explicitly. TS-048 remains active; next slice should target datastore repair workflow or bundle verification/staging.
- 2026-06-05: Completed Slice 17 for datastore repair. Moved `RuntimeDatastoreRepairRunner`, `RuntimeDatastoreRepairResultWaiter`, and `RuntimeDatastoreRepairWorkflow` into `RuntimeWorkflow/DatastoreRepair`, so repair request preparation, VM start/restart selection, guest result waiting, proxy/watchdog restart, runtime health gate, progress status, and failure mapping are no longer HostCLI-owned. HostCLI now supplies guest gateway effects, launchd service effects, status writers, polling sleep, and the datastore repair wait timeout explicitly. TS-048 remains active; next slice should target install directory/runtime effects or bundle verification/staging.
- 2026-06-05: Completed Slice 18 for install directory preparation. Moved `RuntimeInstallDirectoryPreparer` into `RuntimeWorkflow/Install` as a generic preparation workflow, so install directory creation and stale guest-run document cleanup are no longer HostCLI-owned. HostCLI now supplies the concrete installed path list, custom VitalFiles path extraction from `InstallSettings`, and file-store create/existence/remove ports explicitly. TS-048 remains active; next slice should target remaining install runtime effects or bundle verification/staging.
- 2026-06-05: Completed Slice 19 for guest update shutdown preparation. Moved `RuntimeGuestShutdownRunner` and `RuntimeGuestShutdownWorkflow` into `RuntimeWorkflow/GuestShutdown`, so update shutdown request preparation, guest result waiting, progress reporting, timeout handling, and guest-reported failure mapping are no longer HostCLI-owned. HostCLI now supplies guest gateway effects, status writer, polling sleep, request metadata, and the shutdown wait timeout explicitly. TS-048 remains active; next slice should target remaining install runtime effects or bundle verification/staging.
- 2026-06-05: Completed Slice 20 for cloud-init seed creation. Moved `RuntimeCloudInitSeedWriter` into `RuntimeWorkflow/Install` with explicit seed context and filesystem/command/instance-id ports, so seed directory replacement, metadata/user-data generation, stale ISO removal, and ISO build dispatch are no longer HostCLI-owned. HostCLI now supplies concrete runtime paths, hdiutil path, file-store operations, and instance-id generation explicitly. TS-048 remains active; next slice should target remaining install VM provisioning, runtime config, permissions, or service start effects.
- 2026-06-05: Completed Slice 21 for install VM disk provisioning. Added `RuntimeInstallVMDiskProvisioner` in `RuntimeWorkflow/Install`, so rootfs-based VM disk creation, stale temporary disk cleanup, free-space gate calculation, disk move, creation logging, missing-rootfs failure, and final truncate command dispatch are no longer HostCLI-owned. HostCLI now supplies concrete rootfs/vmDisk paths, gunzip/truncate paths, file-store ports, storage guard, and logging explicitly. TS-048 remains active; next slice should target install runtime config, permissions, service start, or start-on-boot effects.
- 2026-06-05: Completed Slice 22 for install service start. Added `RuntimeInstallServiceStarter` in `RuntimeWorkflow/Install`, so start-after-install gating, sleep-prevention start, runtime service start order, and proxy-port cleanup before proxy start are no longer HostCLI-owned. HostCLI now supplies launchd start, proxy cleanup, and logging ports explicitly. TS-048 remains active; next slice should target install runtime config, permissions, or start-on-boot effects.
- 2026-06-05: Completed Slice 23 for install start-on-boot policy. Added `RuntimeInstallStartOnBootPolicyApplier` in `RuntimeWorkflow/Install`, so persisted start-on-boot setting and sleep-prevention launchd enable/disable decision are no longer HostCLI-owned. HostCLI now supplies launchctl path, persisted policy writer, and command execution port explicitly. TS-048 remains active; next slice should target install runtime config or permission effects.
- 2026-06-05: Completed Slice 24 for install permission configuration. Added `RuntimeInstallPermissionConfigurator` in `RuntimeWorkflow/Install`, so runtime/nginx ownership, proxy launchd port injection, and launch daemon plist chmod/chown ordering are no longer HostCLI-owned. HostCLI now supplies concrete paths, service plist list, command paths, and command execution port explicitly. TS-048 remains active; next slice should target install runtime config or bundle verification/staging.
- 2026-06-05: Completed Slice 25 for install settings cleanup. Added `RuntimeInstallSettingsCleaner` in `RuntimeWorkflow/Install`, so post-install settings removal is expressed as an explicit settings-file cleanup workflow instead of HostCLI inline file logic. HostCLI now supplies the default settings path and file-store existence/removal ports explicitly. TS-048 remains active; next slice should target install runtime config or bundle verification/staging.
- 2026-06-05: Completed Slice 26 for install VM runtime config mutation. Added generic `RuntimeInstallVMRuntimeConfigurator` in `RuntimeWorkflow/Install`, so required runtime directory creation, existing/default config selection, install settings mutation, shared-network bridge clearing, shared-directory/vital-files mapping, runtime-default application, encoding, and config write ordering are no longer HostCLI-owned. HostCLI keeps ownership of concrete `VMRuntimeConfig`, path constants, defaults, encoding, and file-store adapters through explicit ports. TS-048 remains active; next slice should target bundle verification/staging or fresh-install preflight boundaries.
- 2026-06-05: Completed Slice 27 for fresh-install preflight composition. Moved `RuntimeFreshInstallPreflightRunner` into `RuntimeWorkflow/Install`, so full-install preflight document assembly is now workflow-level behavior over explicit Host-provided settings, artifact, launchd service, package receipt, and proxy-port states. HostCLI keeps the concrete state readers for install settings files, filesystem artifact inspection, package receipts, launchd state, and `lsof` proxy-port checks. TS-048 remains active; next slice should target bundle verification/staging or remaining install executable/deploy environment effects.
- 2026-06-05: Completed Slice 28 for install executable preparation. Added `RuntimeInstallExecutablePreparer` in `RuntimeWorkflow/Install`, so installed executable chmod ordering is expressed as a workflow over explicit executable paths and a chmod command port instead of inline HostCLI install logic. HostCLI still owns the concrete binary/nginx paths and command executable. TS-048 remains active; next slice should target deploy environment writing or bundle verification/staging.
- 2026-06-05: Completed Slice 29 for bundle staging. Added `RuntimeBundleStager` in `RuntimeWorkflow/ApplyBundle`, so verified/materialized bundle staging now owns managed destination selection, destination cleanup, free-space gate ordering, copy dispatch, and staging completion logging through explicit filesystem/storage ports. HostCLI still owns bundle input materialization, archive validation, manifest loading, CLI printing, and concrete file-store adapters. TS-048 remains active; next slice should target bundle verification/materialization or deploy environment writing.
