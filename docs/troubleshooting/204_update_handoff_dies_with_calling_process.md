# TS-204: Update handoff dies with the calling process

## Symptom

A stable update handoff stops making progress when the CLI or UI process that
started it exits. A restart leaves a running update journal, but there is no
durable owner that can say whether the updater is queued, running, cancelled,
failed, or complete.

## Cause

The original handoff launcher synchronously executed the next updater and
waited for its exit. Process lifetime and update ownership therefore belonged
to the transient caller. A PID alone was also insufficient recovery evidence:
PID absence does not prove successful completion, and a reused PID does not
identify the child that belonged to the admitted update.

## Fix direction

The macOS runtime now contains a dedicated update handoff supervisor boundary:

- a revisioned durable job document owns queued, launching, running,
  cancellation-requested, succeeded, failed, and interrupted states;
- a unique launch identity plus PID and process-group ID identifies the owned
  child process tree;
- exclusive child-start and atomic completion receipts let a restarted
  supervisor reconcile explicit evidence;
- cancel, wait, process observation, and process-tree termination return typed
  outcomes;
- a missing process without a completion receipt becomes `interrupted`, never
  `succeeded`.

The `vitalserver-update-handoff-supervisor` executable and its
`serve`, `serve-once`, `enqueue`, `wait`, `cancel`, and internal `run-child`
commands implement this boundary.

The Helper package installs that executable and a dedicated KeepAlive launchd
service. The stable-bootstrap composition persists a deterministic job under
the product-owned update handoff directory before it starts or restarts the
service. The caller may wait for the explicit terminal job evidence, but the
updater process tree is owned by the supervisor and therefore survives the
caller's lifetime. A loaded service is only availability evidence; it is never
treated as update success.

## Prevention

Give long-running product mutation its own durable process owner. Persist a
launch identity before starting a child, require identity-bound start and
completion receipts, and treat unavailable observation as unavailable or
interrupted state rather than reconstructing success from process absence.
