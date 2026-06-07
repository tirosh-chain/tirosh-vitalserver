# 035 Update가 Guest capability 계약 없이 request/result worker를 가정함

> ID: TS-035  
> Category: Update  
> Owner: macOS runtime / guest runtime contracts  
> Status: active

## Symptoms

VitalServer Helper의 Update 적용 중 아래 증상이 함께 나타날 수 있습니다.

- Update가 `prepare-update-shutdown` 단계에서 오래 진행되지 않습니다.
- command log에 아래 흐름이 보입니다.

```text
guest update shutdown requested version=<version>
waiting for guest update shutdown result timeoutSeconds=300.0
waiting for guest update shutdown worker
```

- `/Library/Application Support/TiroshVitalServer/vm/data/run/prepare-update-shutdown.request`는 존재하지만, `prepare-update-shutdown-result.json`과 `prepare-update-shutdown.log`가 없습니다.
- 이후 timeout 또는 rollback으로 넘어가도 UI는 `Failed to refresh log collection: "tirosh-vitalserver-manager-command.log" couldn't be copied because you don't have permission to access "logs".` 같은 로그 refresh 실패만 보여 실제 update 상태를 흐릴 수 있습니다.

정상 상태라면 Host가 Guest에 update shutdown preparation을 요청하기 전에 Guest가 해당 capability를 제공하는지 명시적으로 알고 있어야 합니다. 요청 후에는 Guest owner가 result 문서로 `running`, `ready`, `failed`, `unsupported` 같은 상태를 제공해야 합니다.

## Impact

Update가 apply 중간에서 멈춘 것처럼 보이고, timeout 이후 rollback 또는 service stop 단계로 넘어갈 수 있습니다.

이 증상은 단순 UI 로그 표시 문제가 아닙니다. 실제 update flow가 Guest worker 응답을 기다리는 상태일 수 있으며, rollback 중 guest service stop까지 길게 대기하면 운영자는 update 실패 원인과 현재 상태를 구분하기 어렵습니다.

데이터 보존 경계에서는 update 전 managed backup이 생성됐는지 먼저 확인해야 합니다. 현재 상태를 로그 refresh 실패만 보고 판단하면 안 됩니다.

## Cause

Host update flow가 Guest 내부의 request/result worker 존재와 dispatch mechanism을 명시 계약으로 확인하지 않고 가정합니다.

현재 Product Update flow는 `prepare-update-shutdown.request`를 host-visible run directory에 쓰고, Guest systemd path unit이 이를 감지해 `prepare-update-shutdown-result.json`을 생성하기를 기다립니다. 하지만 기존 설치본의 Guest에 해당 script/path unit이 설치되어 있지 않거나 활성화되어 있지 않으면 request는 남고 result/log는 생성되지 않습니다.

이 구조는 update 전 필요한 capability를 update bundle 안의 새 guest deploy로 제공하려는 순환 의존을 만들 수 있습니다. 새 worker는 activation 이후 Guest에 설치되는데, Host는 activation 전에 그 worker를 필요로 합니다.

또 다른 실패 모드는 `systemd.path` 자체입니다. Host가 virtiofs/shared run directory에 request 파일을 만들면 Guest의 `PathExists=` watcher가 항상 inotify event로 깨어난다는 보장이 없습니다. 이 경우 request 파일은 실제로 존재하지만 service가 한 번도 실행되지 않아 result/log가 전혀 생기지 않습니다. runtime state가 계속 갱신되고 capability가 true여도 command dispatcher가 request를 소비하지 못하면 Host는 timeout까지 기다립니다.

AGENTS.md 원칙상 Host는 Guest 내부 상태를 로그, 파일명, old command output, absence of data로 추정하면 안 됩니다. Guest 상태 owner가 명시 capability/state를 제공해야 하고, Host는 그 계약을 소비해야 합니다.

## Checks

현재 apply 명령이 살아 있는지 확인합니다.

```sh
ps aux | rg 'vitalserver-vm runtime apply-bundle|osascript'
```

