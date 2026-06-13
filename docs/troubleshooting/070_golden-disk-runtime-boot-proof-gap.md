# Golden Disk Runtime Boot Proof Gap

> ID: TS-070  
> Category: Packaging / Local development / Runtime health / Guest bootstrap  
> Owner: devtools golden disk pipeline  
> Status: active

## Symptoms

Golden rootfs build가 통과했는데도 설치 또는 재설치 후 Runtime이 아래 상태로 빠질 수 있습니다.

```text
initializing에서 전환되지 않음
overall health가 degraded 또는 critical로 전환됨
guest bootstrap result가 running에서 멈춤
runtime-state.json이 missing, invalid, stale로 관측됨
service 상태가 Not Reported와 active/failed 사이를 오감
edge /ready는 한때 성공했지만 Runtime Control status가 정상으로 수렴하지 않음
```

TS-069는 stale `rootfs-ready`/manifest를 proof로 믿는 문제를 막았습니다. 하지만 현재 golden disk
검증은 주로 rootfs 준비 VM 안에서 Docker/Compose/edge readiness를 검증합니다. 실제 Runtime boot
path에서 Host가 의존하는 `bootstrap-result.json`, `runtime-state.json`, systemd service 상태,
runtime health convergence까지는 아직 release proof로 묶이지 않았습니다.

## Impact

- build는 성공했지만 설치 직후 Runtime이 초기화 상태에서 멈출 수 있습니다.
- rootfs smoke는 성공했는데 실제 bootstrap service ordering, runtime-state writer, observability
  writer, command poller 같은 운영 service 문제가 뒤늦게 드러납니다.
- Runtime Control UI는 명시 상태 없이 Not Reported, degraded, critical을 반복 표시할 수 있습니다.
- golden disk가 실제 운영 boot proof를 제공하지 않으면 VM 관련 장애가 설치 후에야 발견됩니다.

## Cause

Rootfs smoke와 Runtime boot proof가 다른 책임을 갖는데, 현재 golden disk pipeline은 Runtime boot proof가
부족합니다.

- Rootfs smoke는 이미지 내부 dependency, Docker runtime, Compose build/up, edge readiness를 확인합니다.
- Runtime boot proof는 실제 bootstrap path 이후 Host가 소비하는 runtime contracts를 확인해야 합니다.

특히 아래 상태는 marker나 HTTP 200 하나로 대체하면 안 됩니다.

- `bootstrap-result.json` missing
- `bootstrap-result.json.status=running` stale
- `bootstrap-result.json.status=failed` with reasonCodes
- `runtime-state.json` missing
- `runtime-state.json` invalid JSON
- `runtime-state.json.updatedAt` stale
- `runtime-state.json.bootID` missing
- `runtime-state.json.containerServices` missing or empty
- required systemd unit inactive/failed/activating timeout
- compose service exited/restarting/unhealthy
- guest HTTP probe failed
- disk health reports read-only rootfs or kernel disk errors
- feature capability flags are missing or false for installed functionality
- Guest command request/result dispatch is not available for update, backup, restore, repair
- Observability read model or event store is unavailable
- Runtime data backup directory is missing but reported as an empty backup list
- TestKit service is expected in dev builds but not available after boot

AGENTS.md 기준으로 Host는 Guest 내부 상태를 로그나 추측으로 만들면 안 됩니다. Guest가 명시 contract를
제공하고, golden disk pipeline은 그 contract가 실제 Runtime boot에서 제공되는지 검증해야 합니다.

## Checks

설치 또는 dev VM에서 아래 proof를 확인합니다.

```sh
sed -n '1,200p' .tmp/vitalserver-vm-dev/data/run/bootstrap-result.json
sed -n '1,260p' .tmp/vitalserver-vm-dev/data/run/runtime-state.json
sed -n '1,200p' .tmp/vitalserver-vm-dev/run/vm-lifecycle.json
tail -n 240 .tmp/vitalserver-vm-dev/logs/launcher.log
```

