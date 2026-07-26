# Guest Public Service Transport Boundary

## Purpose

Host Edge Proxy must forward an explicitly configured public route to a Guest
service without treating a macOS NAT address as an inbound contract. This
document defines the language and ownership of that path. It is intentionally
separate from Guest Runtime Control: a successful public byte connection is
not a Guest Runtime readiness result, Recorder delivery result, browser health
result, or VM lifecycle observation.

## Three declarations, three owners

| Contract | Owner | Declares | Does not declare |
| --- | --- | --- | --- |
| C36 `HostEdgeProxyDeploymentConfiguration` | Host Edge Proxy deployment | public `route.id`, path prefix, HTTP/WebSocket policy, and Host target | Guest IP, Guest process health, or a Guest target selection rule |
| C32 `GuestPublicServiceHostLocalHTTPBridgeConfiguration` | macOS virtual-machine supervisor | named route's Host `127.0.0.1` listener and Guest virtio-socket port | HTTP interpretation, route matching, or Guest TCP service health |
| C37 `GuestPublicServiceVirtioSocketBridge` | Guest Product process deployment | named route's `guestProductProcessName`, Guest virtio-socket listener, and that process's Guest `127.0.0.1` target | Host listener bind, public authentication, process readiness, or VitalServer delivery success |

The package composer must prove that all three documents name exactly the same
route IDs. For each ID, C36's `http://host:port` target must equal C32's
`hostLoopbackAddress:hostLoopbackPort`, and C32's `guestVirtioSocketPort` must
equal C37's `virtioSocketPort`. C37 separately proves that
`guestProductProcessName` is one of its planned child processes and that its
declared loopback listener owns `targetPort`. C32/C36 remain available to the expanded PKG
verifier, which repeats the direct C32/C36 check. It does not invent C37 from
the immutable Guest artifact.

## Runtime components

```text
Recorder or browser
  → HostEdgeProxy
       C36 route decision only
  → GuestPublicServiceHostLocalHTTPBridge
       C32 Host-loopback TCP ↔ VZ AF_VSOCK byte relay only
  → guestpublicservicevirtiobridge
       C37 AF_VSOCK ↔ explicit Guest-loopback TCP byte relay only
  → declared Guest service
```

`HostLocalHTTPToGuestVirtioSocketByteRelay` is shared technical machinery in
the macOS provider. It has no route identity and never interprets HTTP. Its two
semantic wrappers are deliberately distinct:

- `GuestRuntimeControlHostLocalHTTPBridge` — C33/C32/C37 control contract.
- `GuestPublicServiceHostLocalHTTPBridge` — one C36/C32/C37 public route.

Likewise, the Guest `guestvirtiotransport` package knows only how to create an
`AF_VSOCK` listener. `guestruntimecontrolvirtiolistener` and
`guestpublicservicevirtiobridge` name the control and public-route contexts
that consume it. This keeps reusable system-call code below, rather than
inside, domain policy.

## Failure meanings

| Fact | Owner | Meaning |
| --- | --- | --- |
| C32 Host listener cannot bind | macOS supervisor | VM start fails because a required Host transport resource is unavailable |
| VZ socket connection fails for one accepted client | Host byte relay | that client transport is closed; no synthetic HTTP success or Guest state change |
| C37 Guest loopback TCP dial fails | Guest byte relay | that client transport is closed; it is not `ready`, `offline`, or an upstream delivery result |
| Host Edge Proxy target fails | Host Edge Proxy | response is 502 according to its forwarding contract; it does not mutate Recorder or VM state |

No fallback TCP route, NAT IP discovery, default port, or inferred health state
is permitted. A future bridged or external topology must introduce a separate
explicit deployment profile and its own contract validation.