Host command log에서 update가 어디까지 진행됐는지 확인합니다.

```sh
tail -n 240 /private/tmp/tirosh-vitalserver-manager-command.log
```

Guest shutdown request/result/log 존재 여부를 확인합니다.

```sh
stat -f '%Sp %Su:%Sg %z %Sm %N' \
  "/Library/Application Support/TiroshVitalServer/vm/data/run/prepare-update-shutdown.request" \
  "/Library/Application Support/TiroshVitalServer/vm/data/run/prepare-update-shutdown-result.json" \
  "/Library/Application Support/TiroshVitalServer/vm/data/run/prepare-update-shutdown.log"
```

runtime status가 active operation 또는 rollback 상태인지 확인합니다.

```sh
jq '{status,operation,message,progress,vmState,vmService,proxyService,watchdogService}' \
  "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
```

로그 표시 권한 문제가 같이 있는지 확인합니다.

```sh
stat -f '%Sp %Su:%Sg %N' \
  "/Library/Application Support/TiroshVitalServer/logs" \
  "/private/tmp/tirosh-vitalserver-manager-command.log"
```

## Actions

현장 판단:

1. `tirosh-vitalserver-manager-command.log`를 먼저 직접 확인합니다. Helper Logs 탭의 refresh 실패만으로 update 실패 지점을 판단하지 않습니다.
2. `prepare-update-shutdown.request`가 있고 result/log가 전혀 없으면 Guest worker unavailable 또는 not triggered 상태로 봅니다.
3. `runtime-status.json`에서 rollback 또는 service stop 단계인지 확인합니다.
4. destructive cleanup이나 프로세스 kill은 managed backup, current runtime status, VM service 상태를 확인한 뒤 별도 절차로 판단합니다.

제품 수정 방향:

1. `GuestRuntimeStateDocument`에 update/maintenance capability를 명시합니다.
2. Host update preflight는 `prepareUpdateShutdown`, `activateUpdate`, `redisBackup`, `repairDatastore` 같은 capability를 request 작성 전에 확인합니다.
3. capability가 없으면 request를 쓰지 않고 typed failure로 즉시 중단합니다.
4. `missing result`, `invalid result`, `failed result`, `unsupported capability`, `worker timeout`을 서로 다른 상태로 보존합니다.
5. unreleased legacy behavior를 보상하는 묵시 fallback은 추가하지 않습니다. 이미 배포된 설치본을 지원해야 하면 명시 migration 또는 compatibility gate로 처리합니다.
6. Logs read path는 update state와 분리합니다. Helper가 로그를 읽으면서 root-owned central log directory에 copy/touch/create 실패를 만나도, 원본 로그가 읽히면 그 로그를 표시합니다.
7. Host-written request 파일 감지는 `systemd.path`에 의존하지 않습니다. Guest owner process가 짧은 주기로 run directory를 polling하고, request 발견 시 해당 oneshot service를 명시적으로 dispatch합니다.

## Code Notes

2026-05-31 기준 반영된 구조:

- Guest runtime state writer가 `capabilities`를 기록합니다.
- Host는 `RuntimeGuestCapabilityChecker`로 runtime state의 capability를 확인합니다.
- `prepare-update-shutdown`, `activate-update`, `redis-backup`, `repair-datastore` request는 capability 확인 후에만 작성됩니다.
- Update preflight는 managed backup을 만들기 전에 update에 필요한 Guest capability를 확인합니다.
- Logs read path는 refresh 실패를 보존하되, fallback source log가 있으면 refresh permission failure 대신 실제 log text를 반환합니다.
- Guest command dispatch는 `tirosh-vitalserver-command-poller.service`가 담당합니다. 기본 polling interval은 3초이며 guest tools 설정 파일 `guest-tools.toml`의 `intervals.commandPollSeconds`로 조정합니다. bootstrap/activation은 기존 `*.path` unit을 비활성화하고 poller service를 활성화합니다.

## Prevention

Update flow는 Host와 Guest 사이의 capability/state 계약을 먼저 확인해야 합니다.

