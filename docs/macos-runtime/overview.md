# macOS Runtime Overview

Mac mini/Mac Studio에서 VitalServer를 Linux VM 기반 runtime으로 운영하기 위한 문서군의 시작점입니다.

앱 README는 빠른 실행과 주요 시나리오를 다룹니다. 이 문서는 VM launcher 문서군 안에서 어떤 문서를 언제 보면 되는지, 실제 사용자가 접할 흐름이 어디에 대응되는지 정리합니다.

## 기본 구조

장기 제품 구조는 `Web/PWA Helper UI + Runtime Control API + platform-specific host runtime + Linux guest appliance`입니다.

```text
Web/PWA Helper UI
  -> RuntimeClient
      -> HttpRuntimeClient
          -> local Runtime Control API or remote VitalServer control server
              -> host-native Updater / Supervisor / VM Driver / Log collector
                  -> Linux guest Service Stack / VitalServer service
```

macOS/Windows native app은 장기적으로 product UI를 소유하지 않고, local runtime host/native shell 역할을 맡습니다. 설치, local service bootstrap, pairing URL/QR, recovery, native picker/dialog 같은 platform-specific 작업은 native shell과 host runtime component에 남깁니다. 자세한 경계는 [Architecture](architecture.md)와 [ADR 0002](../adr/0002-helper-client-boundary-for-local-and-remote-runtime.md)를 봅니다.

현재 v1 macOS runtime의 네트워크 구조는 아래와 같습니다.

```text
VRecorder / Browser
  -> target Mac LAN IP :80
      -> macOS host proxy
          -> Linux VM shared/NAT IP :80
              -> Docker Compose edge nginx
                  -> VitalServer
                  -> Redis
                  -> Redis UI
                  -> Swagger UI
```

v1 기본값은 `shared/NAT VM + macOS host proxy`입니다. 이 구조는 Docker Desktop/OrbStack류 VM NAT에서 원 IP가 바뀌는 문제를 피하기 위해 host proxy를 Mac에서 직접 실행합니다. bridged mode는 Apple restricted entitlement 승인이 필요한 향후 옵션입니다.

## Helper app 화면 지도

| 탭 | 역할 |
|---|---|
| Status | 사용자가 가장 먼저 보는 운영 상태. VitalServer URL, data directory, overall health, 핵심 service health 표시 |
| Settings | 일반 운영 설정. CPU, memory, disk 증가, shared/NAT network, vital files directory, start-on-boot |
| Update | Product Update bundle 검증/적용. air-gapped와 online update가 같은 bundle 계약을 사용 |
| Logs | Helper/install/command/VM/container log를 선택해서 확인 |
| About | Helper, Updater, Supervisor, VM Driver, Service Stack, VM Image, VitalServer version 같은 제품 정보 |
| Advanced | 네트워크 override, recovery operation, admin operation, 내부 진단 |
| Danger Zone | uninstall, clean uninstall, VM Image Update처럼 되돌리기 어려운 작업 |

## 사용자 시나리오 지도

| 시나리오 | 사용자가 보는 것 | 개발/운영자가 쓰는 것 | 세부 문서 |
|---|---|---|---|
| 신규 현장 설치 | `TiroshVitalServer-<version>.dmg` 안의 installer package | `make vm-dmg` 또는 `make vm-dmg-release` | [Packaging and Update](packaging.md) |
| 폐쇄망 Product Update | offline product update bundle tarball | `make vm-update-bundle`, Helper app Update 탭 | [Packaging and Update](packaging.md) |
| VM Image Update | offline VM image update bundle tarball | `make vm-rootfs-update-bundle`, Danger Zone | [Packaging and Update](packaging.md), [Update](update.md) |
| 온라인 업데이트 | 같은 update bundle 계약, download source만 온라인 | release hardening 대상 | [Packaging and Update](packaging.md) |
| 설치 후 상태 확인 | `/Applications/VitalServer Helper.app` Status 탭 | `make vm-installed-health`, `vitalserver-vm runtime health` | [Runtime](runtime.md), [Troubleshooting](troubleshooting.md) |
| 운영 설정 변경 | Helper app Settings/Advanced 탭 | `vitalserver-vm runtime configure ... --restart` | [Runtime](runtime.md) |
| 장애 대응 | Helper app Status/Logs/Advanced/Danger Zone, uninstaller | watchdog log, runtime status, troubleshooting guide | [Troubleshooting](troubleshooting.md) |
| 개발 VM PoC | package 없이 VM/proxy 직접 실행 | `make vm-up`, `make vm-health`, `make vm-down` | [Runtime](runtime.md) |
| 구조 판단/리뷰 | 왜 host proxy인지, 책임이 어디인지 | ADR, architecture 문서 | [Architecture](architecture.md), [ADR 0001](../adr/0001-macos-host-proxy-for-vrecorder-ip.md), [ADR 0002](../adr/0002-helper-client-boundary-for-local-and-remote-runtime.md), [ADR 0003](../adr/0003-helper-layer-and-component-version-model.md), [ADR 0004](../adr/0004-product-update-and-vm-image-update-contract.md) |

