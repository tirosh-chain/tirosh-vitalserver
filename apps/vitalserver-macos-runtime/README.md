# VitalServer Helper

`apps/vitalserver-macos-runtime`는 Mac mini/Mac Studio에 VitalServer 전용 runtime을 설치하고 운영하기 위한 macOS app, Swift runtime orchestrator, guest VM asset, packaging 도구를 담고 있습니다.

제품 사용자는 `/Applications/VitalServer Helper.app`을 통해 상태 확인, 설정 변경, offline update bundle 적용, 로그 조회, rollback, uninstall을 수행합니다. 개발자는 아래 Make target으로 설치물과 update bundle을 만듭니다.

```text
Browser / VRecorder
  -> target Mac LAN IP :80
      -> macOS host proxy
          -> Linux VM shared/NAT IP :80
              -> Docker Compose
                  - VitalServer
                  - Redis
                  - Redis UI
                  - Swagger UI
```

기본 네트워크 구조는 `shared/NAT VM + macOS host proxy`입니다. bridged mode는 Apple restricted entitlement 승인이 필요한 향후 옵션이며, 현재 사용자 UI에서는 선택하지 않습니다.

## Helper app 탭

| 탭 | 사용 목적 |
|---|---|
| Status | VitalServer URL, data directory, 전체 health와 주요 서비스 상태 확인 |
| Settings | CPU, memory, disk 증가, shared/NAT network, vital files directory, start-on-boot 같은 운영 설정 |
| Update | offline/online 공통 update bundle 검증과 적용 |
| Logs | Helper, install, command, VM/container log를 필터링해 확인 |
| About | Helper, Updater, Supervisor, VM Driver, Service Stack, VM Image, VitalServer version 확인 |
| Advanced | 네트워크 override, service diagnostics, admin password reset, recovery operation |
| Danger Zone | uninstall, clean uninstall, VM Image Update처럼 파괴적인 작업 |

## 먼저 볼 것

| 상황 | 실행/확인 |
|---|---|
| 제품 설치 파일을 만들고 싶다 | `make vm-dmg` |
| `.pkg`만 만들고 싶다 | `make vm-pkg` |
| air-gapped 현장 업데이트 bundle을 만들고 싶다 | `make vm-update-bundle` |
| 만든 update bundle을 검증하고 싶다 | `make vm-update-bundle-verify` |
| 개발용 package를 현재 Mac에 설치해 보고 싶다 | `make vm-pkg-install` |
| 설치된 runtime 상태를 확인하고 싶다 | `make vm-installed-health` |
| 개발용 설치물을 지우고 싶다 | `make vm-pkg-uninstall-dev` |
| VM을 직접 띄워 PoC를 확인하고 싶다 | `make vm-up` |

세부 문서는 [macOS Runtime Overview](../../docs/macos-runtime/overview.md)를 진입점으로 봅니다.

## 사용자 시나리오

### 1. 신규 현장에 설치 파일 제공

완전한 air-gapped 설치물을 만들려면 DMG를 생성합니다.

```sh
make vm-dmg
```

생성물:

```text
dist/TiroshVitalServer-<version>.dmg
```

DMG 안에는 단일 installer package가 들어갑니다.

```text
Install Tirosh VitalServer.pkg
```

이 package는 Helper app, Swift runtime CLI, host proxy, Linux VM runtime asset, golden rootfs, Docker image bundle, LaunchDaemon을 설치합니다. target Mac은 설치 시점에 인터넷이 없어도 됩니다.

package에 들어가는 golden rootfs base는 설치 파일 효율을 위해 기본 4 GiB로 만듭니다. 실제 설치된 VM disk는 wizard 기본값 32 GiB로 확장되며, 설치 후에는 증가만 허용합니다.

반복 개발 중에는 cache를 재사용합니다. release 검증처럼 clean golden rootfs부터 다시 만들려면:

```sh
make vm-dmg-release
```

### 2. 이미 설치된 현장에 offline update bundle 제공

업데이트 입력 단위는 bundle tarball입니다.

```sh
make vm-update-bundle
make vm-update-bundle-verify
```

기본 `vm-update-bundle`은 `product-update`용입니다. Helper UI, Updater/Supervisor/VM Driver tools,
host nginx bundle, Service Stack/guest deploy bundle, migrations만 포함하고 `rootfs-base.raw.gz`는
포함하지 않습니다.

