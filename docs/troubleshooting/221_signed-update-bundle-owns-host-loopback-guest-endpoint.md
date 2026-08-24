# Signed Update Bundle Owns a Host Loopback Guest Endpoint

> ID: TS-221
> Category: Update / Bootstrap handoff / Guest Control
> Owner: macOS runtime
> Status: active

## Symptoms

Runtime Control accepts and launches a signed stable update, but the durable
update journal fails on the first Guest-owned layer:

```text
Guest owner request failed: Could not connect to the server
url=http://127.0.0.1:18330/runtime/update-artifacts/...
```

At the same time, the explicit Host Guest-address resource reports an address
such as `192.168.64.3`, and `http://192.168.64.3:18330/ready` succeeds.

## Cause

The Container and Guest Runtime effect configurations embedded
`guestControlBaseURL=http://127.0.0.1:18330/` in the signed update payload.
There is no Host loopback forward that owns port `18330`. The Guest Control API
is owned by the VM and is reachable through the current Guest address.

This also assigned machine-local runtime state to a portable signed release
artifact. The layer executor consumed that stale value instead of the explicit
Guest address owned by the Host runtime.

## Fix Direction

- Remove `guestControlBaseURL` from signed Guest-owned layer effect
  configurations and their schemas.
- Read the typed Guest address from the Host-owned provider before handoff.
- Carry the resulting URL explicitly through handoff invocation, update runner,
  and layer-effect invocation contracts.
- Reject missing, malformed, and Host-loopback endpoints before applying a
  layer. Do not replace them with a default. Loopback judgment is a reusable
  explicit policy (`RuntimeGuestControlEndpointPolicy`) shared by handoff
  invocation and Guest-owned layer-effect execution; it rejects the `127.0.0.0/8`
  block, `::1`, and the case-insensitive `localhost`, `localhost.`, and
  `*.localhost` hostname forms without a string blacklist.
- Increment the internal handoff and layer-effect invocation schema versions
  because their required fields changed.

## Prevention

Portable release artifacts may define identity transitions, timeouts, and
artifact contracts. They must not own the current VM address or another
machine-local endpoint.

The Host owns runtime networking state. Consumers receive that state through an
explicit invocation contract, and unavailable Guest-address state must remain
an update admission failure.

## Evidence

The generated layer-effect invocation must contain the current Guest endpoint:

```json
{
  "schemaVersion": "vitalserver.product-update-layer-effect-invocation/v2",
  "guestControlBaseURL": "http://192.168.64.3:18330"
}
```

The signed `effect-configuration.json` must not contain
`guestControlBaseURL`. Field proof reads the persisted handoff owner:

```text
/Library/Application Support/VitalServerHelper/update-bootstrap/<update-id>/handoff/invocation.json
```

`prove-update-bootstrap` decodes required `guestControlBaseURL` from that
document, rejects host-loopback and invalid URLs, then correlates the URL to
the Host-owned Guest Control endpoint: current Guest address plus HTTP port
`18330`. Omitted port and wrong port are port mismatch, not a host match.
Guest address missing, invalid, stale, read-failed, and not-reported stay
distinct from host mismatch and port mismatch. The apply API response alone
is only handoff admission evidence.

## Related Cases

- [TS-108: Product Lab send without VitalDB tracks](108_product-lab-send-without-vitaldb-tracks.md)
- [TS-192: Update bootstrap journal requires explicit recovery](192_update-bootstrap-journal-requires-explicit-recovery.md)
- [TS-220: Platform Agent update verifier uses root home](220_platform-agent-update-verifier-uses-root-home.md)
- [TS-227: prove-update-bootstrap rejects persisted layer evidence](227_prove_update_bootstrap_rejects_persisted_layer_evidence.md)
