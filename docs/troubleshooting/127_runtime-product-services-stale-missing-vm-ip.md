# Runtime product services keeps the initial `missing-vm-ip` failure

## Metadata

- ID: TS-127
- Category: Runtime health / macOS Helper UI
- Owner: macOS Runtime product-service presentation and refresh
- Status: active

## Symptom

Immediately after a fresh installation, the macOS Helper can keep showing this
warning after the VM and Guest services have become healthy:

```text
Runtime product services
Guest Control API is unavailable. guest address is unavailable: missing-vm-ip
```

Direct Guest Control reads may already return `state=loaded`, and the Host status
may report a loaded Guest address plus HTTP 200 for Guest Control and the public
proxy.

## Cause

Two presentation behaviors overlapped:

1. The first Runtime stack read occurred while the explicit VM lifecycle was
   `starting` and the Guest address provider reported `missing-vm-ip`. That is a
   normal Guest initialization state, not a product-service read failure.
2. The Swift Helper refreshed the Runtime stack only during a full screen refresh.
   Its periodic status poll refreshed Platform health but did not retry the Runtime
   stack owner. The initial read error therefore remained in client state after the
   Guest became ready.

The PWA already polls `GET /runtime/stack` every two seconds. Windows and Linux
Platform Agents forward the same Runtime Control route; they do not create product
service state from Platform probes.

## Fix

- While the Status or Advanced section is selected, Swift refreshes the Runtime
  stack every five seconds. Redis Relay owner state is refreshed while Advanced
  is selected.
- A missing Runtime stack result is displayed as `Initializing` only when the
  explicit Host VM lifecycle is `starting` and the explicit Guest HTTP state is
  `missing-vm-ip`.
- Once the VM is no longer starting, timeout, decode, permission, and other stack
  read failures remain visible as warnings with their original error message.
- A successful Runtime stack read replaces the earlier error and resource list.

## Prevention

- A presentation may format explicit readiness state, but must not classify an
  error by matching its localized message.
- Platform lifecycle, Guest address availability, Runtime stack reads, and Redis
  Relay status remain separate owner contracts.
- Polling must re-read the owner of the displayed state. Refreshing Platform health
  alone is not evidence that Runtime product-service state was refreshed.
- Regression tests must cover initial `missing-vm-ip`, later successful stack load,
  and a real stack read failure after initialization.

## Checks

Compare the Host and Guest owner contracts instead of relying on the stale UI row:

```sh
cat "/Library/Application Support/VitalServerHelper/vm/run/vm-lifecycle.json"
cat "/Library/Application Support/VitalServerHelper/status/runtime-status.json"
curl "http://$(cat '/Library/Application Support/VitalServerHelper/vm/data/run/vm-ip'):18330/runtime/stack"
```

If the lifecycle is `running`, `guestAddressRead.state` is `loaded`, and the stack
is `loaded`, a remaining `missing-vm-ip` row is this client-refresh issue.

## Related Cases

- `TS-100`: Guest address bootstrap contract is actually missing
- `TS-103`: Runtime product services have missing desired-state specs
- `TS-105`: Runtime stack reads time out on optional Docker statistics
