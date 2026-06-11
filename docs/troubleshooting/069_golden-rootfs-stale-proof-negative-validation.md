# Golden Rootfs Build Trusts Stale Proof After Failed VM Preparation

> ID: TS-069  
> Category: Packaging / Local development / Guest bootstrap  
> Owner: devtools golden rootfs pipeline  
> Status: implemented

## Symptoms

`make internal/vm/golden-rootfs VM_RECREATE_GOLDEN_ROOTFS=true` 또는
`make dist/dmg/dev` 중 golden rootfs 준비가 불안정하게 실패합니다. 대표 증상은 아래처럼 보입니다.

```text
error: timed out waiting for .../.tmp/vitalserver-vm-golden/data/run/rootfs-ready
error: VM launcher log shows terminal guest failure while waiting for rootfs marker: pattern='Internal error: Oops:'
error: VM launcher log shows terminal guest failure while waiting for rootfs marker: pattern='rcu: INFO: rcu_preempt detected stalls'
error: VM launcher process is still running for VM_HOME; refusing to continue with mutable runtime files: ... pids=...
error: rootfs runtime manifest is missing; rebuild the golden rootfs with Docker runtime smoke validation
```

더 위험한 변형은 이전 성공 run의 `rootfs-ready` marker나
`rootfs-runtime-manifest.json`이 남아 있는 상태입니다. 새 VM 준비가 실패했는데 Host/devtools가
이전 marker 또는 manifest를 proof로 오해하면, 실패한 rootfs가 통과했거나 기존
`rootfs-base.raw.gz`를 새 산출물처럼 착각할 수 있습니다.

정상은 golden rootfs 준비의 현재 run이 아래 proof를 모두 새로 제공하는 것입니다.

- 현재 run의 `rootfs-ready`
- 현재 run의 `rootfs-runtime-manifest.json`
- manifest schema v2
- `docker-smoke`, `disk-space`, `compose-build`, `compose-up`, `edge-ready`, `cleanup` 통과
- `ubuntu.metadataStatus=loaded`
- 비어 있지 않은 `ubuntu.baseUrl`, `ubuntu.cacheKey`, `ubuntu.kernel`
- VM lifecycle `stopped`
- 남아 있는 VM launcher process 없음

## Impact

- release/pkg/dmg build가 실제 원인 없이 timeout까지 기다릴 수 있습니다.
- kernel panic, Oops, RCU stall 같은 terminal guest failure를 즉시 실패로 처리하지 못하면 build 시간이 길어집니다.
- 실패한 VM launcher process가 남아 다음 build를 막습니다.
- 이전 성공 manifest나 marker가 남아 있으면 현재 실패가 숨겨지고, rootfs artifact 신뢰성이 깨집니다.
- 기존 `rootfs-base.raw.gz`가 남아 있으면 실패한 build 이후에도 사람이 성공 산출물로 오인할 수 있습니다.

## Cause

Golden rootfs pipeline에서 `rootfs-ready` marker, manifest, launcher log, VM lifecycle, VM process,
compressed rootfs output이 같은 run의 proof인지 명시적으로 묶이지 않으면 stale proof 문제가 생깁니다.

특히 아래 상태는 모두 다른 의미입니다.

- marker missing
- marker stale
- manifest missing
- manifest stale
- manifest failed
- manifest running
- launcher terminal failure
- VM lifecycle failed
- VM lifecycle stopped with terminal reason
- VM launcher process still running
- previous `rootfs-base.raw.gz` still present

이 상태들을 단순히 “없으면 기다림”, “있으면 성공”, “output이 있으면 재사용”으로 처리하면
AGENTS.md의 state/fallback boundary를 위반합니다. Rootfs 준비 proof는 추정하면 안 되고,
현재 run owner가 명시적으로 제공해야 합니다.

## Checks

먼저 현재 `.tmp` 상태와 VM process 잔존 여부를 확인합니다.

```sh
ls -l .tmp/vitalserver-vm-golden/data/run
sed -n '1,260p' .tmp/vitalserver-vm-golden/data/run/rootfs-runtime-manifest.json
sed -n '1,160p' .tmp/vitalserver-vm-golden/run/vm-lifecycle.json
tail -n 240 .tmp/vitalserver-vm-golden/logs/launcher.log

.venv/bin/vitalserver-devtools macos-runtime-require-no-running \
  --vm-home .tmp/vitalserver-vm-golden

rg -n "Internal error: Oops|Kernel panic|rcu_preempt|Undefined instruction|not syncing|timed out waiting for|terminal guest failure" \
  .tmp/vitalserver-vm-golden/logs/launcher.log

ls -lh .tmp/vitalserver-vm-pkg/rootfs-base.raw.gz
```

확인 기준:

- `rootfs-ready`만 있고 manifest가 없으면 proof가 아닙니다.
- manifest가 있어도 schema v2가 아니면 proof가 아닙니다.
- stage가 `running`, `failed`, `timeout`, `not-run`이면 proof가 아닙니다.
- `cleanup.status`가 `passed`가 아니면 proof가 아닙니다.
- launcher log에 kernel panic/Oops/RCU stall이 있으면 timeout까지 기다리지 말고 terminal guest failure로 봅니다.
- VM process가 남아 있으면 mutable runtime files를 다시 쓰면 안 됩니다.

## Actions

개발 환경에서 즉시 조치:

1. VM launcher process가 남아 있으면 먼저 원인을 기록합니다.
2. 현재 `launcher.log`, `vm-lifecycle.json`, `rootfs-runtime-manifest.json`,
   `rootfs-smoke-diagnostics`를 보존합니다.
