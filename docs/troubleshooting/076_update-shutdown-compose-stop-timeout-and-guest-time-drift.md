# Update shutdown compose stop timeout and guest time drift

> Owner: macOS runtime / guest tools

## Symptom

- Product update verification and bundle staging succeed.
- Update enters rollback during `stop-runtime-services`.
- Runtime status reports:

```text
bundle apply failed; rollback completed:
Guest update shutdown failed at guest-services-stop:
service app did not stop; remaining services: app, redis
```

- PWA observability timestamps may show Guest-side dates far behind Host time, such as `2025-02-22 06:21:36 +09:00` while Host is in 2026.

## Cause

The update bundle was valid and storage preflight passed. The failure happened inside Guest shutdown preparation after Redis backup completed:

```text
redis backup completed
guest services stop started
docker compose stop timed out while stopping app after 90s
```

Older Guest shutdown used one whole-stack `docker compose stop` call. When one or two services remained running, the result only said that compose stop timed out. Operators had to inspect `guest-observability/shutdown-failure.latest.json` to learn which services were still up.

Guest time drift is a separate but related boot contract issue. Host writes explicit `host-time.json`, but if Guest only applies it during first bootstrap, a later restart or rollback that reuses the VM disk can keep the image/rootfs clock.

## Fix Direction

- Stop Guest compose services in an explicit update shutdown order: `testkit`, `edge`, `swagger-ui`, `redis-ui`, `recorder-ingress`, `vitaldb-observer`, `app`, then `redis`.
- Use service-specific timeouts: default 30s, `app` 90s, `redis` 60s. These give shutdown-heavy services more time without hiding which service is blocking shutdown.
- On timeout, write typed failure details into `prepare-update-shutdown-result.json`: `failedService`, `remainingServices`, `serviceStates`, stop timeouts, and `failureSnapshotPath`.
- Keep the Host update wait timeout larger than the maximum Guest shutdown path.
- Run Guest host-time synchronization on every boot before Docker, runtime-state, observability, command polling, compose, and TestKit services start.
- Preserve compose stop timeout as a typed Guest dependency failure. Do not infer success from partial logs or missing status.

## Diagnosis

Check the Guest shutdown result first:

```text
/Library/Application Support/VitalServerHelper/vm/data/run/prepare-update-shutdown-result.json
```

For ordered stop failures, expect explicit details:

```json
{
  "status": "failed",
  "step": "failed",
  "message": "Guest update shutdown failed at guest-services-stop: service app did not stop; remaining services: app, redis",
  "details": {
    "stopAction": "ordered-compose-stop",
    "failedService": "app",
    "remainingServices": ["app", "redis"],
    "failureSnapshotPath": "/mnt/tirosh/run/guest-observability/shutdown-failure.latest.json"
  }
}
```

Then inspect the snapshot referenced by `failureSnapshotPath`. It is Guest-owned observed state, not Host log inference.

## Prevention

- Runtime smoke and update verification should include an update shutdown case with active TestKit/observer traffic.
- Update shutdown must report the service that failed to stop. A generic compose timeout is not enough to diagnose rollback cause.
- UI should display Guest-provided timestamps as observed state. It must not correct Guest time drift by formatting with Host time.
- Guest time synchronization must consume the Host-owned `host-time.json` contract. Missing, unreadable, invalid, or stale host time is a contract failure, not a display fallback.
