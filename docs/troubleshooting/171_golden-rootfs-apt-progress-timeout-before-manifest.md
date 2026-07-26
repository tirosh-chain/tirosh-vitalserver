# Golden rootfs times out after APT progress but before manifest

> ID: TS-171
> Category: Packaging / Local development / Guest bootstrap
> Owner: devtools golden rootfs wait contract
> Status: implemented

## Symptoms

`make dist/dmg/dev` fails while waiting for the golden rootfs proof:

```text
error: timed out waiting for .../data/run/rootfs-ready:
last=manifest missing: .../data/run/rootfs-runtime-manifest.json
```

The current run directory may contain a matching `rootfs-apt-plan.json`, but it
does not contain `rootfs-runtime-manifest.json` or `rootfs-failure.json`. In the
earlier variant, the timeout can occur during `apt-get update`, before the APT
plan can be created at all.

The launcher log shows that APT completed near the 600-second wait boundary,
followed immediately by VM shutdown.

## Cause

`VM_ROOTFS_READY_TIMEOUT` is an inactivity timeout. The Host wait workflow
extended its deadline only when `rootfs-runtime-manifest.json` changed. The
Guest does not create that manifest until after package installation, Guest
Tools installation, and rootfs smoke startup.

When the pinned Ubuntu snapshot was slow, the Guest either produced a valid
current-run `rootfs-apt-plan.json` that the Host did not yet consume, or remained
inside `apt-get update` before that plan boundary. The original deadline expired
and cleanup sent SIGTERM to the VM before the Guest could enter rootfs smoke and
create the manifest. Because the Guest command itself had not failed, no
`rootfs-failure.json` was expected.

## Checks

Compare the runId and timestamps without inferring Guest state from log text:

```sh
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/run/rootfs-apt-plan.json
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/run/rootfs-apt-progress.json
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/run/rootfs-failure.json
tail -n 240 .tmp/vitalserver-vm-golden/logs/launcher.log
```

This case applies when the APT plan belongs to the expected runId, no current
failure document exists, and shutdown begins at the Host wait deadline.

## Fix

The Host wait workflow now treats three current-run documents as explicit
progress contracts:

- `rootfs-apt-progress.json`: `runId` plus `updatedAt`
- `rootfs-apt-plan.json`: `runId` plus `generatedAt`
- `rootfs-runtime-manifest.json`: `runId` plus `updatedAt`

During `apt-get update` and `apt-get install`, the Guest atomically publishes a
running heartbeat every 30 seconds. Each command owns an explicit 1,800-second
timeout. A new valid token extends the Host inactivity deadline. Stale documents
with a different runId or documents without the required timestamp do not
extend it. Invalid current-run documents and explicit failed status terminate
the build. Timeout errors print the last accepted progress token and preserve
the APT progress, APT plan, and manifest inspection messages.

## Prevention

- A wait workflow must consume progress documents owned by the operation, not
  infer progress from launcher log text.
- A multi-stage timeout described as inactivity must reset at every durable
  stage boundary that can legitimately consume most of the timeout budget.
- Stale, invalid, failed, and missing progress documents must remain distinct
  and must not keep a build alive.
- VM cleanup must not hide whether the timeout preceded a Guest failure proof.

## Related Cases

- TS-069
- TS-071
- TS-091
- TS-153

## Follow-up

- 2026-07-21: A snapshot fetch took about 508 seconds and package installation
  completed around VM uptime 597 seconds. The 600-second Host wait expired
  before rootfs smoke created its manifest. Added current-run APT plan progress
  to the inactivity deadline contract and a focused clock-driven regression
  test.
- 2026-07-24: A snapshot index fetch was still active at VM uptime 600 seconds,
  before `rootfs-apt-plan.json` existed. Added atomic Guest-owned APT command
  progress heartbeats for both index update and package install, explicit
  command timeouts, Host consumption of that progress contract, and focused
  running/failed regression tests.
