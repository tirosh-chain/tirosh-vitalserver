# Force Clean Uninstaller

Force Clean Uninstaller는 기존 설치 흔적 때문에 Vital Server Helper를 새로 설치할 수 없는
Mac을 복구하기 위한 제거 도구입니다. 일반 uninstall이 아니라, Vital Server Helper가 만든
runtime 상태와 데이터를 지운 뒤 다시 설치할 수 있는 상태로 되돌리는 절차입니다.

이 절차는 VM disk, runtime 설정, logs, backups, Redis backups, 설정된 Vital files directory를
삭제할 수 있습니다. 보존해야 하는 `.vital` 파일이나 운영 로그가 있으면 먼저 병원/운영
절차에 따라 별도로 백업합니다.

## 1. 사용 시점

아래처럼 새 설치가 차단될 때 사용합니다.

```text
VitalServer Helper pkg install supports fresh installs only.
An existing VitalServer Helper install, launchd service, package receipt,
or Host proxy port conflict blocks this install.
```

또는 Installer가 `fresh install preflight blocked` 메시지와 함께 실패할 때 사용합니다.

## 2. 실행 전 확인

- 진행 중인 수집이나 전송 작업이 없는지 확인합니다.
- 보존해야 하는 `.vital` 파일, 운영 로그, 병원 내부 기록은 먼저 백업합니다.
- Helper app이 실행 중이면 uninstaller가 잠시 기다린 뒤 종료를 시도합니다. 그래도 남아 있으면
  강제로 종료하고 제거를 계속합니다.

## 3. 패키지 실행

Mac 사용자에게는 아래 형태의 서명 및 공증된 패키지를 전달합니다.

```text
VitalServerHelperCleanUninstaller-<version>.pkg
```

이 패키지는 Vital Server Helper를 시작하지 않고 강제 정리만 실행합니다.

1. `VitalServerHelperCleanUninstaller-<version>.pkg`를 더블클릭합니다.
2. macOS Installer 안내에 따라 관리자 승인을 진행합니다.
3. 완료 후 Mac을 재시동합니다.
4. `Install VitalServer Helper.pkg`를 다시 실행합니다.

## 4. 완료 확인

완료 여부는 아래 로그로 확인합니다.

```sh
tail -n 200 /private/tmp/tirosh-vitalserver-uninstall.log
```

마지막에 `uninstall completed`가 있어야 합니다. 실패 메시지가 있으면 새 설치를 진행하지 않고
로그를 지원 담당자에게 전달합니다.

## 5. 제거 범위

Force Clean Uninstaller는 Vital Server Helper가 소유한 Mac host와 runtime 상태를 제거합니다.

| 항목 | 예시 |
|---|---|
| Helper app | `/Applications/VitalServer Helper.app` |
| Runtime tools | `/usr/local/bin/vitalserver-vm`, `/usr/local/bin/vitalserver-proxy-run` |
| Uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| Runtime home | `/Library/Application Support/VitalServerHelper/` |
| Configured Vital files directory | Vital Server Helper 설정에 저장된 외부 vital-files 경로 |
| LaunchDaemons | `/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.*.plist` |
| Package receipt | `ai.tirosh.vitalserver.helper` |
| Runtime logs and backups | `/Library/Application Support/VitalServerHelper/logs`, backup areas |

Vital Server Helper가 소유한 상태로 설정된 경로가 아니라면 nginx, Docker, Homebrew,
사용자 문서, 병원 외부 데이터는 제거하지 않아야 합니다.

## 6. 배포본 생성

사전 검증용 배포본은 아래 target으로 만듭니다.

```sh
make dist/clean-uninstaller/dev
```

정식 배포 채널 산출물은 release branch 검증을 통과한 뒤 아래 target으로 만듭니다.

```sh
make dist/clean-uninstaller/release
```

## 7. 지원 담당자 참고

같은 새 설치 사전 검사 실패가 계속 남아 있으면 installer를 반복 실행하지 않습니다.
기존 host 상태를 덮어써도 안전한지 판단할 수 없기 때문에 설치가 차단된 상태입니다.

지원 담당자에게 아래 로그 또는 명령 결과를 전달합니다.

```sh
tail -n 300 /private/tmp/tirosh-vitalserver-uninstall.log
tail -n 300 /var/log/install.log
sudo launchctl print-disabled system | grep -i vitalserver
pkgutil --pkgs | grep -i vitalserver
```
