# Reset Installer

Reset Installer는 Vital Server Helper를 새로 설치할 수 없을 때 사용하는 강제 정리
패키지입니다. DMG 안에서는 `Reset VitalServer Helper for Reinstall.pkg`라는 이름으로
제공합니다.

일반 uninstall이 아닙니다. Helper app, runtime service, VM 데이터, 로그, 백업, 설정된 Vital
files directory까지 정리해서 Mac을 다시 설치 가능한 상태로 되돌립니다.

내부 clean uninstall과의 차이는 [Clean Uninstall and Reset Installer](clean-uninstall.md)를
봅니다. Reset Installer는 정상 제거 UX가 아니라 fresh install blocker를 없애는 recovery
package입니다.

## 1. 언제 사용하나

새 설치가 아래 메시지와 함께 막힐 때 사용합니다.

```text
VitalServer Helper pkg install supports fresh installs only.
An existing VitalServer Helper install, launchd service, package receipt,
or Host proxy port conflict blocks this install.
```

또는 Installer에서 `fresh install preflight blocked`가 보일 때 사용합니다.

installer를 반복 실행하지 않습니다. 기존 host 상태가 남아 있으면 같은 이유로 다시 실패할 수
있습니다.

## 2. 실행 전 확인

이 절차는 되돌리기 어렵습니다. 필요한 자료가 있으면 먼저 백업합니다.

| 확인할 것 | 이유 |
|---|---|
| 진행 중인 수집이나 전송 작업이 없는가 | 작업 중 데이터가 사라질 수 있음 |
| 보존해야 하는 `.vital` 파일이 있는가 | 설정된 Vital files directory가 삭제될 수 있음 |
| 필요한 로그나 병원 내부 기록을 보관했는가 | 정리 후 logs와 backups가 삭제될 수 있음 |

단순 app 재시작 문제라면 Reset Installer를 먼저 쓰지 않습니다. Status, Logs, repair
흐름으로 해결 가능한지 먼저 확인합니다.

## 3. 실행 방법

Mac 사용자에게는 아래 package를 전달합니다.

```text
Troubleshooting Tools/Reset VitalServer Helper for Reinstall.pkg
```

실행 순서는 간단합니다.

1. DMG 안의 `Troubleshooting Tools` 폴더를 엽니다.
2. `Reset VitalServer Helper for Reinstall.pkg`를 더블클릭합니다.
3. macOS Installer 안내에 따라 관리자 승인을 진행합니다.
4. 완료 후 Mac을 재시동합니다.
5. `Install VitalServer Helper.pkg`를 다시 실행합니다.

Helper app이 실행 중이면 uninstaller가 종료를 시도합니다. 그래도 남아 있으면 강제로 종료하고
정리를 계속합니다.

## 4. 완료 확인

완료 여부는 아래 log로 확인합니다.

```sh
tail -n 200 /private/tmp/tirosh-vitalserver-uninstall.log
```

마지막에 아래 메시지가 있어야 합니다.

```text
uninstall completed
```

실패 메시지가 있으면 새 설치를 진행하지 않고 log를 지원 담당자에게 전달합니다.

일반 uninstall 또는 이전 reset package에서 VM stop 단계에 아래 메시지가 보이면 VM
process에 `SIGTERM`은 전달됐지만 900초 안에 종료가 관찰되지 않은 상태입니다.

```text
VM process did not stop within 900s
vm-process-stop-timed-out
```

이 상태는 proxy나 guest log sync stop 실패가 아니라 Host가 소유한 VM process stop 실패입니다.
새 설치를 진행하지 말고 log와 VM pid/launchd 상태를 함께 확인합니다.

최신 Reset Installer는 이 recovery 경로에서 VM graceful stop을 900초 기다리지
않습니다. `--force-clean-uninstaller`는 VM process에 `SIGKILL`을 보내고 짧은 force-stop 확인
후에도 남아 있으면 service stop blocked state를 기록하고 성공으로 표시하지 않습니다.

이전 reset package가 성공한 직후 installer가 아래 blocker로 실패하면 launchd service state가
남아 있는 것입니다.

```text
fresh install preflight blocked blockers=launchd-service-loaded:label=ai.tirosh.vitalserver.helper.vm,launchd-service-loaded:label=ai.tirosh.vitalserver.helper.sleep-prevention
```

이 경우 runtime 파일, plist, package receipt가 absent여도 `launchctl`이 아직 VM 또는
sleep-prevention job을 loaded/running으로 보고 있을 수 있습니다. 최신 Reset Installer는 VM pid
file이 missing이어도 이를 cleanup success로 숨기지 않고, explicit launchd state를 읽어 남은
service를 unload합니다. launchd service, runtime artifact, package receipt 중 하나라도 다음
fresh install을 막으면 cleanup은 completed가 아니라 blocked/failed로 남습니다.

