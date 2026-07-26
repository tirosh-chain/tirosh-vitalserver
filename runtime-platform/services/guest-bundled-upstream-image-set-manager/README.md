# Guest Bundled Upstream Image-set Manager

This is the Guest-owned C64 manager for a bundled VitalServer/Redis container
image set. It is deliberately separate from Guest Product C59 release
activation: a target image set is staged from one verified archive, loaded with
the one declared Guest Docker CLI, and started with the one declared Compose
project. The manager records an explicit `unprovisioned` or `active` state in
its own Guest state directory; it never infers state from `docker ps` or from
the absence of a state file.

Before the long-running API starts, the C39/bootstrap owner must invoke
`--mode initialize-active-image-set` once. That one-shot command creates an
explicit `unprovisioned` selection with exclusive file creation and rejects an
existing selection. A missing selection during normal service is `unavailable`,
not a hidden return to `unprovisioned`; this makes a lost Guest state directory
observable instead of converting it into a safe-looking topology.

It exposes only a loopback and AF_VSOCK HTTP API:

- `POST /v1/bundled-upstream-image-set-updates` — multipart `command`, then
  `imageSetArchive`.
- `GET /v1/bundled-upstream-image-set-updates/{updateId}` — the durable C64
  operation record.

The archive layout is fixed: `image-set.json`, one Compose YAML file, and one
or more `images/*.tar` Docker image archives. Symlinks, special files,
traversal, unknown JSON fields, unverified archive bytes, and an existing
target image-set directory are rejected.

It does not publish a Host listener or own C26/C55. A product release creates
the separately declared C32 Host-loopback bridge and a C55 executor; neither
is allowed to invoke Docker or write C64 state directly.
