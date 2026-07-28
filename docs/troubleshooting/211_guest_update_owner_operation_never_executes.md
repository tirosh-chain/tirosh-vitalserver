# Guest update owner operation never executes

> ID: TS-211
> Category: Update / Guest execution
> Owner: Guest Update Owner Worker
> Status: resolved at Guest execution boundary

## Symptom

- Container image-set or Guest Runtime release `apply`/`rollback` returns a
  durable `pending` operation, but it never reaches a terminal state.
- A Host layer executor can see the target digest but has no safe way to make
  the archive available inside the Guest.
- A process restart can leave an operation in `running`, while the physical
  Docker or release-slot outcome is unknown.

## Cause

The first owner-state implementation deliberately stopped at command
acceptance. It had no explicit archive import contract and no Guest worker that
claimed the durable operation before invoking Docker, Compose, archive
extraction, or release activation.

Treating a Host staging path as a Guest path would cross the Host/Guest
boundary. Reusing the archive filename, a Compose log, or process exit as the
operation result would also infer state rather than obtain it from the owner.

## Fix direction

Guest Control now has two explicit execution boundaries:

- `PUT /runtime/update-artifacts/{kind}/{sha256:digest}` imports bytes into a
  Guest-owned content-addressed store. The store verifies SHA-256 during import
  and again immediately before an effect uses the archive.
- `tirosh-vitalserver-update-owner-worker` reads durable `pending` work,
  records `running`, executes a typed effect port, and records exactly one
  `succeeded`, `failed`, or `unavailable` outcome.

The container effect executes `docker image load` from the verified Guest
archive and then reconciles the declared Compose stack. The Guest Runtime
effect rejects absolute paths, parent traversal, links, and device entries,
extracts into a private staging directory, atomically installs an immutable
release slot, switches the active link, and restores the previous active link
if service reconciliation fails.

A worker restart does not retry an effect whose outcome is unknown. Existing
`running` operations become `unavailable` with
`containerImageSetWorkerInterrupted` or
`guestRuntimeReleaseWorkerInterrupted`. Still-`pending` operations may then be
claimed normally.

The Host bundle executors are a separate boundary. They may write a successful
layer receipt only after importing the archive, submitting a correlated
command, and reading the matching Guest owner operation in a terminal
`succeeded` state.

## Prevention

- Never pass a Host filesystem path as if it were Guest-owned artifact state.
- Reverify immutable bytes at every trust boundary and immediately before the
  side effect.
- Persist `running` before Docker, extraction, active-link switching, or
  service reconciliation.
- Do not infer success after worker restart; the physical effect may have
  completed even though settlement did not.
- Reject archive links and traversal entries before extracting any member.
