# Host install/uninstall state contract gap

> ID: TS-042
> Category: Packaging / Uninstall / Runtime health
> Owner: macOS runtime HostCLI / Packaging
> Status: implemented

## Symptoms

- Clean uninstall starts, but the next pkg install is blocked by fresh-install preflight.
- `preinstall` reports remaining artifacts such as:
  - `existing install artifact found: /Library/Application Support/TiroshVitalServer`
  - `existing launch daemon plist found: /Library/LaunchDaemons/com.tirosh.vitalserver-*.plist`
  - `existing package receipt found: com.tirosh.vitalserver.vm`
  - `existing launchd service is loaded: com.tirosh.vitalserver-vm`
  - `existing host proxy port listener found: port=...`
- `postinstall` failure cleanup can log `postinstall failure cleanup completed`, but product root, runtime tools, launchd plists, package receipts, or VM/proxy processes can still remain.
- Clean uninstall can spend a long time waiting for VM stop when the guest is kernel-panicked or the VM process is stuck.
- Users see repeated install/uninstall attempts fail even though they already ran a clean uninstall.

## Impact

- Fresh pkg install remains correctly blocked because the machine is not actually clean.
- The visible failure can look like an installer problem, but the root issue is incomplete Host-owned cleanup state.
- Runtime files, receipts, launchd services, and processes can disagree with each other, making manual recovery risky.
- If cleanup failure is hidden, operators may retry install while an uninstall or VM stop is still in progress.

## Cause

This is a Host state ownership and contract gap.

AGENTS.md says Host owns runtime/process/filesystem state. That state must be explicit and typed enough to act on. In the current flow, several Host states are still represented by command output, shell cleanup, or absence of files instead of a clear Host-owned contract.

Confirmed boundary violations:

- `launchctl bootout` request is treated too close to `service stopped`. These are different states.
- `launchctl print` failure can collapse into `notLoaded`, which hides permission, command, or domain failures.
- VM process stop uses pid/probe checks, but uninstall does not persist a typed `blocked` state with pid, timeout, and reason before exiting.
- `postinstall` failure cleanup performs `bootout`, process probes, `rm -rf`, and `pkgutil --forget` in shell with `set +e` and ignored failures.
- `pkgutil --forget` and cleanup failures can be hidden, leaving receipts or files behind while logs imply cleanup finished.
- Config decode failure for configured vital files directory can fall back to the default path, even though uninstall deletion scope is a state boundary.
- Preinstall reports blockers but does not have a single Host-owned preflight result contract that can distinguish product root, receipt, process, launchd, and port blockers.

The guest kernel panic or stuck VM is often the trigger, not the root cause. The root cause is that Host-owned install/uninstall states are not expressed as one explicit lifecycle contract.

## Checks

Use these checks to separate the blockers. Do not infer cleanup success from one missing file or one command alone.

```sh
tail -n 250 "/private/tmp/tirosh-vitalserver-uninstall.log"
tail -n 250 "/private/tmp/tirosh-vitalserver-postinstall-failure.log"
tail -n 250 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.err.log"

ls -la "/Library/Application Support/TiroshVitalServer"
ls -la "/Library/LaunchDaemons" | grep 'com.tirosh.vitalserver' || true
ls -la /usr/local/bin | grep 'vitalserver' || true

pkgutil --pkg-info com.tirosh.vitalserver.vm
pkgutil --pkg-info com.tirosh.vitalserver

launchctl print system/com.tirosh.vitalserver-vm
launchctl print system/com.tirosh.vitalserver-proxy
launchctl print system/com.tirosh.vitalserver-guest-log-sync
launchctl print system/com.tirosh.vitalserver-watchdog
launchctl print system/com.tirosh.vitalserver-sleep-prevention

lsof -nP -iTCP:80 -sTCP:LISTEN
pgrep -af 'vitalserver-vm|vitalserver-proxy-run|TiroshVitalServer'
```

