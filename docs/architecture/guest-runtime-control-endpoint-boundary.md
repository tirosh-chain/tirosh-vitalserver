# Guest Runtime Control Endpoint Boundary

## Purpose

Host Agent must manage one Guest **deployment lifecycle** and call one Guest
**Runtime Control** boundary, but these are not the same fact. The previous
`GuestEndpoint` term hid that distinction: it could mean a configured HTTP
address, a selected platform provider, or a failed HTTP probe.

This document fixes the ubiquitous language for the Host-owned aggregate before
the C8/C9/C21 contract rename. It is an unreleased vNext contract change; it
does not require a compatibility alias or a migration from legacy Helper data.

## Owner and aggregate

`GuestRuntimeControlEndpoint` is a Host Agent-owned resource. It is the one
aggregate whose revision guards both a lifecycle command and a Host-to-Guest
Runtime Control call. It does **not** own the Guest Runtime, its SQLite state,
its process, its readiness result, or its network address discovery.

```text
HostAgentDeploymentConfiguration (desired input)
  └─ ConfiguredGuestRuntimeControlHTTPAddress
       └─ GuestRuntimeControlEndpoint (Host SQLite resource)
            ├─ PlatformProviderObservation
            └─ GuestRuntimeControlTransportObservation

macOS C32 MacOSVirtualMachineConfiguration (desired input)
  └─ GuestRuntimeControlHostLocalHTTPBridge
       ├─ Host loopback HTTP: 127.0.0.1:18443
       └─ Guest C37 AF_VSOCK: port 18443

GuestRuntimeControlHTTPClient (outbound adapter)
  └─ consumes the configured Host-local HTTP address only
```

| Name | Owner | Meaning | Must not mean |
| --- | --- | --- | --- |
| `ConfiguredGuestRuntimeControlHTTPAddress` | C33 deployment input author | explicit scheme, host, port which the current HTTP adapter may use | discovered Guest IP or reachability result |
| `PlatformProviderObservation` | selected Platform Provider, persisted by Host Agent | the provider's native VM/service observation | Guest Runtime HTTP availability |
| `GuestRuntimeControlTransportObservation` | Host Agent | a timestamped outcome of an explicit Runtime Control transport probe | provider lifecycle state or Guest Runtime internal state |
| `GuestRuntimeControlEndpoint` | Host Agent | revisioned resource which groups the three named facts | generic network endpoint, VM itself, or Guest state owner |

For the macOS NAT profile, `ConfiguredGuestRuntimeControlHTTPAddress` is the
Host-local C32 bridge address (`127.0.0.1:18443`), not a Guest NAT IP. The
`GuestRuntimeControlHostLocalHTTPBridge` adapter forwards its accepted bytes to
the C37-declared Guest `AF_VSOCK` listener. Neither Host Agent nor the bridge
discovers, stores, or substitutes a Guest IP address. A future transport must
add a separately selected explicit configuration and adapter; it must not
reinterpret the Host-local HTTP address or infer a replacement.

## macOS C32/C37 transport vocabulary

The following names intentionally separate desired transport resources from
runtime observations:

| Name | Owner | Meaning | Must not mean |
| --- | --- | --- | --- |
| `GuestRuntimeControlHostLocalHTTPBridge` | macOS supervisor adapter | Host loopback TCP accept plus transparent byte forwarding to the declared virtio-socket port | HTTP readiness evaluator, Guest state owner, or NAT address resolver |
| `GuestRuntimeControlVirtioSocketListener` | Guest Runtime Linux adapter | `AF_VSOCK` listener bound to the C37 declared port | a TCP fallback or an IP endpoint |
| `HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy` | macOS bridge adapter | pure classification of a nonblocking socket's waiting result versus terminal socket error | VM lifecycle or Guest Runtime readiness policy |
| `GuestRuntimeControlTransportObservation` | Host Agent | result of an explicit Host Runtime Control request | a statement that the provider is running or the Guest process exists |

The complete macOS data path is deliberately small:

```text
Host Agent HTTP client
  → C33 Host-local 127.0.0.1:18443
  → C32 GuestRuntimeControlHostLocalHTTPBridge
  → VZ virtio-socket device
  → C37 GuestRuntimeControlVirtioSocketListener (AF_VSOCK :18443)
  → Guest Runtime HTTP handler
```

An `EAGAIN`, `EWOULDBLOCK`, or `EINTR` result while forwarding an established
byte stream is **waiting**, not peer closure and not readiness success. The
bridge keeps that connection alive. Peer EOF and terminal socket failures close
only that accepted bridge connection; a later Host Agent probe owns its own
transport observation. This prevents an adapter-local I/O detail from being
promoted into Guest lifecycle state.

## Contract language to apply

The C8/C9/C21 implementation and public schema use these names together:

| Previous ambiguous term | Canonical term | Reason |
| --- | --- | --- |
| `GuestEndpoint` | `GuestRuntimeControlEndpoint` | identifies the Guest API boundary, not every Guest-facing fact |
| `GuestAddress` | `ConfiguredGuestRuntimeControlHTTPAddress` | makes configuration and HTTP mechanism explicit |
| `ProviderObservation` | `PlatformProviderObservation` | names the observer and managed platform boundary |
| `TransportObservation` | `GuestRuntimeControlTransportObservation` | names the protocol surface whose reachability was observed |
| `guestEndpoint` | `guestRuntimeControlEndpoint` | makes C33 desired input readable at the document boundary |
| `guestEndpointId` | `guestRuntimeControlEndpointId` | names the C9 lifecycle command target precisely |
| `expectedGuestEndpointRevision` | `expectedGuestRuntimeControlEndpointRevision` | says which Host-owned optimistic concurrency resource C21 guards |

`GuestLifecycleCommand` remains the command noun because it asks the selected
platform provider to change Guest lifecycle. It references the longer endpoint
identifier only to select the Host aggregate and enforce its revision guard.
It must not be renamed as an HTTP command.

## Required behavior preserved by the rename

1. Provider `running`, `starting`, and `stopping` set only the Runtime Control
   transport observation to `not-checked`; none implies reachability.
2. Provider `stopped` or `unavailable` makes the transport explicitly
   `unavailable` and prevents forwarding.
3. An HTTP probe result changes only
   `GuestRuntimeControlTransportObservation`; it never changes provider state.
4. A forwarded command with no response remains
   `FacadeForwardingFailure(deliveryDisposition=unknown)`. It never creates or
   guesses a Guest Runtime operation.
5. Any storage read/decode/write error remains a typed Host state-store failure;
   it cannot yield an empty endpoint or inferred default address.

## Implementation order and proof

1. Rename C8 schema, catalog, OpenAPI read result, C33 field, C9 field, and C21
   revision field in one same-major contract change.
2. Rename Host domain types, SQLite repository methods/table, application ports,
   HTTP adapter package, and public route together. No compatibility alias is
   introduced.
3. Regenerate the resolved contract bundle and unreleased compatibility
   baseline.
4. Update Host/Guest acceptance so it exercises only
   `GuestRuntimeControlEndpoint` language while preserving provider/transport
   separation and revision/idempotency evidence.

The completion criterion is not a successful textual rename. A new maintainer
must be able to determine from a public type, field, route, schema, or error
message whether it refers to configuration, provider observation, transport
observation, or the Host-owned aggregate without reading implementation code.