Guest 안에서 확인할 수 있으면 아래 상태가 Runtime boot proof의 최소 기준입니다.

```sh
systemctl is-active docker
systemctl is-active tirosh-runtime-state.service
systemctl is-active tirosh-vitalserver-compose.service
systemctl is-active tirosh-guest-observability.service
systemctl is-active tirosh-vitalserver-command-poller.service
curl -fsS -I --max-time 5 http://127.0.0.1/ready
curl -fsS -I --max-time 5 http://127.0.0.1/health
tirosh-runtime-state once
```

## Actions

단기 조치:

1. Runtime이 initializing/degraded/critical에서 멈추면 `bootstrap-result.json`과
   `runtime-state.json`을 먼저 확인합니다.
2. `bootstrap-result.status=running`이면 stale인지 bootID/updatedAt 기준으로 판단합니다.
3. `runtime-state.json`이 없거나 invalid면 runtime-state writer/service 문제로 분리합니다.
4. systemd service가 inactive/failed이면 edge HTTP 결과만으로 정상 boot로 보지 않습니다.
5. launcher log의 kernel panic/Oops/RCU stall은 TS-069와 같은 terminal guest failure로 처리합니다.

## Prevention

Golden disk pipeline에 Runtime boot proof target을 추가합니다.

1. `runtime-boot-smoke` guest-tools command를 새로 둡니다.
   - rootfs smoke와 분리합니다.
   - 실제 bootstrap 이후 Host가 소비하는 contract만 검증합니다.
2. `make internal/vm/golden-rootfs/runtime-smoke` target을 추가합니다.
   - golden rootfs cache를 사용해 별도 VM home을 부팅합니다.
   - bootstrap 완료, runtime-state fresh, systemd units active, HTTP health를 검증합니다.
   - 성공 proof를 manifest로 남깁니다.
3. `rootfs-base` 또는 release gate는 runtime smoke proof가 필요한 build mode에서 해당 proof를 요구합니다.
   - rootfs dependency proof와 Runtime boot proof를 서로 다른 manifest로 유지합니다.
   - 두 manifest는 같은 rootfs artifact fingerprint 또는 runId로 연결합니다.
4. 실패 상태는 empty/default success로 바꾸지 않습니다.
   - missing, invalid, stale, failed, timeout을 각각 다른 failure reason으로 기록합니다.

## Feature Scenario Proof

Runtime boot smoke는 “VM이 켜졌다”만 증명하면 안 됩니다. Helper/PWA가 제공하는 기능이 Runtime
contract를 통해 실행 가능한 최소 상태인지도 확인해야 합니다. 단, 모든 기능을 boot smoke 안에서
실제 mutate하지는 않습니다. Boot smoke는 capability와 read contract를 확인하고, destructive 또는
long-running workflow는 별도 scenario smoke로 분리합니다.

| Feature scenario | Runtime boot proof | Separate workflow smoke |
|---|---|---|
| Status / Advanced | runtime status, failure reasons, VM lifecycle, service states, host/guest HTTP가 읽힘 | installed health command |
| Settings read/apply | saved config와 applied VM config snapshot을 구분해서 읽을 수 있음 | restart-required setting apply, no-restart setting apply |
| Update verify/apply | `prepareUpdateShutdown`과 `activateUpdate` capability가 true이고 command poller active | update shutdown, activation, rollback negative |
| Redis backup/restore | `redisBackup`, `redisRestore` capability가 true이고 request/result/log path가 writable | create Redis backup, restore Redis backup |
| Runtime data backup/restore | runtime data backup root가 missing/empty/error를 구분해서 읽힘 | create runtime data backup, restore runtime data backup |
| Repair runtime/datastore | repair capability와 command dispatch path가 available | datastore repair fault/recovery |
| Observability / Events | event store, observability DB, recorder observation read model이 readable | event append/read, corrupt store negative |
| Recorders / Beds | VitalDB observer endpoint responds and observation document is schema valid | testkit recorder observed/missing/stale scenarios |
| TestKit | dev build이면 testkit service/image/API가 available; release build이면 explicit disabled state | start/pause/resume/delete/reset virtual recorders |
| Logs / Export logs | log roots and diagnostic collectors are readable without creating false empty success | export logs archive smoke |
| Clean uninstall / Reset Installer | runtime status writer must not recreate removed product root; force-clean contract remains separate | uninstall/reset package scenario |

