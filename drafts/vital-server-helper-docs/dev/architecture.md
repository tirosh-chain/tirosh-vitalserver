# Architecture

Vital Server Helper는 host platform과 service appliance를 분리합니다.

Mac hardware appliance는 1차 현장 배포 target입니다. Linux VM은 macOS/Linux/Windows
host 어디서든 동일한 Vital Server Helper service appliance를 실행하기 위한 guest
표준화 계층입니다. PWA는 host별 native UI 중복을 피하고 같은 Runtime Control UI를
제공하기 위한 primary UI입니다.

## 핵심 구조

```text
Browser / PWA / Native shell
  -> Runtime Control API
      -> Host runtime adapter
          -> VM provider
              -> Linux guest service stack
                  -> VitalServer wrapper
                  -> Redis
                  -> Recorder Ingress
                  -> VitalDB Observer
                  -> Testkit API
```

## Linux VM 선택 이유

Linux VM은 host OS를 Linux로 한정하기 위한 선택이 아닙니다.

Linux VM은 macOS/Linux/Windows 어디서든 동일한 Vital Server Helper service appliance를
실행하기 위한 guest 표준화 계층입니다. upstream VitalServer의 Windows 중심 전제는
wrapper와 guest service stack에서 흡수하고, host별 차이는 VM provider adapter가
처리합니다.

## Upstream compatibility evidence

upstream VitalServer는 Linux native compatible이라고 보기 어렵습니다.

| 근거 | 의미 |
|---|---|
| `vendor/vitalserver/vitalserver-old/server_start.bat` | upstream 실행 스크립트가 Windows batch 기준 |
| `vendor/vitalserver/vitalserver-old/install/*.msi` | Node와 Redis 설치물이 Windows MSI 기준 |
| `vendor/vitalserver/vitalserver-old/service/include/config.js` | 기본 저장 경로가 `Z:/` drive 기준 |
| `apps/vitalserver/docker/Dockerfile` | Linux container 안에 `Z:` symlink를 만들어 upstream path 전제를 흡수 |
| `apps/vitalserver/runtime/node-preload.js` | Redis host/port, CPU-count assumption, admin password 같은 runtime 전제를 보정 |

따라서 Linux VM은 upstream이 Linux 친화적이라서 선택된 것이 아닙니다. Windows-oriented
upstream을 제품용 Linux guest service stack으로 정규화하고, 그 guest를 여러 host
platform에서 동일하게 운영하기 위한 선택입니다.

## Linux guest strength

Linux guest는 Vital Server Helper backend service stack을 고정하기 좋은 runtime substrate입니다.

| 강점 | 설명 |
|---|---|
| backend service appliance 운영체제 | desktop OS가 아니라 VitalServer backend stack을 고정하는 guest runtime으로 사용 |
| container/service 생태계 | Docker/Compose, nginx, Redis, Node service, sidecar, observer, testkit을 같은 guest 기준으로 묶기 쉬움 |
| headless service 운영 | systemd, journald, timer, log collection, file permission, mount, network namespace 같은 운영 모델이 명확함 |
| image/update 재현성 | golden rootfs, cloud-init, Docker image bundle, offline update bundle과 잘 맞음 |
| upstream 보정 단일화 | Windows path, Windows installer, Redis host, CPU-count assumption을 각 host별로 고치지 않고 guest wrapper/preload에서 흡수 |

## Host platform strengths

Host platform은 VM provider, 설치, 권한, proxy, update entrypoint를 담당합니다.

| Host | 강점 | Runtime 책임 |
|---|---|---|
| macOS | Mac hardware appliance 운영, DMG/PKG, launchd, Apple Virtualization, local Helper app, code signing/notarization | VM lifecycle, host proxy, permission, file picker, update/recovery entrypoint |
| Linux | KVM/QEMU/libvirt, server-friendly networking, systemd, container runtime 접근성 | VM lifecycle, network bridge/NAT, service manager integration, filesystem sharing |
| Windows | 병원/기업 IT의 AD/GPO/Intune/SCCM 친화성, Windows Service, Hyper-V, firewall/endpoint security 정책 연동 | VM lifecycle, Windows Service, firewall/NAT, enterprise management integration |

Host별 VM provider 특성은 다릅니다. guest service stack과 Health Check contract는 같게
유지하고, lifecycle/network/filesystem/permission 차이는 host adapter가 흡수합니다.

## PWA 선택 이유

PWA는 제품 UI를 host OS에 묶지 않기 위한 선택입니다.

| 이유 | 설명 |
|---|---|
| cross-platform 운영 UI | macOS/Linux/Windows host마다 native UI를 중복 구현하지 않고 같은 Runtime Control UI를 제공 |
| local/remote control 통합 | local runtime control과 병원 outbound 허용 시 remote/cloud control을 같은 API contract 뒤에 둠 |
| 현장 접근성 | Mac 앞이 아니라 병원 내부 PC, tablet, phone browser에서도 상태와 로그를 확인 |
| native shell 책임 축소 | native shell은 설치, 권한, tray/menu, file picker, recovery 같은 host-specific 기능만 담당 |

## Source of truth

Runtime 상태와 VitalDB observation은 guest와 host가 명시적으로 생산한 문서를 통해 전달됩니다.

```text
vitaldb-observer
  -> guest runtime-state.json
  -> watchdog/runtime
  -> runtime-status.json
  -> runtime-events.jsonl
  -> runtime-observability.sqlite
  -> Runtime Control API / PWA
```

Log, filename, missing file, old command output에서 domain state를 추측하지 않습니다.
