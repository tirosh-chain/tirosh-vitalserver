# Helper status stays Critical after guest is healthy

## Metadata

- ID: TS-102
- Category: Runtime health / macOS Helper UI
- Owner: Host runtime health
- Status: active

## Symptom

After a fresh Helper install, launchd services are running and the guest app is reachable through the host proxy, but Runtime Control or the status diagnostics projection reports `critical`.

Typical evidence:

- `launchctl print system/ai.tirosh.vitalserver.helper.vm` shows the VM service running.
- `launchctl print system/ai.tirosh.vitalserver.helper.proxy` shows the proxy service running.
- `curl http://127.0.0.1/ready` or the browser reaches the VitalServer app.
- Runtime Control `failureReasons` contain `guest-service-observation-read-failed-.../runtime/stack`. Status diagnostics may only show the last published status context; current failure reasons come from Runtime Control owner reads, not `runtime-status.json`.

## Cause

The watchdog and status readers call the Guest Control `/runtime/stack` contract to observe guest service state. That endpoint can take more than one second during or immediately after startup because it gathers status and resource observations for multiple containers.

A one-second Host status-read timeout can therefore classify the guest service observation as a read failure even when the VM, Guest Control API, host proxy, and VitalServer app are already reachable.

## Confirm

```bash
VM_IP="$(cat '/Library/Application Support/VitalServerHelper/vm/data/run/vm-ip')"
curl -sS -i --max-time 10 "http://${VM_IP}:18330/runtime/stack"
/usr/local/bin/vitalserver-vm runtime guest-stack-status --guest-control-url "http://${VM_IP}:18330"
cat '/Library/Application Support/VitalServerHelper/status/runtime-status.json'
```

If the direct Guest Control call succeeds but Runtime Control still reports `guest-service-observation-read-failed`, compare the endpoint latency with the Host status-read timeout budget. Treat `runtime-status.json` as diagnostics evidence only; current state must come from Runtime Control's explicit owner reads.

## Fix Direction

Keep `/runtime/stack` as an explicit Guest Control contract. Do not infer guest service health from host proxy reachability or application HTML.

The Host status-read timeout must be long enough for the explicit guest service observation to complete under normal startup load. Timeout failures should still remain visible as read failures when the endpoint exceeds that explicit budget.

## Prevention

- Treat Guest Control status reads as contract reads, not optional display probes.
- Keep Host health timeout budgets explicit and tested where requests are created.
- When adding heavier Guest Control status payloads, verify watchdog/status reader latency against the configured timeout.
