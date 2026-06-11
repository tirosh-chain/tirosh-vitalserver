# Clean Uninstall and Reset Installer

이 문서는 내부 clean uninstall 기능과 Reset Installer package의 차이를 설명합니다.

두 기능은 같은 제거 backend를 공유하지만, 운영 목적이 다릅니다. Clean uninstall은 Helper가
실행 중인 상태에서 요청하는 정상 제거 흐름이고, Reset Installer는 새 설치가 막힌 Mac을 다시
설치 가능한 상태로 되돌리는 강제 복구 package입니다.

## 1. 기능 차이

| 구분 | Clean uninstall | Reset Installer |
|---|---|---|
| 목적 | 설치된 Helper/runtime을 정상 제거 | fresh install preflight를 막는 잔존 상태 제거 |
| 실행 위치 | Helper app, Runtime Control API, runtime CLI 내부 경로 | DMG의 `Troubleshooting Tools` package |
| 대표 command | `vitalserver-vm runtime uninstall --clean` | `vitalserver-vm runtime uninstall --force-clean-uninstaller` |
| VM stop | 정상 stop과 service unload를 우선 | VM process force stop을 포함한 recovery 경로 사용 |
| Helper app 처리 | 호출한 Helper app이 종료 예약을 함께 해야 함 | package가 Helper app 종료를 시도하고 필요하면 강제 종료 |
| 삭제 범위 | Helper app, runtime home, runtime tools, LaunchDaemon plist, package receipt, clean 대상 user data | clean uninstall 범위에 더해 fresh install blocker 검증에 필요한 Host state까지 강하게 확인 |
| 완료 기준 | uninstall workflow가 파일 제거, disabled override 정리, receipt 정리를 완료해야 함 | runtime artifact, launchd service, package receipt 중 fresh install blocker가 남지 않아야 함 |
| 사용 시점 | 지원 담당자가 내부 제거 흐름을 검증하거나 운영 UI에서 제거 요청을 수행할 때 | 설치가 `fresh install preflight blocked`로 막혔을 때 |

일반 현장 사용자는 재설치가 목적이면 Clean uninstall을 반복하지 않습니다. 설치가 막힌 상태에서는
[Reset Installer](reset-installer.md)를 사용합니다.

## 2. Clean uninstall의 보존/삭제 정책

표준 uninstall은 clean이 아닐 때 Redis backup을 먼저 만들고 logs, backups, Redis backups,
기본 Vital files directory를 임시 위치에 보존한 뒤 product root를 제거하고 복원합니다.

Clean uninstall은 user data 보존을 하지 않습니다. 설정된 external Vital files directory가 있으면
clean 대상에 포함됩니다. 다만 configured path를 읽지 못하면 external directory cleanup을 추정하지
않고 명시적으로 skip log를 남깁니다.

## 3. Progress 결과 판정

Helper app에서 시작한 Clean uninstall은 background worker와 progress viewer를 사용합니다. viewer는
log marker만으로 성공/실패를 추정하지 않고 현재 runID의 result document를 우선합니다.

result document는 uninstall workflow 결과와 fresh install readiness를 분리해서 기록합니다.

| 필드 | 의미 |
|---|---|
| `runID` | 현재 progress viewer와 worker가 공유하는 실행 ID |
| `state` | `running`, `completed`, `failed` 같은 progress 결과 |
| `exitCode` | worker command의 exit code |
| `uninstallCompleted` | uninstall workflow 자체가 성공했는지 |
| `freshInstallReadiness.state` | fresh install blocker 검증 여부. Clean uninstall progress에서는 `not-checked`가 정상입니다. |
| `freshInstallReadiness.blockers` | readiness가 검증된 경우의 blocker 목록. `not-checked`이면 비어 있어도 fresh install 가능을 뜻하지 않습니다. |

따라서 `uninstallCompleted=true`는 Clean uninstall workflow 성공만 뜻합니다. 새 설치가 계속 막히면
Reset Installer 또는 fresh install preflight 결과의 blocker를 별도로 봐야 합니다.

## 4. Reset Installer를 쓰는 상황

Reset Installer는 정상 제거 UX가 아니라 recovery tool입니다. 아래 blocker가 보이면 Reset
Installer를 사용합니다.

```text
VitalServer Helper pkg install supports fresh installs only.
An existing VitalServer Helper install, launchd service, package receipt,
or Host proxy port conflict blocks this install.
```

Reset Installer가 성공하려면 다음 상태가 모두 정리되어야 합니다.

| 상태 | 왜 확인하나 |
|---|---|
| runtime artifact | product root, app bundle, runtime tool이 남으면 fresh install이 막힘 |
| launchd service | plist가 없어도 loaded/running job이 남을 수 있음 |
| launchd disabled override | plist 밖에 남는 Host state라 다음 bootstrap을 막을 수 있음 |
| package receipt | receipt가 남으면 fresh install 전용 package가 기존 설치로 판단함 |
| Host proxy listener | VitalServer가 띄운 nginx가 orphan process로 port를 점유할 수 있음 |

## 5. 과거 삭제 실패 원인

삭제가 안 된 것처럼 보였던 문제는 대부분 단순 파일 삭제 실패가 아니라 Host-owned state가
남은 문제였습니다.

| 원인 | 증상 | 자세한 문서 |
|---|---|---|
| launchd disabled override 잔존 | 새 설치 중 `Service is disabled` | [TS-046](../../docs/troubleshooting/046_pkg-postinstall-launchd-disabled.md) |
| PWA background command handoff 실패 | UI는 시작됐다고 보이지만 product root/receipt가 남음 | [TS-050](../../docs/troubleshooting/050_pwa-clean-uninstall-background-command.md) |
| VM/launchd state 잔존 | `launchd-service-loaded` blocker | [TS-058](../../docs/troubleshooting/058_clean-uninstall-hung-vm-progress-marker.md) |
| status writer가 product root를 재생성 | `install-artifact-present:path=/Library/Application Support/VitalServerHelper` | [Reset Installer](reset-installer.md) |
| orphan host proxy nginx | port 80 occupied by nginx | [TS-051](../../docs/troubleshooting/051_install-blocked-by-orphan-host-proxy-nginx.md) |

이 원인들은 파일 존재 여부만으로 판단하면 안 됩니다. launchd, process, package receipt, status
writer가 각각 명시적으로 관측되어야 합니다.

## 6. 운영 원칙

- Clean uninstall 성공을 fresh install 가능 상태로 추정하지 않습니다.
- Reset Installer 성공은 runtime artifact, launchd service, package receipt blocker가 없는지로 확인합니다.
- Helper app이나 PWA가 background uninstaller 시작을 보고해도 uninstall 완료로 표시하지 않습니다.
- Progress viewer는 현재 runID의 result document를 우선하고, log tail은 진단 정보로만 취급합니다.
- 제거 후 runtime status writer가 product root를 다시 만들면 안 됩니다.
- 외부 nginx, Docker, Homebrew, 사용자 문서처럼 Helper가 소유하지 않은 상태는 삭제하지 않습니다.
