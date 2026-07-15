# Lab Finish And Recorder Ingress Cold Path Do Not Upload Vital Files

> ID: TS-137
> Category: Product Lab / Recorder streaming / Cold path
> Owner: Product Lab / recorder ingress / recorder recovery
> Status: resolved

## Symptoms

- A Product Lab session is stopped or finished, but no generated `.vital` file appears in VitalServer My Files.
- Recorder ingress raw archive append succeeds, but `rawArchive.autoExport.status` never reaches `uploaded`.
- One recorder disconnects while another remains connected, and the disconnected recorder is never exported.
- A later recovery job uploads old `.vital` files from the recovery output directory again.

## Cause

Product Lab did not distinguish a restartable pause from terminal archive finalization. Stop closed Socket.IO
connections and archive finalization was either absent or coupled to a restartable `stopped` state. Recorder
ingress then relied only on the five-minute inactivity policy.

The inactivity worker evaluated the global `activeRecorderConnections` count and one global archive cursor. Any
other connected recorder therefore blocked every disconnected recorder. The raw archive append result also exposed
the append start offset rather than the completed record end offset, so `0` could be checkpointed for the first
record.

Recorder recovery exported the requested raw archive but discovered upload inputs by scanning the whole output
directory. Artifacts from earlier jobs were therefore included again.

## Fix Direction

- Product Lab `Stop` is a restartable pause and does not finalize an archive.
- Product Lab `Finish` transitions to terminal `finished`, closes execution, and sends one explicit
  vrcode-scoped finalization request to recorder ingress.
- Recorder ingress persists pending finalization requests and owns retry/upload/checkpoint state.
- Inactivity and explicit decisions use recorder-specific connection, archive, spool, and replay state.
- Archive checkpoints use append end offsets and recovery reads only the unexported byte window for that vrcode.
- Recovery uploads only the artifacts returned by the current export operation.

## Checks

Inspect recorder ingress status and verify the selected recorder has no active connection and no replay backlog:

```sh
curl -fsS http://127.0.0.1:8080/recorder-ingress/status
```

Inspect the durable job document in the Guest runtime recovery volume:

```sh
cat /mnt/tirosh/run/recorder-ingress-recovery/raw-archive-auto-export-state.json
```

The document must distinguish `pendingFinalizations`, `activeJob`, `checkpointsByVrcode`, and terminal failure
evidence. Missing or invalid state is not an empty successful job list.

## Prevention

- Lifecycle owners must emit explicit finalization commands only for terminal Finish; disconnect and pause must not
  be promoted to archive completion.
- Finish must fail visibly when no session recorder vrcode or recorder-ingress finalizer is available; it must not
  return a successful terminal upload request with no durable finalization receipt.
- Repeating Finish from `finished` is an explicit archive-finalization retry; starting from `finished` remains
  forbidden.
- Cold-path finalization policy must be recorder-scoped when the archive contains multiple recorders.
- A recovery use case must pass its exact artifacts to upload instead of rediscovering mutable directory contents.
- Byte cursor tests must cover the first append, incremental export, another active recorder, and explicit Lab Finish.

## Related Cases

- TS-092
- TS-108
- TS-130

## Follow-up

- 2026-07-15: Split restartable Stop from terminal Finish, added explicit Product Lab finalization,
  recorder-scoped cold-path jobs, byte-window recovery, and current-job-only uploads.