## 문서 지도

| 문서 | 먼저 볼 때 |
|---|---|
| [Architecture](architecture.md) | As-is/To-be 구조, shared/NAT + host proxy 선택 이유, 단일 노드 가용성, Web/PWA UI/native shell/host runtime 책임 경계를 볼 때 |
| [ADR 0002](../adr/0002-helper-client-boundary-for-local-and-remote-runtime.md) | Web/PWA Helper UI, macOS native shell, local/remote RuntimeClient boundary를 볼 때 |
| [ADR 0003](../adr/0003-helper-layer-and-component-version-model.md) | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, VM Image layer와 version model을 볼 때 |
| [ADR 0004](../adr/0004-product-update-and-vm-image-update-contract.md) | Product Update, VM Image Update, two-phase Product Update 계약을 볼 때 |
| [Packaging and Update](packaging.md) | `make vm-pkg`, `make vm-dmg`, update bundle, install settings, release artifact 흐름을 볼 때 |
| [Update](update.md) | bundle 적용 과정, 보존/변경되는 항목, guest-side activation, rollback 실패 조건을 볼 때 |
| [Runtime](runtime.md) | VM boot asset, cloud-init, guest bootstrap, data sharing, network mode, identity/signing 정책을 볼 때 |
| [Troubleshooting](troubleshooting.md) | 502, stale pid, cloud-init 재실행, disk full, package cleanup, bridged entitlement 문제를 볼 때 |

## 자주 쓰는 명령

### 제품 설치물 만들기

```sh
make vm-dmg
```

clean golden rootfs부터 다시 만들어 release 검증에 가깝게 빌드하려면:

```sh
make vm-dmg-release
```

### `.pkg`만 만들기

```sh
make vm-pkg
```

### update bundle 만들기

```sh
make vm-update-bundle
make vm-update-bundle-verify
```

생성 위치:

```text
dist/update-bundles/update-bundle-<version>.tar.gz
```

Product Update bundle은 Helper UI, Native Shell, Runtime Control API, Updater, Supervisor/VM Driver tools, host nginx bundle, Service Stack/guest deploy 같은 artifact를 `.tar.gz`로 묶습니다. 기본 `make vm-update-bundle`은 rootfs를 포함하지 않는 `product-update` bundle을 만듭니다. `guest-deploy` 변경은 기본 migration과 guest activation 경로를 통해 VM 내부에 반영됩니다. VM Image/rootfs 자체를 바꿔야 하는 경우에만 `make vm-rootfs-update-bundle`을 사용하며, 이 흐름은 Danger Zone의 `vm-image-update` 대상입니다. VM Image bundle도 기존 mutable `vm-disk.img`를 자동 교체하지 않습니다.

## 레이어와 버전 모델

`VitalServer Helper`는 최상위 product release입니다. 플랫폼별 native shell, Runtime Control API implementation, VM provider 구현은 같은 Helper release 아래의 variant로 취급하고, 실제 변경 범위는 component version으로 설명합니다. 각 layer는 platform 종속성과 책임이 다르므로 version label과 bundle manifest도 이 경계를 드러내야 합니다.

| Layer | Platform dependency | 책임 | Manifest key |
|---|---|---|---|
| VitalServer Helper | cross-platform product umbrella | 최상위 관리 제품/클라이언트 패키지, support/release note 기준 | `helperVersion` |
| Helper UI | cross-platform Web/PWA primary | iPhone/Android/iPad/desktop browser와 native shell wrapper에서 쓰는 product UI | `components.helperUI` |
| Native Shell | platform-specific | install/bootstrap/pairing/recovery/native picker/tray/menu | `components.nativeShell` |
| Runtime Control API | host/platform-specific implementation, common API contract | auth/session/pairing, capability, status/log/update/settings/admin endpoint, progress/log streaming | `components.runtimeControl` |
| Updater | host/platform-specific | product update bundle 검증/적용/rollback, manifest compatibility gate | `components.updater`, `minUpdaterVersion` |
| Supervisor | host/platform-aware | health/watchdog/recovery, service state loop, auto-recovery suppression | `components.supervisor` |
| VM Driver | platform-specific | macOS Apple Virtualization, Windows provider 등 VM lifecycle provider | `components.vmDriver` |
| Service Stack | mostly guest/service-specific | guest deploy assets, compose, container image bundle, service activation 단위 | `components.serviceStack` |
| VM Image | guest OS/image-specific | Linux guest OS/base rootfs/kernel/initrd class artifact | `components.vmImage` |
| VitalServer service | service-specific | VM 안에서 실행되는 VitalServer app/container | `components.vitalServer` |

