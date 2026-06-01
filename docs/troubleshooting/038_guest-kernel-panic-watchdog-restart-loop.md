# 038 guest kernel panic 이후 watchdog restart loop가 VM disk 손상을 증폭함

> ID: TS-038  
> Category: Runtime health / VM disk / Watchdog  
> Owner: macOS runtime  
> Status: implemented

## Symptoms

운영 중 별도 update 명령 없이 VitalServer VM이 재시작되고, CPU 사용량이 급격히 올라갑니다. 이후 Remote Console 또는 Helper에는 아래 상태가 반복될 수 있습니다.

- runtime status가 `critical`로 바뀝니다.
- watchdog message가 `guest-http-missing-vm-ip`, `guest-runtime-state-stale`, `host-proxy-http-failed`, `audit-proxy-http-failed`를 보고합니다.
- `launchd.err.log`에 아래 오류가 남습니다.

```text
failed to start VM: Error Domain=VZErrorDomain Code=2 "The storage device attachment is invalid."
```

- `launchd.out.log`에 guest filesystem 또는 kernel panic 로그가 남습니다.

```text
Kernel panic - not syncing: corrupted stack end detected inside scheduler
CPU: ... Comm: jbd2/vda1-8
EXT4-fs error (device vda1): ... checksum invalid
Aborting journal on device vda1-8.
EXT4-fs (vda1): Remounting filesystem read-only
systemd[1]: ... Failed to spawn executor: Input/output error
```

## Impact

- VM이 부팅, guest service start, watchdog restart, launchd respawn을 반복하면서 CPU와 IO 부하가 커집니다.
- guest `runtime-state.json` 갱신이 멈추거나 stale이 되어 Remote Console 상태가 빠르게 악화됩니다.
- host proxy, audit proxy, TestKit/Recorder 상태가 연쇄적으로 failed/stale로 보일 수 있습니다.
- 이미 read-only remount가 발생한 VM disk는 watchdog restart만으로 복구되지 않습니다.
- 같은 update 또는 테스트를 반복하면 mutable VM disk 손상이 더 커질 수 있습니다.

## Cause

2026-05-31 현장 로그에서는 1차 원인이 guest kernel panic이었습니다.

1. guest kernel이 `jbd2/vda1-8` journal thread에서 panic을 기록했습니다.
2. launchd `KeepAlive`가 VM service를 다시 실행했습니다.
3. 재부팅 중 guest runtime state와 host proxy가 잠시 비어 있거나 실패 상태가 됐습니다.
4. watchdog은 이를 recoverable runtime failure로 보고 VM restart를 다시 dispatch했습니다.
5. VM restart는 safe shutdown workflow가 아니라 `launchctl kickstart -k system/com.tirosh.vitalserver-vm` 경로를 탔습니다.
6. loaded launchd job은 `exit timeout = 60`을 사용했고, VM이 60초 안에 종료되지 않자 launchd가 SIGKILL을 보냈습니다.
7. 이후 disk attachment invalid, ext4 journal abort, read-only remount, systemd executor IO error가 반복됐습니다.

이 패턴에서 guest kernel panic과 VM disk read-only 상태가 직접적인 장애입니다. watchdog restart loop는 2차 증폭 요인입니다.

AGENTS.md 기준으로 보면 watchdog은 guest 내부 상태를 로그에서 추정하면 안 됩니다. 하지만 현재 구조에서는 guest가 `kernel-panic`, `filesystem-read-only`, `disk-io-error` 같은 terminal storage 상태를 명시 contract로 제공하지 못하면, host는 `missing vmIP`, `stale runtime-state`, `HTTP failed`만 보고 일반 restart 대상으로 취급합니다.

## Primary Cause Analysis

이번 로그에서 guest kernel panic은 증상 흐름의 1차 원인이지만, 그 원인의 원인은 VM lifecycle ownership gap으로 봅니다. 근거는 아래 순서입니다.

1. `2026-05-31T13:51:11Z` install flow가 VM/watchdog 서비스를 시작했습니다.
2. `2026-05-31T13:51:14Z` install status가 completed로 끝났습니다.
3. `2026-05-31T13:52:12Z` watchdog은 old `bootstrap-result.json`의 `updatedAt=2026-05-23T14:25:45Z`를 보고 guest bootstrap guard가 만료됐다고 판단했습니다.
4. `2026-05-31T13:52:14Z` watchdog은 `guest-http-missing-vm-ip`, `guest-runtime-state-stale`, `host-proxy-http-failed`, `audit-proxy-http-failed`를 recoverable failure로 보고 VM restart를 dispatch했습니다.
5. `2026-05-31T13:52:58Z` guest cloud-init이 완료됐습니다. 즉, watchdog restart 판단은 fresh install 직후 guest bootstrap이 아직 안정화되기 전 구간에서 발생했습니다.
6. `2026-05-31T14:16:xxZ` guest kernel panic이 `jbd2/vda1-8` journal thread에서 발생했습니다.

