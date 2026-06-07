# pkg postinstall fails when launchd service is disabled

> ID: TS-046  
> Category: Packaging  
> Owner: macOS runtime  
> Status: implemented

## Symptoms

- `.pkg` install reaches `Running package scripts...` and then fails.
- `/var/log/install.log` contains:
  - `postinstall failed status=1 command=VITALSERVER_VM_HOME="${vm_home}" "${vm_bin}" runtime install-provision`
  - `launchd service failed to load label=ai.tirosh.vitalserver.helper.sleep-prevention`
- `log show` for the same timestamp contains:
  - `Bootstrap by launchctl ... failed (119: Service is disabled)`
- The failed install removes the app bundle, product root, runtime tools, and LaunchDaemon plists during postinstall failure cleanup.

## Impact

- The package does not remain installed and no package receipt is recorded.
- The VM disk created during this install attempt is removed by fresh-install failure cleanup.
- The machine can keep a launchd disabled override even after the plist and product files are removed.

## Cause

`launchctl disable system/<label>` persists outside the plist file. Clean uninstall disables runtime services before removing LaunchDaemon plists. A later fresh install writes new plists and calls `launchctl bootstrap`, but bootstrap refuses a label that is still disabled. The previous start path did not explicitly call `launchctl enable system/<label>` before bootstrap.

This is Host-owned launchd state. It must be handled as explicit launchd state, not inferred from plist presence, package receipts, or product root files.

## Checks

```sh
tail -n 300 /var/log/install.log | rg -i 'VitalServer|postinstall|sleep-prevention|failed|error'
log show --predicate 'process == "launchd" OR eventMessage CONTAINS[c] "sleep-prevention"' --last 30m --style compact
launchctl print-disabled system | rg -i 'vitalserver|tirosh'
pkgutil --pkgs | rg -i 'vitalserver|tirosh'
find /Library/LaunchDaemons -maxdepth 1 -iname '*vitalserver*' -o -iname '*tirosh*'
```

## Actions

- Use a package built after the start path explicitly enables each launchd service before bootstrap.
- For a one-off recovery on a development Mac, clear the disabled overrides before reinstalling:

```sh
sudo launchctl enable system/ai.tirosh.vitalserver.helper.vm
sudo launchctl enable system/ai.tirosh.vitalserver.helper.proxy
sudo launchctl enable system/ai.tirosh.vitalserver.helper.guest-log-sync
sudo launchctl enable system/ai.tirosh.vitalserver.helper.watchdog
sudo launchctl enable system/ai.tirosh.vitalserver.helper.sleep-prevention
```

## Prevention

- Runtime service start now enables the target launchd label before bootstrap.
- Clean uninstall clears VitalServer launchd disabled overrides before reporting completion.
- Enable failure remains explicit and blocks the operation before bootstrap, with launchctl stderr recorded in the command log.
- Do not treat plist absence or package receipt absence as proof that launchd disabled state is clear.

## Applied Fix

- Uninstall keeps the existing stop-time disable step so launchd does not respawn services during cleanup.
- Before completion, uninstall calls `launchctl enable system/<label>` for every VitalServer managed service to clear host-owned disabled overrides.
- If disabled override cleanup fails, uninstall must not report `completed`.
- Helper-launched uninstall now opens a Terminal progress viewer that follows `/private/tmp/tirosh-vitalserver-uninstall.log`; the privileged uninstaller still runs through the existing administrator-approved path.

## Operational Notes

- This failure is not a VM disk corruption symptom. It happens before VM service start, at host launchd service activation.
- If this appears after a failed clean uninstall, inspect both file residue and `launchctl print-disabled system`.

## Related Cases

- TS-024
- TS-037
- TS-042