If the uninstall log contains `VM process did not stop within ...`, treat the cleanup as blocked until the process, launchd state, and product root are checked separately.

## Actions

1. Preserve logs before manual cleanup:

   ```sh
   cp -p "/private/tmp/tirosh-vitalserver-uninstall.log" /tmp/tirosh-vitalserver-uninstall.last.log 2>/dev/null || true
   cp -p "/private/tmp/tirosh-vitalserver-postinstall-failure.log" /tmp/tirosh-vitalserver-postinstall-failure.last.log 2>/dev/null || true
   ```

2. Identify the concrete blocker reported by `preinstall` rather than deleting all possible paths blindly.

3. If VM process is still running or stuck, record pid, launchd label, and current lifecycle/status files before forcing cleanup.

4. If product root remains, inspect residual entries and open files first:

   ```sh
   find "/Library/Application Support/TiroshVitalServer" -maxdepth 3 -print
   lsof +D "/Library/Application Support/TiroshVitalServer"
   ```

5. Only after blockers are understood, perform targeted cleanup according to operator policy. Forced VM/process cleanup is destructive and should not be treated as a successful graceful uninstall.

## Prevention

- Add a Host-owned install/uninstall lifecycle contract, for example:
  - `installProvision.started`
  - `installProvision.completed`
  - `installCleanup.started`
  - `uninstall.started`
  - `uninstall.stopRequested`
  - `uninstall.serviceUnloaded`
  - `uninstall.vmProcessExited`
  - `uninstall.cleanupBlocked`
  - `uninstall.filesRemoved`
  - `uninstall.receiptsForgotten`
  - `uninstall.completed`
  - `uninstall.failed`
- Model launchd and process state as typed values, not boolean loaded/not-loaded probes.
- Move postinstall failure cleanup out of shell and into a Swift HostCLI use case.
- Keep shell scripts as root/logging/entrypoint wrappers only.
- Make `pkgutil --forget`, launchd read/stop, file removal, and config decode failures visible in the contract.
- Make preinstall a blocker reporter, not a cleanup or state inference boundary.
- Add focused tests for:
  - launchd read failure vs unloaded
  - VM stop timeout producing `cleanupBlocked`
  - receipt forget failure staying visible
  - postinstall failure cleanup not reporting success when artifacts remain
  - invalid runtime config blocking uninstall deletion-scope decisions

## Implementation Result

Implemented on `feature/issue-44`.

- Host launchd state now distinguishes `loaded`, `notLoaded`, `readFailed`, and `permissionDenied`.
- VM process state now distinguishes missing pid file, invalid pid file, running pid, stale pid, stopped, signal failure, read failure, and stop timeout.
- Missing pid file is now a cleanup blocker unless a stop wait has already observed a concrete pid and then observed that process exit. `pidFileMissing` is no longer treated as `stopped`.
- Package receipt state now distinguishes `present`, `absent`, `readFailed`, and `forgetFailed`.
- Fresh-install state now distinguishes install settings defaulted/loaded/readFailed/invalid, install artifact present/absent/inspectFailed, package receipt present/absent/readFailed, launchd state, and host proxy port clear/occupied/inspectFailed.
- Core has uninstall and fresh-install readiness policies that consume explicit Host-owned states and return blockers.
- Uninstall writes `/private/tmp/tirosh-vitalserver-uninstall-state.json` as workflow diagnostics/export evidence, not as a Runtime Control current state owner.
- Uninstall now records separate lifecycle states for service stop blocked, file removal blocked, receipt forget blocked, failed, and completed.
- Uninstall now re-reads service/process state after stop returns and blocks file removal unless stopped state is explicit. A missing pid file after a successful service stop is still a blocker unless a concrete pid was observed and exited.
- Clean uninstall verifies cleanup artifact states before forgetting receipts; command success is not treated as proof that files disappeared.
- `pkgutil --forget` failures are no longer ignored, and a successful forget command is followed by receipt state verification before uninstall can write `completed`.
- Config read failure for the vital files directory no longer falls back into a deletion-scope decision. Default product cleanup continues, but external vital files cleanup is skipped and logged when the configured external path cannot be read.
- `postinstall` failure cleanup no longer runs shell `launchctl`, process probes, `rm -rf`, or `pkgutil --forget`; it delegates to HostCLI `runtime uninstall --clean` and logs `blocked` when that use case fails.
- `preinstall` no longer runs shell `launchctl`, `pkgutil`, `lsof`, `plutil`, or filesystem state decisions. It delegates to packaged HostCLI `runtime preinstall-check`, which prints a `RuntimeFreshInstallPreflightDocument`.

