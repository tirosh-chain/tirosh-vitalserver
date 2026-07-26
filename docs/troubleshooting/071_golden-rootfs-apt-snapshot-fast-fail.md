# Golden Rootfs Apt Snapshot Fast-Fail

> ID: TS-071  
> Category: Packaging / Local development / Guest bootstrap  
> Owner: devtools golden rootfs preflight  
> Status: implemented

## Symptoms

`make dist/dmg/dev/compile` or `make devtools/golden-rootfs/compile` fails after the temporary golden rootfs VM has already started:

```text
error: guest rootfs preparation failed while waiting for rootfs marker:
runId=<run-id> stage=apt-plan exitCode=100
```

The launcher log shows Ubuntu snapshot fetch failures:

```text
Failed to fetch https://snapshot.ubuntu.com/ubuntu/<snapshot>/dists/noble/InRelease
503 Service Unavailable
Unable to locate package docker.io
Package 'python3-venv' has no installation candidate
```

## Impact

The build spends time on Swift build, staging, cloud-init, and VM startup before discovering that the pinned apt snapshot cannot provide package indexes. The final error can look like missing packages even though the root cause is external snapshot unavailability.

## Cause

The golden rootfs pipeline treated apt snapshot availability as Guest-owned work. The Guest script configured snapshot sources and entered `apt-plan`; if `apt-get update` could not fetch indexes, `apt-get -s install` later failed with missing package messages.

Host already owns the build input contract and can read `rootfs-input.json` before starting the VM. It should not defer an unavailable external dependency to a late Guest package operation.

## Checks

```sh
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/run/rootfs-failure.json
tail -n 240 .tmp/vitalserver-vm-golden/logs/launcher.log
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/deploy/build-metadata/rootfs-input.json
```

If the failure is a current `runId`, `stage=apt-plan`, `exitCode=100`, and launcher log contains snapshot `503`, treat it as apt snapshot availability, not a package list change.

## Actions

`macos-runtime-preflight-golden-rootfs` now runs after staging and `macos-runtime-rootfs-begin` but before cloud-init generation and VM start. It checks:

- current `runId` in `golden-rootfs-run.json`
- current `runId`, `guestClockUtc`, and `ubuntu.aptSnapshot` in `rootfs-input.json`
- no running VM launcher for the VM home
- no stale rootfs ready/manifest/failure/apt-plan proof before VM start
- Ubuntu snapshot `noble`, `noble-updates`, and `noble-security` InRelease reachability

The Guest script also separates `apt-index-update` from `apt-plan`, uses bounded APT retries,
and sets `APT::Update::Error-Mode=any`. A partial index fetch therefore fails as
`apt-index-update` instead of advancing to a misleading broken `apt-plan`.

## Prevention

- Host-owned external dependency reads must happen before expensive VM startup.
- Missing, invalid, unavailable, blocked, and failed preflight states must remain distinct.
- Guest should record Guest stage failures, not compensate for missing Host dependency preflight.
- Snapshot endpoint probes may retry bounded transient timeouts, but they must still return `UNAVAILABLE` when all attempts fail. Retry is only for external CDN jitter, not a fallback that treats an unreadable snapshot as valid.

## Related Cases

- TS-069
- TS-070

## Follow-up

- 2026-06-13: Golden rootfs compile reached VM `apt-plan` before detecting snapshot `503 Service Unavailable`. Added Host preflight and separated Guest `apt-index-update` stage.
- 2026-06-19: Dev DMG verify failed before VM start because `noble-updates/InRelease` timed out. Increased snapshot probe timeout and added a bounded retry while preserving final `UNAVAILABLE` status after exhausted attempts.
- 2026-07-21: 세 snapshot 경로가 번갈아 502/503을 반환해 2회 probe가 실제 VM 검증을 막았다. 모든 경로가 실제 2xx를 반환해야 한다는 계약은 유지하고 CDN jitter를 위한 bounded probe를 4회, 3초 간격으로 조정했다.
- 2026-07-21: `apt-get update`가 `noble-updates` 500을 warning으로 남기고 0으로 종료한 뒤 `apt-plan`이 broken package로 실패했다. Partial index를 성공으로 취급하지 않도록 `APT::Update::Error-Mode=any`와 bounded Acquire retry를 명시했다.
