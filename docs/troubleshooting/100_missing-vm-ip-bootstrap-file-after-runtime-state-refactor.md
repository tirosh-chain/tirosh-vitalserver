# 100 Missing `vm-ip` bootstrap file after runtime-state refactor

> ID: TS-100
> Category: Runtime health / Guest bootstrap
> Owner: macOS runtime
> Status: active

## Symptoms

Freshly installed VitalServer Helper reaches a running Guest stack, but Host
runtime status stays `degraded` and later becomes `critical`.

Typical status reasons:

```text
guest-http-missing-vm-ip
guest-http-probe-failed-guestControl=missing-vm-ip
vm-lifecycle-document-stale
guest-service-observation-read-failed-missing-vm-ip
```

At the same time, Guest evidence can show the runtime is actually serving:

```text
/Library/Application Support/VitalServerHelper/vm/data/run/runtime-observation.json
  vmIP: 192.168.64.x
  guestHTTP: 200
  redisUIHTTP: 200
  swaggerUIHTTP: 200
  probeErrors: []
```

The Host proxy may also report `hostProxyHTTP: 200`, while the VM lifecycle
document remains `bootstrapping` until its deadline expires.

## Cause

The Host health checker no longer reads `runtime-observation.json.vmIP` as a VM
address fallback. It expects the explicit bootstrap address contract:

```text
/Library/Application Support/VitalServerHelper/vm/data/run/vm-ip
```

A runtime-state refactor removed Host fallback reads from `runtime-observation.json`,
but Guest runtime-state writing did not continue producing the separate `vm-ip`
file. This left Host health with no Guest Control API base address even though
the Guest-owned runtime-state document contained a valid VM IP.

This is a contract mismatch, not a Guest service outage.

## Fix Direction

Restore the short-term bootstrap file contract by making the Guest runtime-state
writer emit `vm-ip` from the same explicit VM IP observation used for
`runtime-observation.json`.

When the Guest cannot observe a VM IP, remove any existing `vm-ip` file instead
of leaving a stale address behind.

Do not reintroduce Host fallback reads from `runtime-observation.json.vmIP`; that would
make Host health depend on a broader Guest state document after the control-plane
boundary was intentionally narrowed.

## Prevention

Keep bootstrap address ownership explicit:

- Short term: Guest writes `vm-ip`; Host reads only `vm-ip` for Guest Control API
  bootstrap.
- Medium term: Host health consumes a typed Guest address provider result and
  keeps `vm-ip` behind the compatibility provider. The result preserves loaded,
  missing, invalid, stale, and read-failed states instead of collapsing them to
  `nil`.
- Long term: replace the `vm-ip` provider implementation with a typed VM network
  or control-plane provider. Consumers must continue to depend on the provider
  contract, not on the file path.

Runtime smoke should assert both files during the transition:

```text
data/run/runtime-observation.json
data/run/vm-ip
```

`runtime-observation.json` can remain diagnostics and product runtime evidence, but it
must not be promoted back into Host bootstrap address state.

## Checks

On an installed runtime:

```sh
cat "/Library/Application Support/VitalServerHelper/vm/data/run/runtime-observation.json"
cat "/Library/Application Support/VitalServerHelper/vm/data/run/vm-ip"
cat "/Library/Application Support/VitalServerHelper/vm/run/vm-lifecycle.json"
cat "/Library/Application Support/VitalServerHelper/status/runtime-status.json"
```

If `runtime-observation.json.vmIP` is present but `vm-ip` is missing, this case
applies.

## Related Cases

- `TS-017`: VM은 부팅됐지만 VM IP가 계속 Waiting
- `TS-030`: Runtime 상태를 Host/UI가 추정하거나 암묵 보정함
- `TS-040`: VM lifecycle stale after healthy boot and log export gap

## Follow-up

- 2026-07-08: Fresh install produced healthy Guest `runtime-observation.json` and Host
  proxy 200, but no `vm-ip` file. Watchdog kept reporting `missing-vm-ip` and
  failed to mark VM lifecycle `running`.
- 2026-07-08: Short-term recovery restores Guest-owned `vm-ip` production. The
  target architecture remains a typed Guest address provider rather than a
  permanent file contract.
- 2026-07-08: Host health now reads Guest address through a typed provider. The
  compatibility provider reads only `vm-ip`, reports missing/invalid/read-failed
  distinctly, and does not fall back to `runtime-observation.json.vmIP`. The host proxy
  runner also stopped parsing `runtime-observation.json.vmIP`; it waits on the same
  `vm-ip` bootstrap discovery file while `runtime-observation.json.guestHTTP` remains
  bootstrap readiness evidence.
- 2026-07-08: Runtime status documents now preserve `guestAddressRead` from the
  health snapshot so API/UI/status consumers can distinguish missing, invalid,
  stale, and read-failed address reads instead of seeing only `vmIP: null`.
