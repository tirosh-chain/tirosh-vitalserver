# PKG reinstall leaves VM Starting after Guest Docker stop timeout

> ID: TS-164
> Category: Packaging / Guest bootstrap / Guest containers
> Owner: Guest bootstrap
> Status: resolved

## Symptoms

After installing the PKG over an existing installation, Helper reports all Host platform services as
`Running`, while VM state remains `Starting`. Runtime product services reports Guest Control `503` and
a failed `docker compose ... ps --all --format json` command.

The Guest bootstrap log contains this failure during runtime data preparation:

```text
subprocess.TimeoutExpired: Command '['systemctl', 'stop', 'docker.service',
'docker.socket', 'containerd.service']' timed out after 30.0 seconds
```

`bootstrap-result.json` remains terminal `failed` with reason code `guest-bootstrap-failed`, even if
Docker and containerd finish stopping shortly after the timeout.

## Impact

The preserved VM and runtime data are not deleted, but the new Guest bootstrap cannot reach Docker
startup, image loading, compose startup, or readiness. Guest Control therefore cannot read product
service state and the Helper cannot declare the VM healthy.

This failure does not by itself require clean uninstall or deletion of the runtime data disk.

## Cause

The reinstall path preserved an existing stack with multiple running containers. Runtime data
preparation asked systemd to stop Docker, its socket, and containerd with a fixed 30-second client
deadline. The compose unit legitimately allows up to 150 seconds for `ExecStop`. In the captured
failure, the compose stack and Docker completed their stop after the 30-second caller deadline, but
bootstrap had already recorded a terminal failure.

The old implementation also stopped the Docker providers directly instead of first naming their
VitalServer consumer units, and it did not prove each unit's final `ActiveState` before continuing.

## Checks

Inspect the Host-visible bootstrap evidence without deriving health from logs:

```sh
sudo cat "/Library/Application Support/VitalServerHelper/vm/data/run/bootstrap-result.json"
sudo tail -n 200 "/Library/Application Support/VitalServerHelper/vm/data/run/bootstrap.log"
```

Inside the Guest, inspect the state owner for each involved unit:

```sh
systemctl show --property=ActiveState --value tirosh-runtime-observation.service
systemctl show --property=ActiveState --value tirosh-vitalserver-container-logs.service
systemctl show --property=ActiveState --value tirosh-vitalserver-compose.service
systemctl show --property=ActiveState --value docker.service
systemctl show --property=ActiveState --value docker.socket
systemctl show --property=ActiveState --value containerd.service
```

The bootstrap result document is the operation result. Later log lines showing that processes stopped
do not convert its terminal `failed` state into success.

## Actions

1. Install a PKG containing the TS-164 fix over the existing installation. It preserves the VM and
   runtime data disk.
2. On an older affected build, if the first reinstall has already allowed all six units above to
   reach `inactive`, running the same PKG again can recover bootstrap without a clean uninstall.
3. If a unit remains `active`, `activating`, `deactivating`, or `failed`, retain the bootstrap and
   journal evidence and diagnose that unit. Do not delete runtime data to hide an incomplete stop.

The fixed Guest bootstrap stops the runtime-observation, container-log, and compose consumers first.
Each stop group receives a 180-second deadline, longer than the compose unit's declared 150-second stop limit.
After the command returns, bootstrap reads every unit's `ActiveState` and proceeds only when all are
explicitly `inactive`. Timeout, nonzero exit, unreadable state, and non-inactive state remain distinct
reported failures.

## Prevention

- Warm reinstall acceptance must cover an existing running compose stack, not only a fresh VM.
- A command timeout must be aligned with the systemd unit deadline it waits for.
- Bootstrap transitions must consume explicit unit state; later log output cannot repair a failed
  operation or become a success fallback.
- Stop commands must report their unit set, deadline, exit output, and final state diagnostics.

## Operational Notes

Reinstall is data-preserving. Clean uninstall is a separate destructive recovery action and is not the
normal response to this timeout. Product Update can carry the same Guest Tools fix, but an installation
already stuck in failed bootstrap may need the fixed PKG because its Guest update control path is not
healthy.

## Related Cases

- `TS-139`: PKG fresh/reinstall disposition and data-preserving failure cleanup.
- `TS-140`: Installed Guest Docker image load failure after bootstrap reaches Docker.
- `TS-165`: Preserved activity history migration exhausts Guest memory during warm reinstall.
- `TS-166`: A preserved boot starts old consumers before replacement bootstrap and exposes the
  Compose `failed`/`Stopped` race.

## Follow-up

- 2026-07-20: Confirmed the failed bootstrap result and 30-second `systemctl stop` timeout on a warm
  reinstall; Guest console evidence showed the compose/Docker stop completing only after the caller had
  failed.
- 2026-07-20: Added ordered consumer/provider stop groups, a 180-second deadline, explicit unit-state
  proof, and focused success/timeout/nonzero/non-inactive tests.
- 2026-07-20: Full dev DMG compile passed golden rootfs preparation, artifact verification, and
  compressed-rootfs runtime boot smoke. The smoke VM's normal compose shutdown took nearly its
  150-second systemd deadline, independently confirming that the former 30-second caller deadline was
  invalid for a running stack.
- 2026-07-20: Rebuilt and statically verified the dev Product Update bundle; checksum/signature
  validation and Finder-metadata inspection of all nested archives passed.
- 2026-07-20: Preserved-runtime reinstall showed that a blocking stop can return while Compose is
  still transitioning from `failed` to `inactive`. The follow-up uses non-blocking stop plus explicit
  state polling and only resets `failed` after `MainPID=0` and `ControlPID=0`; see `TS-166`.