진행 창이 열려 있지만 log가 더 이상 늘어나지 않으면 cleanup worker가 완료 또는 실패 marker를
남기지 못하고 종료된 상태일 수 있습니다. 이 경우 최신 package에서는 아래 marker를 log에
남기고 실패로 종료합니다.

```text
uninstall process failed exitCode=missing-marker runID=...
```

이 marker는 progress viewer가 자기 background worker의 terminal marker를 보지 못했다는
뜻입니다. 실제 cleanup 원인은 같은 log의 앞뒤 줄, `/var/log/install.log`, 남아 있는
launchd/package 상태로 구분합니다. 새 progress viewer는 run id가 붙은 marker만 자기 작업의
terminal marker로 인정합니다.

Reset Installer가 성공한 뒤 일반 installer가 아래처럼 막히면, clean uninstall 후 status 관측
경로가 `Runtime home`을 다시 만들었는지 확인합니다.

```text
fresh install preflight blocked blockers=install-artifact-present:path=/Library/Application Support/VitalServerHelper
```

실제 장애에서는 clean uninstall completion 이후 `status/runtime-status.json`만 다시 생겨 fresh
install preflight가 product root 잔여물로 차단했습니다. Runtime status는 설치된 product root가
존재할 때만 기록해야 하며, status 기록이 clean uninstall로 제거된 root를 생성하면 안 됩니다.
uninstall/install state는 `/private/tmp`의 전용 state document로 유지하고 runtime status로 복원
또는 추정하지 않습니다.

동시에 여러 cleanup 시도가 겹치면 remove 직전에는 존재하던 파일이 실제 remove 시점에는 이미
없을 수 있습니다. 최신 Reset Installer는 이 경우를 성공으로 숨기지 않고 아래처럼 명시적으로
기록한 뒤 cleanup 검증 단계에서 artifact absence를 다시 확인합니다.

```text
removal target already absent path=/usr/local/bin/vitalserver-proxy-run
```

## 5. 삭제 범위

Reset Installer는 Vital Server Helper가 소유한 항목을 제거합니다.

| 항목 | 예시 |
|---|---|
| Helper app | `/Applications/VitalServer Helper.app` |
| Runtime tools | `/usr/local/bin/vitalserver-vm`, `/usr/local/bin/vitalserver-proxy-run` |
| Uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| Runtime home | `/Library/Application Support/VitalServerHelper/` |
| Vital files directory | Helper 설정에 저장된 외부 vital-files 경로 |
| LaunchDaemons | `/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.*.plist` |
| Package receipt | `ai.tirosh.vitalserver.helper` |
| Logs and backups | runtime logs, rollback backups, Redis backups |

`Runtime home` 안에 있는 Host-owned runtime state도 함께 제거됩니다.

| 내부 상태 | 의미 |
|---|---|
| VM pid/run state | VM pid file, runtime run marker, pid 기반 stop 관측 상태 |
| Status documents | `runtime-status.json`, uninstall/install state, operation lease |
| Runtime data | VM disk, cloud-init seed, deploy inputs, generated runtime config |
| Runtime logs | launcher, VM, proxy, guest log sync, watchdog, uninstall 관련 log |
| Backup data | rollback backups, Redis backups, clean reset 대상 backup directory |

Reset Installer는 먼저 runtime service와 VM process를 멈춘 뒤 이 파일들을 제거합니다. VM pid
file이 이미 없으면 그 자체를 성공으로 추정하지 않고, 남아 있는 launchd service 상태를 읽어
unload합니다. 제거 후에도 launchd service, runtime artifact, package receipt 중 fresh install을
막는 상태가 남으면 완료로 표시하지 않습니다.

Helper가 소유하지 않은 일반 nginx, Docker, Homebrew, 사용자 문서, 병원 외부 데이터는 제거하지
않아야 합니다.

## 6. 실패 시 전달할 정보

같은 설치 실패가 계속되면 installer를 반복 실행하지 않습니다. 아래 정보를 지원 담당자에게
전달합니다.

```sh
tail -n 300 /private/tmp/tirosh-vitalserver-uninstall.log
tail -n 300 /var/log/install.log
```

필요하면 아래 상태도 함께 확인합니다.

```sh
sudo launchctl print-disabled system | rg '\"ai\.tirosh\.vitalserver\.helper\.'
sudo launchctl print system/ai.tirosh.vitalserver.helper.vm
sudo launchctl print system/ai.tirosh.vitalserver.helper.sleep-prevention
pkgutil --pkgs | rg -i 'ai\.tirosh\.vitalserver\.helper'
```

공개 issue에는 환자 정보, 병원 내부 IP, 인증 정보, token, 원본 로그 전체를 올리지 않습니다.

## 7. 지원 담당자 참고

Reset Installer 패키지는 현장 Mac이 아니라 build machine에서 만듭니다.

```sh
make dist/reset-installer/dev
make dist/reset-installer/release
```

빌드 target 이름도 사용자가 받는 package와 같은 의미가 되도록 `reset-installer`로 둡니다.
