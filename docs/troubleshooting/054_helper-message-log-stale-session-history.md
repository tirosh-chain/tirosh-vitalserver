# Helper message log shows stale session history after fresh install

> ID: TS-054  
> Category: Runtime Control PWA / Packaging  
> Owner: macOS runtime Host UI  
> Status: active

## Symptoms

- A user performs a fresh install, but the Runtime Control log source `Helper message`
  still shows previous update or uninstall messages.
- The stale lines can include old strings such as `Applying update bundle...`,
  `bundle apply failed`, `Starting background uninstaller...`, or the old shell
  syntax error containing `&;`.
- Current runtime status can be healthy while the helper message log still looks
  critical or uninstall-related.

## Impact

- Operators can confuse old UI message history with the current install state.
- The stale helper message file does not prove that the fresh install failed.
- Runtime state must still be read from explicit status, service, event, and
  install contracts instead of from this UI message log.

## Cause

`Helper message` is a Mac Control Panel UI session log stored at
`/private/tmp/tirosh-vitalserver-helper-message.log`. That path is outside the
product root and can survive clean uninstall, app reinstall, and helper relaunch.

The UI log reader tailed that persisted file directly, so messages owned by an
old helper session could appear after a fresh install. This violated the state
ownership rule: a display log was able to look like current install state even
though it was only stale UI history.

## Checks

Compare the helper message log timestamps with the current install receipt and
product root timestamps.

```sh
tail -n 120 /private/tmp/tirosh-vitalserver-helper-message.log
pkgutil --pkg-info ai.tirosh.vitalserver.helper
ls -ld "/Library/Application Support/VitalServerHelper"
```

If the helper message timestamps are older than the current install time, treat
them as previous UI session history.

## Actions

- Use `runtime-status.json`, Runtime Control status, install logs, command logs,
  and runtime events to diagnose the current install.
- Do not infer fresh install failure from `Helper message` alone.
- If the file contains old update or uninstall history, restart the updated
  Helper app build that resets this session log on startup.

## Prevention

- The live Mac Control Panel injects `FileRuntimeHelperMessageLog` instead of
  leaving the UI log reader pointed at an unmanaged stale file.
- `FileRuntimeHelperMessageLog` starts a fresh session by removing an existing
  helper message log before writing current UI messages.
- Regression tests cover stale helper message removal and explicit opt-out when
  a caller intentionally preserves the existing file.

## Related Cases

- TS-037
- TS-042
- TS-050
