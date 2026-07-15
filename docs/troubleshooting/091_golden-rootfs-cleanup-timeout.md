# Golden Rootfs Cleanup Wait Timeout

> ID: TS-091
> Category: Packaging / Local development / Guest bootstrap
> Owner: devtools golden rootfs wait
> Status: implemented

## Symptoms

`make dist/dmg/dev/compile` or `make devtools/golden-rootfs/compile` fails while waiting for the golden rootfs proof:

```text
error: timed out waiting for .../data/run/rootfs-ready:
last=waiting for rootfs cleanup: status=not-run
```

or the manifest records a cleanup failure after the service stack became ready:

```text
"stage": "rootfs-smoke"
"cleanup": { "status": "cleanup-failed" }
compose-down failed: ... read unix @->/run/docker.sock: read: connection reset by peer
```

## Impact

The DMG/package compile stops before `rootfs-base.raw.gz` is produced. The rootfs smoke may have already proven that Docker image load, Compose build/up, and edge readiness passed, but the rootfs is still rejected because cleanup did not produce an explicit `passed` proof.

## Cause

The guest rootfs smoke has explicit timeouts for Docker image load, Compose build, Compose up, edge readiness, and cleanup. The Host wait for `rootfs-ready` treated `VM_ROOTFS_READY_TIMEOUT` as one absolute deadline. A slower but still progressing run could therefore reach `edge-ready` near that deadline and then be interrupted during cleanup. When the Host cleanup trap stops the VM, Docker inside the guest can shut down while `docker compose down` or a Docker prune command is still running, causing Docker socket reset and a `cleanup-failed` manifest.

Increasing the absolute timeout only moved this race. The first correction from 420 to 600 seconds was insufficient after the image and Compose surface grew. The missing contract was explicit cleanup progress: the manifest stayed `cleanup.status=not-run` until cleanup completed, so the Host could not distinguish an active cleanup command from a stalled Guest.

This is not a recorder ingress readiness failure when the manifest shows `edge-ready: passed` and `vitalserver-recorder-ingress` is healthy in `rootfs-smoke-diagnostics/compose-ps.json`.

## Checks

```sh
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/run/rootfs-failure.json
python3 - <<'PY'
import json
d=json.load(open(".tmp/vitalserver-vm-golden/data/run/rootfs-runtime-manifest.json"))
for stage in d.get("stages", []):
    print(stage.get("name"), stage.get("status"), stage.get("message"))
print("cleanup", d.get("cleanup", {}).get("status"))
print(d.get("cleanup", {}).get("message"))
PY
sed -n '1,260p' .tmp/vitalserver-vm-golden/data/run/rootfs-smoke-diagnostics/compose-ps.json
tail -n 220 .tmp/vitalserver-vm-golden/data/run/rootfs-smoke-diagnostics/journal-docker.txt
```

Look for:

- `docker-image-load`, `docker-smoke`, `compose-build`, `compose-up`, and `edge-ready` all `passed`
- cleanup status `cleanup-failed` or Host wait message `status=not-run`
- Docker journal lines showing `Stopping docker.service` while cleanup is removing containers

## Actions

Retry the compile after rebuilding Guest Tools and devtools with the progress-aware wait fix:

```sh
make dist/pkg/dev/compile
```

`VM_ROOTFS_READY_TIMEOUT` is now an inactivity budget. The Host renews it only when the current runId manifest publishes a new explicit `updatedAt`. A cleanup manifest also publishes `status=running`, `activeCommand`, and `activeCommandTimeoutSeconds` before each command. For a machine that can legitimately spend more than 600 seconds inside one Guest-owned command, increase the inactivity budget for that run:

```sh
VM_ROOTFS_READY_TIMEOUT=720 make dist/pkg/dev/compile
```

Do not mark a rootfs compile as successful when cleanup did not pass. The cleanup proof is part of the product compile contract and prevents packaging a disk with leftover Compose containers, images, volumes, or mutable runtime stores.

## Prevention

The Host default `VM_ROOTFS_READY_TIMEOUT` remains 600 seconds, but it is applied to absence of current-run manifest progress rather than total wall time. Guest-owned stage and cleanup command timeouts remain inside `tirosh-vitalserver-rootfs-smoke`; the Host wait does not turn stale files or another runId into progress.

Cleanup writes a running manifest before work and after every command. On failure, the manifest preserves the failing command, exit code, stdout, stderr, and artifact path. This allows the Host to fail immediately with the actual cleanup reason instead of timing out with the older `not-run` snapshot.

## Operational Notes

If the run still fails after the larger Host wait budget, treat the manifest as the source of truth. A failed `edge-ready` means service readiness failed. A passed `edge-ready` with failed cleanup means cleanup or Docker daemon lifetime failed.

## Related Cases

- TS-069
- TS-070
- TS-071

## Follow-up

- 2026-06-22: Recorder ingress rename increased the rootfs smoke Compose surface. A dev DMG compile reached `edge-ready` with `vitalserver-recorder-ingress` healthy, then failed during cleanup after Docker socket reset. Raised Host rootfs-ready wait budget to 600 seconds.
- 2026-07-15: A package compile reached `edge-ready` at 564 seconds. The absolute 600-second Host deadline stopped the VM during `docker system prune`; Docker returned `connection reset by peer`, and the final `cleanup-failed` manifest arrived after the Host had already reported stale `not-run`. Replaced the absolute deadline with current-run manifest inactivity tracking and added explicit cleanup command progress.