Bundle manifest는 이 모델을 그대로 반영합니다. `helperVersion`은 최상위 release를 가리키고, `targetPlatforms`는 적용 가능한 platform variant를 제한하며, 하위 version은 `components` map에 기록합니다. 예를 들어 macOS 전용 VM Driver 변경은 `targetPlatforms: ["macos-arm64"]`와 `components.vmDriver`로 표현하고, Service Stack 변경은 platform과 독립적인 `components.serviceStack`으로 표현합니다.

Platform별 runtime 구현은 같은 Runtime Control API contract 뒤에 숨깁니다.

| Layer | macOS | Windows | 공통 계약 |
|---|---|---|---|
| Native shell | menu bar app, pkg/recovery, native panels | tray app, installer/recovery, native dialogs | bootstrap, pairing, recovery entrypoint |
| Runtime Control API | local macOS service | local Windows service | HTTP/SSE API, auth/session, capability, result/reason model |
| Updater | macOS file/service/update flow | Windows file/service/update flow | ADR 0004 manifest/update contract |
| Supervisor | launchd/process/network health | Windows Service/process/network health | health/status/recovery model |
| VM Driver | Apple Virtualization provider | Hyper-V, WSL2, VirtualBox 등 별도 provider | VM lifecycle capability model |
| Service Stack | Linux guest compose/container assets | Linux guest compose/container assets | guest activation and service stack contract |

Update bundle kind는 의도적으로 두 개만 둡니다.

| bundleKind | UI 위치 | 포함 범위 |
|---|---|---|
| `product-update` | Update 탭 | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, 개별 service/container, host proxy, migrations |
| `vm-image-update` | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifact |

Hotfix, service-only update, updater bridge update는 별도 bundle kind를 만들지 않고 `product-update`의 channel, changed components, `requiresTwoPhaseUpdate` 같은 metadata로 표현합니다.

### 개발용 설치 테스트

```sh
make vm-pkg-install
make vm-installed-health
make vm-pkg-uninstall-dev
```

### package 없이 VM 직접 실행

```sh
make vm-up
make vm-health
make vm-down
```

## 산출물 기준

| 산출물 | 위치 | 용도 |
|---|---|---|
| DMG | `dist/TiroshVitalServer-<version>.dmg` | 현장 전달용 설치 매체 |
| PKG | `dist/TiroshVitalServerVM-<version>.pkg` | 실제 macOS Installer payload |
| Product Update bundle | `dist/update-bundles/update-bundle-<version>.tar.gz` | 설치 후 offline/online Product Update 입력 |
| Helper app | `.tmp/VitalServer Helper.app` 또는 `/Applications/VitalServer Helper.app` | 설치 후 운영 UI |
| Golden rootfs | `.tmp/vitalserver-vm-pkg/rootfs-base.raw.gz` | air-gapped 설치용 immutable rootfs base |
| Docker image bundle | `.tmp/vitalserver-vm-pkg/docker-images/vitalserver-images.tar.gz` | guest가 registry 없이 container를 시작하기 위한 image bundle |

## 책임 분리

| 영역 | 주 담당 | 핵심 책임 |
|---|---|---|
| Make | `make/vm/*.mk` | target dependency, 산출물 경로, 개발용 실행/설치 wrapper |
| Build | Python `packages/vm-build` | Ubuntu asset, cloud-init, rootfs, nginx bundle, Docker image bundle, update bundle |
| Updater | Swift `vitalserver-vm` | bundle verify/apply/rollback, manifest compatibility, migration, guest activation 조율 |
| Supervisor | Swift `vitalserver-vm` | health/watchdog/recovery, service state 판단 |
| VM Driver | Swift `vitalserver-vm` | platform-specific VM lifecycle/provider layer |
| Helper UI | Web/PWA primary, SwiftUI during transition | 사용자가 보는 Status/Settings/Update/Logs/About/Advanced/Danger Zone UI |
| Runtime Control API | host-native service | Web/PWA와 native shell이 사용하는 local/remote control boundary |
| Native shell | macOS app / future Windows shell | install, local runtime bootstrap, pairing, recovery, native picker/dialog |
| Installer/launchd | Shell wrapper | `postinstall`, `proxy-run`, uninstall entrypoint 연결 |
| Guest | Shell + Compose | Linux guest Docker Compose stack, edge nginx container, VM runtime state 기록 |

## 읽는 순서

처음 보는 개발자는 아래 순서로 읽는 것을 권장합니다.

1. [앱 README](../../apps/vitalserver-macos-runtime/README.md)
2. [Architecture](architecture.md)
3. [Packaging and Update](packaging.md)
4. [Runtime](runtime.md)
5. [Troubleshooting](troubleshooting.md)
