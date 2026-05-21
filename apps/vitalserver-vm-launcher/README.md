# VitalServer VM Launcher

`vitalserver-vm-launcher`는 Apple Virtualization Framework로 Linux VM을 실행하는 PoC입니다.

목표는 Mac mini 또는 Mac Studio에서 Linux VM을 직접 띄우고, macOS host nginx를 통해 VM 내부 VitalServer를 운영할 수 있는지 검증하는 것입니다.

```text
Mac mini / Mac Studio
  -> host nginx :80
      -> vitalserver-vm
          -> Linux VM shared/NAT
              -> Docker Compose
                  - vitalserver
                  - redis
```

상세 설계와 운영 판단 기준은 [VitalServer VM Launcher 문서](../../docs/vitalserver-vm-launcher.md)를 봅니다.

## 빠른 실행

shared/NAT mode로 부팅 PoC를 확인합니다.

```sh
make vm-up
```

`make vm-up`은 VM을 background로 시작하고, guest가 기록한 VM IP와 HTTP readiness를 기다린 뒤 host nginx를 VM으로 연결합니다.

VM 콘솔을 직접 보고 싶으면 아래처럼 실행합니다.

```sh
make vm-prepare
make vm-start
```

상태 확인과 종료:

```sh
make vm-status
make vm-health
make vm-down
```

VM IP만 확인하거나 host nginx를 다시 연결하고 싶을 때:

```sh
make vm-ip
make vm-proxy-start
```

## Network Mode

v1 기본 구조는 `shared/NAT VM + macOS host nginx`입니다. host nginx 경유 시 VRecorder 원 IP 보존이 확인되었기 때문에, bridged mode는 필수 경로가 아닙니다.

bridged mode는 host nginx 없이 VM을 병원 LAN에 직접 붙이는 옵션입니다. Apple의 restricted entitlement 승인이 필요하므로 별도 조건을 만족할 때만 사용합니다.

