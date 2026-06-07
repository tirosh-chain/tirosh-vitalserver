# Vital Server Helper

Vital Server Helper는 VitalDB/Vital Server를 대체하는 제품이 아닙니다. 이 repository는
Vital Server를 운영 환경에서 감싸기 위한 helper app, runtime tooling, observer,
audit proxy, testkit, 문서를 포함합니다.

현재 문서는 공개 안정 버전 안내가 아니라 preview 문서입니다. installer download
path, checksum, 지원 OS matrix, 병원별 설치 절차는 아직 확정되지 않았습니다.

## Platform Scope

현재 release 문서의 build, package, install, runtime 사용법은 macOS host 기준입니다.
repository에는 macOS Helper app과 macOS runtime package가 있으며, Windows host
지원은 현재 release 문서 범위에 포함하지 않습니다.

| 항목 | 현재 범위 |
|---|---|
| 1차 host | macOS |
| Helper app | macOS app |
| runtime package | `apps/vitalserver-macos-runtime` |
| Windows host | 현재 release 범위 아님 |
| Linux host | 현재 release 범위 아님 |

## Relation To VitalDB

| 항목 | 관계 |
|---|---|
| VitalDB/Vital Server | 원 프로젝트와 공식 배포물을 대체하지 않음 |
| Vital Recorder/VRecorder | 연결 상태와 activity를 관측 대상으로 둠 |
| `.vital` 파일 | 저장 상태와 읽기 가능성을 확인해야 하는 운영 대상 |
| Helper | runtime, 상태 확인, update, log 확인을 위한 별도 보조 계층 |

VitalDB, Vital Server, Vital Recorder, VRecorder 관련 이름과 권리는 각 원 소유자에게
있습니다.

## Provided In This Repository

| 항목 | 현재 repository 구성 |
|---|---|
| macOS Helper app | `apps/vitalserver-macos-runtime`의 `VitalServerHelper` target |
| runtime CLI | `apps/vitalserver-macos-runtime`의 `vitalserver-vm` target |
| Runtime Control PWA | `apps/vitalserver-runtime-pwa` |
| VitalDB observer | `apps/vitaldb-observer` |
| Audit proxy | `apps/vitalserver-audit-proxy` |
| Testkit | recorder simulation과 검증 도구 package |
| Docs | `site-docs/` MkDocs 문서 |

## Usage

현재 release 사용법은 안정 installer 기준이 아니라 repository 기준입니다. 공개 안정
release가 확정되면 installer 다운로드, checksum, 지원 OS, 설치 절차를 별도로
고정해야 합니다.

| 목적 | 참고 |
|---|---|
| 문서 보기 | `uv run --group docs mkdocs serve --dev-addr 127.0.0.1:8000` |
| dev/release build target 확인 | `site-docs/dev/build-and-release.md` |
| runtime package 구조 확인 | `site-docs/dev/package-map.md` |
| Runtime Control API 확인 | `site-docs/dev/api-contracts.md` |
| Health Check 상태 의미 확인 | `site-docs/dev/health-check-contract.md` |

### Swift App Build

Swift package는 `apps/vitalserver-macos-runtime` 아래에 있습니다.

| 목적 | 명령 |
|---|---|
| Helper app executable build | `swift build --package-path apps/vitalserver-macos-runtime --product VitalServerHelper` |
| runtime CLI build | `swift build --package-path apps/vitalserver-macos-runtime --product vitalserver-vm` |
| Swift test | `swift test --package-path apps/vitalserver-macos-runtime` |

Make target으로 app bundle을 만들 때는 아래 명령을 사용합니다.

```sh
make devtools/app
```

### Package And Installer

개발 검증용 package와 installer image는 `release-dev.json`을 기준으로 만듭니다.

| 목적 | 명령 |
|---|---|
| development `.pkg` 생성 | `make dist/pkg/dev` |
| development `.dmg` 생성 | `make dist/dmg/dev` |
| 현재 Mac에 development package 설치 | `make dist/install/dev` |
| 설치된 launchd VM/proxy 상태 확인 | `make dist/installed/health` |
| development 설치물 제거 | `make dist/uninstall/dev` |

release profile artifact는 `release.json`을 기준으로 만듭니다.

| 목적 | 명령 |
|---|---|
| release `.pkg` 생성 | `make dist/pkg/release` |
| release `.dmg` 생성 | `make dist/dmg/release` |

release target은 배포 검증용 target입니다. 공개 download path와 checksum은 아직 이
문서에서 확정하지 않습니다.

### Local Runtime PoC

package 설치 없이 개발 VM과 host proxy를 확인할 때는 runtime target을 사용합니다.

```sh
make runtime/up
make runtime/health
make runtime/down
```

`make runtime/up`은 Linux boot asset 준비, cloud-init 생성, guest deploy bundle
staging, VM background start, VM IP 대기, host proxy 연결을 수행합니다.

### Update Bundle

Product update bundle과 VM image update bundle은 별도 target입니다.

| 목적 | 명령 |
|---|---|
| development product update bundle | `make dist/update/dev` |
| release product update bundle | `make dist/update/release` |
| development update bundle 검증 | `make dist/update/verify/dev` |
| release update bundle 검증 | `make dist/update/verify/release` |
| development VM image update bundle | `make dist/image-update/dev` |
| release VM image update bundle | `make dist/image-update/release` |
| development VM image update 검증 | `make dist/image-update/verify/dev` |
| release VM image update 검증 | `make dist/image-update/verify/release` |

설치된 환경에서 update bundle을 직접 다룰 때 사용하는 CLI는 아래 형태입니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle.tar.gz
```

### Installed Paths

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

## Roadmap

| 단계 | 내용 |
|---|---|
| Preview docs | 현재 repository 구성과 미확정 release 항목 정리 |
| Release artifact | installer, checksum, 지원 OS, 알려진 제한 사항 고정 |
| Field validation | 병원별 네트워크, 저장 위치, 권한, 운영 절차 확인 |
| Operation docs | 실제 artifact와 일치하는 설치/운영/rollback 문서 작성 |

## Boundaries

- 의료 행위나 임상 판단을 자동화하지 않습니다.
- 병원 승인 없는 환자 데이터 외부 전송을 기본 기능으로 설명하지 않습니다.
- 공개 GitHub issue에는 환자 정보, 병원 내부 IP, 인증 정보, token을 올리지 않습니다.