VM Image/rootfs 자체를 교체해야 하는 드문 업데이트는 별도 target을 사용합니다. 이 흐름은 `vm-image-update`이며 Danger Zone 대상입니다.

```sh
make vm-rootfs-update-bundle
make vm-update-bundle-verify
```

생성 위치:

```text
dist/update-bundles/update-bundle-<version>.tar.gz
```

현장에서는 Helper app의 Update 탭에서 bundle tarball을 선택하거나, CLI로 검증/적용합니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle-<version>.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle-<version>.tar.gz
```

`apply-bundle`은 mutable `vm-disk.img`를 보존하고 replaceable artifact만 교체합니다. 적용 전 backup을 만들고 health check 실패 시 rollback합니다.

update bundle 생성 시에도 artifact 압축은 필요합니다. 기본 Product Update bundle은 Helper UI, Updater/Supervisor/VM Driver tools, host nginx bundle, Service Stack/guest deploy bundle을 각각 `.tar.gz`로 묶습니다. 이 압축은 rootfs 전체를 매번 다시 만드는 것보다 훨씬 가볍고, 기본 bundle에는 rootfs를 넣지 않습니다.

`rootfs-base.raw.gz`는 신규 설치나 VM Image 변경용 artifact입니다. 일반 Product Update의 핵심은 `app-bundle`, `runtime-tools`, `nginx-bundle`, `guest-deploy`, 기본 migration입니다. rootfs 변경이 필요한 경우에만 `make vm-rootfs-update-bundle`을 사용합니다.

`guest-deploy`에 들어간 `bootstrap.sh`, compose, guest systemd, Docker image bundle 수정은 update bundle에 포함됩니다. 적용 시 기본 migration이 cloud-init seed를 갱신하고, 새 runtime은 guest activation request를 통해 VM 내부에서 Docker image load와 compose recreate를 수행합니다.

### 3. 개발 Mac에 package 설치 테스트

```sh
make vm-pkg
make vm-pkg-install
make vm-installed-health
```

설치 후 `/Applications/VitalServer Helper.app`을 열어 상태를 확인합니다. VitalServer 접속 URL은 Helper app Status 탭의 `VitalServer URL`을 사용합니다.

개발용 설치물을 지울 때:

```sh
make vm-pkg-uninstall-dev
```

Helper app이 열리지 않는 깨진 설치 상태에서는 아래 fallback을 사용합니다.

```sh
sudo /usr/local/bin/tirosh-vitalserver-uninstall
```

### 4. VM과 proxy를 빠르게 PoC로 확인

package 설치 없이 개발 VM을 직접 띄웁니다.

```sh
make vm-up
make vm-health
make vm-down
```

`make vm-up`은 Linux boot asset 준비, cloud-init 생성, guest deploy bundle staging, VM background start, VM IP 대기, host proxy 연결까지 수행합니다.

VM 콘솔을 직접 보고 싶으면:

```sh
make vm-prepare
make vm-start
```

### 5. 패키징 시간이 너무 오래 걸릴 때

rootfs gzip 압축은 시간이 오래 걸릴 수 있습니다. build machine에 `pigz`가 있으면 병렬 gzip을 사용합니다.

```sh
command -v pigz
brew install pigz
VM_COMPRESSION_THREADS=8 make vm-pkg
```

`pigz`는 build machine 전용 optional accelerator입니다. 최종 `.pkg`, `.dmg`, air-gapped target Mac에는 필요하지 않습니다. `pigz`가 없으면 Python gzip fallback을 사용합니다.

## 버전 관리

VitalServer Helper product/component 버전은 아래 파일을 기준으로 관리합니다.

```text
apps/vitalserver-macos-runtime/release.json
```

`VitalServer Helper`는 최상위 product release입니다. 플랫폼별 UI/VM provider 구현은 같은 Helper release 아래의 variant로 보고, 세부 변경 범위는 Helper UI, Updater, Supervisor, VM Driver, Service Stack, VM Image, VitalServer component version으로 설명합니다.

Update bundle manifest는 `helperVersion`, `targetPlatforms`, `minUpdaterVersion`, `components`를 기준으로 해석합니다. `components` map은 `helperUI`, `updater`, `supervisor`, `vmDriver`, `serviceStack`, `vmImage`, `vitalServer`처럼 실제 변경된 계층을 드러냅니다. Helper UI와 VM Driver는 platform-specific이고, Updater/Supervisor는 host platform에 붙어 있으며, Service Stack과 VM Image는 guest/service 쪽 책임으로 구분합니다.

`make vm-build`, `make vm-pkg`, `make vm-update-bundle`은 이 값을 읽어 app bundle version, package version, update bundle version, update compatibility, bundled service version 표시에 반영합니다. 버전을 올릴 때는 이 파일을 수정합니다.

## 주요 명령

| 명령 | 용도 |
|---|---|
| `make vm-app` | Helper app bundle 생성 |
| `make vm-pkg` | 개발 검증용 `.pkg` 생성 |
| `make vm-dmg` | 전달용 `.dmg` 생성 |
| `make vm-pkg-release` | clean golden rootfs로 `.pkg` 재생성 |
| `make vm-dmg-release` | clean golden rootfs로 `.dmg` 재생성 |
| `make vm-update-bundle` | offline/online 공통 Product Update bundle 생성 |
| `make vm-rootfs-update-bundle` | rootfs-base까지 포함하는 VM Image Update bundle 생성 |
| `make vm-update-bundle-verify` | update bundle checksum/manifest 검증 |
| `make vm-pkg-install` | 현재 Mac에 개발용 package 설치 |
| `make vm-installed-health` | 설치된 launchd VM/proxy 상태 확인 |
| `make vm-pkg-uninstall-dev` | 개발용 설치물 제거 |
| `make vm-up` | 개발 VM start + host proxy 연결 |
| `make vm-health` | 개발 VM health 확인 |
| `make vm-down` | 개발 VM 종료 |

## 설치되는 항목

| 항목 | 위치 |
|---|---|
| Helper app | `/Applications/VitalServer Helper.app` |
| runtime CLI | `/usr/local/bin/vitalserver-vm` |
| host proxy runner | `/usr/local/bin/vitalserver-proxy-run` |
| uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| runtime home | `/Library/Application Support/TiroshVitalServer/` |
| status file | `/Library/Application Support/TiroshVitalServer/status/runtime-status.json` |
| logs | `/Library/Application Support/TiroshVitalServer/logs/` |
| LaunchDaemons | `/Library/LaunchDaemons/com.tirosh.vitalserver-*.plist` |

## 책임 경계

| 영역 | 책임 |
|---|---|
| `apps/vitalserver-macos-runtime` | macOS runtime distribution. Helper app, runtime CLI, packaging, guest asset을 같은 release 단위로 묶음 |
| Make | target orchestration, artifact path, developer wrapper |
| Python `packages/vm-build` | Ubuntu asset, golden rootfs, nginx bundle, Docker image bundle, update bundle 생성/검증 |
| Swift `HostCLI` | VM lifecycle, runtime install/configure/health/watchdog/update/rollback |
| Swift `RuntimeControl` | Helper UI가 보는 runtime usecase 입출력 계약 |
| Swift `Contracts` | PWA/API/server/host runtime이 공유할 status/progress/update/guest JSON 계약 |
| Swift `MacHostRuntimeAdapter` | `RuntimeControl`의 macOS local file/process/CLI 구현 |
| Swift `MacRuntimeControlApp` | Helper app UI, presentation, native shell, composition |
| Packaging shell | `postinstall`, `proxy-run`, uninstall entrypoint |
| Guest support | cloud-init 이후 Docker Compose bootstrap, guest state 기록, diagnostics |

## 문서

| 문서 | 볼 때 |
|---|---|
| [macOS Runtime Overview](../../docs/macos-runtime/overview.md) | 문서군 전체 지도와 시나리오 |
| [Architecture](../../docs/macos-runtime/architecture.md) | As-is/To-be 구조와 책임 경계 |
| [Packaging and Update](../../docs/macos-runtime/packaging.md) | PKG/DMG/update bundle 계약 |
| [Runtime](../../docs/macos-runtime/runtime.md) | VM boot, cloud-init, guest bootstrap, network/identity |
| [Troubleshooting](../../docs/macos-runtime/troubleshooting.md) | 502, stale pid, disk full, install cleanup 등 |
| [macOS host proxy ADR](../../docs/adr/0001-macos-host-proxy-for-vrecorder-ip.md) | host proxy가 필요한 이유 |
