# 037 clean uninstall 이후 stale operation이 rollback/recovery를 유발함

> ID: TS-037  
> Category: Uninstall / Update / Runtime health  
> Owner: macOS runtime  
> Status: implemented

## Symptoms

Clean uninstall 또는 재설치 직후 아래 증상이 이어서 나타납니다.

- VM이 사라진 것처럼 보이거나 runtime disk가 새로 만들어진 것처럼 보입니다.
- `runtime-events.jsonl`에 uninstall 직후 `rollback` 이벤트가 남습니다.
- watchdog log에 `watchdog recovery plan vm=true proxy=true`가 남고 VM/proxy restart가 수행됩니다.
- `bootstrap-result.json`이 오래된 `running` 상태로 남아 watchdog이 `watchdog guest bootstrap guard expired`를 반복 기록합니다.
- rollback이 없는 artifact를 복원하려다 아래와 같은 오류를 남깁니다.

```text
step failed: rollback-restore-rootfs-base: The file "rootfs-base.raw.gz" couldn't be opened because there is no such file.
```

정상 상태라면 clean uninstall은 이전 update/rollback/watchdog state를 추정 가능한 잔여물로 남기지 않아야 합니다. 이후 새 install 또는 watchdog은 명시된 current operation/guest boot contract만 근거로 동작해야 합니다.

## Impact

- Clean uninstall이 의도한 destructive operation인지, update 실패로 인한 runtime 손상인지 구분하기 어렵습니다.
- 이전 update/rollback runner가 뒤늦게 status/event를 쓰면 운영자는 현재 설치본의 상태로 오해할 수 있습니다.
- watchdog이 stale bootstrap state를 현재 bootstrap으로 취급하면 불필요한 VM/proxy restart가 발생할 수 있습니다.
- rollback preflight가 불충분하면 존재하지 않는 backup artifact를 복원하려고 하며 recovery 로그를 더 혼탁하게 만듭니다.

VM disk가 실제로 삭제됐는지와 VM process가 watchdog으로 재시작됐는지는 반드시 분리해서 판단해야 합니다.

## Cause

확인된 원인은 clean uninstall, update/rollback, watchdog이 같은 runtime 자원을 만지면서도 current operation ownership을 명시 계약으로 공유하지 않는 것입니다.

2026-05-31 현장 로그에서는 아래 흐름이 확인됐습니다.

1. `2026-05-31T13:20:07Z` clean uninstall이 시작됐고 `remove-installed-files`가 완료됐습니다.
2. `2026-05-31T13:21:08Z` runtime event에 `rollback`이 기록됐지만 manager command log에는 rollback 요청이 없었습니다.
3. rollback은 `/Library/Application Support/TiroshVitalServer/backups/20260531T131407Z-before-0.1.10-dev/rootfs-base.raw.gz`를 복원하려다 파일 없음으로 실패했습니다.
4. `2026-05-31T13:24:09Z` fresh install이 시작됐고 `provision-vm-disk`가 새 disk를 만들었습니다.
5. 이후 watchdog은 `guest-http-missing-vm-ip`, `guest-runtime-state-stale`, `host-proxy-http-failed`, `audit-proxy-http-failed`를 근거로 VM/proxy recovery를 수행했습니다.
6. guest `bootstrap-result.json`은 2026-05-23의 `Guest bootstrap is running.` 상태로 남아 있었습니다.

AGENTS.md 원칙상 Host/UI/watchdog은 logs, filename, stale result, 부재 상태를 조합해서 domain state를 추정하면 안 됩니다. State owner가 current state를 explicit contract로 제공하고, consumer는 그 상태를 표시하거나 정책 입력으로만 사용해야 합니다.

## Checks

먼저 destructive action 없이 current state와 timeline을 확인합니다.

```sh
tail -n 200 /private/tmp/tirosh-vitalserver-manager-command.log
tail -n 200 "/private/tmp/tirosh-vitalserver-uninstall.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/install.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/runtime/watchdog.out.log"
tail -n 120 "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl"

jq '{status,operation,message,updatedAt,progress,failureReasons,vmState,vmErrors,vmDisk,runtimeVersion}' \
  "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"

cat "/Library/Application Support/TiroshVitalServer/vm/data/run/bootstrap-result.json"
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json"

find "/Library/Application Support/TiroshVitalServer/backups" -maxdepth 3 -print
stat -f "%Sm %Sp %Su:%Sg %z %N" \
  "/Library/Application Support/TiroshVitalServer/vm/runtime/vm-disk.img" \
  "/Library/Application Support/TiroshVitalServer/vm/runtime/rootfs-base.raw.gz" \
  "/Library/Application Support/TiroshVitalServer/status/runtime-status.json" \
  "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl"
```

확인할 분기:

- `manager-command.log`에 `uninstall started clean=true`가 있으면 VM file 제거의 직접 원인은 clean uninstall입니다.
- watchdog log의 `launchd restart label=com.tirosh.vitalserver-vm`은 VM process restart이지 VM disk 삭제가 아닙니다.
- `runtime-events.jsonl`에 rollback이 있으나 command log에 rollback 요청이 없으면 stale/in-flight runner가 뒤늦게 event를 쓴 가능성을 봅니다.
- `bootstrap-result.json`의 `updatedAt` 또는 boot identity가 현재 VM boot와 맞지 않으면 active bootstrap으로 취급하면 안 됩니다.