Boot smoke가 직접 실행해도 되는 것은 read-only 또는 bounded local probe입니다.

- Runtime status read
- Settings read contract
- backup list read with missing/error/empty distinction
- Observability/event store read
- TestKit availability read
- command capability read
- command poller service active check

Boot smoke가 직접 실행하지 말아야 하는 것은 VM stop, update apply, restore, uninstall처럼 side effect가
큰 workflow입니다. 이들은 별도 scenario target에서 실행하고, TS-070 manifest에는 “scenario smoke
required”로 남깁니다.

## Required Positive Proof

Runtime boot smoke는 최소 아래를 통과해야 합니다.

| Proof | Required result |
|---|---|
| `bootstrap-result.json` | schema valid, `status=completed`, current bootID 또는 current runId |
| `runtime-state.json` | schema valid, fresh `updatedAt`, non-empty `bootID` |
| VM IP | non-loopback `vmIP` present |
| HTTP | `/ready` and `/health` return 2xx |
| systemd | docker, runtime-state, compose, observability, command-poller active |
| compose services | expected service set reported; no exited/restarting required service |
| disk health | root filesystem not read-only; no kernel disk error lines |
| capabilities | `prepareUpdateShutdown`, `activateUpdate`, `redisBackup`, `redisRestore`, `repairDatastore` are explicit booleans |
| command dispatch | command poller service active; request/result directory writable; no stale request files |
| backup read models | host, Redis, runtime-data backup lists distinguish missing/error/empty |
| runtime data backup root | missing directory is reported as unavailable, not empty success |
| settings read contract | saved config and applied VM config snapshot are both present when applicable |
| observability read | event store and runtime observability DB can be opened read-only |
| recorder observation | VitalDB observer endpoint returns schema-valid JSON or explicit unavailable state |
| testkit availability | dev build reports testkit available; release build reports explicit disabled state |
| log collection readiness | log roots exist or explicit unavailable state is recorded |
| lifecycle | VM lifecycle is running during smoke and stopped after cleanup |
| launcher process | no stale launcher process after target cleanup |

## Required Negative Cases

P0 negative validation은 실제 VM 또는 command-level integration으로 반드시 확인합니다.

| Case | Fault injection | Expected result |
|---|---|---|
| bootstrap result remains running | write `bootstrap-result.status=running` and stale updatedAt | runtime smoke rejects stale bootstrap |
| bootstrap result failed | write `status=failed` with reasonCodes | runtime smoke rejects and reports reasonCodes |
| runtime state missing | remove `runtime-state.json` | runtime smoke rejects missing state |
| runtime state invalid | write invalid JSON | runtime smoke rejects invalid state |
| runtime state stale | write old `updatedAt` | runtime smoke rejects stale state |
| runtime state missing bootID | write state without `bootID` | runtime smoke rejects incomplete contract |
| compose service failed | stop/fail compose unit or report exited service | runtime smoke rejects service failure |
| runtime-state service inactive | stop `tirosh-runtime-state.service` | runtime smoke rejects systemd failure |
| observability service inactive | stop `tirosh-guest-observability.service` | runtime smoke rejects systemd failure |
| guest HTTP unavailable | block/stop edge | runtime smoke rejects `/ready` or `/health` failure |
| disk health read-only | inject diskHealth rootFilesystemReadOnly=true | runtime smoke rejects storage failure |
| capability missing | remove `capabilities` from runtime-state | runtime smoke rejects incomplete feature contract |
| command poller inactive | stop `tirosh-vitalserver-command-poller.service` | runtime smoke rejects command dispatch unavailable |
| stale request file exists | leave backup/update/repair request without matching result | runtime smoke rejects stale dispatch trigger |
| runtime data backup root missing | remove runtime-data backup directory | runtime smoke reports unavailable, not empty list |
| backup list decode failure | write invalid backup metadata | runtime smoke rejects read model corruption |
| settings applied snapshot missing | remove applied VM config snapshot | runtime smoke rejects Settings/Status mismatch risk |
| observability DB unreadable | remove permission or corrupt sqlite file | runtime smoke rejects observability read issue |
| event store append/read unavailable | deny event store path | runtime smoke rejects event store unavailable |
| observer endpoint invalid JSON | make VitalDB observer return non-object | runtime smoke rejects recorder observation contract |
| dev testkit unavailable | dev build without testkit service/image | runtime smoke rejects missing testkit feature |

