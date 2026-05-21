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

## 사용자 시나리오 지도

| 시나리오 | 사용자가 보는 것 | 개발/운영자가 쓰는 것 | 세부 문서 |
|---|---|---|---|
| 신규 현장 설치 | `TiroshVitalServer-<version>.dmg` 안의 installer package | `make vm-dmg` 또는 `make vm-dmg-release` | [Packaging and Update](packaging.md) |
| 폐쇄망 현장 업데이트 | offline update bundle directory | `make vm-update-bundle`, Helper app Update 탭 | [Packaging and Update](packaging.md) |
| 온라인 업데이트 | 같은 update bundle 계약, download source만 온라인 | release hardening 대상 | [Packaging and Update](packaging.md) |
| 설치 후 상태 확인 | `/Applications/VitalServer Helper.app` Status 탭 | `make vm-installed-health`, `vitalserver-vm runtime health` | [Runtime](runtime.md), [Troubleshooting](troubleshooting.md) |
| 운영 설정 변경 | Helper app Settings/Advanced 탭 | `vitalserver-vm runtime configure ... --restart` | [Runtime](runtime.md) |
| 장애 대응 | Helper app Health/Log/Advanced, uninstaller | watchdog log, runtime status, troubleshooting guide | [Troubleshooting](troubleshooting.md) |
| 개발 VM PoC | package 없이 VM/proxy 직접 실행 | `make vm-up`, `make vm-health`, `make vm-down` | [Runtime](runtime.md) |
| 구조 판단/리뷰 | 왜 host proxy인지, 책임이 어디인지 | ADR, architecture 문서 | [Architecture](architecture.md), [ADR 0001](../adr/0001-macos-host-proxy-for-vrecorder-ip.md) |

## 문서 지도

| 문서 | 먼저 볼 때 |
|---|---|
| [Architecture](architecture.md) | shared/NAT + host proxy 선택 이유, 단일 노드 가용성, build/runtime/GUI 책임 경계를 볼 때 |
| [Packaging and Update](packaging.md) | `make vm-pkg`, `make vm-dmg`, update bundle, install settings, release artifact 흐름을 볼 때 |
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

일반 update bundle은 Helper app, runtime tools, host nginx bundle, guest deploy bundle 같은 작은 artifact를 `.tar.gz`로 묶습니다. `rootfs-base.raw.gz`나 Docker image bundle은 크기가 크므로 base OS/package 또는 container image 갱신이 있을 때만 포함하는 방향입니다.

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
| Manager UI | Swift `VitalServer Helper.app` | 사용자가 보는 status/settings/update/advanced/log UI |
| Installer/launchd | Shell wrapper | `postinstall`, `proxy-run`, uninstall entrypoint 연결 |
| Guest | Shell + Compose | Linux guest Docker Compose stack, edge nginx container, VM runtime state 기록 |

## 읽는 순서

처음 보는 개발자는 아래 순서로 읽는 것을 권장합니다.

1. [앱 README](../../apps/vitalserver-vm-launcher/README.md)
2. [Architecture](architecture.md)
3. [Packaging and Update](packaging.md)
4. [Runtime](runtime.md)
5. [Troubleshooting](troubleshooting.md)
