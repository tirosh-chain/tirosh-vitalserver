# VitalServer VM Packaging and Update

빌드 산출물, 설치 흐름, install/update 계약을 정리합니다. `make dist/pkg/dev`/`make dist/pkg/release`, `make dist/dmg/dev`/`make dist/dmg/release`, update bundle, 설치 설정 JSON을 볼 때 사용합니다.

## 이 문서에서 바로 알아야 할 것

| 질문 | 답 |
|---|---|
| 최종 설치 단위는? | `.pkg` |
| DMG의 역할은? | `.pkg`를 전달하는 껍데기 |
| 최종 산출물 위치는? | `dist/` |
| build 작업의 주 구현은? | Python `packages/vitalserver-devtools` |
| 설치 후 provisioning 주 구현은? | Swift `vitalserver-vm runtime install-provision` |
| Shell script 역할은? | `postinstall`, launchd, uninstall wrapper |
| update bundle은 누가 검증/적용하나? | Swift `RuntimeLifecycle` |

## 배포 시나리오

| 시나리오 | 산출물 | 생성 명령 | 현장 적용 |
|---|---|---|---|
| 신규 설치 dev 검증 | `dist/VitalServerHelper-<version>.dmg` | `make dist/dmg/dev` | release-dev.json 기반 개발 검증 |
| 신규 설치 release 검증 | `dist/VitalServerHelper-<version>.dmg` | `make dist/dmg/release` | release.json 기반 release 검증 |
| `.pkg` 직접 배포 dev 검증 | `dist/VitalServerHelper-<version>.pkg` | `make dist/pkg/dev` | `sudo installer -pkg ... -target /` |
| `.pkg` 직접 배포 release 검증 | `dist/VitalServerHelper-<version>.pkg` | `make dist/pkg/release` | `sudo installer -pkg ... -target /` |
| air-gapped Product Update | `dist/update-bundles/update-bundle-<channel>-product-update-<releaseLabel>.tar.gz` | `make dist/update/release` | Helper app Update 탭 또는 `vitalserver-vm runtime apply-bundle` |
| VM Image Update | `dist/update-bundles/update-bundle-<channel>-vm-image-update-<releaseLabel>.tar.gz` | `make dist/image-update/release` | rootfs-base 교체가 필요한 경우에만 사용 |
| Product Update bundle 검증 | product update tarball | `make dist/update/verify/release` | 전달 전 manifest/checksum 검증 |
| VM Image Update bundle 검증 | VM image update tarball | `make dist/image-update/verify/release` | 전달 전 manifest/checksum 검증 |
| 개발 설치 테스트 | installed runtime | `make dist/install/dev` | 현재 Mac에 설치 후 `make dist/installed/health` |

사용자에게 “bundle”로 제공하는 대상은 두 가지입니다. 신규 설치는 `.dmg`/`.pkg`이고, 이미 설치된 현장 업데이트는 `update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz` tarball입니다. air-gapped 환경에서는 이 파일을 USB나 폐쇄망 파일 서버로 전달합니다. 적용 과정과 보존/변경 범위는 [Update](update.md)에 따로 정리합니다.

## 버전 source of truth

package, DMG, update bundle, Helper product/component version은 아래 파일을 기준으로 관리합니다.

```text
apps/vitalserver-macos-runtime/release.json
apps/vitalserver-macos-runtime/release-dev.json
```

`release.json`은 stable channel, `release-dev.json`은 내부 dev channel SoT입니다. `*-release` target은 `release.json`을 사용하고 현재 repository branch가 `main`일 때만 실행됩니다. `*-dev` target은 `release-dev.json`을 사용하며 branch 제약을 두지 않습니다.