P1 negative validation:

| Case | Expected result |
|---|---|
| container observation missing | runtime smoke rejects missing compose service documents |
| probeErrors contain critical source | runtime smoke rejects explicit probe failure |
| VM stops during smoke | lifecycle failure is reported instead of timeout-only failure |
| Redis backup command result missing | scenario smoke rejects missing result instead of pending forever |
| Redis restore command result failed | scenario smoke reports failed restore result |
| runtime data backup create fails | scenario smoke preserves failure reason |
| update activation command unavailable | scenario smoke fails before applying update bundle |
| Settings no-restart field causes VM restart | scenario smoke rejects configure policy regression |
| Settings restart-required field is shown as applied before restart | scenario smoke rejects saved/applied state collapse |
| Export logs archive missing required runtime files | scenario smoke rejects incomplete support bundle |

## Implementation Direction

1. Add a `RuntimeBootSmokeContext` and manifest schema.
   - `schemaVersion`
   - `runId`
   - `rootfsArtifactFingerprint`
   - `startedAt`, `updatedAt`
   - `stages`
   - `bootstrapResult`
   - `runtimeState`
   - `systemdUnits`
   - `http`
   - `capabilities`
   - `commandDispatch`
   - `settingsRead`
   - `backupReadModels`
   - `observabilityRead`
   - `recorderObservation`
   - `testkitAvailability`
   - `logCollectionReadiness`
   - `cleanup`
2. Add guest-tools command:
   - `tirosh-vitalserver-runtime-boot-smoke`
3. Add devtools wait/gate command:
   - `macos-runtime-wait-runtime-boot-smoke`
4. Add Make targets:
   - `internal/vm/golden-rootfs/runtime-smoke`
   - `internal/vm/golden-rootfs/runtime-negative`
   - `internal/vm/golden-rootfs/feature-smoke`
   - `internal/vm/golden-rootfs/feature-negative`
5. Add scenario groups.
   - `status-read`
   - `settings-read`
   - `backup-read`
   - `observability-read`
   - `recorder-observation-read`
   - `testkit-availability`
   - `command-dispatch-readiness`
6. Add tests before VM target wiring.
   - unit tests for bootstrap/runtime-state validators
   - unit tests for capability/read-model validators
   - command-level tests for missing/invalid/stale cases
   - one actual VM positive runtime smoke
   - at least one actual VM negative runtime smoke
   - one non-destructive feature smoke for read-only feature contracts

## Implementation Status

2026-06-11 phase 1 implemented the Runtime boot smoke contract layer.

- Added guest command `tirosh-vitalserver-runtime-boot-smoke`.
- Added manifest `runtime-boot-smoke-manifest.json`.
- Added Host/devtools wait gate `macos-runtime-wait-runtime-boot-smoke`.
- Added Make target `internal/vm/golden-rootfs/runtime-smoke`.
- Bootstrap runs runtime boot smoke only when deploy metadata explicitly sets
  `runtimeBootSmoke.enabled=true`.
- Runtime boot smoke currently validates the 18 positive proof items through these stages:
  - `bootstrap-result`
  - `runtime-state`
  - `systemd-units`
  - `http`
  - `compose-services`
  - `disk-health`
  - `capabilities`
  - `command-dispatch`
  - `feature-readiness`

