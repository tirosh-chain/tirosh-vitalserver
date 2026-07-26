# VitalServer App OOM Boundary And Evidence

> ID: TS-090
> Category: Runtime health / Recorder streaming
> Owner: macOS runtime / guest compose / recorder ingress
> Status: implemented

## Symptom

During long-running recorder streaming, the upstream VitalServer app process can grow until the guest kernel or container runtime kills the Node process. Operators may then see `guestHTTP: 502`, recorder-ingress upstream failures, host proxy readiness failures, or stale guest runtime state around the same incident.

The app container may later restart, but without explicit container evidence the incident can look like a broad VM failure instead of an app-boundary OOM.

## Cause

The upstream VitalServer application owns internal `send_data`, Redis, filter, and export processing. This repository does not modify upstream VitalServer internals, so downstream runtime code must not pretend to know the app's internal queue or heap state.

Without a container memory boundary, the app can consume memory from the same VM that runs Redis, recorder-ingress, vitaldb-observer, and the guest runtime state writer. Without container inspection evidence, `502` and stale status are only symptoms; they do not prove whether the app was OOM-killed, manually restarted, or failed for another reason.

## Fix Direction

- Set an explicit memory boundary on the VitalServer app container.
- Set an explicit Node old-space limit while preserving the runtime preload shim.
- Collect Docker-owned container evidence in guest runtime state:
  - `oomKilled`
  - `restartCount`
  - `finishedAt`
  - `error`
  - `memoryLimitBytes`
- Record recorder-ingress observed `send_data` ingress counters:
  - observed event count
  - observed compressed payload bytes
  - last observed timestamp
  - recorder-level observed count, bytes, and timestamp

These values are evidence only. The recorder ingress observes recorder ingress traffic, not upstream app in-flight work.

## Prevention Principle

Do not hide upstream app OOM as a generic VM memory problem. The app must fail inside an explicit app boundary, and the runtime state must preserve the difference between OOM, restart, missing inspection data, HTTP `502`, and stale state.

VM memory increases can buy time, but they must not replace an app container boundary or explicit incident evidence.

## Verification

1. `docker compose config` shows an app memory limit and the `NODE_OPTIONS` preload plus old-space setting.
2. `runtime-observation.json` includes app container `oomKilled`, `restartCount`, `finishedAt`, `error`, and `memoryLimitBytes` when Docker inspect provides them.
3. Docker inspect failures remain visible in `probeErrors`; they are not converted into healthy or empty container state.
4. `/recorder-ingress/status` reports observed `send_data` count, bytes, and last timestamp globally and per recorder.
5. A soak test records elapsed time, messages, bytes, app restart/OOM evidence, Redis memory, and guest HTTP status together so the incident chain can be read without inferring state from symptoms.
