# Clean Uninstall and Reset Installer Boundary

> ID: TS-065
> Category: Uninstall / Packaging
> Owner: macOS runtime
> Status: active

## Symptoms

Clean uninstall 또는 Reset Installer 실행 후 새 설치가 계속 막힙니다. 대표 blocker는 다음과
같습니다.

```text
fresh install preflight blocked blockers=install-artifact-present:path=/Library/Application Support/VitalServerHelper
fresh install preflight blocked blockers=launchd-service-loaded:label=ai.tirosh.vitalserver.helper.vm
fresh install preflight blocked blockers=host-proxy-port-occupied:port=80 listeners=nginx/<pid>
```

또는 PWA에서 clean uninstall을 눌렀지만 product root, LaunchDaemon plist, package receipt가
그대로 남습니다.

Clean Uninstall 또는 Reset Installer가 실패한 뒤 다음 fresh install preflight에서 product root,
runtime tools, package receipt가 동시에 blocker로 남을 수도 있습니다.

```text
runtime stop state blocked blockers=stop-runtime-services-failed:reason=failed to read configured Host proxy port
fresh install preflight blocked blockers=install-artifact-present:path=/Library/Application Support/VitalServerHelper,
install-artifact-present:path=/usr/local/bin/vitalserver-vm,
install-artifact-present:path=/usr/local/bin/vitalserver-proxy-run,
install-artifact-present:path=/usr/local/bin/tirosh-vitalserver-uninstall,
package-receipt-present:identifier=ai.tirosh.vitalserver.helper
```

## Cause

Clean uninstall과 Reset Installer의 목적이 다릅니다.

- Clean uninstall은 설치된 Helper/runtime을 정상 제거하는 workflow입니다.
- Reset Installer는 fresh install preflight를 막는 잔존 Host state를 강제로 정리하는 recovery
  package입니다.

과거 삭제 실패는 대부분 단순 파일 삭제 실패가 아니라 Host-owned state가 명시적으로 정리되지
않은 문제였습니다.

| 원인 | 의미 | 관련 문서 |
|---|---|---|
| launchd disabled override | plist를 지워도 `launchctl disable system/<label>` 상태가 남아 bootstrap을 막음 | TS-046 |
| background uninstaller handoff 실패 | PWA/API가 background start를 성공처럼 보여도 root shell에서 command가 시작되지 않음 | TS-050, TS-062, TS-063 |
| VM/launchd loaded state 잔존 | pid file 부재를 stop 성공으로 추정하면 loaded/running job이 남음 | TS-058 |
| status writer가 product root 재생성 | clean uninstall 후 `status/runtime-status.json` 기록이 runtime home을 다시 만듦 | TS-042 |
| orphan host proxy nginx | launchd unload 후 nginx child process가 port 80을 계속 점유 | TS-051 |
| proxy 설정 부재를 reset stop failure로 처리 | proxy plist/vm-config/nginx bundle은 이미 없는데 `/usr/local/bin` runtime tools가 남았다는 이유로 proxy port cleanup을 요구함 | this case |

`vitalserver-vm`, `vitalserver-proxy-run`, uninstaller binary, package receipt는 uninstall workflow의
뒤 단계에서 제거해야 하는 install artifacts입니다. 이들이 남아 있다는 사실만으로 Host proxy port
설정이 존재한다고 추정하면 안 됩니다. Clean uninstall/reset에서 proxy plist, vm-config,
nginx bundle이 명시적으로 없으면 proxy port cleanup skip을 로그로 남기고 파일/receipt 제거
단계로 진행합니다.

## Checks

새 설치를 다시 시도하기 전에 아래 상태를 확인합니다.

```sh
tail -n 300 /private/tmp/tirosh-vitalserver-uninstall.log
tail -n 300 /var/log/install.log
sudo launchctl print-disabled system | rg '\"ai\.tirosh\.vitalserver\.helper\.'
sudo launchctl print system/ai.tirosh.vitalserver.helper.vm
sudo launchctl print system/ai.tirosh.vitalserver.helper.sleep-prevention
pkgutil --pkgs | rg -i 'ai\.tirosh\.vitalserver\.helper'
lsof -nP -iTCP:80 -sTCP:LISTEN
```

## Actions

- 재설치 목적이면 clean uninstall을 반복하지 말고 최신 Reset Installer package를 사용합니다.
- `/private/tmp/tirosh-vitalserver-uninstall.log` 마지막에 `uninstall completed`가 있는지 확인합니다.
- launchd service, package receipt, product root 중 하나라도 fresh install blocker로 남으면 새
  installer를 반복 실행하지 않습니다.
- port 80 listener가 남아 있으면 TS-051 기준으로 VitalServer-owned nginx인지 확인합니다. 외부
  listener는 uninstall이 삭제하면 안 됩니다.

## Prevention

- Clean uninstall 완료를 fresh install 가능 상태로 추정하지 않습니다.
- Reset Installer는 runtime artifact, launchd service, package receipt blocker 검증을 완료해야
  성공입니다.
- Uninstall state는 `/private/tmp`의 전용 state document로 유지하고 runtime status 문서로 복원하거나
  추정하지 않습니다.
- UI/API는 background command start와 uninstall completion을 구분해서 표시해야 합니다.
- 파일 부재, pid file 부재, plist 부재는 launchd/process/receipt state 부재를 의미하지 않습니다.

## Related Cases

- [TS-042: Host install/uninstall state contract gap](042_host-install-uninstall-state-contract-gap.md)
- [TS-046: pkg postinstall fails when launchd service is disabled](046_pkg-postinstall-launchd-disabled.md)
- [TS-050: PWA clean uninstall이 background uninstaller를 시작하지 못함](050_pwa-clean-uninstall-background-command.md)
- [TS-051: Install Blocked by Orphan Host Proxy nginx](051_install-blocked-by-orphan-host-proxy-nginx.md)
- [TS-058: Reset Installer Leaves VM Launchd State Behind](058_clean-uninstall-hung-vm-progress-marker.md)
- [TS-062: Helper Clean Uninstall Nohup Detach Failure](062_helper-clean-uninstall-nohup-detach-failure.md)
- [TS-063: Helper Clean Uninstall Progress Log Permission Failure](063_helper-clean-uninstall-progress-log-permission.md)