Verification:

- `swift test --filter HostCLITests`
- `swift test --filter 'ContractsTests|CoreTests|HostInfrastructureTests'`
- focused Host install/uninstall state tests covering TS-042
- `uv run pytest packages/vitalserver-devtools/tests/unit/test_packaging_templates.py`
- `git diff --check`

Known test-suite note:

- Full `swift test` currently reaches RuntimeControl API stream tests and exits with xctest signal 11. `RuntimeControlAPITests.RuntimeControlAPITests/testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents` passes in isolation, and the TS-042 affected targets pass separately.

Remaining follow-up:

- Consider a dedicated HostCLI `cleanup-failed-install` command if failed-install cleanup needs behavior that differs from clean uninstall.

## Implementation Plan

Start from state ownership, not from additional cleanup behavior.

### 1. Declare State Owners

- Host owns launchd service state, VM process state, pid file state, filesystem artifact state, package receipt state, host proxy port listener state, and install/uninstall operation lifecycle state.
- Guest owns guest boot id, guest runtime state, guest HTTP/container/systemd state, update shutdown phase, and guest observability snapshots.
- Packaging shell owns root-entrypoint checks, log redirection, and HostCLI process invocation only.
- Consumers must not create state from probes, logs, filenames, or absence. They may only read explicit owner-provided state and use it as policy input or display data.

### 2. Add Host State Contracts First

Introduce typed Host state values before changing uninstall behavior.

```text
LaunchdServiceState
- loaded
- notLoaded
- readFailed(reason)
- permissionDenied(reason)

VMProcessState
- pidFileMissing
- pidFileInvalid(reason)
- running(pid)
- stopped
- stalePid(pid)
- signalFailed(pid, signal, errno)
- stopTimedOut(pid, timeoutSeconds)

PackageReceiptState
- present(identifier)
- absent(identifier)
- readFailed(identifier, reason)
- forgetFailed(identifier, reason)

InstallArtifactState
- present(path)
- absent(path)
- inspectFailed(path, reason)
```

`readFailed` is not `notLoaded`. `pidFileMissing` is not proof that the VM process is stopped. `absent` is not proof that uninstall completed.

### 3. Add Uninstall Lifecycle State

Uninstall is a Host-owned operation and must publish its own lifecycle.

```text
RuntimeUninstallState
- notStarted
- started
- redisBackupRequested
- redisBackupCompleted
- stopServicesRequested
- serviceStopBlocked(blockers)
- vmProcessStopBlocked(processState)
- filesRemovalStarted
- filesRemovalBlocked(residuals)
- receiptsForgetStarted
- receiptsForgetBlocked(receipts)
- completed
- failed(reason)
```

`blocked`, `failed`, and `completed` must stay distinct. A stuck VM after kernel panic is a cleanup blocker until Host-owned process state says otherwise.

### 4. Put Decisions in Core Policies

Core/domain policies must take explicit state as input and return decisions. They must not run `launchctl`, inspect files, parse logs, or infer state from missing data.

```text
UninstallReadinessPolicy
input:
- launchd states
- VM process state
- artifact states
- receipt states

output:
- canRemoveFiles
- blocked(blockers)
- failed(reason)
```

### 5. Make Use Cases Orchestrate Explicit State

