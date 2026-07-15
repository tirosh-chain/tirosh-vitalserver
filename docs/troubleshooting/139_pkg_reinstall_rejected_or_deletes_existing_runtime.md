# PKG fresh/reinstall transition is misclassified or failed postinstall deletes the runtime

> ID: TS-139
> Category: Packaging / Host state persistence
> Owner: macOS package install lifecycle
> Status: fixed and verified

## Symptoms

Installing a new VitalServer Helper PKG over an installed version fails in `preinstall` with
existing app, product root, launchd service, and receipt blockers:

```text
fresh install preflight blocked blockers=install-artifact-present:...,launchd-service-loaded:...,package-receipt-present:...
```

An older installed version can also have materialized Host settings files but no
`runtime/runtime-state.sqlite` Host settings row yet. Merely bypassing preflight then makes
postinstall either reject `alreadyExists`, initialize defaults, resize the existing VM disk, or
remove the product root during failure cleanup.

A reinstall can also pass preinstall while the configured Host proxy is still running, then fail
only after payload replacement when the old proxy stops and exposes an external listener such as
OrbStack on the same port:

```text
proxy port cleanup blocked by external listeners port=80 listeners=OrbStack-59042,OrbStack-59042
postinstall failed ... runtime install-provision
```

A fresh install can pass preinstall and then fail immediately in postinstall even though the target
was empty before PackageKit copied the payload:

```text
Legacy Host settings migration blocked by incomplete materialized state:
.../vm/runtime/vm-config.json=missing,
.../vm/data/deploy/runtime-config.json=file,
.../vm/data/deploy/runtime-settings.json=file
```

After correcting that transition, the next fresh-install attempt can reach permission setup and
fail when the optional Host Runtime Control settings document has not yet been materialized:

```text
command failed: /bin/chmod 0644 .../runtime-control-settings.json
chmod: .../runtime-control-settings.json: No such file or directory
```

## Cause

The package scripts implemented only a fresh-install transition even though PackageKit declares
the payload overwrite action as `upgrade`. Existing product-owned artifacts and services were
therefore treated as foreign blockers. The shared provision workflow also did not distinguish an
existing authoritative settings revision from a fresh missing settings state, and failure cleanup
was destructive without an explicit install disposition.

The fresh/reinstall disposition was previously printed only as preinstall diagnostic output.
Postinstall recomputed behavior from files after PackageKit copied the payload. At that point the
packaged Guest configuration documents existed while the Host VM configuration had not yet been
materialized, so a valid fresh-install intermediate state was incorrectly classified as a partial
legacy migration.

Permission setup also assumed that `runtime-control-settings.json` already existed. Fresh install
had no owner step that materialized its documented initial values, so `chmod` became an accidental
existence probe and failed after the VM disks had already been created.

## Fix

The preinstall CLI now derives one explicit disposition from package receipt state:

- no receipt: run the strict fresh-install preflight;
- current receipt present: select data-preserving reinstall and stop package-owned services;
- unreadable receipt or artifact inspection: block with the exact failure.

Preinstall writes that disposition to a schema-versioned package-install contract inside the
current PackageKit Scripts sandbox. Postinstall must read and validate the same contract, including
schema version and package identifier. A missing, unreadable, or mismatched contract blocks the
install. Fresh provision initializes SQLite without legacy migration; reinstall provision runs the
explicit migration before loading preserved settings.

Before permission setup, the Host settings owner now inspects `runtime-control-settings.json`.
Fresh missing state is materialized with the documented Runtime Control defaults. A valid existing
document is decoded and preserved byte-for-byte. Inspection failure, invalid JSON, or an unexpected
path type remains an explicit install failure. Permission setup therefore only applies mode `0644`
to a validated materialized document.

Preinstall preserves an existing SQLite Host settings revision before PackageKit replaces payload
files. For a pre-SQLite installation, it imports `vm-config.json`, Guest `runtime-config.json`, and
Guest `runtime-settings.json` only when all three files exist and decode successfully. Partial
legacy state is a hard failure. Postinstall consumes that preserved SQLite revision.

Existing VM and runtime-data disks are preserved; install provisioning only sizes a newly created
VM disk. Existing cloud-init seed, configured backup schedule, proxy port, start-on-boot state,
and sleep-prevention setting are read from their explicit owners rather than reset to installer
defaults. A postinstall failure stops services and preserves data and package artifacts for retry.

Before stopping the installed services, reinstall preflight now classifies the configured proxy
port listeners using the explicit nginx PID and installed nginx command path. Existing
VitalServer-owned nginx listeners are allowed. Any external listener, listener inspection
failure, or nginx ownership inspection failure blocks before service stop and payload replacement.
Preflight never terminates the external listener.

## Checks

The development PKG was verified on 2026-07-15 with both transitions:

- clean target: fresh install succeeded, materialized Runtime Control settings as `root:wheel`
  mode `0644`, and loaded all six core launchd services;
- installed target: same-PKG upgrade succeeded, preserved the VM disk inode and logical size,
  Runtime Control settings digest, runtime-data disk, and cloud-init seed.

Before reinstall:

```sh
pkgutil --pkg-info ai.tirosh.vitalserver.helper
ls -lh '/Library/Application Support/VitalServerHelper/vm/runtime/vm-disk.img'
launchctl print-disabled system | grep ai.tirosh.vitalserver.helper
```

After reinstall, verify that the VM disk size is unchanged and Host settings were imported or
preserved:

```sh
sqlite3 '/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite' \
  'select revision, materialized_revision from host_runtime_settings;'
ls -lh '/Library/Application Support/VitalServerHelper/vm/runtime/vm-disk.img'
tail -200 '/Library/Application Support/VitalServerHelper/logs/install.log'
```

If an enabled proxy cannot restart because another process owns its configured port, the install
log must report that external listener explicitly. Do not kill or relabel the external process as
VitalServer state.

To inspect the reported conflict directly:

```sh
sudo lsof -nP -iTCP:80 -sTCP:LISTEN
```

Stop the external owner or change the persisted Host proxy port, then retry the same package. Do
not delete the VM disks or SQLite state to resolve a port conflict.

## Prevention

- Package receipt state, not file presence, selects fresh install versus reinstall.
- A transition selected before payload replacement must be passed to postinstall through an
  explicit contract; postinstall must not infer it from the replaced filesystem.
- Permission commands must not serve as file-existence probes; the configuration owner must first
  provide a validated existing document or explicitly materialize documented fresh defaults.
- Existing SQLite state must be consumed as authoritative state; legacy JSON import is an explicit
  migration only.
- Provisioning must never resize an existing VM disk.
- Failed package cleanup must not delete persistent runtime state without an explicit destructive
  uninstall command.
- Partial or unreadable legacy state must remain failed, not become default settings.
- Reinstall must classify external proxy listeners before it stops installed services or allows
  PackageKit to replace the payload.

## Related Cases

- [TS-134 PKG fresh install Host settings materialization](134_pkg-fresh-install-host-settings-before-materialization.md)
- [TS-136 Clean uninstall leaves Platform Agent loaded](136_clean-uninstall-leaves-platform-agent-loaded.md)
- [Host runtime state persistence](../runtime/macos/host-runtime-state-persistence.md)
