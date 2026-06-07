# Release Usage

현재 사용법은 안정 installer 기준이 아니라 repository preview 기준입니다. 공개 안정
release가 확정되면 installer 다운로드, checksum, 지원 OS, 설치 절차를 별도로 고정해야
합니다.

## Source Preview Build

repository에서 preview package를 직접 만들 때 사용하는 release 문서상 build entrypoint는
아래 하나로 제한합니다.

```sh
make dist/pkg/dev
```

생성된 package는 `dist/` 아래에 놓입니다. Swift build, DMG 생성, update bundle 생성,
runtime PoC, low-level staging target은 release 사용자 인터페이스로 문서화하지 않고 dev
문서에서 다룹니다.

## Fresh Install Requirement

현재 preview package는 기존 VitalServer Helper 설치 위에 덮어쓰는 upgrade package가
아닙니다. 기존 설치물, launchd service, package receipt, 또는 Host proxy port 충돌이
있으면 설치 전 검사가 실패해야 합니다.

기존 preview 설치를 제거한 뒤 다시 설치합니다.

```sh
sudo /usr/local/bin/tirosh-vitalserver-uninstall --clean
```

repository 개발 환경에서는 아래 target을 사용할 수 있습니다.

```sh
make dist/uninstall/dev VM_UNINSTALL_ARGS=--clean
```

## Installed Runtime CLI

설치된 환경에서 update bundle을 직접 다룰 때 사용하는 CLI는 아래 형태입니다. update
bundle을 만드는 방법은 release 사용자 인터페이스가 아니라 배포 준비 절차로 둡니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle.tar.gz
```

## Installed Paths

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

## Dev References

| 목적 | 참고 |
|---|---|
| 문서 보기 | `uv run --group docs mkdocs serve --dev-addr 127.0.0.1:8000` |
| runtime package 구조 확인 | `site-docs/dev/package-map.md` |
| Runtime Control API 확인 | `site-docs/dev/api-contracts.md` |
| runtime 상태 의미 확인 | `site-docs/dev/health-check-contract.md` |
