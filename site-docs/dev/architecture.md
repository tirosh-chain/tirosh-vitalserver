# Architecture

Vital Server Helper는 host platform과 service appliance를 분리합니다.

이 구조는 병원 내부망 가까이에 놓인 작은 운영 장비를 전제로 합니다. 이 장비는
사용자가 매일 직접 관리하지 않아도 장기간 켜져 있어야 하고, 문제가 생겼을 때
상태와 로그를 확인할 수 있어야 합니다.

Mac hardware appliance는 공개 release의 1차 현장 배포 target입니다. Linux VM은
macOS/Linux/Windows host 어디서든 동일한 Vital Server Helper service appliance를
실행하기 위한 architecture direction입니다. PWA는 host별 native UI 중복을 피하고
같은 Runtime Control UI를 제공하기 위한 운영 UI입니다.

## Operating Assumptions

| 운영 조건 | 구조적 대응 |
|---|---|
| 병원 내부망 가까이에서 동작해야 함 | local host runtime과 guest service stack을 기본 경로로 둠 |
| Recorder 접속 상태를 운영자가 확인해야 함 | observer와 audit proxy가 Recorder activity를 관측 |
| 장애 조사 자료를 모을 수 있어야 함 | status, event history, logs, read model을 분리 |
| update가 네트워크 접근에만 의존하면 안 됨 | offline update bundle과 verify/apply 흐름을 둠 |
| host OS별 UI 중복을 줄여야 함 | PWA와 Runtime Control API를 분리 |

## System Overview

```text
Browser / PWA / Native shell
  -> Runtime Control API
      -> Host runtime adapter
          -> VM provider
              -> Linux guest service stack
                  -> Vital Server wrapper
                  -> Redis
                  -> Audit Proxy
                  -> VitalDB Observer
                  -> Testkit API
```

## Linux VM 선택 이유

Linux VM은 host OS를 Linux로 한정하기 위한 선택이 아닙니다.

Linux VM은 macOS/Linux/Windows 어디서든 동일한 Vital Server Helper service appliance를
실행하기 위한 guest 표준화 계층입니다. Vital Server integration은 guest service
stack의 명시 contract 뒤에 두고, host별 차이는 VM provider adapter가 처리합니다.

## Vital Server Integration Inputs

Vital Server Helper는 Vital Server가 제공하는 연구와 데이터 수집 기능을 전제로,
현장 appliance 운영에 필요한 runtime 입력을 명시 contract로 연결합니다.

| 입력 | 의미 |
|---|---|
| launch entrypoint | service 시작 방식을 guest runtime에서 일관되게 실행 |
| runtime dependencies | Node, Redis, proxy, sidecar dependency를 guest 기준으로 묶음 |
| storage path | `.vital` 저장 위치를 host/guest contract로 명시 |
| container wrapper | guest 안에서 Vital Server integration surface를 고정 |
| runtime preload | Redis host/port, CPU-count, admin password 같은 runtime 입력을 명시화 |

따라서 Linux VM은 Vital Server의 목적이나 구현 방향에 대한 판단이 아닙니다. 병원
현장 appliance에서 같은 운영 표면을 제공하기 위한 integration boundary입니다.

## Linux guest strength

Linux guest는 Vital Server Helper backend service stack을 고정하기 좋은 runtime substrate입니다.

| 강점 | 설명 |
|---|---|
| backend service appliance 운영체제 | desktop OS가 아니라 Vital Server backend stack을 고정하는 guest runtime으로 사용 |
| container/service 생태계 | Docker/Compose, nginx, Redis, Node service, sidecar, observer, testkit을 같은 guest 기준으로 묶기 쉬움 |
| headless service 운영 | systemd, journald, timer, log collection, file permission, mount, network namespace 같은 운영 모델이 명확함 |
| image/update 재현성 | golden rootfs, cloud-init, Docker image bundle, offline update bundle과 잘 맞음 |
| integration input 명시화 | storage path, Redis host, CPU-count, credential input을 host별 추측 없이 guest wrapper/preload에서 명시 |

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

## Layer Boundaries

Runtime control flow는 상태 소유자와 판단 책임을 분리합니다.

| Layer | 책임 |
|---|---|
| Contracts | state, event, command, document type을 정의하고 실패/부재/오래됨/빈 값의 의미를 보존 |
| Domain/Core | complete explicit input만 받아 policy, guard, invariant, state transition을 순수하게 계산 |
| Application/Usecase | stateless decision layer. explicit state와 port result를 받아 Domain/Core를 호출하고 command/effect/event를 결정 |
| Workflow | stateful orchestration layer. Usecase 호출 순서, wait/retry loop, progress, persisted workflow status를 관리 |
| Adapters | inbound/outbound boundary에서 decode, format, filesystem, process, network, repository effect를 수행 |
| Bootstrap | concrete dependency graph, constants, path composition만 조립 |
| Hosts | process/environment/filesystem boundary와 host-owned effect closure를 연결 |

Usecase는 class나 hidden state로 operation state를 소유하지 않습니다. Workflow는 operation
state와 진행률을 관리할 수 있지만, domain 판단을 직접 수행하거나 Host effect를 직접 실행하지
않습니다. Bootstrap은 실행 경계가 아니라 조립 경계입니다.
