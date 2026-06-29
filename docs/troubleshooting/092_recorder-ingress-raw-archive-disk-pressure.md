# Recorder Ingress Raw Archive Disk Pressure

> ID: TS-092
> Category: Runtime health / Recorder streaming
> Owner: recorder ingress / guest runtime storage
> Status: active

## Symptoms

- `/recorder-ingress/status` shows `rawArchive.status = failed`.
- `/recorder-ingress/status` shows `rawArchive.writeFailures > 0`.
- `rawArchive.lastFailure.message` includes disk, permission, or append errors.
- `rawArchive.autoExport.status` stays `retryable_failed` or `failed` because the recovery
  volume, TestKit recovery API, or VitalServer upload endpoint is unavailable.
- Heavy recorder streaming continues, but `spool.skippedRealtimeEvents` also increases.

`spool.skippedRealtimeEvents` is not the same failure. It means pending items were excluded from realtime replay candidates. If raw archive is failed at the same time, those skipped realtime candidates must not be treated as recoverable until archive persistence is confirmed.

## Impact

Raw archive is the cold-path source of truth for `.vital` recovery. If it cannot append, realtime sampling or skip events may become unrecoverable data loss for the affected interval.

Realtime replay can still keep the UI fresh while archive writes fail, so operators must check raw archive state explicitly instead of relying on live monitor updates.

## Cause

Known causes:

- raw archive volume is full
- raw archive directory is missing or not mounted
- recorder-ingress container lacks write permission
- rotation or retention settings are too large for the runtime data disk
- generated `.vital` export output is written to the same constrained volume and consumes remaining free space

## Checks

Check recorder ingress status first:

```sh
curl -fsS http://127.0.0.1:8080/recorder-ingress/status
```

Check the configured raw archive path and free space from the host or guest context that owns the volume:

```sh
df -h data/recorder-ingress-raw
du -sh data/recorder-ingress-raw
ls -la data/recorder-ingress-raw
```

For macOS runtime, the raw archive path is mounted under runtime data:

```sh
df -h "vm/data/run/recorder-ingress-raw"
du -sh "vm/data/run/recorder-ingress-raw"
ls -la "vm/data/run/recorder-ingress-raw"
```

Confirm the runtime settings:

```sh
grep RECORDER_INGRESS_RAW_ARCHIVE compose.yaml
grep RECORDER_INGRESS_RAW_ARCHIVE apps/vitalserver-macos-runtime/Support/Guest/compose.yaml
```

## Actions

1. Stop treating realtime skip as recoverable until `rawArchive.status` is back to `ready`.
2. Preserve existing raw archive files before deleting or pruning anything manually.
3. Free or expand the runtime data disk volume.
4. Lower `RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILE_BYTES` or `RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILES` if retention exceeds available disk.
5. Restart recorder ingress only after the archive path is writable.
6. Run recovery export/upload for the persisted interval:

```sh
uv run vitalserver-testkit recover-raw-archive-vital \
  data/recorder-ingress-raw/send-data-raw.jsonl \
  --output-dir /private/tmp/recorder-ingress-vital-export \
  --vitalserver-url http://127.0.0.1:8080 \
  --endpoint /upload
```

## Prevention

- Alert when raw archive free space drops below the operational threshold.
- Alert when `rawArchive.writeFailures` increases.
- Alert when `rawArchive.status` is `failed`.
- Alert when `rawArchive.autoExport.status` is `failed`, or when it stays
  `retryable_failed` beyond the configured retry window.
- Keep export output outside the raw archive volume when investigating disk pressure.
- Size retention from measured heavy-load bytes per minute, not from recorder count alone.

## Operational Notes

Raw archive rotation deletes old rotated archive files when `RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILES` is exceeded. That retention is a filesystem policy, not proof that `.vital` recovery/upload has already happened.

Automatic idle export/upload is not yet enabled. Until an operation state machine records export checkpoints and upload results, `recover-raw-archive-vital` is the supported one-command recovery path.

## Related Cases

- TS-090
- TS-084
- TS-085

## Follow-up

- 2026-06-28: Added one-command `recover-raw-archive-vital` path and documented raw archive disk pressure as an explicit runtime runbook.
