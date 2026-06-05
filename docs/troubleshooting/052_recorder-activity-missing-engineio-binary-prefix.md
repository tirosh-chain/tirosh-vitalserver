# TS-052: Recorder Activity Missing from Engine.IO Binary Prefix

## Symptom

The PWA Observability or Recorder Details view reports:

```text
activityTimeline is not reported
Recorder activity history is not reported.
```

The runtime status can still show VitalServer, network access, and VitalDB Observer as healthy. The observer database may contain no rows in `vitaldb_recorder_activity_buckets`, while `vitalDBObservation.readIssues` reports skipped `send_data` events missing `rooms_count/roomsCount`.

## Cause

The audit proxy observes raw WebSocket frames. For Socket.IO binary attachments over Engine.IO, the frame payload can begin with the Engine.IO `message` packet type byte `0x04`, followed by the compressed VRecorder `send_data` payload.

If the proxy passes the raw frame directly to `zlib.inflateSync`, decompression fails with:

```text
incorrect header check
```

The audit event is then recorded with `decode_error` but without `payload_summary.rooms_count`. The VitalDB Observer correctly refuses to create activity buckets because recorder activity requires explicit `rooms_count` from the audit event contract.

## Fix Direction

Normalize Socket.IO binary attachment payloads at the audit proxy application boundary before summarizing `send_data`:

- preserve plain compressed payloads as-is,
- strip exactly the Engine.IO binary message prefix byte `0x04` when present,
- keep other decode failures visible as `decode_error`.

Do not make the observer or PWA infer activity from bytes, logs, timestamps, or recorder online state.

## Prevention

Wire framing belongs at the proxy boundary. Domain summarization should receive the explicit application payload, and the observer should only build activity history from audit events that report the required contract fields.
