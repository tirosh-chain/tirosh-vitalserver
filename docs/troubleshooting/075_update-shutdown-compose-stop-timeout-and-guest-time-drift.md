# Update shutdown compose stop timeout and guest time drift

> Owner: macOS runtime / guest tools

## Symptom

- Product update verification and bundle staging succeed.
- Update enters rollback during `stop-runtime-services`.
- Runtime status reports:

```text
bundle apply failed; rollback completed:
Guest update shutdown failed at: docker compose stop timed out after 30s
```

- PWA observability timestamps may show Guest-side dates far behind Host time, such as
  `2025-02-22 06:21:36 +09:00` while Host is in 2026.

## Cause

The update bundle was valid and storage preflight passed. The failure happened inside
Guest shutdown preparation after Redis backup completed:

```text
redis backup completed
guest services stop started
docker compose stop timed out after 30s
```

The old Guest default used `compose.stopTimeoutSeconds = 20` with a 10 second command
timeout buffer. This is too short for update shutdown when TestKit sessions, observer
polling, websocket clients, or container health probes are active.

Guest time drift is a separate but related boot contract issue. Host writes explicit
`host-time.json`, but if Guest only applies it during first bootstrap, a later restart
or rollback that reuses the VM disk can keep the image/rootfs clock.

## Fix Direction

- Increase the Guest compose stop timeout used by update shutdown.
- Keep the Host update wait timeout larger than the maximum Guest shutdown path.
- Run Guest host-time synchronization on every boot before Docker, runtime-state,
  observability, command polling, compose, and TestKit services start.
- Preserve compose stop timeout as a typed Guest dependency failure. Do not infer
  success from partial logs or missing status.

## Prevention

- Runtime smoke and update verification should include an update shutdown case with
  active TestKit/observer traffic.
- UI should display Guest-provided timestamps as observed state. It must not correct
  Guest time drift by formatting with Host time.
- Guest time synchronization must consume the Host-owned `host-time.json` contract.
  Missing, unreadable, invalid, or stale host time is a contract failure, not a display
  fallback.
