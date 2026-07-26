# Golden rootfs preparation passes but compression requires lifecycle JSON

> ID: TS-138
> Category: Packaging / Host state persistence
> Owner: devtools golden rootfs compression
> Status: resolved

## Symptoms

`make dist/pkg/dev`, `make dist/dmg/dev`, or their compile targets finish the Guest rootfs proof
and stop the temporary VM, but fail before producing the package:

```text
Air-gapped rootfs is prepared: .../runtime/vm-disk.img
error: rootfs source VM lifecycle is missing; stop the golden VM cleanly before compressing rootfs:
.../run/vm-lifecycle.json
```

The authoritative database can already contain `vm_lifecycle.state=stopped`, and no launcher
process is running for the Golden VM home.

## Cause

The Host lifecycle owner moved to `runtime/runtime-state.sqlite`, but two packaging consumers
still used the diagnostic `run/vm-lifecycle.json` projection inconsistently:

- the shutdown wait allowed process absence to succeed even when lifecycle state was missing;
- rootfs compression required the JSON projection as its shutdown proof.

The diagnostic projector is not required to run for a disposable Golden VM, so a valid clean
shutdown could have no lifecycle JSON. Re-running `compile` did not repair this contract mismatch
and could repeat the complete rootfs build before failing at the same compression guard.

## Fix

Both consumers now read the `vm_lifecycle` row from `runtime/runtime-state.sqlite` in read-only
mode. Shutdown wait succeeds only when the authoritative state is `stopped` and the launcher
process is absent. Rootfs compression requires the same stopped state, rejects terminal failure,
and independently requires process absence before reading or compressing mutable VM files.

Missing database, missing row, invalid schema/state, read failure, lifecycle failure, incomplete
shutdown, and a remaining launcher PID stay distinct failures. There is no JSON fallback.

## Checks

```sh
sqlite3 .tmp/vitalserver-vm-golden/runtime/runtime-state.sqlite \
  'select revision, state, run_id, terminal_reason, updated_at from vm_lifecycle;'

.venv/bin/vitalserver-devtools macos-runtime-wait-stopped \
  --vm-home "$PWD/.tmp/vitalserver-vm-golden" \
  --timeout 30

.venv/bin/vitalserver-devtools macos-runtime-require-no-running \
  --vm-home "$PWD/.tmp/vitalserver-vm-golden"
```

The SQLite query must report `stopped`, both commands must pass, and rootfs compression must not
read or require `run/vm-lifecycle.json`.

## Prevention

- JSON and JSONL projections must not be used as current Host state or command guards.
- A package stage must consume the same explicit owner contract as the stage that precedes it.
- Lifecycle state and launcher process state are separate proofs; neither implies the other.
- Late compile failures must identify the authoritative database and exact rejected state.

## Related Cases

- [TS-133 Golden rootfs cleanup reports stopped while launcher still runs](133_golden-rootfs-stopped-lifecycle-launcher-process-race.md)
- [TS-132 Golden rootfs launcher Host settings SQLite](132_golden-rootfs-launcher-missing-host-settings-sqlite.md)
- [Host runtime state persistence](../runtime/macos/host-runtime-state-persistence.md)
