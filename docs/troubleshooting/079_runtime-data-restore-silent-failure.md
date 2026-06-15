# Runtime Data Restore Silent Failure

## Case Metadata

| Field | Value |
|---|---|
| ID | TS-079 |
| Category | Data store / Runtime health |
| Owner | Host CLI runtime-data-restore |
| Status | implemented |

## Symptoms

VitalServer Helper backup restore fails, but the Helper app does not show a useful failure message.
The recovery progress area can also remain empty or keep only the generic running text, so the operator
cannot tell whether restore is still running, failed before Redis restore, or failed while validating the
backup artifact.

## Cause

The `runtime-data-restore` Host CLI command called the restore composition directly and only printed a
success message after the composition returned. It did not publish runtime progress for restore start,
restore completion, or restore failure.

When restore failed before a later refresh, the UI could only depend on command output. If a refresh then
loaded a status document without restore progress, the visible message could be replaced by unrelated or
empty status text.

## Actions

`runtime-data-restore` must publish explicit progress around the restore operation:

- `restore-runtime-data-backup` started with phase `running`
- `restore-runtime-data-backup` completed with phase `completed`
- `restore-runtime-data-backup` failed with phase `failed`, reason code `runtime-data-restore-failed`, and
  the concrete restore error message

The failure message must include the selected backup path and the restore error. Examples include missing
manifest, unsupported restore compatibility version, artifact checksum failure, Redis restore failure, or
start-on-boot restoration failure.

## Prevention

- Mutating recovery operations must always publish terminal progress on failure.
- UI refresh must consume explicit Host progress/state instead of inferring restore state from logs or
  command output.
- Backup/restore validation errors must remain visible as failed restore state; they must not be converted
  into generic command cancellation or hidden by a later status refresh.

## Related Cases

- [TS-077 Runtime Data Backup Compatibility Gate](077_runtime-data-backup-compatibility.md)
- [Backup/Restore 계약](../../site-docs/dev/backup-restore-contracts.md)