## Actions

현장 조치:

1. 현재 runtime이 `healthy`인지 확인합니다.
2. clean uninstall이 의도된 작업이었다면 fresh install 완료 여부와 `vmDisk=present`를 확인합니다.
3. rollback 실패 이벤트가 남아도 현재 install 이후 상태가 healthy이면 과거 stale event로 분리합니다.
4. 동일 현상이 반복되면 update/rollback을 다시 시도하기 전에 command log, runtime events, backup directory manifest를 먼저 수집합니다.
5. VM disk 손상 또는 Redis data 보존 판단이 필요하면 clean uninstall을 반복하지 않고 TS-013, TS-025, TS-016을 먼저 확인합니다.

이번 hotfix에서 반영한 제품 수정:

1. Fresh install 시작 시 guest run directory의 stale state/result 문서를 제거합니다.
   - 제거 대상: `vm-ip`, `runtime-state.json`, `bootstrap-result.json`, update activation/shutdown/datastore repair result.
   - 새 install owner가 이전 guest boot/result를 current state로 승계하지 않습니다.
2. Guest bootstrap result를 boot-scoped contract로 바꿉니다.
   - `bootstrap-result.json`에 `bootID`를 기록합니다.
   - Host health/watchdog은 현재 `runtime-state.json.bootID`와 일치하거나, runtime state가 아직 없을 때 매우 최근인 result만 active bootstrap으로 취급합니다.
   - boot identity가 없거나 현재 boot와 다르면 stale result로 보고 failure/recovery 입력에서 제외합니다.
3. Rollback preflight를 manifest 기반으로 바꿉니다.
   - backup manifest가 `rootfs-base.raw.gz`를 선언한 경우에만 rootfs restore step을 포함합니다.
   - manifest가 선언한 artifact가 없으면 preflight 단계에서 `missingFile`로 중단합니다.
   - manifest가 optional artifact를 선언하지 않으면 존재하지 않는 파일을 복원하려고 시도하지 않습니다.

남은 구조 개선 방향:

1. `RuntimeOperationOwnershipDocument` 같은 명시적 operation owner contract를 추가합니다.
   - 예: `operationID`, `operation`, `owner`, `phase`, `startedAt`, `updatedAt`, `terminalReason`.
   - update/rollback/uninstall/watchdog은 이 contract를 통해 current owner를 확인합니다.
2. clean uninstall은 terminal owner가 됩니다.
   - 시작 시 `operation=uninstall`을 기록합니다.
   - 이전 update/rollback process는 operationID mismatch를 확인하면 status/event/rollback write를 중단합니다.
3. Watchdog recovery 판단을 단순화합니다.
   - watchdog은 operation owner contract, health snapshot, guest state contract만 사용합니다.
   - logs, 오래된 result file, 부재 상태를 조합해 current domain state를 만들지 않습니다.

## Prevention

- Runtime state는 owner가 명시 contract로 제공하고 consumer가 추정하지 않습니다.
- Clean uninstall은 이전 update/rollback이 남긴 request/result/status를 terminal state로 끊습니다.
- Guest result는 boot identity 없이 current state로 사용하지 않습니다.
- Rollback은 backup manifest/preflight가 통과한 artifact만 복원합니다.
- Watchdog은 update/rollback/uninstall owner가 명시된 동안 recovery를 수행하지 않습니다.
- Destructive installed-runtime chaos는 TS-036의 Tier 4 절차로만 검증합니다.

## Operational Notes

- `vm-disk.img`의 수정 시간은 VM이 실행 중이면 계속 바뀔 수 있습니다. mtime만으로 disk가 새로 만들어졌다고 판단하지 않습니다.
- clean uninstall은 의도적으로 VM 영역과 backup 영역까지 제거할 수 있습니다. Redis backup/VM disk 보존이 필요하면 clean uninstall 전에 별도 확인이 필요합니다.
- watchdog recovery log는 service restart 기록입니다. disk deletion, rollback restore, reinstall과 구분해서 읽어야 합니다.
- runtime event history는 과거 operation의 이벤트를 포함하므로 current owner/status와 함께 해석해야 합니다.

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-013`: update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨
- `TS-025`: update 후 VM disk attachment가 invalid로 실패
- `TS-029`: update 중 Host가 Guest shutdown 상태를 추정함
- `TS-030`: Runtime 상태를 Host/UI가 추정하거나 암묵 보정함
- `TS-035`: Update가 Guest capability 계약 없이 request/result worker를 가정함
- `TS-036`: macOS runtime 카오스 테스트 체계가 필요함

## Follow-up

- 2026-05-31: clean uninstall 이후 rollback event와 watchdog recovery가 이어진 현장 로그를 근거로 TS-037을 등록했습니다. 핵심 수정 원칙은 operation ownership, boot-scoped guest result, rollback preflight, watchdog recovery input을 명시 계약으로 분리하는 것입니다.
- 2026-05-31: hotfix에서 fresh install stale guest-run cleanup, `bootstrap-result.json.bootID`, boot-scoped bootstrap result validation, manifest 기반 rollback preflight/restore plan을 추가했습니다. Full operation ownership document는 후속 구조 개선으로 남겼습니다.
- 2026-06-01: 핵심 hotfix가 반영되어 문서 상태를 `implemented`로 갱신했습니다. `RuntimeOperationOwnershipDocument`는 별도 구조 개선 후보로 유지합니다.
