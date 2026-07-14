# Golden rootfs times out before creating the runtime manifest

> ID: TS-132
> Category: Packaging / Guest bootstrap
> Owner: macOS VM build staging
> Status: resolved

## Symptoms

- `make dist/dmg/dev` waits for `rootfs-ready` until timeout.
- The last wait evidence is `manifest missing: .../rootfs-runtime-manifest.json`.
- `rootfs-failure.json`, `rootfs-apt-plan.json`, and Guest failure evidence are also absent.
- `launcher.log` contains `Host settings SQLite read failed` and `unable to open database file`.

## Cause

The VM launcher correctly requires authoritative Host settings from
`runtime/runtime-state.sqlite`. Installed provisioning initialized that owner, but the
golden/dev VM staging path only generated `vm-config.json`, `runtime-config.json`, and
`runtime-settings.json`. The launcher therefore exited before starting the VM. Since the Guest
never ran, the wait command could only observe a missing manifest and eventually timed out.

The missing manifest was a downstream symptom, not a Guest rootfs preparation failure.

## Fix

`internal/vm/stage` now performs this explicit order:

1. initialize the VM workspace and generate VM config;
2. stage the complete Guest deploy bundle;
3. invoke `runtime configure` without a restart;
4. initialize/migrate the Host SQLite store and commit the staged settings as a materialized
   revision;
5. start the golden/dev VM.

The launcher remains strict. It does not import JSON when SQLite is missing and does not treat
files as a fallback owner.

## Checks

```sh
sqlite3 .tmp/vitalserver-vm-golden/runtime/runtime-state.sqlite \
  'select schema_version, database_id from runtime_metadata;'

sqlite3 .tmp/vitalserver-vm-golden/runtime/runtime-state.sqlite \
  'select revision, materialized_revision, boot_revision from host_runtime_settings;'

tail -n 100 .tmp/vitalserver-vm-golden/logs/launcher.log
```

Before VM start, `revision` and `materialized_revision` must match. During a successful rootfs
run, `rootfs-runtime-manifest.json` must carry the expected run ID and every required stage must
report `status=passed`. The wait validator must report `manifestStatus=passed`, and
`rootfs-ready` must be created for the same run ID.

## Prevention

- Every VM workspace, including golden, runtime-smoke, and local dev workspaces, must prepare the
  same authoritative Host settings owner before launcher start.
- Build staging must call an explicit configure/materialization boundary after all three boot
  documents exist.
- Launcher startup must continue to fail on missing, unreadable, invalid, or unmaterialized
  SQLite settings.
- Rootfs timeout diagnostics must inspect launcher exit evidence before classifying a missing
  Guest manifest as a Guest failure.

## Related Cases

- [TS-069 Golden rootfs stale proof negative validation](069_golden-rootfs-stale-proof-negative-validation.md)
- [TS-070 Golden disk runtime boot proof gap](070_golden-disk-runtime-boot-proof-gap.md)
- [TS-131 Settings VM restart fails after saving VM activation settings](131_settings-vm-restart-invalid-config-and-platform-agent-stop.md)