이 timeline만으로 host restart가 kernel panic의 유일한 원인이라고 단정할 수는 없습니다. 다만 가장 강한 구조적 원인은 다음 세 가지가 겹친 것입니다.

1. install completion과 VM boot readiness가 같은 lifecycle contract로 묶여 있지 않습니다.
2. watchdog bootstrap guard가 stale guest file에 의존했고, fresh boot ownership을 명시적으로 받지 못했습니다.
3. recovery planner가 `missing vmIP`와 `guest HTTP failed`를 booting/waiting 상태와 구분하지 못하고 VM restart로 해석했습니다.

따라서 1차 원인의 원인은 특정 로그 문자열이 아니라, VM boot/update/recovery의 소유 상태가 명시 contract로 모델링되지 않은 구조입니다. guest kernel panic은 그 구조 위에서 발생한 직접 장애이며, 이후 watchdog과 launchd가 같은 disk에 반복 restart pressure를 가하면서 read-only remount와 disk attachment error를 증폭했습니다.

## Checks

먼저 destructive action 없이 timeline을 확인합니다.

```sh
tail -n 260 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.out.log"
tail -n 120 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.err.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/runtime/watchdog.out.log"
tail -n 120 "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl"

jq '{status,operation,message,updatedAt,failureReasons,vmState,vmErrors,guestHTTP,hostProxyHTTP}' \
  "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"

plutil -p "/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist" | grep ExitTimeOut
launchctl print system/com.tirosh.vitalserver-vm | grep "exit timeout"
```

확인할 증거:

- `Kernel panic - not syncing`이 있으면 guest kernel panic이 1차 원인입니다.
- `jbd2/vda1-8`, `EXT4-fs error`, `Aborting journal`, `Remounting filesystem read-only`는 VM disk/journal 손상을 의미합니다.
- `Failed to spawn executor: Input/output error`가 반복되면 guest root filesystem이 정상적으로 실행 파일을 읽지 못하는 상태입니다.
- watchdog log에 `launchd restart label=com.tirosh.vitalserver-vm`가 반복되면 recovery loop입니다.
- plist는 최신 `ExitTimeOut`인데 loaded job이 더 짧은 `exit timeout`을 유지하면 현재 launchd job에는 최신 shutdown timeout이 적용되지 않은 상태입니다.

## Actions

현장 조치:

1. update, rollback, TestKit chaos, Recorder start/stop 같은 추가 쓰기 작업을 멈춥니다.
2. 위 로그와 `runtime-status.json`, `runtime-events.jsonl`을 먼저 export합니다.
3. `EXT4-fs error`, `read-only`, `Input/output error`, `disk attachment invalid`가 확인되면 일반 watchdog recovery를 반복하지 않습니다.
4. Redis backup 또는 보존해야 할 데이터를 확인합니다.
5. VM이 부팅 가능하면 Redis backup을 먼저 시도합니다.
6. VM이 부팅 불가능하거나 read-only가 반복되면 VM disk repair/recreate를 우선 검토합니다.

관련 수동 복구:

```sh
sudo /usr/local/bin/vitalserver-vm runtime repair-vm-disk
```

주의: VM disk repair/recreate는 guest 내부 Docker/Redis runtime state를 새 disk로 교체할 수 있습니다. 호스트의 configured Vital files directory는 VM disk 밖에 있으므로 별도 보존 대상입니다.

## Fix Direction

제품 수정 방향:

1. VM lifecycle owner contract를 추가합니다.
   - VM launcher 또는 install/update workflow가 `bootID`, `operationID`, `state`, `startedAt`, `updatedAt`, `deadlineAt`, `terminalReason`을 가진 lifecycle document를 씁니다.
   - 최소 상태는 `starting`, `bootstrapping`, `running`, `stopping`, `stopped`, `failed`로 분리합니다.
   - 이 contract가 fresh boot의 소유자가 되며, watchdog은 guest file의 오래된 bootstrap result로 boot 상태를 추정하지 않습니다.
2. Guest storage failure를 명시 contract로 올립니다.
   - guest 또는 VM launcher가 `kernel-panic`, `guest-filesystem-read-only`, `guest-disk-io-error`, `disk-attachment-invalid`를 status/event로 기록합니다.
   - Host watchdog은 이 상태를 logs에서 추정하지 않고 contract만 소비합니다.
   - terminal storage failure는 `backupAndRecreateVM` 또는 수동 repair 대상이지 일반 VM restart 대상이 아닙니다.
