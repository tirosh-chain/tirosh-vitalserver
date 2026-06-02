# pkg 설치가 `Running package scripts...`에서 실패함

> ID: TS-024  
> Category: Packaging  
> Owner: macOS runtime  
> Status: active

## Symptoms

- macOS Installer가 `Running package scripts...` 단계에서 오래 멈춘 뒤 실패합니다.
- Installer UI에는 다음과 같이 표시됩니다.
  - `An error occurred during installation.`
  - `The installation failed.`
- `/var/log/install.log`에는 다음 패턴이 남습니다.

```text
PackageKit: Terminating PKInstallTask(...). Task has exceeded its 600 seconds of runtime.
PKInstallErrorDomain Code=112
```

정상 설치라면 `postinstall` script가 600초 제한에 걸리지 않고 종료되어야 합니다. 이 케이스는 패키지 payload 손상보다는 설치 script 실행 시간이 macOS Installer 제한을 초과한 상태입니다.

## Impact

- pkg 설치가 실패하고 `/Applications` 또는 runtime home에 일부 파일만 남을 수 있습니다.
- 설치가 중간에 종료되므로 launchd service, VM disk, proxy 설정이 불완전할 수 있습니다.
- Redis 데이터 손상 이슈는 아니지만, 부분 설치 상태에서 재설치를 반복하기 전에 runtime 로그와 install 로그를 먼저 확인해야 합니다.

## Cause

확인된 원인은 `postinstall` 중 runtime progress/event 기록이 너무 무거웠던 것입니다.

설치 workflow는 progress와 command event를 자주 기록합니다. 그런데 progress/event 기록마다 전체 runtime health snapshot을 새로 계산하면서 `curl`, `lsof`, `launchctl` 같은 probe가 반복 실행되었습니다. 각 이벤트 기록이 수십 초씩 지연되면서 누적 시간이 macOS Installer의 600초 script 제한을 초과했습니다.

특히 runtime event history에서 다음과 같은 흐름이 보이면 이 케이스에 가깝습니다.

- progress `updatedAt`과 실제 event `timestamp` 사이가 반복적으로 크게 벌어짐
- `runtime-command-started` event 이후 다음 단계로 넘어가지 못하고 Installer가 종료됨
- `/var/log/install.log`에 600초 timeout이 기록됨

다른 확인 원인은 launchd service start 실패가 설치 workflow에서 명시 실패로 전파되지 않은 상태입니다. `start-installed-services`가 completed로 기록됐지만 `runtime-status.json`에 `vm-service-not-loaded`, `proxy-service-not-loaded`, `watchdog-service-not-loaded`가 반복되고 `bootstrap.log`가 생성되지 않았다면 guest 문제가 아니라 host launchd loading 경계에서 멈춘 것입니다.

## Checks

먼저 macOS Installer 로그에서 timeout 여부를 확인합니다.

```sh
grep -n "exceeded its 600 seconds\\|PKInstallErrorDomain Code=112\\|postinstall" /var/log/install.log
```

runtime install 로그와 status도 함께 확인합니다.

```sh
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/install.log"
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
tail -n 100 "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl"
```

event 지연을 볼 때는 `progress.updatedAt`과 event `timestamp`가 반복적으로 크게 차이 나는지 확인합니다.

부분 설치 흔적이 있는지 확인합니다. `.pkg`는 fresh install 전용이므로 아래 흔적이 있으면 설치 전에 clean uninstall을 완료해야 합니다.

```sh
ls -ld "/Library/Application Support/TiroshVitalServer" "/Applications/VitalServer Helper.app"
ls /Library/LaunchDaemons/com.tirosh.vitalserver*.plist
pkgutil --pkg-info com.tirosh.vitalserver.vm
```

## Actions

1. 설치 실패 직후 `/var/log/install.log`에서 600초 timeout을 확인합니다.
2. runtime status가 `installing` 또는 stale progress 상태로 남아 있는지 확인합니다.
3. `start-installed-services` 이후 `vm-service-not-loaded`가 반복되면 launchd service start failure로 보고, install이 health wait까지 지연되지 않고 실패하는지 확인합니다.
4. 수정된 패키지로 다시 설치합니다. 수정된 패키지는 progress/command event 기록 시 전체 health probe를 반복하지 않고, `postinstall` 자체도 guard timeout을 둡니다.
5. 이전 실패로 부분 설치물이 남아 있으면 uninstall/clean 정책에 맞춰 정리한 뒤 재설치합니다.

부분 설치 상태에서는 수동으로 VM disk나 Redis data를 삭제하지 않습니다. 데이터 보존이 필요한 환경이면 Redis backup 여부를 먼저 확인합니다.

## Prevention

- progress document와 command event 기록은 최신 status snapshot을 재사용하는 lightweight health snapshot을 사용합니다.
- 전체 runtime health probe는 실제 status/health check 경계에서만 수행합니다.
- 설치, update, rollback처럼 많은 progress event가 발생하는 경로에서는 event 기록이 lifecycle 실행 시간을 지배하지 않도록 유지합니다.
- macOS Installer의 600초 제한에 기대지 않고, 제품 `postinstall`에서 300초 timeout을 먼저 적용합니다. 이 guard에 걸리면 `install.log`에 `runtime install timed out timeoutSeconds=300`이 남습니다.
- launchd start는 명령 실행 여부가 아니라 service loaded 상태까지 확인합니다. 서비스가 로드되지 않으면 install step failure로 전파합니다.
- `.pkg`는 fresh install 전용입니다. 기존 product root, Helper app, tools, LaunchDaemon plist, receipt가 있으면 `preinstall`에서 실패시키고 update flow로 우회하지 않습니다.
- Fresh install `postinstall` 실패 시 이번 package attempt가 만든 package-owned 잔여물을 cleanup합니다. 삭제 전에 install log를 `/private/tmp/tirosh-vitalserver-postinstall-failure.log`로 보존합니다.

## Operational Notes

- macOS Installer의 600초 제한은 제품 코드에서 직접 제어할 수 없는 외부 제한입니다.
- 제품 guard인 300초는 정상 목표 시간이 아닙니다. 정상적인 `postinstall`은 60-120초 내 종료되는 것이 목표입니다.
- Installer UI는 상세 원인을 거의 보여주지 않으므로 `/var/log/install.log`가 SoT입니다.
- runtime status/event 로그는 보조 진단 자료입니다. event 기록 자체가 느린 경우에는 이벤트의 `timestamp`가 실제 작업 진행보다 늦게 찍힐 수 있습니다.
- 실패 cleanup 이후 product root 로그가 사라질 수 있으므로, fresh install postinstall failure는 `/private/tmp/tirosh-vitalserver-postinstall-failure.log`도 함께 확인합니다.
- 같은 증상이 재발하면 `postinstall`에서 오래 걸리는 단계가 실제 작업인지, 관측/event 기록인지 먼저 분리해서 봅니다.

## Related Cases

- TS-012
- TS-013
- TS-018

## Follow-up

- 2026-05-28: 0.1.8-dev pkg 설치 중 재현. `/var/log/install.log`에서 `Task has exceeded its 600 seconds of runtime` 확인.
- 2026-05-28: progress/command event 기록이 full runtime health probe를 반복하지 않도록 macOS runtime lifecycle 경계를 수정.
- 2026-05-28: `postinstall`에 300초 timeout guard를 추가해 macOS Installer의 600초 제한보다 먼저 실패 원인을 로그로 남기도록 수정.