```sh
make vm-interfaces
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

제품 GUI에서는 `shared/NAT`를 기본값으로 두고, bridged는 승인/네트워크 조건을 만족할 때 선택하게 하는 방향입니다.

## 주요 명령

| 명령 | 설명 |
|---|---|
| `make vm-prepare` | Linux boot asset 준비, cloud-init 생성, guest bundle staging |
| `make vm-up` | shared/NAT VM 시작, VM IP/HTTP 대기, host nginx 연결 |
| `make vm-up-bridged` | 승인된 signing identity로 bridged mode 준비 후 시작 |
| `make vm-down` | VM 종료 |
| `make vm-status` | VM process 상태 확인 |
| `make vm-health` | VM IP, guest HTTP, host nginx proxy 연결 확인 |
| `make vm-ip` | guest가 기록한 VM IP 표시 |
| `make vm-proxy-start` | host nginx를 VM endpoint로 시작 |
| `make vm-clean` | VM runtime state 삭제, shared data는 보존 |
| `make vm-interfaces` | bridged network interface 목록 확인 |
| `make vm-network-shared` | VM config를 shared/NAT mode로 설정 |
| `make vm-network-bridged` | VM config를 bridged mode로 설정 |
| `make vm-nginx-bundle` | nginx와 비시스템 dylib를 self-contained bundle로 묶기 |
| `make vm-docker-images` | air-gapped 설치용 Docker image bundle 생성 |
| `make vm-airgap-rootfs` | 온라인 빌드 환경에서 rootfs에 Docker/Compose 설치 |
| `make vm-app` | `/Applications`에 설치될 가벼운 macOS control app 생성 |
| `make vm-pkg` | control app, VM runtime, boot asset, guest bundle, host proxy launcher를 `.pkg`로 묶기 |
| `make vm-pkg-install` | 생성된 개발용 `.pkg`를 설치 |
| `make vm-pkg-uninstall-dev` | 개발용 설치물을 제거 |
| `make vm-installed-health` | 설치된 launchd VM/proxy 상태와 HTTP 확인 |

## Package

제품 목표는 Mac mini/Mac Studio에 설치 가능한 `.pkg`입니다. 현재 `make vm-pkg`는 개발 검증용 package를 만듭니다.
단일 PKG를 기본 배포물로 쓰는 이유는 이 제품이 단순 app bundle이 아니라 system-wide runtime을
설치하기 때문입니다. 설치 과정은 `/Applications` 밖의 경로, `/usr/local/bin`, LaunchDaemon,
host nginx bundle, Linux VM runtime asset, postinstall provisioning을 다룹니다.

`.app`만 제공하는 방식은 앱이 self-contained이고 `/Applications`로 복사한 뒤 사용자 권한으로 실행할 수
있을 때 적합합니다. 예를 들어 system daemon, privileged helper, `/usr/local/bin` CLI, shared runtime
asset, install-time provisioning이 없으면 `.app` 또는 drag-and-drop DMG가 더 자연스럽습니다. 이
프로젝트는 Mac mini/Mac Studio에 VM 기반 서비스를 설치하고 부팅 시 자동 시작해야 하므로 `.pkg`가
source of truth입니다.

```sh
make vm-pkg
```

`make vm-pkg` 생성물:

```text
dist/TiroshVitalServerVM-0.1.0.pkg
```

전달용 DMG가 필요하면 `make vm-dmg`를 실행합니다. DMG에는 단일 PKG만 들어갑니다.

```text
dist/TiroshVitalServer-0.1.0.dmg
```

이 package는 아래 항목을 설치하고, `postinstall`에서 runtime provisioning을 수행합니다.

| 항목 | 설치 위치 |
|---|---|
| control app | `/Applications/VitalServer Helper.app` |
| VM launcher and runtime lifecycle CLI | `/usr/local/bin/vitalserver-vm` |
| host proxy runner | `/usr/local/bin/vitalserver-proxy-run` |
| uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| nginx bundle | `/Library/Application Support/TiroshVitalServer/nginx/` |
| install log | `/Library/Application Support/TiroshVitalServer/logs/install.log` |
| runtime status | `/Library/Application Support/TiroshVitalServer/status/runtime-status.json` |
| Linux runtime assets | `/Library/Application Support/TiroshVitalServer/vm/runtime/` |
| guest deployment bundle | `/Library/Application Support/TiroshVitalServer/vm/data/deploy/` |
| Docker image bundle | `/Library/Application Support/TiroshVitalServer/vm/data/deploy/docker-images/` |
| nginx config template | `/Library/Application Support/TiroshVitalServer/vm/Support/Proxy/` |
| LaunchDaemons | `/Library/LaunchDaemons/com.tirosh.vitalserver-*.plist` |

shared/NAT mode에서는 VM IP가 부팅 후에 결정되므로, `vitalserver-proxy-run`이 VM IP 파일을 감시합니다. VM IP가 바뀌면 host nginx config를 다시 렌더링하고 proxy를 reload합니다.

`vm-disk.img`는 package에 그대로 넣지 않고 immutable base artifact인 `rootfs-base.raw.gz`로 묶습니다. 설치 시 `postinstall`이 이 base에서 mutable `vm-disk.img`를 생성합니다.

`make vm-pkg`는 Docker registry 없이도 container를 시작할 수 있도록 `vitalserver`, `redis`, `redis-ui`, `swagger-ui` image를 `vitalserver-images.tar.gz`로 묶어 포함합니다. Guest bootstrap은 이 bundle을 먼저 `docker load`한 뒤 Compose를 실행합니다.

## Interface Contracts

현재 제품화 경로의 주요 계약은 아래처럼 고정합니다.

| 경계 | 입력 | 출력/부작용 |
|---|---|---|
| `make vm-dmg` | `.artifacts` 입력, source tree | `dist/TiroshVitalServer-<version>.dmg` |
| `make vm-pkg` | golden rootfs, nginx bundle, Docker image bundle | `dist/TiroshVitalServerVM-<version>.pkg` |
| PKG `postinstall` | installed payload, optional install settings JSON | `/Library/Application Support/TiroshVitalServer/vm` runtime provisioning |
| `vitalserver-vm runtime install` | `rootfs-base.raw.gz`, deploy bundle, LaunchDaemon plist | mutable `vm-disk.img`, `vm-config.json`, `seed.iso`, loaded services |
| LaunchDaemon VM service | `VITALSERVER_VM_HOME`, `VITALSERVER_VM_DETACHED=1`, `vm-config.json` | background VM process |
| LaunchDaemon watchdog service | `VITALSERVER_VM_HOME`, `runtime-status.json` | periodic health check, VM/proxy restart, updated runtime status |
| `vitalserver-proxy-run` | `vm/data/run/vm-ip`, proxy template | host nginx config and proxy process |
| guest `bootstrap.sh` | `runtime-config.json`, `bin/*`, `systemd/*`, Docker image bundle | Docker Compose stack, edge nginx container, guest systemd service, diagnostics, Redis backup timer |
| update bundle | `manifest.json`, `checksums.txt`, `signature`, `rootfs-base.raw.gz`, migrations | verified/staged bundle, rootfs-base backup/replacement, migrations |

`runtime-status.json`은 Helper app, watchdog, 운영 CLI가 공유하는 운영 상태 파일입니다. `runtime install`, `health`, `watchdog`, `apply-bundle`, `rollback`이 이 파일을 갱신하며, 상태 값은 `installing`, `updating`, `recovering`, `healthy`, `degraded`, `critical` 중 하나입니다.

설치/업데이트 경로는 적용 전에 free-space preflight를 수행합니다. 설치 로그와 runtime launchd/proxy/watchdog 로그는 10 MiB 기준으로 최대 5개까지 rotation하며, guest bootstrap은 Docker image bundle을 load한 뒤 dangling image cleanup을 수행합니다. Guest에는 `tirosh-vitalserver-health`, `tirosh-vitalserver-diagnostics`, `tirosh-vitalserver-redis-backup.timer`를 설치해 현장 진단과 Redis volume 백업을 같은 계약으로 운용합니다.

주요 source 책임은 아래처럼 나눕니다.

| 영역 | 파일 | 책임 |
|---|---|---|
| Make | `make/vm.mk`, `make/vm/config.mk` | build/install target orchestration, artifact path |
| Python | `packages/vm-build/src/tirosh_vitalserver/vm_build` | Ubuntu/rootfs/nginx/Docker/update bundle build tooling |
| Runtime orchestrator | `Sources/RuntimeOrchestrator` | VM start/stop/status, runtime install/update/health |
| PKG wrapper | `Support/Packaging/postinstall` | install log 연결 후 `vitalserver-vm runtime install` 호출 |
| launchd proxy | `Support/Packaging/proxy-run` | VM IP 감시, host nginx config render/reload |
| Guest | `Support/Guest/bootstrap.sh` | Docker Compose bootstrap, edge nginx container, compose systemd service, runtime state marker, diagnostics, Redis backup timer |
| Helper app | `Sources/ManagerApp` | 설치 후 runtime-status/settings/update/rollback/health/open/uninstall UI |

DMG build/install 흐름은 아래입니다.

```text
make vm-dmg
  -> make vm-pkg-stage
    -> vm-app, vm-golden-rootfs, vm-nginx-bundle, vm-docker-images
    -> .tmp/vitalserver-vm-pkg/root
  -> pkgbuild
    -> dist/TiroshVitalServerVM-<version>.pkg
  -> hdiutil create
    -> dist/TiroshVitalServer-<version>.dmg

Install Tirosh VitalServer.pkg
  -> payload copy
  -> postinstall
  -> vitalserver-vm runtime install
  -> vm-disk.img, vm-config.json, seed.iso 생성
  -> launchd VM/proxy service 등록/시작
  -> guest bootstrap
  -> host nginx proxy ready
```

상세한 파일별 책임은 `docs/vm-launcher/architecture.md`, DMG/PKG 설치 단계는 `docs/vm-launcher/packaging.md`를 기준으로 봅니다.

현재 `runtime apply-bundle`이 실제로 적용하는 artifact type은 아래입니다.

| type | artifact name | 적용 대상 |
|---|---|---|
| `rootfs-base` | `rootfs-base.raw.gz` | 이후 provisioning 기준 rootfs base |
| `app-bundle` | `app-bundle.tar.gz` | `/Applications/VitalServer Helper.app` |
| `runtime-tools` | `runtime-tools.tar.gz` | `/usr/local/bin` runtime tools |
| `nginx-bundle` | `nginx-bundle.tar.gz` | host nginx bundle |
| `guest-deploy` | `guest-deploy.tar.gz` | VM shared deploy bundle |

각 artifact는 apply 전 backup 대상이며, migration 또는 health check 실패 시 rollback 대상입니다.

`rootfs-base.raw.gz`는 immutable base artifact이고, 설치된 `vm-disk.img`는 mutable runtime instance입니다. 따라서 update에서 rootfs base를 교체해도 이미 실행 중인 `vm-disk.img` 내부 OS/runtime이 자동으로 교체되지는 않습니다. 설치된 VM 내부 변경은 migration이나 별도 guest update contract로 처리해야 합니다.

기본 host proxy port는 80입니다. 설치 설정에서 다른 `proxyPort`를 지정하면 LaunchDaemon environment에 저장되고, runtime CLI와 Helper app은 설치된 plist에서 port를 읽어 health/open URL에 반영합니다.

설치 시 설정값은 installer 실행 전에 `/private/tmp/tirosh-vitalserver-install.json`에 partial JSON으로 씁니다. 누락된 값은 기본값을 사용합니다.

```json
{
  "cpuCount": 8,
  "memoryGiB": 16,
  "diskGiB": 128,
  "proxyPort": 8080,
  "vitalFilesDirectory": "/Users/Shared/TiroshVitalFiles",
  "publicHost": "vitalserver.local",
  "publicPort": 8080
}
```

```sh
sudo install -m 0600 install-settings.json /private/tmp/tirosh-vitalserver-install.json
sudo installer -pkg dist/TiroshVitalServerVM-0.1.0.pkg -target /
```

개발용 install target에서는 같은 동작을 아래처럼 실행할 수 있습니다.

```sh
VM_INSTALL_SETTINGS=install-settings.json make vm-pkg-install
```

업데이트 입력 단위는 bundle directory입니다.

```sh
make vm-update-bundle
make vm-update-bundle-verify
```

`make vm-update-artifacts`는 package staging root에서 아래 tarball을 자동 생성합니다.

```text
.tmp/vitalserver-vm-pkg/update-artifacts/
  app-bundle.tar.gz
  runtime-tools.tar.gz
  nginx-bundle.tar.gz
  guest-deploy.tar.gz
```

`make vm-update-bundle`은 이 artifact들을 기본 포함합니다.

설치된 Mac mini/Mac Studio에서는 runtime lifecycle CLI가 같은 bundle을 검증하고 적용합니다.

```sh
sudo vitalserver-vm runtime verify-bundle /path/to/update-bundle-0.1.0
sudo vitalserver-vm runtime stage-bundle /path/to/update-bundle-0.1.0
sudo vitalserver-vm runtime apply-bundle /path/to/update-bundle-0.1.0
sudo vitalserver-vm runtime rollback
```

`apply-bundle`은 mutable `vm-disk.img`를 보존하고 replaceable artifact만 교체합니다. 적용 전 backup을 만들고, runtime health check가 실패하면 Swift runtime lifecycle command가 해당 backup으로 rollback합니다.

기본 생성 위치:

```text
dist/update-bundles/update-bundle-0.1.0/
```

완전한 air-gapped 설치물은 개발용 VM disk가 아니라 별도 golden VM home에서 만든 clean rootfs base를 사용합니다.

```sh
make vm-golden-rootfs
make vm-pkg
```

`make vm-pkg`도 `vm-golden-rootfs`를 dependency로 실행하므로, package payload에는 `.tmp/vitalserver-vm-pkg/rootfs-base.raw.gz`가 들어갑니다. 기본 package용 rootfs는 4GB입니다. 반복 개발 중에는 기존 golden rootfs cache를 재사용합니다. release 검증처럼 clean rootfs를 반드시 다시 만들려면 `make vm-pkg-release` 또는 `make vm-dmg-release`를 사용합니다. 설치된 VM은 target Mac에서 `apt-get`을 실행하지 않습니다. 필요한 guest package는 golden rootfs에 미리 포함되어야 합니다.

설치 테스트:

```sh
make vm-pkg-install
make vm-installed-health
```

`make vm-pkg-install`은 `/Library/LaunchDaemons`, `/usr/local/bin`, `/Library/Application Support/TiroshVitalServer`에 설치하므로 관리자 권한이 필요합니다.

반복 테스트 중 설치물을 지우려면:

```sh
make vm-pkg-uninstall-dev
```

설치된 Mac mini/Mac Studio에서 사용자가 직접 제거할 때는:

```sh
sudo tirosh-vitalserver-uninstall
```

이 명령은 VM/proxy LaunchDaemon을 내리고, 설치된 runtime 파일을 제거합니다.

`make vm-pkg`는 package에 넣을 macOS nginx bundle도 함께 준비합니다. 기본값은 build machine의 `/opt/homebrew/opt/nginx/bin/nginx`를 `.artifacts/nginx/macos/bin/nginx`로 복사한 뒤, `vm-build.toml`의 `expected_version`으로 검증하는 흐름입니다. 현재 pinned version은 `nginx/1.31.0`입니다.

```sh
make vm-nginx-bundle
```

`vm-nginx-bundle`을 단독으로 실행해도 기본 artifact를 먼저 준비합니다. 다른 nginx binary를 직접 쓰려면 `VM_NGINX_BIN=/path/to/nginx make vm-nginx-bundle`처럼 명시합니다. `.artifacts`는 build-machine 입력 cache이며 repository에 commit하지 않습니다. nginx가 참조하는 비시스템 dylib는 package 내부 `nginx/lib`로 복사하고, nginx load path를 `@executable_path/../lib`로 바꿉니다.

## Control App

사용자용 진입점은 `.app`입니다. 제품 설치에서는 `.pkg`가 이 app을 `/Applications`에 설치합니다.

```sh
make vm-app
open ".tmp/VitalServer Helper.app"
```

App bundle은 가벼운 관리 UI만 포함합니다. Runtime package, rootfs, VM disk는 app Resources에 넣지 않습니다.

```text
VitalServer Helper.app
  Contents/MacOS/VitalServer Helper
  Contents/Info.plist
  Contents/Resources/AppIcon.icns
```

앱에서 제공하는 기능은 아래입니다.

| 기능 | 내부 동작 |
|---|---|
| Health Check | VM IP, guest HTTP, host proxy HTTP 확인 |
| Settings | `vitalserver-vm runtime configure ... --restart`로 VM/runtime/proxy/start-on-boot 설정 저장 |
| Apply Bundle | 선택한 offline update bundle을 `runtime apply-bundle`로 검증/적용 |
| Rollback | 최신 backup을 `runtime rollback`으로 복원 |
| Open VitalServer | `http://127.0.0.1/` 열기 |
| Uninstall | 설치된 `/usr/local/bin/tirosh-vitalserver-uninstall` 실행 |
| Clean Uninstall | 설치된 `/usr/local/bin/tirosh-vitalserver-uninstall --clean` 실행 |

Uninstall의 주 진입점은 Helper app입니다. Helper app을 열 수 없는 깨진 설치 상태에서는
`sudo /usr/local/bin/tirosh-vitalserver-uninstall`을 fallback으로 실행합니다. MDM/Jamf 배포에서도
같은 uninstaller를 root로 실행합니다.

기본 Uninstall은 Helper app, LaunchDaemon, runtime tools, VM disk, logs, package receipt를 제거하지만
`.vital` 파일 경로와 backups는 보존합니다. Clean Uninstall은 backups와 설정된 vital files directory까지
삭제합니다.

CPU는 VitalServer 내부 동작 조건 때문에 7 vCPU 이상만 허용하고, target Mac 운영 기본값은 8 vCPU입니다.

## 현재 범위

지원하는 launcher 명령:

```sh
vitalserver-vm init
vitalserver-vm start
vitalserver-vm stop
vitalserver-vm status
vitalserver-vm network shared
vitalserver-vm network bridged <interface>
vitalserver-vm interfaces
vitalserver-vm configure --cpu <count> --memory-mib <mib> --network shared
vitalserver-vm runtime install
vitalserver-vm runtime status
vitalserver-vm runtime health
vitalserver-vm runtime watchdog
vitalserver-vm runtime configure [--cpu <count>] [--memory-gib <gib>] [--network shared|bridged] [--bridged-interface <id>] [--proxy-port <port>] [--vital-files-dir <path>] [--public-host <host>] [--public-port <port>] [--admin-password-file <path>] [--start-on-boot true|false] [--restart]
vitalserver-vm runtime verify-bundle <bundle-dir>
vitalserver-vm runtime stage-bundle <bundle-dir>
vitalserver-vm runtime apply-bundle <bundle-dir>
vitalserver-vm runtime rollback [backup-dir]
vitalserver-vm clean
vitalserver-vm version
```

아직 제품 기능은 아닙니다.

- codesign/notarization 제품화
- VM image 업데이트

## 참고 문서

- [VitalServer VM Launcher 문서](../../docs/vitalserver-vm-launcher.md)
- [macOS host proxy ADR](../../docs/adr/0001-macos-host-proxy-for-vrecorder-ip.md)
