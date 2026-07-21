# Lab Finish And Recorder Ingress Cold Path Export/Publish Semantics

> ID: TS-137
> Category: Product Lab / Recorder streaming / Cold path
> Owner: Product Lab / recorder ingress / recorder recovery
> Status: resolved; export/publish boundary revised by ADR 0006

## Symptoms

- A Product Lab session is stopped or finished, but no generated `.vital` file appears in VitalServer My Files.
- Recorder ingress raw archive append succeeds, but `rawArchive.autoExport.status` never reaches `exported`.
- One recorder disconnects while another remains connected, and the disconnected recorder is never exported.
- A later recovery job uploads old `.vital` files from the recovery output directory again.
- `Finish & export`가 끝났지만 UI가 export가 진행 중인지, 실패했는지, 완료됐는지 표시하지 못한다.

## Cause

Product Lab did not distinguish a restartable pause from terminal archive finalization. Stop closed Socket.IO
connections and archive finalization was either absent or coupled to a restartable `stopped` state. Recorder
ingress then relied only on the five-minute inactivity policy.

The inactivity worker evaluated the global `activeRecorderConnections` count and one global archive cursor. Any
other connected recorder therefore blocked every disconnected recorder. The raw archive append result also exposed
the append start offset rather than the completed record end offset, so `0` could be checkpointed for the first
record.

이전 구현은 recovery export와 VitalServer publish를 한 operation에 결합하고 mutable output directory를 다시
scan했습니다. 그 결과 현재 job의 artifact와 과거 artifact를 구분할 수 없었고, cold-path recovery 파일도
Vital Recorder의 native `.vital` upload와 같은 provenance로 보였습니다.

## Fix Direction

- Product Lab `Stop` is a restartable pause and does not finalize an archive.
- Product Lab `Finish` transitions to terminal `finished`, closes execution, and sends one explicit
  vrcode-scoped finalization request to recorder ingress.
- Recorder ingress persists pending finalization requests and owns retry/export/checkpoint state.
- Lab persists only the accepted ingress request IDs, then exposes a read-only archive-export summary on the existing
  session read. Guest Control, Swift, and PWA do not receive ingress job/checkpoint documents or call ingress directly.
- Inactivity and explicit decisions use recorder-specific connection, archive, spool, and replay state.
- Archive checkpoints use append end offsets and recovery reads only the unexported byte window for that vrcode.
- Recovery returns receipts only for artifacts created by the current export operation. Receipts explicitly record
  `origin=coldPathRecovery`, writer/format version, source byte range, coverage, SHA-256, and artifact ID.
- Inactivity, shutdown, and current Product Lab Finish perform export only. A separate explicit publish workflow must
  own collision checks, VitalServer upload, index verification, and publish receipts.

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
- A successful finalization acceptance is not export success, and `exported` is not publish success. The UI displays
  the ingress-owned `exported` and `published` states as different meanings; `failed`, `partial`, `missing`, and
  `unavailable` remain distinct.
- Repeating Finish from `finished` is an explicit archive-finalization retry; starting from `finished` remains
  forbidden.
- Cold-path finalization policy must be recorder-scoped when the archive contains multiple recorders.
- A publish use case must consume explicit artifact IDs/receipts instead of rediscovering mutable directory contents.
- Byte cursor tests must cover the first append, incremental export, another active recorder, and explicit Lab Finish.

## Related Cases

- TS-092
- TS-108
- TS-130

## Follow-up

- 2026-07-15: Split restartable Stop from terminal Finish, added explicit Product Lab finalization,
  recorder-scoped cold-path jobs, byte-window recovery, and current-job-only uploads.
- 2026-07-19 Runtime Platform mapping: the Lab Runner exposes one terminal
  `stop` effect. Guest Runtime persists the Runner-selected
  `terminalArchivePolicy` and a receipt-bound `terminalArchiveIntent` before
  dispatching Archive Export. The intent's `submitted` state means only that
  an Archive operation exists; the separate `ExportReceipt` remains the sole
  upload/index success evidence. A missing Runner policy is a decode failure,
  never an implicit `no-export` choice.
- 2026-07-21: Split cold-path export from publish, added explicit recovery artifact origin/receipt contracts, and
  changed automatic inactivity/shutdown/Product Lab finalization to export-only.
