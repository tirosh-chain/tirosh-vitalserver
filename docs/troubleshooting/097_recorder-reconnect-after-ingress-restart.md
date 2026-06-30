# Recorder reconnect after ingress restart

> ID: TS-097  
> Category: Runtime health / Recorder streaming / Proxy  
> Owner: recorder ingress / nginx proxy  
> Status: implemented

## Symptoms

- VRecorder streams normally at first.
- After `recorder-ingress` is stopped or restarted, the recorder does not appear to reconnect.
- Web Monitoring keeps showing stale/offline recorder or bed state even after `recorder-ingress` health returns.
- Status/Overview can show active recorder connections and stale recorders at the same time even when the recorder has reconnected.
- Edge or host proxy logs may show `/socket.io/` requests ending around the default nginx proxy timeout instead of staying open as a long-lived WebSocket.

## Cause

The recorder path crosses two proxy boundaries:

```text
VRecorder -> macOS host nginx -> guest edge nginx -> recorder-ingress -> VitalServer app
```

The guest edge had a `/socket.io/` WebSocket location but did not set explicit `proxy_read_timeout` or `proxy_send_timeout`. The macOS host proxy used a generic `/` location for WebSocket upgrade and also did not set explicit WebSocket proxy timeouts.

For VRecorder traffic, Socket.IO/WebSocket is an explicit long-lived transport contract. Leaving this to nginx defaults can close a recovered connection during quiet periods or while the recorder is backing off after ingress restart. That looks like "ingress is healthy but recorder never reconnects."

A second presentation bug can make the same situation look stale after transport recovery. The detailed recorder history used recorder-ingress activity when calculating recorder status, but the Status/Overview summary rebuilt the same read model without passing the explicit recorder-ingress status document. That allowed `activeConnections > 0` and `staleRecorders > 0` to appear together for the same current recorder.

## Fix Direction

- Set `proxy_read_timeout 1h` and `proxy_send_timeout 1h` on the guest edge `/socket.io/` route.
- Set the same timeouts on the macOS host proxy route that carries WebSocket upgrade traffic.
- Require macOS host proxy readiness to prove both `/ready` and `/recorder-ingress/health`.
  `/ready` alone proves the web app path is reachable; it does not prove recorder Socket.IO traffic is
  passing through recorder-ingress.
- Build Status/Overview recorder summary with the same VitalDB observation plus recorder-ingress status inputs used by recorder history.
- Keep Docker DNS re-resolution on the guest edge through `resolver 127.0.0.11` and variable upstreams; do not replace that with a static container IP.

## Checks

Check ingress liveness and recorder status separately:

```sh
curl -fsS http://127.0.0.1:8080/recorder-ingress/health
curl -fsS http://127.0.0.1:8080/recorder-ingress/status
```

Check whether Socket.IO requests are being cut at a proxy boundary:

```sh
tail -n 100 vm/data/logs/vitalserver-edge/access.jsonl
tail -n 100 logs/runtime/proxy-nginx.access.log
tail -n 100 logs/runtime/proxy-nginx.error.log
```

Do not infer recorder state from a successful health check. Health only proves the ingress process can serve local checks; recorder connection state must come from the ingress status document and VitalDB observation.

## Prevention

- Treat WebSocket timeout settings as part of the recorder ingress contract, not as generic nginx defaults.
- Treat recorder-ingress health through the public proxy as part of the host proxy readiness contract.
  If `/ready` succeeds but `/recorder-ingress/health` fails, the system must report proxy readiness
  failure instead of accepting a path that can make recorders look connected while ingress activity stays stale.
- Keep proxy timeout assertions in packaging tests for both host proxy and guest edge configs.
- Keep RuntimeControl summary tests for the case where VitalDB observation is stale but recorder-ingress activity is recent.
- When ingress is restarted during validation, confirm both the transport path and recorder observation refresh after the health check returns.

## Related Cases

- TS-031
- TS-090
- TS-094

## Follow-up

- 2026-06-30: Added explicit Socket.IO/WebSocket proxy timeouts to guest edge nginx and macOS host proxy config, with packaging tests to prevent regression.
- 2026-06-30: Fixed Status/Overview recorder summary so recent recorder-ingress activity is passed into the summary read model, matching the Recorders detail status calculation.
- 2026-07-01: Strengthened macOS host proxy runner readiness so the proxy is not reported ready unless
  recorder-ingress health is reachable through the same public path.
