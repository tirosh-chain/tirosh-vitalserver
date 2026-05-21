# VM Launcher Overview

Mac mini/Mac Studio에서 VitalServer를 Linux VM 기반 runtime으로 운영하기 위한 문서군의 시작점입니다.

앱 README는 빠른 실행과 주요 시나리오를 다룹니다. 이 문서는 VM launcher 문서군 안에서 어떤 문서를 언제 보면 되는지, 실제 사용자가 접할 흐름이 어디에 대응되는지 정리합니다.

## 기본 구조

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
| Update | 현장 update bundle 검증/적용. air-gapped와 online update가 같은 bundle 계약을 사용 |
| Logs | Helper/install/command/VM/container log를 선택해서 확인 |
| About | Helper, VitalServer, container image, runtime version 같은 제품 정보 |
| Advanced | 네트워크 override, recovery operation, admin operation, 내부 진단 |
| Danger Zone | uninstall, clean uninstall, 향후 VM/rootfs 교체처럼 되돌리기 어려운 작업 |

## 사용자 시나리오 지도

| 시나리오 | 사용자가 보는 것 | 개발/운영자가 쓰는 것 | 세부 문서 |
|---|---|---|---|
| 신규 현장 설치 | `TiroshVitalServer-<version>.dmg` 안의 installer package | `make vm-dmg` 또는 `make vm-dmg-release` | [Packaging and Update](packaging.md) |
| 폐쇄망 현장 업데이트 | offline update bundle directory | `make vm-update-bundle`, Helper app Update 탭 | [Packaging and Update](packaging.md) |
| 온라인 업데이트 | 같은 update bundle 계약, download source만 온라인 | release hardening 대상 | [Packaging and Update](packaging.md) |
| 설치 후 상태 확인 | `/Applications/VitalServer Helper.app` Status 탭 | `make vm-installed-health`, `vitalserver-vm runtime health` | [Runtime](runtime.md), [Troubleshooting](troubleshooting.md) |
| 운영 설정 변경 | Helper app Settings/Advanced 탭 | `vitalserver-vm runtime configure ... --restart` | [Runtime](runtime.md) |
| 장애 대응 | Helper app Status/Logs/Advanced/Danger Zone, uninstaller | watchdog log, runtime status, troubleshooting guide | [Troubleshooting](troubleshooting.md) |
| 개발 VM PoC | package 없이 VM/proxy 직접 실행 | `make vm-up`, `make vm-health`, `make vm-down` | [Runtime](runtime.md) |
| 구조 판단/리뷰 | 왜 host proxy인지, 책임이 어디인지 | ADR, architecture 문서 | [Architecture](architecture.md), [ADR 0001](../adr/0001-macos-host-proxy-for-vrecorder-ip.md) |

## 문서 지도

| 문서 | 먼저 볼 때 |
|---|---|
| [Architecture](architecture.md) | shared/NAT + host proxy 선택 이유, 단일 노드 가용성, build/runtime/GUI 책임 경계를 볼 때 |
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
dist/update-bundles/update-bundle-<version>/
```

일반 update bundle은 Helper app, runtime tools, host nginx bundle, guest deploy bundle 같은 작은 artifact를 `.tar.gz`로 묶습니다. 현재 기본 target은 호환성을 위해 `rootfs-base.raw.gz`도 함께 만들 수 있지만, 이미 설치된 현장의 mutable `vm-disk.img`를 자동 교체하지는 않습니다. Docker image bundle과 rootfs base는 base OS/package 또는 container image 갱신이 있을 때만 의미가 큽니다.

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
| Update bundle | `dist/update-bundles/update-bundle-<version>/` | 설치 후 offline/online 업데이트 입력 |
| Helper app | `.tmp/VitalServer Helper.app` 또는 `/Applications/VitalServer Helper.app` | 설치 후 운영 UI |
| Golden rootfs | `.tmp/vitalserver-vm-pkg/rootfs-base.raw.gz` | air-gapped 설치용 immutable rootfs base |
| Docker image bundle | `.tmp/vitalserver-vm-pkg/docker-images/vitalserver-images.tar.gz` | guest가 registry 없이 container를 시작하기 위한 image bundle |

## 책임 분리

| 영역 | 주 담당 | 핵심 책임 |
|---|---|---|
| Make | `make/vm/*.mk` | target dependency, 산출물 경로, 개발용 실행/설치 wrapper |
| Build | Python `packages/vm-build` | Ubuntu asset, cloud-init, rootfs, nginx bundle, Docker image bundle, update bundle |
| Runtime | Swift `vitalserver-vm` | VM lifecycle, install, health, configure, update, rollback, watchdog |
| Helper UI | Swift `VitalServer Helper.app` | 사용자가 보는 Status/Settings/Update/Logs/About/Advanced/Danger Zone UI |
| Installer/launchd | Shell wrapper | `postinstall`, `proxy-run`, uninstall entrypoint 연결 |
| Guest | Shell + Compose | Linux guest Docker Compose stack, edge nginx container, VM runtime state 기록 |

## 읽는 순서

처음 보는 개발자는 아래 순서로 읽는 것을 권장합니다.

1. [앱 README](../../apps/vitalserver-vm-launcher/README.md)
2. [Architecture](architecture.md)
3. [Packaging and Update](packaging.md)
4. [Runtime](runtime.md)
5. [Troubleshooting](troubleshooting.md)
