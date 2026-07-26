# Clean uninstall이 Platform Agent를 남겨 재설치를 차단함

> ID: TS-136
> Category: Uninstall / Packaging
> Owner: macOS runtime
> Status: resolved in code; package install verification pending

## Symptoms

- Helper의 clean uninstall은 실패하지만 app, launchd plist, runtime tool, package receipt가 그대로 남습니다.
- uninstall log에는 다음 blocker가 기록됩니다.

```text
runtime stop state blocked blockers=launchd-service-loaded:label=ai.tirosh.vitalserver.helper.platform-agent
```

- 그 상태에서 새 PKG를 설치하면 preinstall이 stale 설치를 정리하지 않고 다음과 같이 차단합니다.

```text
fresh install preflight blocked blockers=install-artifact-present,...launchd-service-loaded:label=ai.tirosh.vitalserver.helper.platform-agent,package-receipt-present:identifier=ai.tirosh.vitalserver.helper
PKInstallErrorDomain Code=112
```

## Impact

Clean uninstall의 파일 삭제 단계가 시작되지 않으므로 data directory를 포함한 기존 설치가 보존됩니다.
하지만 운영자는 uninstall 완료로 오해할 수 있고, 남은 설치 계약 때문에 새 PKG 설치를 진행할 수 없습니다.

## Cause

일반 runtime stop은 Runtime Control API를 제공하는 Platform Agent를 유지해야 하므로
`RuntimeManagedService.stopOrder`에서 Platform Agent를 제외합니다. 이 변경 뒤에도 uninstall composition이
일반 stop 경로를 재사용했습니다. 반면 uninstall readiness는 `uninstallOrder`의 모든 서비스가
`notLoaded`여야 한다고 요구하므로, stop effect와 readiness 계약이 서로 모순됐습니다.

Force-clean recovery도 forced VM stop 후 일반 `stopOrder`만 unload해 같은 문제를 가졌습니다.
Compile과 기존 composition test는 service-state reader를 항상 `notLoaded`로 stub해 실제 Platform Agent의
loaded state를 검증하지 않았습니다.

## Checks

```sh
cat /private/tmp/tirosh-vitalserver-uninstall-progress.command.result.json
tail -n 200 /private/tmp/tirosh-vitalserver-uninstall-current.log
launchctl print system/ai.tirosh.vitalserver.helper.platform-agent
pkgutil --pkg-info ai.tirosh.vitalserver.helper
grep -n "fresh install preflight blocked\|PKInstallErrorDomain Code=112" /var/log/install.log | tail -n 20
```

현재 실행의 truth는 `*.command.result.json`과 current log입니다. 이전 실행에서 남은
`tirosh-vitalserver-uninstall-state.json`의 `completed` 값을 현재 결과로 사용하지 않습니다.

## Actions

1. 수정된 uninstaller 또는 그 uninstaller를 포함한 troubleshooting reset tool로 clean uninstall을 다시 실행합니다.
2. result document가 `state=completed`, `uninstallCompleted=true`, `exitCode=0`인지 확인합니다.
3. Platform Agent를 포함한 모든 `uninstallOrder` 서비스가 unloaded이고 package receipt와 설치 파일이 제거됐는지 확인합니다.
4. 그 뒤 새 PKG를 설치하고 installed health를 검증합니다.

실패한 clean uninstall은 삭제 단계 전에 중단됐으므로 같은 명령을 수정된 도구로 재시도할 수 있습니다.

## Prevention

- 일반 runtime stop과 uninstall stop을 별도 Host adapter 계약으로 제공합니다.
- 일반 stop은 `stopOrder`만 사용해 Platform Agent를 유지합니다.
- graceful uninstall과 force-clean recovery는 모두 `uninstallOrder`를 사용하고 Platform Agent를 마지막에 unload합니다.
- Controller test는 두 service set의 차이를 고정하고, lifecycle test는 Platform Agent가 실제 loaded state일 때 clean/force-clean 경로가 이를 마지막에 내리는지 검증합니다.
- Uninstall composition test에서 service state를 무조건 `notLoaded`로 만드는 stub만으로 installed cleanup 계약을 검증하지 않습니다.

## Operational Notes

Fresh-install preflight은 stale state를 삭제하거나 성공으로 바꾸지 않습니다. uninstall result가 실패한 경우
installer를 반복 실행하지 말고 uninstall log의 explicit blocker를 먼저 해결합니다.

## Related Cases

- TS-042
- TS-131
- TS-134

## Follow-up

- 2026-07-15: `406920c0` 이후 clean uninstall에서 재현. 일반 stop과 uninstall stop의 Platform Agent lifecycle 계약을 분리함.
- 2026-07-15: 11:21의 installed clean uninstall 로그에서 구 설치본이 `stopping runtime services`를 사용해 같은 blocker를 재현함. 12:19의 새 package payload는 실패 cleanup에서 `stopping runtime services for uninstall`을 사용하고 Platform Agent까지 종료했으므로, source fix와 installed 구버전의 실행 결과를 구분해 진단해야 함.
