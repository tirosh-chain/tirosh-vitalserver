# Force Clean Uninstaller (Clean Uninstall Recovery)

이 문서는 fresh install이 기존 설치 흔적 때문에 막힌 Mac에서 Vital Server Helper를 완전히
제거한 뒤 다시 설치하기 위한 지원 절차입니다. 실무에서는 **Force Clean Uninstaller**로
부르며 `runtime uninstall --force-clean-uninstaller`를 사용합니다.

Clean Uninstall은 보존용 제거가 아니라 Vital Server Helper가 소유한 데이터와 기능을 모두
삭제하는 복구 작업입니다. VM disk, runtime 설정, logs, backups, Redis backups, 설정된 Vital
files directory까지 제거합니다. 필요한 `.vital` 파일이나 운영 로그가 있으면 먼저 병원/운영
절차에 따라 별도로 보존합니다.

## When To Use

아래처럼 새 설치가 차단될 때 사용합니다.

```text
VitalServer Helper pkg install supports fresh installs only.
An existing VitalServer Helper install, launchd service, package receipt,
or Host proxy port conflict blocks this install.
```

또는 Installer가 `fresh install preflight blocked` 메시지와 함께 실패할 때 사용합니다.

## Preferred Recovery Artifact

Mac 사용자에게는 별도 signed/notarized package를 전달합니다.

```text
VitalServerHelperCleanUninstaller-<version>.pkg
```

repository preview build에서는 아래 target으로 만듭니다.

```sh
make dist/clean-uninstaller/dev
```

release channel 산출물은 release branch guard를 통과한 뒤 아래 target으로 만듭니다.

```sh
make dist/clean-uninstaller/release
```

사용자는 이 package를 더블클릭하고 macOS Installer의 안내에 따라 관리자 승인을 합니다.
package는 Vital Server Helper를 시작하지 않고 Clean Uninstall만 실행해야 합니다.

완료 후 다시 설치합니다.

```text
Install VitalServer Helper.pkg
```

## Terminal Fallback

이미 uninstaller가 설치되어 있고 Terminal 사용이 가능한 경우에는 아래 명령을 사용할 수
있습니다.

```sh
sudo /usr/local/bin/tirosh-vitalserver-uninstall --force-clean-uninstaller
```

완료 여부는 아래 로그로 확인합니다.

```sh
tail -n 200 /private/tmp/tirosh-vitalserver-uninstall.log
```

마지막에 `uninstall completed`가 있어야 합니다. 실패 메시지가 있으면 새 설치를 진행하지
않고 로그를 지원 담당자에게 전달합니다.

## Support Checklist

1. Helper app이 실행 중이면 clean uninstaller가 대기 후 필요 시 강제 종료합니다.
2. `VitalServerHelperCleanUninstaller-<version>.pkg`를 실행합니다.
3. `/private/tmp/tirosh-vitalserver-uninstall.log`에서 완료를 확인합니다.
4. Mac을 재시동합니다.
5. `Install VitalServer Helper.pkg`를 다시 실행합니다.

## What It Removes

Clean Uninstall recovery는 Vital Server Helper가 소유한 host/runtime 상태를 제거합니다.

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

It must not remove unrelated nginx, Docker, Homebrew, user documents, or external hospital data
unless that path is explicitly configured as Vital Server Helper-owned state.

## Escalation Notes

Do not retry the installer repeatedly if the same fresh-install preflight failure remains. The
installer is intentionally refusing to guess whether existing host state is safe to overwrite.

Send the following files or command output to support:

```sh
tail -n 300 /private/tmp/tirosh-vitalserver-uninstall.log
tail -n 300 /var/log/install.log
sudo launchctl print-disabled system | grep -i vitalserver
pkgutil --pkgs | grep -i vitalserver
```
