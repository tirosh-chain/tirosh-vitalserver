# Watchdog Treats Stale Guest Runtime State As Unrecoverable

## Summary

- ID: TS-057
- Category: Runtime health / Watchdog recovery
- Owner: Runtime watchdog recovery policy
- Status: resolved

## Symptom

`helper-message.log` or Status details repeatedly show:

```text
watchdog cannot recover missing installed artifacts: container-observation-read-failed-guest-runtime-state-stale
Failure reasons: Guest runtime state stale, Host proxy HTTP failed, Audit proxy HTTP failed, Container observation read failed (Guest Runtime State Stale)
```

The wording suggests missing installed files, but the reported blocker is stale guest runtime-state observation.

## Cause

`runtime-state.json` can be present but stale when the guest agent or VM stops updating it. Health evaluation correctly preserves that state as `guest-runtime-state-stale` and derives `container-observation-read-failed-guest-runtime-state-stale` for the compose-services read.

The watchdog recovery policy treated every `containerObservationReadFailed` as an observation-source issue before it reached the recovery planner. That made a stale guest-runtime-state condition terminal, even though the recovery planner can handle it with VM, guest-log-sync, and proxy restart actions when lifecycle and services are available.

## Fix Direction

- Keep real observation-source failures unrecoverable.
- Do not classify `container-observation-read-failed-guest-runtime-state-stale` as missing installed artifacts.
- Let stale guest runtime-state derived container observation failures reach the recovery planner.
- Preserve the failure reason in status/events; only change the recovery decision.

## Prevention

Watchdog policy tests must cover derived failure reasons, not only primary failure reasons. A primary `guest-runtime-state-stale` plus derived `container-observation-read-failed-guest-runtime-state-stale` should produce a recovery plan when VM lifecycle and service state are explicit and recoverable.