3. `macos-runtime-require-no-running`이 통과하지 않으면 golden rootfs 재시도를 시작하지 않습니다.
4. stale marker/manifest가 의심되면 현재 run proof와 구분될 때까지 `rootfs-base.raw.gz`를 release
   산출물로 사용하지 않습니다.
5. rootfs size가 8G 미만이면 VM을 띄우기 전에 config/domain validation에서 실패해야 합니다. 실제
   VM disk 부족으로 증상을 재현하려고 작은 rootfs를 부팅하지 않습니다.

## Prevention

적용된 제품/도구 수정:

1. Golden rootfs run identity를 명시합니다.
   - rootfs 준비 시작 시 `runId`를 생성합니다.
   - `rootfs-ready`, `rootfs-runtime-manifest.json`, diagnostics, lifecycle에 같은 `runId`를 기록합니다.
   - 압축 gate는 현재 expected `runId`와 일치하는 manifest만 proof로 인정합니다.
2. 새 run 시작 전 stale proof를 제거하거나 runId mismatch로 무시합니다.
   - `data/run/rootfs-ready`
   - `data/run/rootfs-runtime-manifest.json`
   - `data/run/rootfs-smoke-diagnostics`
   - stale lifecycle/result
3. `wait-rootfs-ready`는 marker만 보지 않습니다.
   - marker 발견 후 manifest schema/stage/cleanup/runId를 함께 확인합니다.
   - failed manifest는 즉시 실패합니다.
   - running manifest는 bounded wait를 계속합니다.
   - launcher terminal pattern은 즉시 실패합니다.
4. 실패한 run은 output artifact를 갱신하지 않습니다.
   - negative test는 `rootfs-base.raw.gz`가 생성되지 않았거나 mtime/hash가 바뀌지 않았음을 확인합니다.
5. 실패 후 process cleanup을 검증합니다.
   - negative runner는 `macos-runtime-require-no-running`을 마지막에 실행합니다.
   - 실패가 expected여도 VM launcher process가 남으면 test 실패입니다.
6. Rootfs size는 두 단계로 방어합니다.
   - `rootfs_size < 8G`는 VM 실행 전 domain gate에서 실패합니다.
   - guest smoke는 disk free space stage를 추가해 Docker/Compose 성공 후 남은 공간이 너무 작으면
     manifest 실패로 기록합니다.

## Applied Fix

- `macos-runtime-rootfs-begin` command가 golden rootfs run context를 만들고 stale
  `rootfs-ready`, manifest, diagnostics를 invalidates 합니다.
- guest deploy metadata의 `runId`가 guest-tools rootfs smoke manifest로 전달됩니다.
- `rootfs-ready`는 JSON marker가 되었고 `runId`를 포함합니다.
- `macos-runtime-wait-rootfs-ready`는 marker만 보지 않고 manifest schema, expected `runId`,
  required stages, cleanup status를 함께 확인합니다.
- `rootfs-base` compression gate는 stopped lifecycle, no running VM process, manifest `runId`,
  ready marker `runId`, required stages, cleanup status를 모두 확인합니다.
- rootfs gzip output은 temporary file validation 후 atomic replace 합니다.
- test-only fault injection은 deploy metadata의 `faultInjection`으로만 활성화되며,
  `testMode=true`가 아니면 guest smoke가 무시합니다.
- `make internal/vm/golden-rootfs/negative`는 실제 VM에서 `edge-ready` fault를 주입하고,
  manifest failure, VM process cleanup, rootfs-base rejection을 검증합니다.

## Required Negative Cases

P0 negative validation은 실제 VM 또는 command-level integration으로 반드시 확인합니다.

| Case | Expected result |
|---|---|
| stale `rootfs-ready` exists before VM start | previous marker is ignored or removed |
| stale passed manifest exists before new run | previous manifest cannot authorize compression |
| marker exists but manifest is missing | compression is rejected |
| marker exists but manifest has failed/running stage | compression is rejected |
| marker exists but cleanup is not passed | compression is rejected |
| launcher log contains `Internal error: Oops` | wait fails before timeout |
| launcher log contains `rcu_preempt detected stalls` | wait fails before timeout |
| VM launcher process remains after failure | negative runner fails cleanup verification |
| previous `rootfs-base.raw.gz` exists before failed run | output is not updated or reported as new |

P1 negative validation can be split between unit tests and VM tests.

| Case | Expected result |
|---|---|
| `edge-ready` timeout | manifest stage is `timeout`, diagnostics are written |
| `compose-up` failure | manifest stage is `failed`, diagnostics are written |
| cleanup failure | `cleanup.status=cleanup-failed`, compression rejected |
| rootfs size below 8G | VM launch is skipped and domain validation fails |
| low disk free space | disk-space stage fails with `df` diagnostics |

## Operational Notes

`rootfs-ready` is a completion marker, not the source of truth. The source of truth is the
current run's validated manifest plus stopped VM lifecycle and absence of a running launcher
process.

When this case recurs, do not fix it by increasing timeout alone. Longer timeout only hides
terminal guest failure, stale proof, or process cleanup bugs.

## Related Cases

- TS-004: rootfs size and Docker install disk full
- TS-038: guest kernel panic and VM lifecycle/recovery ownership
- TS-064: stale build attachment state during DMG rebuild

## Follow-up

- 2026-06-11: golden rootfs smoke was moved into guest-tools and manifest schema v2 was added.
- 2026-06-11: remaining gap identified: robust validation must include stale marker/manifest,
  current-run identity, failed-run artifact protection, and VM process cleanup negative cases.
- 2026-06-11: TS-069 fix implemented with runId proof, stale proof invalidation,
  manifest-aware wait, rootfs-base runId gate, disk-space stage, atomic gzip output,
  and actual negative VM validation for `edge-ready` timeout fault.
