# Watchdog Treats Stale Guest Runtime State As Unrecoverable

## Summary

- ID: TS-057
- Category: Runtime health / Watchdog recovery
- Owner: Runtime watchdog recovery policy
- Status: resolved

## Symptom

Older helper builds could show a stale Guest runtime-state condition as a
container-observation blocker:

```text
watchdog cannot recover missing installed artifacts
Failure reasons: Guest runtime state stale, Host proxy HTTP failed, Recorder ingress HTTP failed
```

The wording suggested missing installed files, but the real condition was stale
Guest runtime state.

## Cause

`runtime-state.json` can be present but stale when the guest agent or VM stops
updating it. The old health path also derived a container observation read
failure from that stale document and then treated the derived diagnostic failure
as the blocker.

The v2 policy keeps the primary state explicit. Stale Guest runtime state remains
`guest-runtime-state-stale`, while container observation stays diagnostics
evidence and does not create typed Host failure reasons.

## Fix Direction

- Keep Guest runtime-state failures as Guest agent failures.
- Do not derive Host recovery blockers from container observation read failures.
- Let stale Guest runtime-state reach the recovery planner directly.
- Keep container observation as diagnostics evidence only.

## Prevention

Watchdog policy tests must cover primary failure reasons, not only derived
diagnostics. A primary `guest-runtime-state-stale` should produce a recovery
plan when VM lifecycle and service state are explicit and recoverable.
