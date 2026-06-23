# 075 Service liveness uptime shows hundreds of days

> Category: Runtime health / Runtime Control PWA  
> Owner: runtime status presentation and guest runtime-state contract  
> Status: implemented  
> First seen: 2026-06-13

## Symptom

Helper Advanced > Service liveness shows services as healthy or reachable, but inline uptime is hundreds of days, for example `476d 11:27:30`, immediately after a fresh install or runtime smoke.

## Cause

Guest `runtime-state.json` reports two different time facts for each compose service:

- `startedAt`: Docker/container timestamp from the guest clock.
- `uptimeSeconds`: explicit duration computed by the guest state owner.

The presentation formatter treated `runtimeStateUpdatedAt` as a host-safe observation timestamp and added `now - observedAt` to `uptimeSeconds`. When the guest clock differed from the host clock, the UI created a new inferred duration across the Host/Guest boundary. A fresh runtime could therefore display hundreds of days even though `uptimeSeconds` was only tens of seconds.

## Fix Direction

- Treat `uptimeSeconds` as the explicit duration owned by the guest runtime-state writer.
- Use `startedAt` only when `uptimeSeconds` is missing.
- Do not extrapolate uptime from `runtimeStateUpdatedAt` in presentation code.
- Extend runtime boot smoke to require explicit, non-negative, bounded service `uptimeSeconds` for fresh smoke compose services.

## Prevention

Do not combine timestamps from different clock owners to create domain state. Host/UI may format explicit state, but must not infer uptime from guest timestamps when an explicit duration exists.

Validation coverage should stay split by responsibility:

- Swift compile/tests verify presentation policy uses explicit `uptimeSeconds`.
- `runtime-smoke` verifies actual guest `runtime-state.json` contains sane explicit service uptime for the fresh boot proof.
- `verify` combines the package build and runtime smoke gates before install handoff.