3. Recovery planner 입력을 lifecycle-aware하게 바꿉니다.
   - `missing vmIP`, `guest HTTP failed`, `runtime-state missing/stale`는 lifecycle state와 함께 해석합니다.
   - lifecycle이 `starting` 또는 `bootstrapping`이면 `waitForGuest`가 policy 결과여야 합니다.
   - lifecycle이 `running`인데 같은 failure가 deadline 이후 지속될 때만 recovery 대상이 됩니다.
   - lifecycle이 `failed`이고 terminal storage reason이 있으면 automatic VM restart를 suppress합니다.
4. Watchdog VM restart 경로를 safe shutdown workflow로 통합합니다.
   - watchdog이 VM을 재시작해야 할 때도 `launchctl kickstart -k`를 직접 호출하지 않습니다.
   - VM process에 graceful stop을 요청하고 명시 timeout 결과를 확인한 뒤 다음 start로 넘어갑니다.
   - stop timeout 결과는 숨기지 않고 event/status에 기록합니다.
5. install/update handoff를 명확히 합니다.
   - install/update status가 completed가 되기 전에 VM lifecycle owner가 fresh `starting` 또는 `bootstrapping` state를 기록해야 합니다.
   - watchdog은 active install/update status만 보는 것이 아니라 lifecycle owner의 boot deadline을 함께 소비합니다.
   - completed는 command process 종료가 아니라 runtime handoff가 끝났다는 뜻으로 제한합니다.
6. loaded launchd job timeout drift를 운영 상태로 노출합니다.
   - plist `ExitTimeOut`과 loaded job `exit timeout` mismatch를 settings/status issue로 표시합니다.
   - mismatch가 있으면 repair/migration이 launchd job reload를 명시 수행합니다.

## Applied Fix

이 TS의 1차 수정은 watchdog restart loop 증폭을 끊는 데 집중합니다.

1. Host-owned VM lifecycle contract를 추가했습니다.
   - `vm/run/vm-lifecycle.json`이 VM process lifecycle을 명시합니다.
   - VM launcher가 `starting`, `bootstrapping`, `stopping`, `stopped`, `failed`를 기록합니다.
   - `failed`는 `disk-attachment-invalid` 같은 terminal reason을 contract로 남깁니다.
2. Health snapshot이 VM lifecycle contract를 소비합니다.
   - lifecycle read/decode/deadline failure는 `vm-lifecycle-document-invalid` 또는 `vm-lifecycle-document-stale`로 노출합니다.
   - missing lifecycle file은 booting으로 추정하지 않습니다.
3. Recovery planner와 watchdog policy가 booting state를 restart로 해석하지 않습니다.
   - lifecycle이 `starting` 또는 `bootstrapping`이고 deadline 안이면 `missing vmIP`와 `guest HTTP missing`은 VM restart가 아니라 recovery deferred로 처리합니다.
   - deadline이 지난 boot lifecycle은 stale로 보고 일반 recovery 판단으로 넘어갑니다.
4. Watchdog VM restart action을 safe workflow로 바꿨습니다.
   - watchdog은 VM restart가 필요할 때 `launchctl kickstart -k`를 직접 dispatch하지 않습니다.
   - guest-log-sync를 멈추고, VM graceful stop/wait path를 통과한 뒤 VM과 guest-log-sync를 다시 시작합니다.
   - safe restart 준비/대기 실패는 critical status/event로 드러냅니다.
5. Storage terminal failure suppress를 contract 기반으로 유지합니다.
   - lifecycle terminal reason이 `disk-attachment-invalid`이면 `RuntimeVMError.diskAttachmentInvalid`로 반영됩니다.
   - data preservation이 필요한 VM error는 automatic recovery를 suppress합니다.

## Resolution Flow

AGENTS.md에 맞춘 구현 순서는 아래가 안전합니다.

1. Contract first
   - `RuntimeVMLifecycleDocument` 또는 동등한 contract를 `Contracts`에 추가합니다.
   - 상태 enum과 terminal reason enum을 먼저 테스트로 고정합니다.
2. Owner write path
   - VM launcher가 process start/stop/failure를 lifecycle document로 씁니다.
   - install/update workflow는 VM start를 요청할 때 fresh `operationID`와 `bootID`를 연결합니다.
3. Consumer read path
   - health checker는 lifecycle document를 snapshot에 싣습니다.
   - read failure, missing, invalid는 각각 다른 failure reason으로 유지합니다.
4. Policy change
   - recovery planner가 lifecycle state를 입력으로 받아 `wait`, `restartProxy`, `safeRestartVM`, `suppress`를 명확히 구분합니다.
   - booting 상태의 `missing vmIP`는 restart가 아니라 wait입니다.
   - terminal storage failure는 suppress + explicit repair action입니다.