Implemented command-level negative coverage:

| Case | Coverage |
|---|---|
| bootstrap result remains running | unit test |
| bootstrap result failed | unit test |
| runtime state missing | unit test |
| runtime state invalid | unit test |
| runtime state stale | unit test |
| runtime state missing bootID | unit test |
| runtime-state service inactive | unit test |
| guest HTTP unavailable | unit test |
| disk health read-only | unit test |
| capability missing | unit test |
| stale request file exists | unit test |
| observer endpoint invalid JSON/read model shape | unit test |
| dev testkit unavailable | unit test |
| runtime boot smoke manifest failed stage | devtools unit test |
| runtime boot smoke manifest stale runId | devtools unit test |
| runtime boot smoke stale lifecycle proof | devtools unit test |
| wait-stopped stale stopping lifecycle with no launcher process | devtools unit test |

2026-06-11 phase 2 verified the actual golden disk runtime boot path locally.

- `make internal/vm/golden-rootfs/runtime-smoke` passed end-to-end.
- Positive VM proof runId: `ce055712-8df2-41df-ba7a-fe2b266c87bd`.
- The target now invalidates stale `runtime-boot-smoke-manifest.json` and
  stale `vm-lifecycle.json` before starting a new runtime smoke run.
- Bootstrap starts the compose stack through `tirosh-vitalserver-compose.service`
  so the systemd proof matches the actual runtime owner.
- Compose stop is bounded to avoid multi-minute VM shutdown hangs during build
  verification.
- `macos-runtime-wait-stopped` accepts explicit Host process absence when a stale
  lifecycle document remains in `stopping`, while still rejecting lifecycle
  `failed`.

Still separate from this phase:

- CI required checks must run an explicit package/runtime validation target before release handoff.
- Runtime data backup/restore create and restore scenarios remain separate workflow smoke.
- Redis backup/restore create and restore scenarios remain separate workflow smoke.
- Settings apply restart/no-restart scenario remains separate workflow smoke.
- Update activation/shutdown/rollback scenario remains separate workflow smoke.
- Observability event append/read and export logs archive completeness remain separate
  workflow smoke.

2026-06-13 follow-up added explicit package validation workflows:

- `make dist/dmg/dev/runtime-smoke`
- `make dist/pkg/dev/runtime-smoke`
- `make dist/dmg/dev/verify`
- `make dist/pkg/dev/verify`
- `make dist/dmg/release/verify`
- `make dist/pkg/release/verify`

`compile` remains the artifact creation contract. `runtime-smoke` owns golden runtime boot proof.
`verify` is the installation/release handoff gate that runs both.

## Operational Notes

Do not merge this into TS-069. TS-069 proves the golden rootfs preparation run. TS-070 proves that
the resulting disk can pass the actual Runtime boot contracts that Host and UI consume.

Do not solve this by extending timeout only. Timeout only helps a slow success path. The repeated
failures here are state contract gaps: missing, invalid, stale, failed, and unknown must stay
separate.

## Related Cases

- TS-038: Guest kernel panic 이후 watchdog restart loop
- TS-047: Guest log sync service remains stopped after runtime restart
- TS-053: Update와 watchdog이 runtime status를 두고 경합함
- TS-067: Initial install shows degraded during VM bootstrap
- TS-069: Golden rootfs build trusts stale proof after failed VM preparation

## Follow-up

- 2026-06-11: TS-069 closed the rootfs proof/stale marker gap. Remaining robust golden disk work
  requires actual Runtime boot proof and runtime negative cases.
- 2026-06-11: Runtime boot smoke phase 1 added guest manifest validation, Host wait gate,
  Make target, and command-level positive/P0 negative tests. Mutating feature workflows are
  still tracked as separate scenario smoke work.
- 2026-06-11: Runtime boot smoke phase 2 passed an actual golden disk boot and exposed two
  host-side robustness gaps: stale lifecycle proof before smoke start and stale `stopping`
  lifecycle after launcher exit. Both are now covered by devtools tests.
