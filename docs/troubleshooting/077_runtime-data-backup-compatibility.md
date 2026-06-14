# Runtime Data Backup Compatibility Gate

## Metadata

| Field | Value |
|---|---|
| ID | TS-077 |
| Category | Data store / Runtime health |
| Owner | Host backup/restore |
| Status | active |

## Symptom

A VitalServer backup can be selected and restore starts, but the backup was created by
a runtime with a different data layout. The restore may overwrite Host config files,
status documents, observability SQLite, or Redis data before incompatibility becomes
visible.

Related visible failures can include:

- Runtime Control cannot decode restored settings/status documents.
- Recorders, Beds, activity, or relationship history disappears or fails to query after restore.
- Redis restore completes, but the current VitalServer cannot read old Redis keys.
- Restore appears successful even though the selected backup lacks a compatibility contract.

## Cause

VitalServer backup is one product-level restore unit, but it contains multiple data
schemas. Redis data, VM config, guest runtime config, guest runtime settings, proxy
LaunchDaemon plist, start-on-boot state, status/events documents, and observability
SQLite are owned by different contracts.

Recording only `runtimeVersion` is not enough. Product version and backup data layout
compatibility can move independently. Restore must use an explicit
`dataCompatibilityVersion` from the backup manifest before writing any artifact.

## Fix Direction

The backup manifest must include `dataCompatibilityVersion`. Restore must reject the
backup before writing files when:

- `dataCompatibilityVersion` is missing;
- the declared compatibility version is unsupported by the current Helper;
- manifest schema/product/artifact identity validation fails;
- required artifact size, checksum, state, or relative path validation fails.

If an older compatibility version must be supported, add an explicit migration before
restore writes to runtime destinations. Do not infer compatibility from filenames,
runtime version strings, artifact presence, or successful checksum validation alone.

## Prevention

- Treat backup compatibility as a data layout contract, not as UI copy or product version text.
- Bump `RuntimeDataBackupCompatibility.currentDataCompatibilityVersion` when old backups
  cannot be restored safely without migration.
- Add tests for missing and unsupported compatibility versions whenever backup manifest
  schema or restored artifact schemas change.
- Document every artifact's schema owner in `docs/runtime/macos/runtime-data-backup.md`.

## Related

- [VitalServer Backup](../runtime/macos/runtime-data-backup.md)