Release manifest는 build input이고, Test 탭/API 구현의 세부 contract는 소유하지 않습니다.
Runtime 전체 SoT map은 [Runtime observability model](observability.md#source-of-truth-map)에
정리합니다. Packaging 관점에서는 release manifest가 artifact identity와 service catalog를 소유하고,
`vm-build.toml`이 build/deploy 경로와 Docker image bundle 구성을 소유합니다.

| Field | Owner | 의미 |
|---|---|---|
| `channel` | release manifest | updater channel compatibility와 artifact routing. 설치된 updater channel과 bundle channel이 다르면 apply preflight에서 거부 |
| `helperVersion` | release manifest | Apple/pkg-safe numeric Helper product version |
| `releaseLabel` | release manifest | package/DMG/update bundle/staging/backup/installed version 표시에 쓰는 artifact identity |
| `targetPlatform` | release manifest | 이 release artifact/update bundle을 적용할 수 있는 단일 platform variant |
| `distribution.profile` | release manifest | stable/dev build profile. Test 탭과 local browser console은 `dev`에서만 노출 |
| `distribution.audience` | release manifest | artifact의 intended audience 설명 |
| `services.*` | release manifest | bundled service image, version, display name |
| `bundle.optionalContainerServices` | release manifest | 이번 package/update bundle에 포함할 선택 container service 목록 |

`bundle.optionalContainerServices`는 Testkit API처럼 컨테이너로 제공되는 선택 서비스를 포함할지 여부만 표현합니다. 선택 서비스의 image/version/display name은 `services.<name>`에 둡니다. Test 탭의 route, API shape, 화면 정책은 release manifest가 아니라 Test 탭/API 구현이 소유합니다.

Runtime Control PWA는 package/update bundle에 static asset으로 포함됩니다. `make devtools/app`,
`make dist/pkg/*`, `make dist/dmg/*`, `make dist/update/*`는 `make pwa/build`를 먼저 실행합니다.
빌드 머신에서는 packaging 전에 한 번 `make pwa/install`을 실행해야 하며, 현장 Mac에는 npm/Vite나
registry 접근이 필요하지 않습니다.

`VitalServer Helper`는 최상위 product release입니다. platform별 build는 같은 Helper release 아래의 variant이며, 세부 변경 범위는 Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, VM Image, VitalServer component version으로 설명합니다.

`make devtools/build`는 이 값을 Swift `Bootstrap/Composition/GeneratedVersion.swift`와 Helper app의 `GeneratedRelease.swift`에 반영하고, `make devtools/app`은 app bundle `Info.plist`의 `CFBundleShortVersionString`에 같은 helper version을 씁니다. `make dist/pkg/dev`/`make dist/pkg/release`, `make dist/update/dev`/`make dist/update/release`, `make dist/image-update/dev`/`make dist/image-update/release`는 release manifest 값을 artifact name, package version, update bundle version, compatibility metadata에 반영합니다. `services.*.displayName`은 Helper UI의 service 표시명 source of truth입니다. 특별한 검증이 아니라면 버전, 표시명, image, update compatibility, optional container service 포함 정책 변경은 이 파일 하나에서 관리합니다.

Update bundle manifest는 `schemaVersion: 3`, `channel`, `helperVersion`, `releaseLabel`, `targetPlatform`, `minUpdaterVersion`, `components`를 기준으로 작성합니다. `components`에는 `helperUI`, `updater`, `supervisor`, `vmDriver`, `serviceStack`, `vmImage`, `vitalServer`처럼 실제 변경 범위를 드러내는 version을 넣습니다. platform-specific artifact는 `targetPlatform`과 component version suffix로 제한하고, 공통 Service Stack이나 VM Image는 같은 Helper release 아래에서 platform 간 공유할 수 있습니다.

Layer별 platform dependency도 manifest 설계 기준입니다. Helper UI와 VM Driver는 platform-specific이고, Updater는 host/platform-specific compatibility gate이며, Supervisor는 host/platform-aware health/recovery loop입니다. Service Stack은 guest/service-specific 실행 세트이고, VM Image는 Linux guest OS image artifact입니다.

Update bundle kind는 두 개로 제한합니다.

| bundleKind | 생성 target | UI 위치 | 포함 범위 |
|---|---|---|---|
| `product-update` | `make dist/update/release` | Update 탭 | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, 개별 service/container, host proxy, migrations |
| `vm-image-update` | `make dist/image-update/release` | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifact |

Hotfix, service-only update, updater bridge update는 별도 kind가 아니라 `product-update` metadata로 표현합니다.

## Bundled observer services

기본 Service Stack에는 VitalServer app, Redis, audit proxy, edge/nginx, Redis UI, Swagger UI와 함께
`vitaldb-observer` container가 포함됩니다. `vitaldb-observer`는 Redis와 proxy/access log를 읽어
recorder/bed/anomaly snapshot을 계산하지만, 자체 SQLite를 소유하지 않습니다. 최종 observation SoT는
watchdog/runtime observability SQLite입니다.

```text
vitaldb-observer
  -> /health
  -> /ready
  -> /api/v1/observations
  -> guest runtime-state.json
  -> watchdog
  -> runtime-observability.sqlite
  -> Runtime Control API /vitaldb/*
```

Docker image bundle과 guest deploy 대상은 `config/vm-build.toml`이 소유합니다. observer image,
Dockerfile, guest deploy `include` 항목을 변경할 때는 Makefile literal을 추가하지 말고 TOML 값을
수정합니다.

## Package 구성

현재 repository의 `make dist/pkg/dev`는 `.pkg`까지 가기 위한 개발 검증용 packaging target입니다.
최종 배포 산출물은 `dist/`에 두고, `.tmp/`는 중간 작업물 전용으로 사용합니다.

```sh
make dist/pkg/dev
make dist/install/dev
make dist/installed/health
make dist/uninstall/dev
```

`make dist/pkg/dev` 생성물:

```text
dist/VitalServerHelper-<version>.pkg
```

패키징 시간이 길면 압축 단계에서 CPU를 더 쓰도록 설정할 수 있습니다. `rootfs-base.raw.gz`와
`vitalserver-images.tar.gz` 생성은 `VM_COMPRESSION_THREADS` 값을 사용합니다.

```sh
VM_COMPRESSION_THREADS=8 make dist/pkg/dev
```

이 설정은 Python/uv package를 병렬화하는 옵션이 아닙니다. 빌드 머신에 `pigz` binary가 있을 때만
병렬 gzip 경로를 사용합니다. `pigz`가 없으면 자동으로 Python gzip fallback을 타며, 이 fallback은
single-thread로 동작합니다.

```sh
command -v pigz
brew install pigz
VM_COMPRESSION_THREADS=8 make dist/pkg/dev
```

정상적으로 병렬 압축을 타면 build log에 아래처럼 표시됩니다.

```text
using pigz compression threads=8
```

아래처럼 표시되면 `pigz`를 찾지 못한 것이고 병렬 압축을 사용하지 않은 것입니다.

```text
using Python gzip compression
```

`pigz`는 build machine 전용 optional accelerator입니다. 최종 `.pkg`, 병원 Mac runtime,
air-gapped target 환경에는 설치할 필요가 없습니다. `make -j`는 일부 target을 병렬 실행할 수 있지만,
golden VM 부팅과 Swift binary signing이 같은 중간 산출물을 공유하므로 기본 권장 경로는
`VM_COMPRESSION_THREADS`와 `pigz`로 압축 병목을 줄이는 것입니다.

전달용 release DMG가 필요하면 `make dist/dmg/release`를 실행합니다. DMG에는 단일 PKG만 들어갑니다.

```text
dist/VitalServerHelper-<version>.dmg
```

설치 후 구조:

```text
/Applications/VitalServer Helper.app
/usr/local/bin/vitalserver-vm
/usr/local/bin/vitalserver-proxy-run
/usr/local/bin/tirosh-vitalserver-uninstall
/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.vm.plist
/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.proxy.plist
/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.watchdog.plist
/Library/Application Support/VitalServerHelper/
  backups/
  logs/
    install.log
  status/
    runtime-status.json
  vm/
    runtime/
      Image
      initrd.img
      rootfs-base.raw.gz  # immutable package payload
      vm-disk.img         # install 시 생성되는 mutable runtime disk
      vm-config.json      # install 시 생성/수정
      seed.iso            # install 시 생성
      runtime-version.json
    data/
      deploy/
      run/
      vital-files/
      vr-release/
    Support/
      Proxy/vitalserver.conf.template
  nginx/
    sbin/nginx
    lib/
      libpcre2-8.0.dylib
      libssl.3.dylib
      libcrypto.3.dylib
    vitalserver.conf # VM IP 확인 후 생성
    logs/
```

shared/NAT mode에서는 VM IP가 부팅 후에 결정됩니다. 그래서 package는 nginx config에 upstream을 미리 박아두지 않습니다.

```text
launchd
  -> ai.tirosh.vitalserver.helper.watchdog
      -> vitalserver-vm runtime watchdog
      -> health snapshot 확인
      -> 필요 시 VM/proxy launchd kickstart
      -> runtime-status.json 갱신

launchd
  -> ai.tirosh.vitalserver.helper.vm
      -> vitalserver-vm start
      -> VM이 /mnt/tirosh/run/runtime-state.json 기록

launchd
  -> ai.tirosh.vitalserver.helper.proxy
      -> vitalserver-proxy-run
      -> runtime-state.json 대기
      -> nginx config 렌더링
      -> nginx start/reload
      -> VM IP 변경 감시
```

이 구조에서 운영자가 `VITALSERVER_PROXY_UPSTREAM`을 직접 설정할 필요는 없습니다.

`vm-disk.img`는 sparse disk라 package payload에 그대로 넣으면 `pkgbuild`가 실패할 수 있습니다. 따라서 package에는 immutable base artifact인 `rootfs-base.raw.gz`를 넣고, 설치 시 `postinstall`에서 `vm-disk.img`를 생성합니다.

직접 배포되는 `.pkg`는 fresh install 전용입니다. 이미 `/Library/Application Support/VitalServerHelper`, Helper app, runtime tools, LaunchDaemon plist, package receipt가 있거나 Host proxy port가 다른 listener에 점유되어 있으면 `preinstall`에서 실패해야 합니다. 기존 설치본의 교체는 Helper app의 update flow가 소유하며, `.pkg` 설치가 기존 `vm-disk.img`나 partially installed runtime을 재사용해서 upgrade처럼 동작하면 안 됩니다.

## DMG Build 흐름

`make dist/dmg/release`는 최종 전달 매체를 만들지만, 실제로는 아래 dependency chain을 실행합니다.

```text
make dist/dmg/release
  -> make pwa/build               # Runtime Control PWA static assets
  -> make devtools/golden-rootfs         # clean VM disk -> rootfs-base.raw.gz
  -> vitalserver-devtools release-dmg
     -> release-pkg staging/pkgbuild
     -> hdiutil create
```

빌드 단계의 원칙은 아래입니다.

| 단계 | 주 책임 구현 | 이유 |
|---|---|---|
| target dependency 연결 | `make/vm/package.mk` | 개발자가 실행할 명령과 산출물 경로를 한 곳에서 노출 |
| Runtime Control PWA build | `apps/vitalserver-runtime-pwa` Vite build | 현장 Mac에는 npm/Vite를 요구하지 않고 static asset만 배포 |
| Ubuntu/cloud-init/rootfs/nginx/Docker/update bundle 생성 | `packages/vitalserver-devtools` Python package | build-machine 전용 작업이고 입력/출력 검증과 unit test가 필요 |
| Swift binary와 Helper app build/sign | SwiftPM, `codesign`, Make target | macOS toolchain과 app bundle 조립이 필요 |
| PKG root staging | Make + filesystem tools | payload 배치가 명령형이고 `pkgbuild` 입력 구조와 1:1 대응 |
| 설치 후 provisioning | Swift `RuntimeLifecycle` | target Mac 상태, launchd, backup/rollback, health를 하나의 runtime source of truth로 관리 |

따라서 `postinstall`이나 Make target에 provisioning 정책을 다시 넣지 않습니다. `postinstall`은 설치 log를 연결한 뒤 `vitalserver-vm runtime install-provision`을 호출하는 wrapper로 유지합니다.

`install-provision`은 package payload, VM disk/config, cloud-init seed, 권한, launchd service 시작 요청까지 담당합니다. runtime이 실제로 healthy인지 판단하는 일은 `postinstall`이 하지 않습니다. Helper app, watchdog, `vitalserver-vm runtime health`가 `runtime-status.json`과 guest-owned state를 읽어 별도 readiness로 보고합니다. 따라서 `.pkg` 성공은 "runtime service start가 요청됨"을 뜻하고, "VitalServer backend가 ready"를 뜻하지 않습니다. Provision 완료 status는 active operation이 아니어야 하며, watchdog이 이어서 Guest-owned state를 반영할 수 있어야 합니다.

Fresh install `postinstall`이 실패하면 wrapper는 실패 로그를 `/private/tmp/tirosh-vitalserver-postinstall-failure.log`에 보존한 뒤 이번 package attempt가 만든 product root, Helper app, runtime tools, LaunchDaemon plist, package receipt를 제거합니다. Cleanup은 package nginx 경로로 확인된 orphan host proxy process도 종료합니다. 이 cleanup은 fresh install 경계에서만 동작하며, 외부 `.vital` 경로나 별도 사용자 데이터 경로는 삭제하지 않습니다.

중간 파일과 최종 파일은 아래 위치를 사용합니다.

| 단계 | 경로 | 의미 |
|---|---|---|
| nginx artifact cache | `.artifacts/nginx/macos/bin/nginx` | repository에 commit하지 않는 pinned build input |
| package work dir | `.tmp/vitalserver-vm-pkg/` | PKG staging, rootfs cache, nginx bundle, Docker bundle |
| package root | `.tmp/vitalserver-vm-pkg/root/` | `pkgbuild --root` 입력 |
| app bundle staging | `.tmp/VitalServer Helper.app` | `/Applications` payload로 들어갈 app |
| PWA static build | `apps/vitalserver-runtime-pwa/dist/` | Helper app resource로 들어갈 Runtime Control PWA |
| golden VM home | `.tmp/vitalserver-vm-golden/` | package용 clean rootfs를 만들기 위한 임시 VM home |
| DMG staging | `.tmp/vitalserver-vm-dmg/` | DMG root에 들어갈 파일 배치 |
| PKG output | `dist/VitalServerHelper-<version>.pkg` | installer payload |
| DMG output | `dist/VitalServerHelper-<version>.dmg` | 사용자 전달 매체 |

DMG root에는 `Install VitalServer Helper.pkg`만 둡니다. 사용자는 pkg를 열어 macOS Installer로 설치합니다.

## DMG 설치 흐름

사용자 관점의 설치 순서는 아래입니다.

```text
1. VitalServerHelper-<version>.dmg mount
2. Install VitalServer Helper.pkg 실행
3. macOS Installer가 payload 복사
4. PKG postinstall 실행
5. Swift runtime install-provision이 runtime instance provision
6. launchd VM/proxy/watchdog service 등록 및 정책 적용
7. Helper.app, watchdog, CLI가 status/health 확인
```

실제 코드 호출은 아래처럼 이어집니다.

```text
Install VitalServer Helper.pkg
  -> payload copy
    -> /Applications/VitalServer Helper.app
    -> /usr/local/bin/vitalserver-vm
    -> /usr/local/bin/vitalserver-proxy-run
    -> /Library/Application Support/VitalServerHelper/vm/runtime/rootfs-base.raw.gz
    -> /Library/Application Support/VitalServerHelper/vm/data/deploy/*
    -> /Library/Application Support/VitalServerHelper/nginx/*
    -> /Library/LaunchDaemons/ai.tirosh.vitalserver.helper.*.plist
  -> rendered postinstall from Support/Packaging/postinstall.template
    -> vitalserver-vm runtime install-provision
      -> read /private/tmp/tirosh-vitalserver-install.json if present
      -> create runtime/data/log directories
      -> write deploy/runtime-config.json
      -> gunzip rootfs-base.raw.gz into runtime/vm-disk.img if missing
      -> truncate vm-disk.img to configured diskGiB
      -> write runtime/vm-config.json
      -> create runtime/seed.iso
      -> write runtime/runtime-version.json
      -> chown/chmod installed files
      -> write proxy port into proxy LaunchDaemon plist
      -> launchctl bootstrap/kickstart VM/proxy/watchdog services when startAfterInstall=true
      -> launchctl enable/disable according to startOnBoot
      -> remove install settings JSON
```

VM service가 시작되면 `vitalserver-vm start`가 `vm-config.json`을 읽어 Apple Virtualization VM을 띄웁니다. guest cloud-init은 `seed.iso`의 `runcmd`로 `/mnt/tirosh/deploy/bootstrap.sh`를 실행합니다. guest bootstrap은 Docker image bundle을 load하고 Compose stack 안의 edge nginx container를 구성한 뒤 `/mnt/tirosh/run/runtime-state.json`에 VM IP와 guest HTTP readiness를 기록합니다. proxy service의 `vitalserver-proxy-run`은 이 runtime state를 기다렸다가 host nginx config를 렌더링하고 nginx를 시작 또는 reload합니다.

설치 시 설정값은 MDM 또는 고급 설치 wrapper가 `installer` 실행 전에 `/private/tmp/tirosh-vitalserver-install.json`에 쓸 수 있습니다. 이 파일은 partial JSON이며 `postinstall` 이후 삭제됩니다. 일반 사용자 설치는 기본값으로 진행하고, 설치 후 Helper app의 Settings에서 runtime 설정을 변경합니다.

Uninstall 로직은 Helper app에 중복 구현하지 않고, 설치된
`/usr/local/bin/tirosh-vitalserver-uninstall`을 관리자 권한으로 호출합니다. Helper app을 열 수 없는 깨진 설치 상태에서는 같은 command를 Terminal 또는 MDM/Jamf에서 root로 실행합니다.

기본 Uninstall은 먼저 VM 안의 Redis volume에서 복구 가능한 Redis backup을 생성합니다. 이 backup이 완료되지 않으면 제거를 중단합니다. 이후 Helper app, LaunchDaemon, runtime tools, uninstaller, VM disk, package receipt를 제거하지만 `.vital` 파일 경로, logs, rollback backups, Redis backups는 보존합니다. Clean Uninstall은 `--clean`을 전달해 Redis backup 생성과 보존 단계를 건너뛰고 VM 영역, logs, backups, Redis backups, 설정된 vital files directory까지 삭제합니다. Helper UI에서 시작한 uninstall은 관리자 승인 후 background uninstaller를 시작했다는 handoff까지만 표시하고 Helper app을 종료합니다. 실제 cleanup 진행과 실패/완료 로그는 root uninstaller가 `/private/tmp/tirosh-vitalserver-uninstall.log`에 기록합니다.

Fresh install 차단 조건과 uninstall 제거 대상은 같은 계약을 따라야 합니다. `preinstall`이 검사하는 `/Library/Application Support/VitalServerHelper`, Helper app, runtime tools, uninstaller, LaunchDaemon plist, loaded launchd service, package receipt, Host proxy port listener가 uninstall 이후 남으면 다음 `.pkg` 설치는 실패해야 합니다. Package receipt는 현재 installer receipt인 `ai.tirosh.vitalserver.helper`만 검사하고 정리합니다.

```text
VitalServer Helper.app
  운영 중:
    Status
    Settings
    Update
    Rollback
    Logs
    Uninstall
    Clean Uninstall

Fallback:
  sudo /usr/local/bin/tirosh-vitalserver-uninstall
  sudo /usr/local/bin/tirosh-vitalserver-uninstall --clean
```

### Reset Installer recovery artifact

Fresh install이 기존 Host state 때문에 막힌 현장에는 일반 installer와 별도로 reset cleanup만
수행하는 복구 artifact를 전달합니다. 사용자에게 Terminal 명령만 전달하는 방식은 권한 승인,
오타, shell 환경, MDM 정책에 따라 흔들리므로 기본 전달물은 signed/notarized macOS flat package로
둡니다.

```text
VitalServerHelperResetForReinstall-<version>.pkg
```

빌드 target:

```sh
make dist/reset-installer/dev
make dist/reset-installer/release
```

이 package는 제품을 설치하거나 update하지 않습니다. root `postinstall`에서 reset cleanup
workflow만 실행하고 `/private/tmp/tirosh-vitalserver-uninstall.log`에 진행 상태와 실패 원인을
남깁니다. GUI를 열 수 없는 깨진 설치 상태를 다루기 위한 artifact이므로 Helper app, Runtime
Control API, 기존 설치된 uninstaller가 반드시 살아 있다고 가정하면 안 됩니다.

작성 원칙:

- 별도 package identifier를 사용합니다. 예: `ai.tirosh.vitalserver.helper.reset-installer`.
- 사용자가 보는 package 이름은 `Reset VitalServer Helper for Reinstall.pkg`로 두고,
  DMG 안에서는 `Troubleshooting Tools` 폴더 아래에 배치합니다.
- package entrypoint는 `runtime uninstall --force-clean-uninstaller`이며 별도 설정이나 fallback
  mode를 숨겨 두지 않습니다.
- 제거 대상은 Vital Server Helper가 소유한 explicit path, LaunchDaemon label, package receipt,
  runtime process, host proxy listener로 제한합니다.
- clean reset 대상에는 `productRoot` 전체가 포함됩니다. 따라서 product root 아래의 VM pid file,
  run marker, status documents, runtime state, VM disk, cloud-init seed, logs, rollback backups,
  Redis backups도 함께 제거됩니다.
- VM pid file이 missing이면 cleanup success로 추정하지 않습니다. force clean recovery는 explicit
  launchd state를 읽고 VM/sleep-prevention service unload를 계속 시도해야 합니다.
- 외부 nginx, Homebrew, Docker, 사용자 문서, 병원 데이터 경로는 product-owned state로 명시되지
  않은 한 제거하지 않습니다.
- 기존 `/usr/local/bin/tirosh-vitalserver-uninstall`이 있으면 같은 uninstall 계약을 사용할 수
  있지만, 없거나 실행 불가능한 상태도 명시 failure로 보고해야 합니다.
- fresh install preflight와 Reset Installer 제거 대상은 같은 state contract를 공유해야 합니다.
- 완료 후에도 preflight blocker가 남으면 새 installer가 계속 실패해야 하며, recovery package가
  그 blocker를 empty success로 바꾸면 안 됩니다.

지원팀/MDM용으로는 같은 cleanup workflow를 root script entrypoint로 제공할 수 있습니다. 다만
사용자에게 직접 전달하는 기본 형식은 `.command` 파일이나 shell snippet보다 signed package가
적합합니다. macOS Installer가 관리자 권한 요청과 실행 로그 흐름을 제공하고, Gatekeeper/보안
정책에서 출처를 확인하기 쉽기 때문입니다.

## 인터페이스 계약

현재 제품화 흐름은 여러 실행 환경을 건너므로, 각 경계의 입력과 출력 계약을 분리해서 관리합니다.

| 경계 | 호출자 | 피호출자 | 입력 계약 | 출력/부작용 |
|---|---|---|---|---|
| build orchestration | `make/vm.mk` | `vitalserver-devtools` | `vm-build.toml`, source tree, optional Make overrides | `.tmp/vitalserver-vm-pkg/*`, `dist/*` |
| Ubuntu/rootfs build | `make devtools/golden-rootfs` | Python `ubuntu`, `cloud-init`, Swift launcher | Ubuntu cloud image, deploy bundle, bootstrap script | clean `vm-disk.img`, compressed `rootfs-base.raw.gz` |
| nginx bundle | `make devtools/nginx/bundle` | Python `nginx-bundle` | pinned macOS nginx binary, expected version | self-contained `nginx/sbin`, `nginx/lib` bundle |
| Docker image bundle | `make devtools/docker/images` | Python `docker-images` | Dockerfile, image list, build platform | `vitalserver-images.tar.gz` |
| PKG/DMG staging | `vitalserver-devtools release-pkg` / `release-dmg` | Python build CLI, Swift, macOS packaging tools | release manifest, app source, rootfs base, nginx binary, Docker image list, templates | package root under `.tmp/vitalserver-vm-pkg/root`, `dist/*` |
| install provisioning | PKG `postinstall` | `vitalserver-vm runtime install-provision` | installed payload, optional `/private/tmp/tirosh-vitalserver-install.json` | `vm-disk.img`, `vm-config.json`, `seed.iso`, permissions, launchd services, degraded runtime status until health is observed |
| runtime status | RuntimeLifecycle | `runtime-status.json` | health/install/update/rollback result | Helper/watchdog-readable status |
| VM launch | launchd | `vitalserver-vm start` | `VITALSERVER_VM_HOME`, `VITALSERVER_VM_DETACHED=1`, `runtime/vm-config.json` | Virtualization.framework VM process |
| watchdog | launchd | `vitalserver-vm runtime watchdog` | runtime files, launchd state, guest runtime state, HTTP health | runtime status update, VM/proxy kickstart |
| host proxy | launchd | `vitalserver-proxy-run` | `vm/data/run/runtime-state.json`, legacy `vm-ip`, proxy template, nginx binary | rendered host nginx config, nginx process |
| guest bootstrap | cloud-init | `bootstrap.sh`, Guest tools wheel | VirtioFS mounts, `runtime-config.json`, Docker bundle | Docker Compose stack, edge nginx container, runtime state marker |
| update verification | operator/Helper | `vitalserver-vm runtime verify-bundle` | bundle tarball | manifest/checksum validation |
| update apply | operator/Helper | `vitalserver-vm runtime apply-bundle` | verified bundle tarball | staged bundle, backup, artifact replacement, migrations, health check |

이 표가 현재 source of truth입니다. Shell은 installer/launchd wrapper로 제한하고, manifest parsing, checksum 검증, backup, rollback 정책은 Swift runtime lifecycle command가 담당합니다.

### 설치 설정 계약

설치 시 optional settings 파일은 아래 경로를 사용합니다.

```text
/private/tmp/tirosh-vitalserver-install.json
```

파일이 없으면 기본값을 사용합니다.

| 설정 | 기본값 | 현재 계약 |
|---|---:|---|
| `cpuCount` | 8 | 7-64 |
| `memoryGiB` | 8 | 4-64 GiB, 4 GiB 단위 |
| `diskGiB` | 32 | 4-512 GiB, 4 GiB 단위. 설치 후에는 증가만 허용 |
| `networkMode` | `shared` | `shared` 또는 `bridged` |
| `proxyPort` | 80 | 1-65535, LaunchDaemon plist에 저장하고 Runtime CLI/Helper가 해당 값을 읽음 |
| `vitalFilesDirectory` | `/Library/Application Support/VitalServerHelper/vm/data/vital-files` | absolute path |
| `adminPassword` | `admin` | admin 계정 reset 값. empty가 아니면 guest runtime에 적용 |
| `vmHostname` | `tirosh-vitalserver` | hostname-safe 문자열 |
| `sshAuthorizedKeys` | `[]` | optional OpenSSH public key 배열. 제공한 key만 cloud-init `ubuntu` 계정에 등록하며 password SSH는 항상 비활성화 |
| `vitalServerURL` | empty | optional absolute `http`/`https` URL. Reverse proxy/HTTPS/domain 운영 시 Status와 runtime advertised URL에 사용 |
| `remoteConsoleURL` | empty | optional absolute `http`/`https` URL. Remote Console이 VitalServer와 다른 도메인일 때 사용 |
| `publicHost` | empty | legacy guest compatibility field. `vitalServerURL`이 있으면 Host가 host를 파생 |
| `publicPort` | 80 | legacy guest compatibility field. `vitalServerURL`이 있으면 Host가 port를 파생 |
| `startAfterInstall` | true | bool |
| `startOnBoot` | true | bool |

현재 settings JSON은 partial override 계약입니다. 파일을 제공하는 installer UI, MDM, 또는 설치 wrapper는 바꾸고 싶은 필드만 쓰면 됩니다. 누락된 필드는 기본값을 사용합니다. 기존 numeric/URL 범위를 벗어난 값은 무시하지만, `sshAuthorizedKeys`처럼 보안 접근 경로를 여는 값이 제공됐는데 형식이 맞지 않으면 설치 설정 로드가 실패합니다.

예시:

```json
{
  "cpuCount": 8,
  "memoryGiB": 16,
  "diskGiB": 128,
  "proxyPort": 8080,
  "vitalFilesDirectory": "/Users/Shared/TiroshVitalFiles",
  "adminPassword": "change-me",
  "sshAuthorizedKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexample operator@example.test"
  ],
  "vitalServerURL": "https://vitaldb.tirosh.ai/",
  "remoteConsoleURL": "https://console.tirosh.ai/",
  "startAfterInstall": true,
  "startOnBoot": true
}
```

설치 wrapper는 `installer` 실행 전에 이 파일을 씁니다.

```sh
sudo install -m 0600 /path/to/install-settings.json /private/tmp/tirosh-vitalserver-install.json
sudo installer -pkg dist/VitalServerHelper-<version>.pkg -target /
```

개발용 Make target은 같은 계약을 `VM_INSTALL_SETTINGS`로 감쌉니다.

```sh
VM_INSTALL_SETTINGS=/path/to/install-settings.json make dist/install/dev
```

`postinstall`이 설정을 읽어 runtime provisioning에 반영한 뒤 settings 파일을 삭제합니다.

### Proxy Port 계약

v1 기본 proxy port는 80입니다.

```text
external client
  -> target Mac host nginx :80
  -> Linux VM edge nginx :80
  -> VitalServer container :18080
```

`proxyPort`는 설치 설정과 LaunchDaemon environment로 전달됩니다. Runtime CLI와 Helper app은 설치된 proxy LaunchDaemon plist에서 `VITALSERVER_PROXY_PORT`를 읽어 health/open URL에 반영합니다.

```text
install settings JSON
  -> postinstall
  -> proxy LaunchDaemon EnvironmentVariables:VITALSERVER_PROXY_PORT
  -> vitalserver-proxy-run
  -> RuntimeLifecycle status/health
  -> Helper app health/open URL
```

### Update Bundle 계약

`make dist/update/release`는 현재 아래 artifact를 만들 수 있습니다.

| artifact type | 생성 여부 | Swift verify | Swift apply |
|---|---:|---:|---:|
| `rootfs-base` | `vm-rootfs-update-bundle-release`에서만 포함 | 예 | `rootfs-base.raw.gz` 교체 |
| `app-bundle` | 기본 포함 | 예 | `/Applications/VitalServer Helper.app` 교체 |
| `runtime-tools` | 기본 포함 | 예 | `/usr/local/bin` Updater/Supervisor/VM Driver tools 교체 |
| `nginx-bundle` | 기본 포함 | 예 | host nginx bundle 교체 |
| `guest-deploy` | 기본 포함 | 예 | VM shared deploy bundle 교체 |
| `migration` | optional | 예 | executable이면 순차 실행 |

따라서 현재 update apply의 실제 효과는 아래입니다.

```text
verify bundle
stage bundle
backup managed artifacts/runtime-version
stop services
replace app/runtime-tools/nginx/guest-deploy artifacts
replace rootfs-base only when the bundle includes rootfs-base
run executable migrations
write runtime-version.json
restart services if previously running
health check
rollback on failure
```

중요한 제약은 `rootfs-base.raw.gz`와 `vm-disk.img`의 역할 차이입니다.

```text
rootfs-base.raw.gz = immutable base artifact
vm-disk.img        = installed mutable runtime instance
```

update에서 rootfs base를 교체해도 기존 `vm-disk.img` 내부 OS와 application runtime은 자동으로 교체되지 않습니다. 이미 설치된 VM 내부를 바꾸는 작업은 migration, guest deploy 변경, Docker image bundle 갱신 같은 별도 artifact로 정의해야 합니다.

설치 테스트는 실제 시스템 경로를 사용합니다.

| 경로 | 내용 |
|---|---|
| `/usr/local/bin` | VM launcher/runtime lifecycle CLI, proxy runner |
| `/Library/LaunchDaemons` | VM/proxy 자동 실행 plist |
| `/Library/Application Support/VitalServerHelper` | VM image, deploy bundle, nginx runtime |
| `/Library/Application Support/VitalServerHelper/logs/install.log` | installer provisioning log, 10 MiB 기준 rotation |
| `/Library/Application Support/VitalServerHelper/status/runtime-status.json` | Helper/watchdog용 runtime 상태 |

설치 후 `make dist/installed/health`로 launchd load 상태, VM IP, guest HTTP, host proxy HTTP를 확인합니다.

개발 중 설치/제거를 반복할 때는 `make dist/uninstall/dev`를 사용합니다. 이 target은 `/Library/Application Support/VitalServerHelper`, 관련 LaunchDaemon plist, `/usr/local/bin/vitalserver-*`를 제거하므로 운영 환경에서는 사용하지 않습니다.

설치된 Mac mini/Mac Studio에서 사용자가 CLI로 제거할 때는 아래 명령을 사용합니다.

```sh
sudo tirosh-vitalserver-uninstall
```

이 명령은 Redis backup을 생성한 뒤 VM/proxy/guest-log-sync/watchdog LaunchDaemon을 unload하고, package가 설치한 runtime 파일과 Helper app을 제거합니다. 기본 모드는 `.vital` 파일 경로, logs, rollback backups, Redis backups를 보존합니다. 완전 삭제가 필요하면 `sudo tirosh-vitalserver-uninstall --clean`을 사용합니다. Clean Uninstall은 Redis backup 보존 없이 VM 영역과 backup 영역까지 제거합니다. GUI 제품에서는 Helper app의 “Uninstall”과 “Clean Uninstall”이 background uninstaller를 시작한 뒤 종료합니다. 삭제 완료 여부는 `/private/tmp/tirosh-vitalserver-uninstall.log`를 확인합니다.

`.pkg`로 재설치하려면 먼저 uninstall 또는 clean uninstall을 완료해야 합니다. `preinstall`은 stale install artifact를 정리하지 않고 설치 실패로 보고합니다. 삭제와 재설치 책임을 분리해야 fresh install과 update가 서로의 state를 추정하지 않습니다.

### nginx release artifact

`make dist/pkg/dev`와 `make dist/pkg/release`는 package에 넣을 macOS nginx bundle까지 포함해서 만듭니다. `make devtools/nginx/bundle`은 기본적으로 build machine의 nginx를 release artifact cache로 복사한 뒤, `config/vm-build.toml`의 `[nginx]` 설정으로 bundle을 만듭니다. 기본 artifact 경로는 아래입니다.

```text
.artifacts/nginx/macos/bin/nginx
```

이 파일은 repository에 commit하지 않는 build-machine 입력 cache입니다. 로컬 unsigned build에서는 Homebrew nginx를 자동으로 복사해 release artifact를 만듭니다.

```sh
make devtools/nginx/bundle
```

기본 source binary는 `/opt/homebrew/opt/nginx/bin/nginx`입니다. 다른 위치에서 artifact cache를 만들려면 source path를 명시합니다.

```sh
VM_NGINX_SOURCE_BIN=/path/to/nginx make devtools/nginx/artifact
```

build tooling은 이 binary의 `nginx -v` 출력이 선택된 release manifest의 `services.hostProxy.image`와 맞는지 확인한 뒤, 실행 파일과 비시스템 dylib를 package 내부로 복사합니다. artifact cache가 없거나 release manifest와 맞지 않으면 `source_binary_path`에서 캐시를 다시 채웁니다.

```text
nginx/sbin/nginx
  -> @executable_path/../lib/libpcre2-8.0.dylib
  -> @executable_path/../lib/libssl.3.dylib
  -> @executable_path/../lib/libcrypto.3.dylib
  -> /usr/lib/libz.1.dylib
  -> /usr/lib/libSystem.B.dylib
```

즉 운영 target Mac에 Homebrew가 없어도 host proxy가 뜰 수 있는 구조입니다. 임시로 다른 binary를 bundle 입력으로 직접 쓰려면 명시적으로 override합니다. 이 경우 artifact cache 생성 단계는 건너뜁니다.

```sh
VM_NGINX_BIN=/path/to/nginx \
make devtools/nginx/bundle
```

air-gapped 제품 package는 외부 Docker registry 없이 container를 시작할 수 있어야 합니다. 현재 package flow는 `make devtools/docker/images`로 아래 image를 하나의 bundle로 만들고, 설치 후 guest bootstrap에서 `docker load`를 먼저 수행합니다.

```text
vitalserver:2.3.4
redis:3.2.12-alpine
ghcr.io/joeferner/redis-commander:0.9.0
swaggerapi/swagger-ui:v5.17.14
nginx:1.24-alpine
```

Docker image bundle은 guest VM architecture에 맞춰 `linux/arm64`로 생성합니다. Apple Virtualization Framework 기반 guest가 arm64 Ubuntu로 부팅되므로, amd64 image를 넣으면 guest에서 `exec format error`가 발생합니다. Redis Commander는 Docker Hub의 `latest`가 아니라 GHCR의 pinned multi-arch image를 사용합니다.

생성/설치 경로는 아래와 같습니다.

```text
.tmp/vitalserver-vm-pkg/docker-images/vitalserver-images.tar.gz
/Library/Application Support/VitalServerHelper/vm/data/deploy/docker-images/vitalserver-images.tar.gz
```

Docker image만으로는 충분하지 않습니다. Guest VM이 처음 부팅될 때 `docker.io`, Docker Compose 같은 runtime package를 apt로 설치해야 한다면 air-gapped 환경에서 실패합니다. 그래서 제품용 package는 개발용 VM disk가 아니라 별도 golden VM home에서 만든 clean rootfs base를 사용합니다. VM 내부 edge nginx는 OS package가 아니라 `nginx:1.24-alpine` container로 실행합니다.

```sh
make devtools/golden-rootfs
make dist/pkg/dev
```

기본 package용 rootfs는 `8G`(8 GiB)입니다. `VM_ROOTFS_SIZE`의 `G` suffix는 build tool 입력 형식이며 GiB 기준으로 해석합니다. `make devtools/golden-rootfs`는 `.tmp/vitalserver-vm-golden` 아래에서 VM을 임시로 띄우고 `prepare-airgap-rootfs.sh`만 실행한 뒤 `.tmp/vitalserver-vm-pkg/rootfs-base.raw.gz`를 생성합니다. 이 스크립트는 OS package를 설치하고 `/mnt/tirosh/run/rootfs-ready` marker를 기록한 뒤 종료됩니다. Container는 시작하지 않기 때문에 운영 데이터나 Redis volume을 golden rootfs에 섞지 않습니다.

반복 개발 중에는 기존 golden rootfs cache를 재사용합니다. cache가 없으면 `make dist/pkg/dev`가 자동으로 한 번 생성합니다. release 검증처럼 clean rootfs를 반드시 다시 만들려면:

```sh
make dist/pkg/release
make dist/dmg/release
```

동일한 동작을 변수로 직접 지정할 수도 있습니다.

```sh
VM_RECREATE_GOLDEN_ROOTFS=true make dist/pkg/dev
```

## Update Bundle

온라인/오프라인 업데이트는 같은 bundle tarball을 입력으로 사용합니다.

```sh
make dist/update/release
make dist/update/verify/release
```

VM Image/rootfs/base OS까지 포함하는 업데이트는 별도 target을 사용합니다. 이 bundle은 `vm-image-update`로 취급하고 Danger Zone에서 다룹니다.

```sh
make dist/image-update/release
make dist/image-update/verify/release
```

`make dist/update/release`는 Product Update artifact staging을 `packages/vitalserver-devtools` CLI에서 수행하고
`app-bundle.tar.gz`, `runtime-tools.tar.gz`, `nginx-bundle.tar.gz`, `guest-deploy.tar.gz`를 기본 포함합니다.
`app-bundle.tar.gz`에는 Swift Helper app과 Runtime Control PWA static assets
(`Contents/Resources/runtime-control-pwa`)가 함께 들어갑니다. 따라서 Helper UI, PWA UI, Native Shell,
Runtime Control API, Updater/Supervisor/VM Driver tools, host nginx, Service Stack/guest deploy bundle까지
같은 online/offline Product Update 계약으로 배포할 수 있습니다.

update bundle도 압축이 필요합니다. 다만 압축 대상은 update artifact 단위입니다. 일반적인 현장 업데이트는 작은 `.tar.gz` artifact를 교체하는 흐름이고, 무거운 `rootfs-base.raw.gz`를 매번 다시 압축하거나 배포하는 흐름이 아닙니다.

| artifact | 압축 파일 | Product Update 포함 여부 | 비고 |
|---|---|---|---|
| Helper UI + Runtime Control PWA | `app-bundle.tar.gz` | 기본 포함 | `/Applications/VitalServer Helper.app` 교체. PWA는 app resource static asset으로 포함 |
| Updater/Supervisor/VM Driver tools | `runtime-tools.tar.gz` | 기본 포함 | `/usr/local/bin` local control tools 교체 |
| host nginx bundle | `nginx-bundle.tar.gz` | 기본 포함 | host proxy binary/dylib 교체 |
| Service Stack / guest deploy bundle | `guest-deploy.tar.gz` | 기본 포함 | VM shared deploy script/config, compose, container image bundle 교체 |
| migration | executable files | 기본 포함 | cloud-init seed refresh 등 설치된 VM/runtime 상태 변경 |
| Docker images | `vitalserver-images.tar.gz` | 필요 시 포함 | container image 갱신이 있을 때만 무겁게 포함 |
| VM Image / rootfs base | `rootfs-base.raw.gz` | `vm-rootfs-update-bundle-release`에서만 포함 | 신규 설치 또는 base OS/package 변경용. 기존 `vm-disk.img`를 자동 교체하지 않음 |

따라서 “bundle을 만든다”는 것은 보통 작은 product artifact를 압축해 묶는다는 뜻입니다. rootfs나 Docker image 갱신이 없는 Product Update bundle은 package build보다 훨씬 가벼워야 합니다.

기본 update bundle에는 `apps/vitalserver-macos-runtime/Support/Build/migrations` 아래의 기본 migration들이 포함됩니다. 구버전 Helper가 bundle을 적용해도 이 migration은 실행되므로, 새 `guest-deploy/bootstrap.sh`가 다음 VM 부팅에서 실행될 수 있습니다.

추가 마이그레이션 실행 파일을 bundle에 포함하려면 build CLI를 직접 호출합니다.

```sh
uv run --project packages/vitalserver-devtools vitalserver-devtools \
  --config config/vm-build.toml \
  release-update-bundle \
  --release-file apps/vitalserver-macos-runtime/release.json \
  --migration release/migrations/001-example
```

생성물:

```text
dist/update-bundles/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
```

tarball 내부 구조:

```text
update-bundle-<channel>-<kind>-<releaseLabel>/
  manifest.json
  checksums.txt
  signature
  app-bundle.tar.gz
  runtime-tools.tar.gz
  nginx-bundle.tar.gz
  guest-deploy.tar.gz
  migrations/
```

`make dist/image-update/release`로 만든 bundle에는 위 목록에 `rootfs-base.raw.gz`가 추가됩니다.

`manifest.json`은 `schemaVersion: 3`을 사용합니다. `channel`, `helperVersion`, `releaseLabel`은 required입니다. `helperVersion`은 package-safe numeric version이고, `releaseLabel`은 dev/stable artifact identity입니다. `artifacts`와 `migrations`는 모두 `checksums.txt`와 manifest 자체의 sha256/size 값으로 검증됩니다.

현재 `signature`는 `unsigned` placeholder입니다. 이 파일은 호환 레이어가 아니라 bundle 계약의 고정 자리이며, release hardening 단계에서 실제 signature 검증으로 교체합니다.

설치된 Mac mini/Mac Studio에서는 Swift runtime lifecycle command가 bundle을 검증하고 적용합니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime stage-bundle /path/to/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime rollback
```

`apply-bundle`은 mutable `vm-disk.img`를 보존하고, replaceable artifact만 backup/rollback 대상으로 삼습니다. 적용 전 backup을 만들고 VM/proxy를 중지한 뒤 artifact를 교체하고 executable migration을 순서대로 실행합니다. 새 runtime은 `guest-deploy`가 포함된 update에서 cloud-init seed를 갱신하고 guest activation request를 생성해 VM 내부 Docker image load와 compose recreate를 수행합니다. 기존에 서비스가 실행 중이었다면 재시작 후 health check를 통과해야 성공 처리합니다. migration 또는 health check 실패 시 `rollback`으로 직전 backup을 복원합니다.

지원 artifact type:

| type | artifact name | 적용 대상 |
|---|---|---|
| `rootfs-base` | `rootfs-base.raw.gz` | `vm-image-update` bundle에 포함된 경우에만 이후 provisioning 기준 rootfs base 교체 |
| `app-bundle` | `app-bundle.tar.gz` | `/Applications/VitalServer Helper.app` |
| `runtime-tools` | `runtime-tools.tar.gz` | `/usr/local/bin` Updater/Supervisor/VM Driver tools |
| `nginx-bundle` | `nginx-bundle.tar.gz` | host nginx bundle |
| `guest-deploy` | `guest-deploy.tar.gz` | VM shared deploy bundle |

### Guest deploy 변경 반영 정책

`guest-deploy.tar.gz`는 host shared directory의 `vm/data/deploy`를 교체합니다. 여기에 `bootstrap.sh`, `guest-tools.toml`, compose, guest bin/systemd, Docker image bundle이 포함됩니다. 단순 파일 교체만으로 VM 내부 Docker daemon이나 systemd unit이 자동 갱신되는 것은 아니므로, update bundle은 아래 경로로 반영합니다.

```text
apply-bundle
  -> guest-deploy 교체
  -> 기본 migration으로 seed.iso 갱신
  -> VM 재시작 시 bootstrap.sh 재실행
  -> 새 runtime이면 activate-update.request 생성
  -> VM 내부에서 Docker image load + compose recreate
  -> runtime-state.json 갱신
```

따라서 `bootstrap.sh` 같은 guest deploy 수정은 새 update bundle을 만들면 포함됩니다. 이미 설치된 현장에서는 해당 bundle을 적용해야 실제 `/Library/Application Support/VitalServerHelper/vm/data/deploy`와 VM 내부 runtime에 반영됩니다.

설치 후 runtime 설정 변경은 아래 command가 source of truth입니다.

```sh
sudo /usr/local/bin/vitalserver-vm runtime configure \
  --cpu 8 \
  --memory-gib 8 \
  --network shared \
  --bridged-interface "<interface-id-if-bridged>" \
  --proxy-port 80 \
  --vital-files-dir "/Library/Application Support/VitalServerHelper/vm/data/vital-files" \
  --vitalserver-url "http://127.0.0.1:80/" \
  --remote-console-url "http://127.0.0.1:18321/" \
  --public-host "" \
  --public-port 80 \
  --start-on-boot true \
  --admin-password-file "/private/tmp/admin-password" \
  --restart
```

이 command는 `vm-config.json`, deploy `runtime-config.json`, proxy LaunchDaemon plist, launchd enable/disable 정책을 갱신하고 `--restart`가 있으면 VM/proxy/watchdog을 kickstart합니다. Helper app의 Settings tab도 이 command를 호출합니다. Helper UI는 advertised service URL 입력에 local 기본 URL을 채우며, Apply 시 빈 값이나 absolute `http`/`https` URL 형식이 아닌 값은 실패시킵니다. remote client가 접속해야 하는 운영 환경에서는 `127.0.0.1` 기본값을 외부에서 도달 가능한 URL로 바꿔야 합니다. Helper app의 admin password 입력은 기존 값을 표시하지 않고, 운영자용 admin password reset을 선택했을 때만 `/private/tmp` 아래 0600 임시 파일을 만들고 `--admin-password-file`을 전달합니다. CLI의 `--admin-password`는 개발/수동 복구용으로 남기지만, 운영 UI에서는 argv/log 노출을 줄이기 위해 file 입력을 사용합니다.

admin password reset은 VitalServer 본체의 사용자 계정 기능을 확장하거나 수정하는 기능이 아닙니다. VitalServer UI의 비밀번호 변경은 현재 비밀번호를 아는 사용자가 본인 계정을 변경하는 흐름이고, Helper의 reset은 설치/운영 관리자가 `admin` 계정을 복구하거나 초기화하기 위한 패키징 레벨의 유지보수 기능입니다. 위험도가 높은 설정이므로 향후 운영 정책에 따라 Helper UI에서 제거하고 CLI 또는 recovery flow로만 남길 수 있습니다. deploy `runtime-config.json`은 admin reset 값을 포함하므로 install/configure 직후 0600 권한으로 제한합니다.

설치 후 Helper에서 바로 변경하는 범위와 별도 기능으로 분리해야 하는 범위는 아래처럼 구분합니다.

| 범위 | 처리 |
|---|---|
| CPU, memory, network, bridged interface | `vm-config.json` 갱신 후 restart |
| proxy port | proxy LaunchDaemon environment 갱신 후 restart |
| Vital files directory | VM shared directory와 guest runtime config 갱신 후 restart |
| advertised URLs, admin password reset | guest `runtime-config.json`/`runtime-settings.json` 갱신 후 restart |
| start on boot | `launchctl enable/disable system/<label>`로 VM/proxy/watchdog 정책 갱신 |
| disk size | 별도 resize/migration flow 필요 |
| VM hostname | `seed.iso`/guest hostname 재생성 또는 guest migration flow 필요 |

rootfs base 교체는 이후 install/provisioning 기준 artifact를 바꾸는 동작입니다. 이미 생성된 `vm-disk.img` 내부에 새 rootfs를 자동 전개하지 않습니다.

Shell은 installer/launchd wrapper로만 남깁니다. Bundle manifest parsing, checksum 검증, backup, rollback 정책은 Swift runtime lifecycle command가 담당합니다.

남은 제품화 항목은 아래입니다.

Swagger UI는 VM guest deploy bundle의 `deploy/docs`를 읽어 multi-spec catalog를 제공합니다.
기본 포함 spec은 `api/vitalserver.openapi.yaml`(VitalServer), `runtime/macos/runtime-control.openapi.json`
(Runtime Control API), `api/audit-proxy.openapi.yaml`(Audit Proxy API)입니다.
기존 `/swagger/openapi.yaml` 호환 경로는 유지합니다.

| 항목 | 필요한 이유 |
|---|---|
| Developer ID signing | launchd/Virtualization binary 배포 신뢰성 확보 |
| notarization | Gatekeeper 환경에서 설치 마찰 감소 |
