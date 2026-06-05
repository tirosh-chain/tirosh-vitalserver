# Guest log sync service remains stopped after runtime restart

> ID: TS-047  
> Category: Runtime health  
> Owner: macOS runtime service lifecycle  
> Status: active

## Symptoms

- Helper `Advanced > Service health` shows `Guest log sync service` as `Stopped`.
- VM service, proxy service, sleep prevention service, watchdog service, and user-facing HTTP checks can still be green.
- `launchctl print system/ai.tirosh.vitalserver.helper.guest-log-sync` reports `Could not find service`.
- The service plist still exists and launchd disabled state can still be `enabled`.

## Impact

The runtime can keep serving VitalServer, but host-side guest log synchronization is not running. This creates an observability gap and makes later troubleshooting weaker.

## Cause

The confirmed failure pattern is a runtime restart or repair command booting out `ai.tirosh.vitalserver.helper.guest-log-sync` without treating it as an explicit required service during the following start and health wait.

This is not a guest container failure. It is a Host-owned launchd service lifecycle gap.

## Checks

```sh
launchctl print system/ai.tirosh.vitalserver.helper.guest-log-sync
launchctl print-disabled system | rg 'ai\.tirosh\.vitalserver\.helper\.guest-log-sync'
plutil -p /Library/LaunchDaemons/ai.tirosh.vitalserver.helper.guest-log-sync.plist
tail -n 200 "/Library/Application Support/VitalServerHelper/logs/install.log"
```

To confirm an unload race, inspect system launchd logs around the restart time:

```sh
log show --style compact --start '<local start time>' --end '<local end time>' | grep guest-log-sync
```

Look for `bootout initiated by`, `service inactive`, and `removing service`.

## Actions

1. Confirm the plist exists and is enabled.
2. Restart runtime services from Helper or CLI after applying a build that explicitly restarts `guest-log-sync`.
3. Verify `launchctl print system/ai.tirosh.vitalserver.helper.guest-log-sync` reports a loaded service.
4. Verify Helper service health shows `Guest log sync service` as `Running`.

## Prevention

Runtime restart policy must carry `guest-log-sync` as explicit state, not infer it from VM state. Health wait must require `guest-log-sync` when the restart policy says it should be running, and must fail instead of reporting success with the sidecar missing.

## Related Cases

- `TS-030`: Runtime state inference
- `TS-033`: Runtime Control Helper read permissions
- `TS-046`: launchd service disabled during pkg postinstall

## Follow-up

- 2026-06-04: Added explicit `restartGuestLogSync` restart policy and health wait requirement after field observation where `authtrampoline -> vitalserver-vm -> launchctl bootout` removed the service.
