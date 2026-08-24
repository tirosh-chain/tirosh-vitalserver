# prove-update-bootstrap Rejects Persisted Guest URL or Host Platform Journal

> ID: TS-227
> Category: Update / Field proof
> Owner: macOS runtime
> Status: active

## Symptoms

`prove-update-bootstrap` reaches a terminal Host update journal, then fails
before printing `update bootstrap lifecycle proof verified`. The error names
one of:

- `guestControlBaseURLHostLoopback`
- `guestControlHostMismatch`
- `guestControlPortMismatch`
- `guestAddressMissing` / `guestAddressInvalid` / `guestAddressStale` /
  `guestAddressReadFailed` / `guestAddressNotReported`
- `hostPlatformOperationMissing` / `hostPlatformOperationReadFailed`
- `hostPlatformPhaseMismatch`
- `hostPlatformIdentityMismatch` / `hostPlatformInstallationIdentityMismatch`

The Host update journal and execution report may already look terminal.

## Impact

Field apply/rollback smoke cannot close. A completed journal is not enough to
prove Guest endpoint ownership or Host Platform reconciliation.

## Cause

Proof now reads two additional owners that remain at proof time:

1. Staged `handoff/invocation.json` `guestControlBaseURL`, correlated to the
   current Host-owned Guest address observation.
2. Host Platform SQLite journal at the signed effect configuration
   `manager.databasePath`, operation `<update-id>.host-platform.apply`.

Those documents can disagree with the top-level update journal: loopback or
stale Guest URL, missing/read-failed Guest address, missing Host Platform
database, non-terminal phase, or installation identity mismatch. Proof does
not repair them from the `current` symlink or from logs.

## Checks

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime prove-update-bootstrap \
  <update-id> --expect succeeded \
  --timeout-seconds 30 --poll-interval-milliseconds 250
```

Inspect the persisted owners directly. Do not infer from process tables.

```sh
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["guestControlBaseURL"])' \
  "/Library/Application Support/VitalServerHelper/update-bootstrap/<update-id>/handoff/invocation.json"
```

The Host Platform database path comes from the digest-bound signed
configuration in the same staged bundle, typically:

```text
/Library/Application Support/VitalServerHelper/update-manager/state.sqlite
```

Missing, unreadable, and decode-failed documents stay distinct.

## Actions

- Loopback or host mismatch: the handoff captured a Host-local endpoint or the
  Guest address changed after apply. Re-read the current Guest address owner;
  do not edit invocation.json.
- Port mismatch: the persisted URL omitted port `18330` or used another port.
  Host Guest Control is HTTP on `18330`; do not treat default HTTP port 80 as
  that endpoint.
- Guest address missing/read-failed: Runtime Control Guest address resource is
  the owner. Fix that read; do not substitute a remembered IP.
- Host Platform operation missing/read-failed: confirm the staged configuration
  `databasePath` still points at the journal used during apply.
- Phase mismatch: resume Host Platform reconciliation or accept the durable
  `failed`/`compensated` phase with `--expect failed-rolled-back`. Do not
  treat the `current` symlink as the phase.
- Installation identity mismatch: the SQLite active installation is not this
  update's apply operation. Do not promote a later or earlier activation.

## Prevention

Keep Guest Control endpoint and Host Platform phase as explicit persisted
owners. Field proof must consume those documents; it must not reconstruct them
from source defaults, logs, or symlink targets.

## Related Cases

- [TS-220: Platform Agent update verifier uses root home](220_platform-agent-update-verifier-uses-root-home.md)
- [TS-221: Signed update bundle owns a Host loopback Guest endpoint](221_signed-update-bundle-owns-host-loopback-guest-endpoint.md)
- [TS-226: Host Platform reconciliation is now a durable, resumable lifecycle](226_host_platform_durable_reconciliation.md)
