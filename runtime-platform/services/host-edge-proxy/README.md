# Host Edge Proxy

`host-edge-proxy` is the Host-owned C36 public HTTP/WebSocket trust boundary.
It exposes only the routes explicitly declared in
`HostEdgeProxyDeploymentConfiguration` and forwards them to their configured
Host-local upstreams. It is not a Guest Runtime controller, a VitalServer
state owner, or a generic reverse-proxy configuration surface.

## Responsibility map

| Location | Owns / does | Does not own |
| --- | --- | --- |
| `internal/hostedgeproxydomain/` | pure C36 validation and explicit route selection | network listener, HTTP forwarding, Guest readiness, upstream health |
| `internal/hostedgeproxydeployment/` | strict decoding of one C36 desired configuration document | live listener or route state, fallback routes |
| `internal/hostedgeproxyhttpserver/` | HTTP/WebSocket forwarding, request-size enforcement, client-identity trust-boundary handling | route policy invention, upstream selection from request headers |
| `cmd/host-edge-proxy/` | CLI composition, listener creation, signal-driven server closure, diagnostics | C36 policy or HTTP routing decisions |

## Request contract

```text
C36 HostEdgeProxyDeploymentConfiguration (desired input)
  -> ValidateHostEdgeProxyDeploymentConfiguration (pure policy)
  -> NewHostEdgeProxyHTTPHandler (Host HTTP/WebSocket adapter)
  -> ResolveHostEdgeProxyRoute (configured route only)
  -> HostEdgeProxyRoute.ConfiguredHTTPUpstreamURL (explicit C36 target only)
  -> configured Host-local upstream
```

An unmatched request receives `404`; there is no implicit default backend.
The readiness path is an HTTP-handler fact only: it does not claim Guest
Runtime readiness or configured-upstream health. Before forwarding, the proxy
removes client-supplied forwarding headers and establishes the one Host-observed
remote address according to the explicit C36 client-identity policy.

## Naming rules in this module

- `hostedgeproxydomain` identifies the C36 bounded context; bare `domain`
  would lose the Host trust-boundary owner in imports and stack traces.
- `HostEdgeProxyDeploymentConfigurationSchemaVersion` belongs to the C36
  desired-input document, not to arbitrary JSON.
- `ConfiguredHTTPUpstreamURL` returns only the target that C36 already
  selected; it does not resolve a request-derived destination.
- `HostEdgeProxyDeploymentConfigurationUnavailableError` and
  `HostEdgeProxyDeploymentConfigurationInvalidError` preserve unreadable and
  invalid C36 input as separate meanings.

## Run

```sh
host-edge-proxy \
  --deployment-configuration /etc/vitalserver/host-edge-proxy.json
```

The command rejects a missing, unreadable, malformed, or semantically invalid
C36 document. It does not start with a default listener, target, or route.
