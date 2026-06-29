# Watchdog VitalDB Observation Blocks Compose Recovery

> ID: TS-094  
> Category: Runtime health / Watchdog recovery / Guest containers  
> Owner: macOS runtime health  
> Status: active

## Symptoms

- Installed VitalServer Helper status becomes `critical`.
- `status/runtime-status.json` may show these together:
  - `container-service-app-state-created`
  - `recorder-ingress-http-failed`
  - `host-proxy-http-... Failed to connect to 127.0.0.1 port 80`
  - `vitaldb-observation-missing`
- `logs/runtime/watchdog.out.log` reports `watchdog: critical` and may say it cannot recover because of `vitaldb-observation-missing`.
- Guest boot can reach Docker, but `tirosh-vitalserver-compose.service` fails and only Redis remains running.

## Cause

VitalDB observation is downstream of the guest Compose stack. When the Compose stack is down, missing VitalDB observation is secondary evidence, not the state that owns recovery.

The watchdog recovery policy treated `vitaldb-observation-missing` as an unrecoverable observation source issue even when explicit container state already showed a recoverable Compose failure such as `app` in `created` state. Separately, a failed guest HTTP probe could block recovery even when the container observation provided enough state to plan a Compose reconcile.

## Checks

```sh
cat "/Library/Application Support/VitalServerHelper/status/runtime-status.json"
cat "/Library/Application Support/VitalServerHelper/vm/run/vm-lifecycle.json"
tail -n 120 "/Library/Application Support/VitalServerHelper/logs/runtime/watchdog.out.log"
tail -n 240 "/Library/Application Support/VitalServerHelper/logs/guest/bootstrap.log"
tail -n 240 "/Library/Application Support/VitalServerHelper/logs/guest/container-logs.log"
```

The important distinction is whether `composeServicesReadState` is loaded and reports a critical service state. If it does, that container state should drive recovery before missing downstream VitalDB observation.

## Fix Direction

- Let explicit critical container service state plan guest Compose reconcile even when `vitaldb-observation-missing` is also present.
- Do not let a guest HTTP probe read failure block recovery when loaded container observation already proves a Compose reconcile target.
- Keep `vitaldb-observation-missing` unrecoverable when it is the only observation source issue and no explicit container recovery target exists.

## Prevention

- Watchdog recovery policy must prefer owner-provided container state over downstream observation absence.
- Runtime status messages should not describe downstream observation absence as missing installed artifacts when container recovery evidence is present.
- Guest Compose failures should preserve actionable systemd/journal evidence in shared diagnostics so operators do not need SSH access to see the inner cause.

## Related Cases

- `TS-057`: Watchdog Treats Stale Guest Runtime State As Unrecoverable
- `TS-070`: Golden Disk Runtime Boot Proof Gap
- `TS-088`: Redis Relay Missing From Package Bundle
- `TS-093`: Golden Runtime Smoke Missing Runtime Settings

## Follow-up

- 2026-06-29: Installed Helper `0.1.17` showed `app`/UI containers stuck in `created`, host proxy HTTP connection refused, and `vitaldb-observation-missing`. The recovery policy was updated so explicit container recovery evidence is not blocked by missing downstream VitalDB observation.
