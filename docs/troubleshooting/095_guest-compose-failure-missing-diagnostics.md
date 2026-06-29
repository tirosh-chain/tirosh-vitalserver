# Guest Compose Failure Missing Diagnostics

> ID: TS-095  
> Category: Guest bootstrap / Runtime health / Diagnostics  
> Owner: macOS runtime guest tools  
> Status: active

## Symptoms

- Helper install or watchdog recovery reaches the VM, but runtime status reports `guest-bootstrap-failed`.
- `tirosh-vitalserver-compose.service` is `failed`.
- Redis may be `running` and `healthy`, while `app`, `redis-relay`, `redis-ui`, or `swagger-ui` remain in Docker `created` state with `startedAt=null`.
- Shared bootstrap logs only show:

```text
Job for tirosh-vitalserver-compose.service failed because the control process exited with error code.
See "systemctl status tirosh-vitalserver-compose.service" and "journalctl -xeu tirosh-vitalserver-compose.service" for details.
```

The actionable `docker compose` stderr is missing from host-visible logs.

## Cause

Guest bootstrap started Compose through systemd. When `/usr/local/bin/tirosh-vitalserver-compose up` failed, the Python subprocess boundary surfaced only the `systemctl start` failure. The inner Compose command output, service state snapshot, and container logs were not preserved in the shared diagnostics that the Host can read.

This does not mean the Host should infer container state from logs. The missing logs are diagnostic evidence only; runtime state must still come from explicit guest-owned documents such as `runtime-state.json`.

## Fix Direction

- Wrap ordered Compose startup commands with a guest-owned diagnostic boundary.
- On failed `docker compose up`, include:
  - failing stage
  - exit code
  - command
  - captured stdout/stderr
  - `docker compose ps --all`
  - `docker compose ps --all --format json`
  - `docker compose logs --tail=200`
- Raise a typed guest dependency failure so systemd and bootstrap logs preserve the evidence.

## Prevention

- VM build and guest bootstrap failures are product compile/runtime failures; never reduce them to a generic systemd exit code.
- Host diagnostics may classify external logs as failure evidence, but must not convert those logs into runtime/domain state.
- Guest services that fail before SSH is available must write enough explicit evidence into shared diagnostics for Host-side troubleshooting.

## Related Cases

- `TS-070`: Golden Disk Runtime Boot Proof Gap
- `TS-093`: Golden Runtime Smoke Missing Runtime Settings
- `TS-094`: Watchdog VitalDB Observation Blocks Compose Recovery

## Follow-up

- 2026-06-29: Installed Helper `0.1.17` repeatedly failed guest Compose startup after Redis became healthy. The shared logs did not include inner Compose stderr, leaving `app` containers in `created` state without an actionable cause. Guest Compose startup now captures command output and compose state/log snapshots before raising the failure.