`RuntimeUninstallRunner` should:

```text
write uninstall.started
read Host-owned states
request service stop
read service/process states again
if blocked:
  write uninstall.cleanupBlocked(blockers)
  exit non-zero

remove files
verify artifact states
if residual:
  write uninstall.filesRemovalBlocked(residuals)
  exit non-zero

forget receipts
verify receipt states
if receipt remains or read failed:
  write uninstall.receiptsForgetBlocked(receipts)
  exit non-zero

write uninstall.completed
```

### 6. Keep Shell Thin

Move `postinstall` failure cleanup into a Swift HostCLI use case. Shell should not perform runtime state decisions with `launchctl`, `pgrep`, `lsof`, `rm -rf`, or `pkgutil`.

```sh
VITALSERVER_VM_HOME=... vitalserver-vm runtime install-provision
```

If failed-install cleanup is needed, shell should delegate:

```sh
VITALSERVER_VM_HOME=... vitalserver-vm runtime cleanup-failed-install
```

### 7. Make Preinstall a Blocker Reporter

Preinstall may report blockers, but shell must not inspect Host state, clean up, or infer success. Shell invokes the HostCLI preflight use case and relays its result.

```text
RuntimeFreshInstallPreflightDocument
- passed
- proxyPort
- blockers
- settingsState
- artifactStates
- serviceStates
- packageReceiptStates
- proxyPortState
```

`inspectFailed`, `readFailed`, `invalid`, `unknown`, and `occupied` are not `passed`.

### 8. Add Tests Around Fallback Boundaries

- `testLaunchdReadFailureDoesNotBecomeNotLoaded`
- `testMissingPidFileDoesNotDeclareUninstallCompleted`
- `testVMStopTimeoutWritesCleanupBlocked`
- `testReceiptForgetFailureDoesNotCompleteUninstall`
- `testConfigDecodeFailureDoesNotFallbackDeletionScope`
- `testPostinstallCleanupDoesNotReportCompletedWhenArtifactsRemain`

Recommended implementation order:

1. Add Host state contracts for launchd, process, receipt, and artifacts.
2. Add Core policy that computes uninstall blockers from explicit Host state.
3. Update `RuntimeUninstallRunner` to publish lifecycle state and use the policy.
4. Move preinstall blocker reporting to Swift preflight.
5. Move postinstall failure cleanup to Swift cleanup use case.
6. Update this TS entry with implemented tests and release status.

## Operational Notes

- Fresh install preflight failure is correct when artifacts remain. The problem is not that preinstall blocks; the problem is that uninstall/postinstall cleanup did not expose why the machine is still dirty.
- Guest-owned observability can explain why VM shutdown failed, but Host-owned process/filesystem/receipt state must decide cleanup readiness.
- Do not use guest logs, VM log markers, or absence of runtime files to claim Host cleanup success.
- This case overlaps with TS-037, but TS-037 focuses on stale operation/recovery after clean uninstall. TS-042 focuses on the Host install/uninstall lifecycle contract itself.

## Related Cases

- [TS-024 pkg postinstall timeout/failure](024_pkg-postinstall-timeout.md)
- [TS-037 clean uninstall stale operation recovery](037_clean-uninstall-stale-operation-recovery.md)
- [TS-038 guest kernel panic watchdog restart loop](038_guest-kernel-panic-watchdog-restart-loop.md)
- [TS-039 AGENTS.md fallback audit](039_agents-compliance-fallback-audit.md)
- [TS-040 VM lifecycle stale after healthy boot](040_vm-lifecycle-stale-after-healthy-boot-log-export-gap.md)

## Follow-up

- 2026-06-02: issue #44 review found that install/uninstall failures are caused by Host-owned state contract gaps: stop request vs stopped state, shell cleanup hiding failures, boolean launchd state, and missing uninstall lifecycle/result state. Next implementation should start with Host install/uninstall contracts before adding more cleanup behavior.
