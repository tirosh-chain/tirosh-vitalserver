# 074 Installed bootstrap fails when lsblk PARTNUM is empty

> Category: Packaging / Install / Guest bootstrap  
> Owner: guest bootstrap infrastructure  
> Status: implemented  
> First seen: 2026-06-13

## Symptom

Fresh reinstall leaves the installed runtime unhealthy or Critical. Host health reports that
`runtime-state.json` is missing and guest HTTP/host proxy are unavailable even though the VM launchd
service is running.

Installed guest `bootstrap.log` contains:

```text
RuntimeError: command returned no output: lsblk -no PARTNUM /dev/nvme1n1p1
```

The guest bootstrap result is failed before runtime services create `runtime-state.json`.

## Cause

`expand_root_filesystem()` treated every command read as required state. On the installed guest,
`findmnt -n -o SOURCE /` returned the explicit root source `/dev/nvme1n1p1`, but
`lsblk -no PARTNUM /dev/nvme1n1p1` returned empty output. The code raised before reaching the
existing explicit parser that can derive partition number `1` from `/dev/nvme1n1p1`.

This was not a safe fallback boundary. `findmnt SOURCE` and `findmnt FSTYPE` are required contract
reads. `lsblk PKNAME` and `lsblk PARTNUM` are auxiliary probes because the root source itself can
carry the same explicit device identity.

## Fix Direction

- Keep required reads strict: missing root source or filesystem type remains a bootstrap failure.
- Treat `lsblk PKNAME` and `lsblk PARTNUM` as optional probes.
- If optional probe output is empty, derive parent device and partition number from the explicit
  root source with `parent_device_from_source()` and `partition_number_from_source()`.
- Add infrastructure-level unit tests for installed NVMe root source shapes instead of only testing
  the bootstrap workflow with fake operations.

## Prevention

`compile passed` must not be read as `installed runtime passed`. Packaging compile proves artifact
creation and golden rootfs preparation. Guest bootstrap/runtime contracts need a separate runtime
smoke gate.

Use the explicit validation workflows before installation handoff:

```sh
make dist/dmg/dev/verify
make dist/pkg/dev/verify
```

For focused runtime validation:

```sh
make dist/dmg/dev/verify
make dist/pkg/dev/runtime-smoke
```

DMG dev runtime smoke is an internal phase of `dist/dmg/dev/verify`; it is not exposed as a
separate public workflow target.

The runtime smoke must fail explicitly when bootstrap result, runtime state, systemd units,
Docker/Compose health, HTTP readiness, disk health, capabilities, or command dispatch contracts do
not hold.
