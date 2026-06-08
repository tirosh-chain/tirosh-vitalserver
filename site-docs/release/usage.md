# Release Usage

현재 사용법은 안정 installer 기준이 아니라 사전 검증용 배포본 기준입니다. 공개 안정
release가 확정되면 installer 다운로드, checksum, 지원 OS, 설치 절차를 별도로 고정해야
합니다.

## 1. 사전 검증용 배포본 생성

소스 저장소에서 사전 검증용 배포본을 직접 만들 때는 아래 명령을 사용합니다.

```sh
make dist/pkg/dev
```

생성된 패키지는 `dist/` 아래에 놓입니다. Swift build, DMG 생성, update bundle 생성,
runtime PoC, low-level staging target은 release 사용자 문서로 다루지 않고 dev
문서에서 다룹니다.

## 2. Fresh Install Requirement

현재 사전 검증용 패키지는 기존 VitalServer Helper 설치 위에 덮어쓰는 upgrade package가
아닙니다. 기존 설치물, launchd service, package receipt, 또는 Host proxy port 충돌이
있으면 설치 전 검사가 실패해야 합니다.

기존 사전 검증용 설치가 남아 있으면 Force Clean Uninstaller로 제거한 뒤 다시 설치합니다.
일반 Uninstall은 재설치 가능한 상태를 보장하지 않아 현재 사용자 절차로 제공하지 않습니다.

Mac 사용자에게 전달할 때는 [Force Clean Uninstaller](clean-uninstall.md) 절차를 사용합니다.
지원 artifact는 `VitalServerHelperCleanUninstaller-<version>.pkg`처럼 강제 정리만 수행하는
별도 패키지로 제공합니다.

```sh
make dist/clean-uninstaller/dev
```

## 3. Installed Runtime CLI

설치된 환경에서 update bundle을 직접 다룰 때 사용하는 CLI는 아래 형태입니다. update
bundle을 만드는 방법은 release 사용자 인터페이스가 아니라 배포 준비 절차로 둡니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle.tar.gz
```

## 4. Installed Paths

development package 설치 후 주요 경로는 아래와 같습니다.

| 항목 | 위치 |
|---|---|
| Helper app | `/Applications/VitalServer Helper.app` |
| runtime CLI | `/usr/local/bin/vitalserver-vm` |
| host proxy runner | `/usr/local/bin/vitalserver-proxy-run` |
| uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| runtime home | `/Library/Application Support/VitalServerHelper/` |
| status file | `/Library/Application Support/VitalServerHelper/status/runtime-status.json` |
| logs | `/Library/Application Support/VitalServerHelper/logs/` |
| LaunchDaemons | `/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.*.plist` |

## 5. Dev References

| 목적 | 참고 |
|---|---|
| 문서 보기 | `make docs/serve` |
| runtime package 구조 확인 | `site-docs/dev/repository-map.md` |
| Runtime Control API 확인 | `site-docs/dev/runtime-contracts.md` |
| runtime 상태 의미 확인 | `site-docs/dev/runtime-contracts.md` |