- State owner는 Guest입니다. Guest가 capability와 operation result를 명시적으로 제공합니다.
- Host는 capability가 없을 때 Guest 내부 상태를 추정하지 않습니다.
- Request/result 파일은 provider contract가 확인된 뒤에만 사용합니다.
- Absence of result는 성공, 빈 상태, 또는 fallback trigger가 아닙니다.
- Host가 shared directory에 파일을 생성하는 방식은 event notification 계약이 아닙니다. Guest는 파일 생성 event를 기다리지 말고 명시 dispatcher로 request를 읽어야 합니다.
- Guest shutdown preparation이 timeout, invalid result, failed result로 끝나면 Host는 `prepare-update-shutdown.request`와 `prepare-update-shutdown-result.json`을 함께 정리해야 합니다. stale request가 남으면 rollback 후 VM 재시작 시 Guest가 이전 shutdown 요청을 다시 처리할 수 있습니다.
- UI/Helper read path는 domain state를 만들거나 변경하지 않습니다.
- 권한 문제나 log refresh 실패는 update state와 별도 issue로 보존합니다.

## Operational Notes

이 케이스는 `TS-012`처럼 update가 오래 멈춘 증상으로 보일 수 있지만, 핵심 원인은 health wait가 아니라 Guest capability contract 부재입니다.

`Failed to refresh log collection`은 별도 read-path 권한 문제입니다. 이 메시지가 보인다고 해서 update apply가 그 지점에서 실패했다는 뜻은 아닙니다. 반드시 command log와 runtime status를 같이 확인합니다.

유사한 request/result 의존 경로:

- `prepare-update-shutdown.request` / `prepare-update-shutdown-result.json`
- `activate-update.request` / `activate-update-result.json`
- `redis-backup.request` / `redis-backup-result.json`
- `repair-datastore.request` / `repair-datastore-result.json`

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-029`: Update 중 Host가 Guest shutdown 상태를 추정함
- `TS-030`: Runtime 상태를 Host/UI가 추정하거나 암묵 보정함
- `TS-032`: macOS runtime 코드의 상태/관측 책임이 섞임
- `TS-033`: Runtime Control Helper가 설정/로그/event를 읽지 못함
- `TS-034`: macOS runtime 권한 실패 검증이 부족함

## Follow-up

- 2026-05-31: dev product update `0.1.10-dev` 적용 중 `prepare-update-shutdown.request`는 생성됐지만 `prepare-update-shutdown-result.json`과 `prepare-update-shutdown.log`가 생성되지 않는 상태를 확인했습니다.
- 2026-05-31: 동시에 Helper Logs read path가 root-owned central logs directory에 command log를 복사하려다 permission failure를 표시해 실제 update 대기/rollback 상태를 흐리는 것을 확인했습니다.
- 2026-05-31: AGENTS.md 원칙에 따라 fallback 진행이 아니라 Guest capability 계약과 typed failure를 추가하는 방향으로 정리했습니다.
- 2026-05-31: `GuestRuntimeCapabilities`, Host capability preflight, request writer guard, log refresh fallback 분리를 구현하고 targeted Swift tests 86개를 통과했습니다.
- 2026-05-31: `systemd.path` watcher가 virtiofs/shared run directory의 host-written request를 깨우지 못하는 구조적 실패를 확인했습니다. Guest command dispatch를 3초 polling service로 전환하고, bootstrap/activation에서 기존 path unit을 비활성화하도록 hotfix 범위를 확장했습니다.
- 2026-06-07: dev product update `0.1.12-dev` 적용 중 guest shutdown preparation timeout 뒤 rollback이 시작됐지만 stale `prepare-update-shutdown.request`가 남아 VM 재시작 후 Guest가 이전 shutdown 요청을 다시 처리하는 흐름을 확인했습니다. Host apply-bundle workflow는 guest shutdown preparation 자체가 실패해도 cleanup을 실행하고, installed gateway cleanup은 request/result를 함께 제거하도록 수정했습니다.
