# Golden rootfs cleanup reports stopped while launcher still runs

> ID: TS-133
> Category: Packaging / Local development / VM lifecycle
> Owner: devtools VM stop wait
> Status: resolved

## Symptoms

`make dist/pkg/dev/compile` or `make dist/dmg/dev/compile` completes the Guest rootfs proof but
stops before creating the package:

```text
Air-gapped rootfs marker is ready:
  manifestStatus=passed
VM lifecycle is stopped
error: VM launcher process is still running for VM_HOME; refusing to continue with mutable runtime files
```

## Cause

The stop wait returned as soon as SQLite lifecycle state became `stopped`. The launcher process
could still need a short interval to exit after persisting that state. The following package
step correctly refused to mutate or compress runtime files while that PID still existed, so the
compile failed even though the process exited normally moments later.

Lifecycle state and process state have different owners. A `stopped` lifecycle document does not
mean that the Host process has already exited.

## Fix

`macos-runtime-wait-stopped` now waits until the launcher process is absent. When lifecycle is
already `stopped` but a PID remains, it keeps waiting and reports both states in timeout evidence.
It does not infer process exit from the lifecycle document and does not turn a timeout into
success.

## Checks

```sh
.venv/bin/vitalserver-devtools macos-runtime-wait-stopped \
  --vm-home .tmp/vitalserver-vm-golden \
  --timeout 30

.venv/bin/vitalserver-devtools macos-runtime-require-no-running \
  --vm-home .tmp/vitalserver-vm-golden
```

Both commands must pass before rootfs compression or package assembly starts.

## Prevention

- Wait contracts that protect mutable runtime files must observe Host process absence explicitly.
- Lifecycle documents must not be used as a fallback for process state.
- Package compile tests must cover `lifecycle=stopped` while the launcher PID remains briefly.

## Related Cases

- [TS-069 Golden rootfs stale proof negative validation](069_golden-rootfs-stale-proof-negative-validation.md)
- [TS-091 Golden rootfs cleanup wait timeout](091_golden-rootfs-cleanup-timeout.md)
- [TS-132 Golden rootfs launcher Host settings SQLite](132_golden-rootfs-launcher-missing-host-settings-sqlite.md)