5. Action change
   - watchdog의 VM restart action을 safe VM lifecycle workflow로 교체합니다.
   - proxy restart는 기존 launchd restart를 유지할 수 있지만 VM restart와 같은 경로로 묶지 않습니다.
6. UI and observability
   - Remote Console은 lifecycle/status/event contract를 표시만 합니다.
   - UI가 kernel panic, read-only, booting 상태를 로그에서 찾아 만들지 않습니다.
7. Tests
   - booting VM에서 `vmIP == nil`이어도 restart하지 않는 planner test를 추가합니다.
   - terminal storage failure에서 watchdog recovery가 suppress되는 test를 추가합니다.
   - watchdog VM restart가 safe shutdown workflow를 호출하는 test를 추가합니다.
   - stale old bootstrap result가 fresh lifecycle state를 덮어쓰지 못하는 test를 추가합니다.

## Implementation Cautions

AGENTS.md 원칙을 이 TS에 적용할 때 특히 조심할 점:

1. Host가 guest kernel panic을 로그 문자열로 domain state화하지 않습니다.
   - `launchd.out.log`의 `Kernel panic`, `EXT4-fs`, `Input/output error`는 현장 진단 증거입니다.
   - 제품 동작은 guest 또는 VM launcher가 제공하는 명시 contract를 입력으로 삼아야 합니다.
   - 로그 parser를 recovery policy에 직접 넣으면 state owner 경계가 깨집니다.
2. Missing, stale, failed, terminal storage failure를 같은 값으로 합치지 않습니다.
   - `runtime-state missing`은 boot 중일 수 있습니다.
   - `runtime-state stale`은 writer 정지 또는 guest hang일 수 있습니다.
   - `guest-filesystem-read-only`와 `guest-disk-io-error`는 data preservation이 필요한 terminal failure입니다.
   - 이 상태들은 UI 표시, watchdog 판단, repair action에서 서로 다르게 다뤄야 합니다.
3. Watchdog이 repair 도구가 되지 않게 합니다.
   - watchdog은 건강 상태를 관찰하고 제한된 recovery만 수행합니다.
   - VM disk repair/recreate, Redis backup, destructive cleanup은 별도 명령과 확인 가능한 workflow가 맡아야 합니다.
   - storage failure가 보이면 watchdog은 자동 restart를 줄이고, 명시 조치가 필요한 상태를 남깁니다.
4. Safe shutdown을 우회하는 새 restart path를 추가하지 않습니다.
   - `launchctl kickstart -k`는 VM disk flush를 보장하지 않습니다.
   - VM restart가 필요하면 기존 graceful stop과 timeout result 기록을 통과해야 합니다.
   - timeout을 늘리는 것만으로는 구조적 해결이 아닙니다.
5. Recovery planner에 편의 fallback을 넣지 않습니다.
   - `missing vmIP`를 `starting`으로 추정하거나, stale state를 legacy file/probe로 보정하지 않습니다.
   - VM lifecycle owner가 `booting`, `stopping`, `recovering`, `failed-storage` 같은 상태를 명시 제공해야 합니다.
   - consumer는 그 contract를 읽고 policy를 적용합니다.
6. UI가 domain state를 만들지 않습니다.
   - Remote Console은 kernel panic/read-only를 “발견”하거나 추정하지 않습니다.
   - status/event contract에 담긴 failure type과 suggested action을 표시합니다.
   - contract read failure는 empty/healthy/default로 숨기지 않습니다.
7. 테스트는 증폭 루프를 먼저 고정합니다.
   - watchdog이 storage-preserving error에서 restart를 suppress하는 단위 테스트가 필요합니다.
   - VM restart action이 safe shutdown workflow를 호출하는 테스트가 필요합니다.
   - runtime-state missing/stale과 terminal storage failure가 분리되는 테스트가 필요합니다.
   - 로그 문자열에 의존하는 테스트보다 contract 입력/출력 테스트를 우선합니다.

## Prevention

- Guest kernel panic, filesystem read-only, disk IO error는 recoverable HTTP failure와 분리합니다.
- Watchdog은 storage-preservation이 필요한 VM error를 만나면 자동 restart를 suppress합니다.
- VM restart는 항상 guest shutdown과 disk flush가 보장되는 단일 workflow를 사용합니다.
- launchd plist 변경은 loaded job에도 적용됐는지 검증합니다.
- CPU spike만 보고 테스트를 반복하지 않고, 먼저 VM boot loop와 disk health 로그를 확인합니다.

## Related

- TS-013: update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨
- TS-025: update VM disk attachment race
- TS-029: update guest shutdown inference
- TS-037: clean uninstall 이후 stale operation이 rollback/recovery를 유발함
