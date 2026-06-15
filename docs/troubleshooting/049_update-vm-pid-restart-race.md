# 049 Update VM stop follows launchd-restarted pid

> ID: TS-049  
> Category: Update / VM lifecycle  
> Owner: macOS runtime  
> Status: resolved

## Symptoms

Update apply enters `stop-runtime-services`, guest shutdown preparation completes, but Host waits for VM stop until the 900s timeout.

Observed on 2026-06-04:

```text
guest update shutdown result ready message=Guest poweroff requested after services stopped and filesystems synced.
waiting for VM process to exit after guest poweroff request
step=stop-runtime-services status=failed
bundle apply failed; rolling back error=VM process did not stop within 900s pid=93046
step=rollback-stop-runtime-services status=failed
bundle apply rollback failed error=VM process did not stop within 900s pid=2579
```

Runtime may later recover and pass health, but the bundle apply itself failed and rollback may also record a failed stop step.

Observed again on 2026-06-15 with a narrower signature:

```text
guest update shutdown result ready message=Guest services are stopped and filesystems synced. Guest poweroff request is being issued.
guest update shutdown ready version=0.1.15-dev
stopping runtime services after guest poweroff request
waiting
```

At the same time, `prepare-update-shutdown-result.json` had `status=ready` and `shutdownPhase=poweroff-ready`, the originally captured VM pid was gone, and `launchctl print system/ai.tirosh.vitalserver.helper.vm` showed a replacement `vitalserver-vm start` pid.

## Impact

- Update spends up to 900s waiting on the wrong VM process.
- Rollback can repeat the same wait and take another 900s.
- Proxy, watchdog, and guest-log-sync can remain down until cleanup/startup runs.
- Runtime health after cleanup can look healthy even though the update operation failed.

## Cause

Host waited on the pid currently stored in `vitalserver-vm.pid`.

During update, guest correctly reported `shutdownPhase=poweroff-requested`. In newer bundles the equivalent handoff may be `shutdownPhase=poweroff-ready`, written immediately after final sync and before requesting OS poweroff. The VM process then exited, but launchd `keepalive | runatload` started a replacement VM and rewrote the pid file. Host then followed the replacement pid instead of the VM process that was active when the guest shutdown request was issued.

The same issue existed in direct stop paths: `requestStopAndWait` signaled one pid, then `waitUntilStopped` could re-read the pid file and follow a newly written pid.

A later regression kept the same shape at a different boundary. The update post-poweroff path called a helper named `unloadAndWaitIfLoaded`, but that helper internally called `stopIfLoaded`. `stopIfLoaded` runs the normal VM `prepareForStop` hook, which reads the current pid file and sends SIGTERM before launchd bootout. If launchd has already respawned the VM service after the guest poweroff handoff, update shutdown can start waiting on the replacement VM process instead of simply unloading the launchd job.

## Fix

Host now captures the running VM pid before writing the guest update shutdown request and passes that explicit pid into the post-poweroff stop path.

`ProcessState` now waits for the observed pid that it was asked to stop or verify. If the pid file changes while waiting:

- the original observed pid remains the stop target,
- the replacement pid file is left intact,
- timeout errors name the original observed pid,
- missing, invalid, stale, and read-failed pid states remain distinct.

The update post-poweroff launchd cleanup now calls `unloadIfLoaded` directly. This keeps the normal VM stop path unchanged, but prevents the update poweroff path from invoking `prepareForStop` on a launchd-respawned replacement VM.

## Checks

Look for the signature:

```sh
rg -n "VM process did not stop within 900s|pid file changed while waiting for observed VM process exit" \
  "/Library/Application Support/VitalServerHelper/status/runtime-events.jsonl" \
  "/private/tmp/tirosh-vitalserver-manager-command.log"
```

For the post-poweroff unload regression, also check:

```sh
rg -n "stopping runtime services after guest poweroff request|guest update shutdown ready|waiting$" \
  "/private/tmp/tirosh-vitalserver-manager-command.log"

cat "/Library/Application Support/VitalServerHelper/vm/data/run/prepare-update-shutdown-result.json"
launchctl print system/ai.tirosh.vitalserver.helper.vm
```

Confirm the installed runtime state with a host-side health check, not only the status JSON:

```sh
make dist/installed/health
```

In sandboxed tooling, localhost proxy checks can be misleading. Verify `http://127.0.0.1:80/ready` from the host environment when checking the actual proxy.

## Prevention

- Stop waits must target an explicit process identity captured before the side effect that can change it.
- Do not follow mutable pid-file state after a stop request has selected its process.
- Do not remove a pid file that has been rewritten for a replacement process.
- After an explicit guest `poweroff-ready` or `poweroff-requested` handoff, Host cleanup should unload launchd state; it must not re-enter the normal VM graceful-stop preparation path.
- Do not treat recovered runtime health as update success; operation status and command result are separate states.

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-025`: update 후 VM disk attachment가 invalid로 실패
- `TS-029`: update 중 Host가 Guest shutdown 상태를 추정함
- `TS-047`: Guest log sync service만 Stopped로 남음
