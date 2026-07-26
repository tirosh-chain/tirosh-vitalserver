# Settings VM restart fails after saving VM activation settings

> ID: TS-131
> Category: Packaging / Runtime health / macOS Helper
> Owner: macOS runtime
> Status: source fixed; package install verification pending

## Symptoms

- Settings Apply fails with `DecodingError.dataCorrupted` at `publicHost`.
- Memory allocation or the Vital Files directory remains unchanged after Apply.
- `Restart VM Runtime` then shows Host proxy or Watchdog as `Not Loaded` and eventually fails after the runtime health timeout.
- The VM process may be running while status repeatedly reports `vm-lifecycle-document-invalid`.

## Cause

Six contract violations combined into one user-visible failure.

1. Fresh-install defaults and packaged Guest documents wrote `publicHost` as an empty string, while `GuestRuntimeConfigDocument` requires a non-empty value.
2. Configure reads the current Guest runtime document before planning or writing changes, so the invalid installed document blocked every later settings change.
3. The Settings restart button called full runtime repair instead of the `restartAfterSettingsApply` configure workflow.
4. Full runtime repair stopped `RuntimeManagedService.uninstallOrder`, which includes Platform Agent, but its restart policy did not start Platform Agent. HostCLI health also read VM lifecycle through the Platform API instead of the durable SQLite lifecycle owner.
5. A later `Restart VM Runtime` action reused the change-relative `--restart` flag. Because Apply had already written the new settings, configure observed no current-file delta and discarded the restart request even though the UI still had an explicit saved-versus-applied VM activation requirement.
6. The first explicit-intent fix was not present in the installed package under investigation. Its helper log showed `restart=true restartRequirement=guestStack`, followed by Guest Control `runtime/stack/reconcile` timeout. The command therefore never entered the VM shutdown/start workflow, even though the UI action was `Restart VM Runtime`. In addition, `applied-vm-config.json` was published as soon as `VZVirtualMachine.start` returned success, before Guest health was proven, so a failed activation could look applied.

The general VM stop path also sent SIGTERM before unloading the launchd `KeepAlive` job. launchd could therefore start a replacement VM and rewrite the pid file while the stop operation was still waiting.

## Fix

- Fresh-install and packaged Guest defaults now contain explicit, mutually consistent advertised URL compatibility fields.
- Guest runtime config writing proves that the encoded document can be decoded before persisting any file.
- Change-relative activation uses `--restart`: it activates only components changed by the same configure operation.
- Explicit Settings activation uses `--restart-vm-runtime`: it executes the dedicated VM restart workflow even when the saved configuration already matches the configuration files. The UI no longer asks configure to rediscover the saved-versus-applied state from file differences.
- Host settings are persisted as a monotonic SQLite desired revision. Desired and applied payloads are retained independently. The three JSON documents are boot materializations, are read back and compared with that revision, and cannot initiate restart until materialization succeeds.
- VM start records the materialized settings revision against the new SQLite VM lifecycle run ID. The desired payload becomes the applied payload only after the same run passes runtime health. A restart/health failure leaves the old applied payload/revision intact and `desiredRevision != appliedRevision`; it does not publish success.
- Schema v7 invalidates a v6 applied revision whose payload cannot be proven. It does not infer the old payload from the current desired row or mutable JSON files, so the Helper continues to show `Requires VM restart` until a new boot/health proof succeeds.
- `applied-vm-config.json` is now a post-health UI/diagnostic projection. VM process start alone no longer writes it.
- Runtime service stop uses `stopOrder`; Platform Agent remains available as the control-plane owner. `uninstallOrder` remains limited to uninstall cleanup.
- HostCLI health reads the SQLite VM lifecycle repository directly. The UI/API client continues to consume Platform Agent resources and does not invent state when that API is unavailable.
- VM service stop unloads the launchd job before waiting, preventing `KeepAlive` from replacing the selected VM process.

## Checks

```sh
jq '{publicHost,publicPort,vitalServerURL,remoteConsoleURL}' \
  "/Library/Application Support/VitalServerHelper/vm/data/deploy/runtime-config.json"

launchctl print system/ai.tirosh.vitalserver.helper.platform-agent
launchctl print system/ai.tirosh.vitalserver.helper.vm

sqlite3 "/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite" \
  'select revision, materialized_revision, boot_revision, boot_run_id, applied_revision, applied_run_id, applied_vm_config_json is not null as has_applied_vm_config from host_runtime_settings;'

sqlite3 "/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite" \
  'select revision, run_id, state, operation, updated_at from vm_lifecycle;'

rg -n 'publicHost must be a non-empty string|vm-lifecycle-document-invalid|pid file now references another process' \
  /private/tmp/tirosh-vitalserver-helper-message.log \
  /private/tmp/tirosh-vitalserver-manager-command.log
```

After installing a package containing the fix, Apply must succeed before the restart action is offered. Restart must preserve the Platform Agent launchd job, activate the saved VM config, and finish health verification without following a replacement pid.

The explicit activation path can be checked independently after settings are already saved:

```sh
sudo /usr/local/bin/vitalserver-vm runtime configure --restart-vm-runtime
```

The command must run the VM restart workflow even when it writes no configuration delta. A successful return requires `host_runtime_settings.applied_revision = host_runtime_settings.revision`, all three applied payload columns to be present, and `applied_run_id = vm_lifecycle.run_id`. If shutdown, start, or health verification fails, the command must fail and the previous applied revision/payload must remain unchanged.

## Prevention

- Packaged default documents must satisfy the same decoder used by installed runtime commands.
- A writer must reject a non-round-trippable contract before the first persistent write.
- Settings activation, runtime repair, service stop, and uninstall must use distinct operation intents and service sets.
- “Activate changes detected in this write” and “restart the VM now” must remain separate typed intents; a provider must not reconstruct explicit user intent from a later configuration diff.
- “VM process started” and “settings applied” are different states. Applied settings require a materialized revision, a new lifecycle run ID, and explicit health proof for that run.
- Control-plane owner services must not be included in a product-runtime stop list unless the same operation explicitly starts and verifies them.
- HostCLI lifecycle reads must use the durable owner repository and must not require an HTTP listener owned by another process.
- A launchd `KeepAlive` job must be unloaded before its process is stopped or awaited.

## Related Cases

- [TS-040 VM lifecycle stale after healthy boot](040_vm-lifecycle-stale-after-healthy-boot-log-export-gap.md)
- [TS-049 Update VM stop follows launchd-restarted pid](049_update-vm-pid-restart-race.md)
- [TS-068 Settings Apply enters update-like shutdown](068_settings-apply-update-shutdown-confusion.md)
- [TS-110 VM launcher requires UI-hosted Platform API](110_vm-launcher-requires-ui-hosted-platform-api.md)
