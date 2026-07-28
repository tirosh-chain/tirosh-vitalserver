# TS-210: Helper update UI infers stable bootstrap state

## Symptom

The Helper shows an update as running because the button action is still executing,
or enables another update when the Platform Agent cannot read the latest stable
update journal. A durable handoff may therefore continue while the UI appears idle.

## Cause

The Host-owned `update_bootstrap_journals` table was not exposed through the
Platform Agent operation-state contract. The Helper compensated with a local
`isApplyingUpdateBundle` flag and the generic runtime operation projection. Those
values describe a UI call and a shared operation lease, not the durable bootstrap
lifecycle after handoff.

## Fix direction

Expose the latest stable update journal as the typed `stableUpdate` resource on
`GET /platform/operations`:

- `missing` means no journal exists and a new update may be admitted.
- `loaded` carries the owner journal and its exact lifecycle state.
- `unavailable` means the owner cannot be reached.
- `failed` preserves a read or decode failure.

The Helper must read this complete contract through the Platform Agent. It may
format the state and disable actions, but it must not reconstruct update state
from a local task, a generic operation, logs, or absence after a failed read.

## Prevention

Every durable operation shown by the Helper needs an explicit owner read model.
Presentation tests must prove that unavailable and failed reads remain visible
and fail closed, and that only owner-declared nonterminal states render progress.
