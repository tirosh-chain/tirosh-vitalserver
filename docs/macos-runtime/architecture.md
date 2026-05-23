# VitalServer macOS Runtime Architecture

제품 구조와 책임 경계를 정리합니다. shared/NAT + host nginx를 v1 기본값으로 두는 이유, 단일 노드에서 보장할 수 있는 범위, Web/PWA UI, native shell, package, host runtime의 책임을 다룹니다.

## 이 문서에서 바로 알아야 할 것

| 질문 | 답 |
|---|---|
| v1 기본 네트워크는? | `shared/NAT VM + macOS host nginx` |
| VRecorder는 어디로 붙나? | target Mac의 LAN IP `:80` |
| VM이 병원 LAN IP를 직접 받아야 하나? | v1에서는 아니다. host nginx가 public edge다. |
| 원 IP 보존은 어떻게 하나? | host nginx가 Docker/VM NAT 앞에서 `X-Forwarded-*`를 재작성한다. |
| bridged mode는? | Apple `com.apple.vm.networking` 승인이 필요한 향후 옵션 |
| build/runtime 책임은? | build는 Python, runtime은 Swift, Shell은 얇은 wrapper |

## 목표

Mac mini 또는 Mac Studio에서 Linux VM을 직접 실행하고, VM 내부에서 VitalServer stack을 운영합니다.

장기 제품 아키텍처는 `Web/PWA UI + platform-specific host runtime + Linux guest appliance`입니다. UI는 iPhone, Android, iPad, desktop browser, macOS/Windows shell에서 같은 product workflow를 제공하고, host-specific 실행은 Runtime Control API 뒤에 둡니다.

```text
Web/PWA Helper UI
  - iPhone / Android / iPad / desktop browser
  - optional macOS/Windows native shell wrapper
        |
        v
RuntimeControlClient contract
        |
        +-- HttpRuntimeClient
        |     local Runtime Control API
        |     remote VitalServer control server
        |
        +-- MacHostRuntimeClient
              transition adapter for current macOS native app
```

Host runtime은 platform별로 구현하되 UI에는 같은 API contract를 제공합니다.

```text
Runtime Control API
  - auth/session/pairing
  - capability negotiation
  - status/settings/logs/update/admin endpoints
  - progress/log streaming
  - dangerous operation confirmation
        |
        v
Host-native runtime components
  - Updater
  - Supervisor
  - VM Driver
  - Service control
  - Log collector
        |
        v
Linux guest
  - Service Stack
  - VitalServer service
  - VM Image/rootfs
```

핵심 원칙:

- UI는 Web/PWA를 primary implementation으로 둔다.
- macOS/Windows native app은 product UI가 아니라 local runtime host/native shell 역할을 맡는다.
- platform-specific 실행 로직은 Runtime Control API와 host-native runtime component 내부에 격리한다.
- platform 차이는 capability와 component version으로 노출한다.
- Web/PWA는 host operation을 직접 실행하지 않는다.

## As-is / To-be

현재 코드는 macOS native Helper app에서 시작한 전환기 구조입니다. 최종 구조는 같은 product workflow를 Web/PWA, macOS shell, Windows shell이 공유하고, host-specific 실행은 Runtime Control API 뒤로 숨기는 구조입니다.

### As-is

현재 macOS Helper app은 SwiftUI presentation, native shell, composition을 담고 있습니다. `MacHostRuntimeAdapter`는 별도 SwiftPM target이며, `MacRuntimeControlApp` 안에서는 composition 파일만 adapter를 import합니다. 다만 아직 같은 Helper app process 안에서 `MacHostRuntimeClient`가 host file, privileged command, `vitalserver-vm` CLI를 직접 호출합니다.

```text
MacRuntimeControlApp
  - SwiftUI UI
  - RuntimeViewModel
  - NativeShell
  - app composition
        |
        | RuntimeControlClient protocol
        | composition-only MacHostRuntimeClient wiring
        v
MacHostRuntimeAdapter
  - MacHostRuntimeClient
  - status/settings/log/backup file readers
  - privileged command runner
  - vitalserver-vm CLI command factory
        |
        | CLI / file / process
        v
HostCLI
  - vitalserver-vm command entrypoint
  - install/configure/update/rollback/watchdog workflows
        |
        | shared directory JSON / logs
        v
Guest VM
  - bootstrap
  - service stack
  - update activation / datastore repair
```

현재 Swift target의 책임은 아래와 같습니다.

| Target | 현재 책임 | 전환기 성격 |
|---|---|---|
| `MacRuntimeControlApp` | SwiftUI 화면, view model, app composition, native shell | presentation/native shell은 adapter 세부 구현을 모름. composition만 local adapter를 조립 |
| `RuntimeControl` | UI/usecase 입출력 계약, `RuntimeControlClient`, DTO, enum | 최종 API/client/server가 공유할 계약의 시작점 |
| `Contracts` | runtime status/progress/health/guest request/result/update bundle/file name 계약 | PWA/API/server/host runtime이 공유할 schema와 enum의 독립 target |
| `MacHostRuntimeAdapter` | `RuntimeControl`의 macOS local 구현, file/process/CLI adapter | 외부 public surface는 `MacHostRuntimeClient` facade 중심. 나중에 Runtime Control API server 쪽 adapter로 이동하거나 축소 가능 |
| `HostCLI` | `vitalserver-vm` CLI와 runtime workflow 실행 | 현재 host runtime source of truth |
| `Core` | evaluator, operation plan, health/recovery policy, port protocol | `Contracts`에 의존하는 순수 도메인/워크플로 정책 |
| `HostInfrastructure` | installed path, file store, JSON repository/gateway | host filesystem/shared directory 구현 |

As-is의 계층 간 통신은 아래처럼 섞여 있습니다.

| 방향 | 현재 방식 | 비고 |
|---|---|---|
| Helper UI -> local runtime | `RuntimeControlClient` protocol 호출 | 좋은 경계. PWA/API에서도 유지할 usecase contract |
| `MacHostRuntimeClient` -> host runtime | CLI command, host file read, privileged process | 전환기 adapter 책임 |
| Host runtime -> Helper UI | `runtime-status.json`, logs, backup metadata file read | API server가 생기면 endpoint/read model로 감쌀 대상 |
| Host runtime <-> Guest VM | shared directory JSON, logs, deploy files | 최종 구조에서도 유지할 VM/process boundary |

### To-be

최종 구조에서는 product UI가 host operation을 직접 실행하지 않습니다. UI는 `RuntimeControl` 계약을 HTTP/SSE API 또는 client SDK로 사용하고, host-specific 실행은 platform별 Runtime Control service가 처리합니다.

```text
Helper UI
  - Web/PWA primary
  - iOS / Android / iPad / desktop browser
  - macOS/Windows native shell wrapper
        |
        | Runtime Control API
        | HTTP/SSE, auth/session, capability, status/settings/log/update/admin
        v
Runtime Control Service
  - API handlers
  - usecase orchestration boundary
  - progress/log streaming
        |
        v
Host Runtime Application
  - Updater
  - Supervisor
  - VM Driver
  - Service control
  - Log collector
        |
        | VM provider + shared directory contract
        v
Linux Guest Appliance
  - Service Stack
  - VitalServer / Redis / UI / guest nginx
  - VM Image/rootfs
  - guest activation / repair jobs
```

To-be의 모듈 방향은 아래처럼 둡니다.

```text
Helper UI / Native Shell
        |
        v
ManagementClient
        |
        v
ManagementAPI / ManagementServer
        |
        v
Host Runtime Application
        |
        +--> Core
        +--> HostInfrastructure
        |
        v
Guest VM contract

RuntimeControl
  -> UI/client/server가 공유하는 API DTO와 usecase contract

Contracts
  -> PWA/API/server/host runtime이 공유하는 JSON schema, enum, file contract

Core
  -> host runtime 내부 domain workflow와 policy
```

최종 책임 분리는 아래를 목표로 합니다.

| Layer | To-be 책임 | 현재 코드에서 이동/변경될 것 |
|---|---|---|
| Helper UI | product workflow, 화면 상태, 사용자 입력 | SwiftUI transition UI는 Web/PWA primary로 대체 가능해야 함 |
| Native Shell | install/bootstrap/pairing/recovery/native picker | product UI 로직을 소유하지 않음 |
| Runtime Control API | auth/session, capability, status/settings/log/update/admin endpoint, progress/log streaming | `RuntimeControlClient` local 호출을 HTTP/SSE boundary로 노출 |
| Runtime Control Client | UI가 local/remote runtime에 붙는 client | `MacHostRuntimeClient` 대신 `HttpRuntimeClient`가 primary가 됨 |
| Host Runtime Application | install/configure/update/rollback/watchdog/service usecase | 현재 `HostCLI` CLI workflow를 service/usecase 중심으로 재배치 |
| Runtime Adapter/Infrastructure | file/process/launchd/VM provider/guest gateway 구현 | 현재 `MacHostRuntimeAdapter`와 `HostInfrastructure` 책임을 API server/usecase 아래로 정렬 |
| Runtime Contracts | typed status, reason, manifest, guest request/result, file names | PWA/API/server/host runtime이 공유하는 schema/enum으로 유지 |
| Runtime Core | evaluator, operation plan, recovery policy, testable ports | 순수 정책과 workflow로 유지 |
| Guest Appliance | Linux service stack, activation/repair 실행 | shared JSON/file contract 유지 |

As-is에서 To-be로 갈 때의 판단 기준은 아래입니다.

| 질문 | 판단 |
|---|---|
| UI가 알아야 하는가? | status/settings/log/update 같은 usecase 입출력만 알아야 한다. host path, launchd, command string은 몰라야 한다. |
| 파일 기반 계약이 맞는가? | process/VM 경계를 넘을 때만 맞다. Swift module 사이에서는 protocol/API 호출을 사용한다. |
| enum으로 닫을 수 있는가? | status, operation, log source, artifact kind, bundle kind, failure reason은 enum/typed value로 둔다. |
| platform 차이가 어디에 있어야 하는가? | capability, component version, Runtime Control service implementation에 둔다. UI flow에는 직접 새지 않게 한다. |
| CLI는 최종 source of truth인가? | 아니다. 최종적으로는 host runtime service/API가 source of truth이고 CLI는 관리/복구 entrypoint가 된다. |

PWA 착수 직전까지 현재 branch가 보장해야 하는 compatibility baseline은 아래입니다.

| Baseline | 현재 상태 |
|---|---|
| UI/usecase 계약 | `RuntimeControl`의 `RuntimeControlClient`, DTO, enum을 기준으로 고정 |
| Runtime schema 계약 | `Contracts` target으로 분리해 status/progress/health/update bundle/guest request-result 계약을 독립 |
| SwiftUI presentation 의존성 | `RuntimeControl`만 직접 사용하고, local adapter 구현은 import하지 않음 |
| Native shell 의존성 | AppKit/native picker/open/terminate만 담당하고, runtime command factory를 import하지 않음 |
| Local adapter 공개면 | `MacHostRuntimeAdapter` 외부 public surface는 `MacHostRuntimeClient` facade 중심으로 제한 |
| Adapter 내부 구현 | command factory, status/settings/file/log reader, privileged runner는 internal 구현 세부로 유지 |
| API 전환 지점 | `RuntimeViewModel` 또는 future PWA client는 `RuntimeControlClient` 계약만 보고, `MacHostRuntimeClient`는 composition에서 교체 가능 |
| 후속 이슈 | Runtime Control API/server/client skeleton은 #30에서 진행 |

Repository layout 기준은 아래처럼 둡니다.

| 위치 | 둬야 하는 것 | 둬서는 안 되는 것 |
|---|---|---|
| `apps/vitalserver` | VM/컨테이너 안에서 실행되는 VitalServer service wrapper와 runtime shim | macOS host runtime, package installer 정책 |
| `apps/vitalserver-macos-runtime` | macOS runtime distribution. Swift Helper app, `vitalserver-vm` CLI, packaging scripts, launchd template, guest deploy assets, release metadata | build-machine 전용 rootfs/image 생성 로직, PWA product UI |
| `packages/vm-build` | Python build-machine tooling. Ubuntu image, cloud-init, rootfs compression, nginx bundle, Docker image bundle, update bundle 생성/검증 | 설치 후 runtime 상태 전이, launchd/VM lifecycle 정책 |
| `packages/vitalserver-testkit` | 운영/통합 검증용 testkit | 제품 runtime 구현 |
| future `apps/vitalserver-helper-pwa` 또는 동등한 PWA app | Web/PWA primary Helper UI | host file/process/launchd 직접 호출 |

`apps/vitalserver-macos-runtime`을 `packages`로 옮기지 않는 이유는 이 디렉터리가 재사용 라이브러리가 아니라 설치 가능한 macOS runtime product를 만들기 위한 distribution boundary이기 때문입니다. 반대로 `packages/vm-build`는 설치 대상에 포함되지 않는 build-machine 도구라 `packages`에 남깁니다.

Platform별 차이는 아래처럼 격리합니다.

| Layer | macOS | Windows | 공통 계약 |
|---|---|---|---|
| Web/PWA Helper UI | browser/PWA/native shell wrapper | browser/PWA/native shell wrapper | 동일 product UI |
| Runtime Control API | local macOS service | local Windows service | HTTP/SSE API, auth/session, capability, result/reason model |
| Native shell | menu bar app, pkg, recovery, native panels | tray app, installer, recovery, native dialogs | bootstrap, pairing, recovery entrypoint |
| Updater | macOS file/service/update flow | Windows file/service/update flow | Product/VM Image update manifest contract |
| Supervisor | launchd/process/network health | Windows Service/process/network health | health/status/recovery model |
| VM Driver | Apple Virtualization provider | Hyper-V, WSL2, VirtualBox, or other provider | VM lifecycle capability model |
| Service Stack | Linux guest compose/container assets | Linux guest compose/container assets | guest activation and service stack contract |

v1 기본 구조는 아래와 같습니다.

```text
shared/NAT mode

VRecorder / Browser
  -> target Mac LAN IP :80
      -> host nginx
          -> Linux VM shared/NAT IP
              -> Docker Compose edge nginx
                  -> VitalServer
                  -> Redis
                  -> Redis UI
                  -> Swagger UI
```

bridged mode는 Apple 승인이 필요한 향후 옵션입니다.

```text
bridged mode

VRecorder / Browser
  -> Linux VM LAN IP :80
      -> Docker Compose edge nginx
          -> VitalServer
          -> Redis
          -> Redis UI
          -> Swagger UI
```

두 구조를 비교하면 아래와 같습니다.

| 항목 | shared/NAT mode | bridged mode |
|---|---|---|
| 제품 v1 기본값 | 예 | 아니오 |
| VRecorder 접속 대상 | target Mac LAN IP | Linux VM LAN IP |
| edge proxy 위치 | macOS host nginx | Linux VM Compose edge nginx |
| VM IP 부여 | macOS Virtualization NAT DHCP | 병원 LAN DHCP |
| 원 IP 보존 | host nginx 경유로 보존 | VM이 LAN에서 직접 수신 |
| Apple `com.apple.vm.networking` 승인 | 필요 없음 | 필요 |
| 주요 리스크 | host nginx package/launchd 관리 | Apple 승인, 병원망 bridged 허용 여부 |

이 구조는 macOS Docker Desktop/OrbStack 의존성을 제거하면서도, 이미 검증한 host nginx 경유 원 IP 보존 방식을 제품화하기 위한 것입니다. VRecorder는 target Mac의 LAN IP로 접속하고, host nginx가 요청을 VM 내부 VitalServer로 전달합니다.

bridged mode는 host nginx 없이 VM이 병원 LAN에 직접 붙는 선택지로 남깁니다. 다만 `com.apple.vm.networking` restricted entitlement 승인이 필요하므로 v1 제품 blocker로 두지 않습니다.

## 배포 모델

최종 목표는 병원 Mac mini/Mac Studio에 설치 가능한 self-contained package입니다. 운영 target Mac은 air-gapped 환경까지 고려합니다.

### Build Machine

개발자 또는 CI가 VM image를 준비합니다.

```text
download Ubuntu cloud image
  -> convert root disk to raw
  -> expand rootfs
  -> install Docker/Compose and guest prerequisites inside rootfs
  -> preload required container images
  -> install systemd units
  -> build signed/notarized macOS pkg
```

이 단계에서는 `qemu-img`, image customization 도구, 네트워크 접근이 필요할 수 있습니다.

### Target Mac

병원 Mac mini/Mac Studio는 설치 파일만 받습니다.

```text
TiroshVitalServer.pkg
  -> /usr/local/bin/vitalserver-vm
  -> /usr/local/bin/vitalserver-proxy-run
  -> /usr/local/bin/tirosh-vitalserver-uninstall
  -> /Applications/VitalServer Helper.app
  -> /Library/Application Support/TiroshVitalServer/nginx/sbin/nginx
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-watchdog.plist
  -> /Library/Application Support/TiroshVitalServer/vm/runtime/
       Image
       initrd.img
       rootfs-base.raw.gz
       vm-disk.img
       vm-config.json
       seed.iso
       runtime-version.json
  -> /Library/Application Support/TiroshVitalServer/vm/data/
       vital-files/
       vr-release/
```

운영 target Mac에는 아래 의존성이 없어야 합니다.

| 의존성 | 운영 target Mac 필요 여부 |
|---|---|
| Homebrew | 필요 없음 |
| `qemu-img` | 필요 없음 |
| Docker Desktop | 필요 없음 |
| OrbStack | 필요 없음 |
| brew nginx | 필요 없음, package에 포함 |
| 외부 apt repository | 필요 없음 |
| 외부 container registry | 필요 없음 |

## 단일 노드 가용성 범위

이 제품은 단일 Mac mini/Mac Studio 위에서 동작하는 single-node runtime입니다. 따라서 제품 문구에서 “고가용성”은 여러 장비로 구성한 HA cluster가 아니라, 단일 장비 안에서 가능한 self-healing, 자동 복구, 데이터 보존, rollback을 의미합니다.

제품이 단일 target Mac에서 보장할 수 있는 범위는 아래입니다.

| 범위 | 보장 방식 |
|---|---|
| macOS 재부팅 후 자동 기동 | VM/proxy LaunchDaemon `RunAtLoad`, start-on-boot policy |
| VM launcher 비정상 종료 복구 | VM LaunchDaemon `KeepAlive`, detached VM process, watchdog recovery |
| host nginx proxy 비정상 종료 복구 | proxy LaunchDaemon `KeepAlive`, `vitalserver-proxy-run` loop, watchdog recovery |
| VM IP 변경 대응 | `vitalserver-proxy-run`이 guest `runtime-state.json`을 감시하고 nginx config reload. legacy `vm-ip` 파일은 fallback |
| guest service 복구 | guest systemd unit, Docker, nginx, Compose restart policy |
| 설치/업데이트 실패 진단 | 고정 log path, runtime status/health command |
| update 실패 복구 | apply 전 backup, health check 실패 시 rollback |
| 설정/데이터 보존 | rootfs artifact와 mutable runtime/data 영역 분리 |
| 디스크 full 예방 | install/update 사전 용량 check, log rotation, Docker dangling image cleanup |

단일 target Mac에서 보장할 수 없는 범위도 명확히 둡니다.

| 범위 | 이유 | 필요한 외부 구성 |
|---|---|---|
| 하드웨어 고장 시 무중단 서비스 | 장애 도메인이 하나임 | standby Mac, VIP/DNS failover |
| 단일 내장 디스크 완전 손상 시 데이터 보존 | local disk가 단일 실패 지점 | 외부 backup, RAID/replication, Time Machine/remote backup |
| 전원 장애 중 서비스 지속 | 장비 전원이 끊김 | UPS |
| macOS kernel panic/OS 손상 중 서비스 지속 | runtime host 자체가 중단됨 | standby Mac, 재설치/복구 절차 |
| 네트워크 장비 장애 대응 | 제품 밖의 network path | 이중화 switch/router, 병원망 HA |
| zero-downtime update | 단일 VM runtime을 중지/교체해야 함 | active-standby node 또는 rolling pair |

제품 수준의 정확한 표현은 아래처럼 둡니다.

```text
Single-node self-healing runtime

보장:
- macOS reboot 후 자동 기동
- VM/proxy/guest service 비정상 종료 후 자동 복구
- update 실패 시 rollback
- mutable data/config 영역 보존
- health 기반 장애 감지와 진단 로그 제공

보장하지 않음:
- 단일 Mac mini/Mac Studio 하드웨어 장애 시 무중단 운영
- 전원/디스크/macOS 전체 장애 중 서비스 지속
- 두 대 이상의 장비를 쓰는 cluster HA
```

현재 구현된 단일 노드 복구 장치는 아래입니다.

1. VM/proxy LaunchDaemon은 `RunAtLoad`, `KeepAlive`, `ThrottleInterval`, stdout/stderr log path를 가진다.
2. watchdog LaunchDaemon은 `vitalserver-vm runtime watchdog`을 주기 실행한다.
3. watchdog은 VM/proxy/HTTP health를 기준으로 VM/proxy를 kickstart하고 `runtime-status.json`을 갱신한다.
4. guest 내부 Docker Compose stack은 `tirosh-vitalserver-compose.service`로 재부팅 후 재적용된다.
5. Helper app은 `/Library/Application Support/TiroshVitalServer/status/runtime-status.json`을 읽어 정상/복구중/장애/업데이트중 상태를 표시한다.
6. install/update는 free-space preflight를 수행하고, installer/runtime log는 size 기반 rotation을 수행한다.
7. guest bootstrap은 bundled image load 후 Docker dangling image cleanup을 수행한다.

### Runtime Status 계약

운영 상태의 source of truth는 아래 JSON 파일입니다.

```text
/Library/Application Support/TiroshVitalServer/status/runtime-status.json
```

이 파일은 `vitalserver-vm runtime install`, `health`, `watchdog`, `apply-bundle`, `rollback`이 갱신합니다. Helper app, watchdog, 운영 CLI는 같은 파일을 읽어 상태를 판단합니다.

`runtime-status.json`은 update/watchdog coordination에도 사용합니다. update와 rollback은 VM/proxy/watchdog launchd service를 직접 stop/start하므로, 이 구간에서 watchdog auto-recovery가 동시에 실행되면 같은 자원을 두 process가 재시작하는 경쟁 상태가 됩니다. 따라서 watchdog은 상태 문서가 아래 operation을 진행 중이라고 판단하면 recovery를 건너뜁니다.

| status | operation | 의미 |
|---|---|---|
| `updating` | `apply-bundle` | host artifact 교체, migration, service restart 진행 중 |
| `recovering` | `activate-guest-update` | guest Docker image load/compose recreate 진행 중 |
| `recovering` | `rollback` | managed backup 복원 진행 중 |

이 guard는 stale 상태를 영구적으로 믿지 않습니다. 상태 파일의 `updatedAt`이 grace timeout보다 오래되면 watchdog은 update process가 더 이상 살아 있지 않은 것으로 보고 일반 recovery로 돌아갑니다.

상태 값은 아래로 제한합니다.

| status | 의미 |
|---|---|
| `installing` | installer가 runtime instance를 provision 중 |
| `updating` | update bundle 적용 중 |
| `recovering` | rollback 또는 복구 동작 중 |
| `healthy` | 현재 health 기준 통과 |
| `degraded` | 서비스는 복구됐거나 일부 실패가 있으나 진단/조치가 필요한 상태 |
| `critical` | install/provisioning 실패 또는 자동 복구 불가 상태 |

현재 schema:

```json
{
  "product": "TiroshVitalServer",
  "status": "healthy",
  "operation": "health",
  "message": "runtime health check passed",
  "updatedAt": "2026-05-21T00:00:00Z",
  "productRoot": "/Library/Application Support/TiroshVitalServer",
  "runtimeHome": "/Library/Application Support/TiroshVitalServer/vm",
  "runtimeVersion": "<version>",
  "vmService": "loaded",
  "proxyService": "loaded",
  "watchdogService": "loaded",
  "vmIP": "192.168.64.2",
  "proxyPort": 80,
  "hostProxyHTTP": "302",
  "guestHTTP": "302",
  "redisUIHTTP": "200",
  "swaggerUIHTTP": "200",
  "rootfsBase": "present",
  "vmDisk": "present",
  "failureReasons": [],
  "latestBackup": "/Library/Application Support/TiroshVitalServer/backups/..."
}
```

상태 전이의 기본 원칙은 아래입니다.

```text
install start       -> installing
install success     -> healthy
install failure     -> critical
health success      -> healthy
health failure      -> degraded
watchdog success    -> healthy
watchdog recovery   -> recovering -> healthy
watchdog failure    -> critical
apply-bundle start  -> updating
apply success       -> healthy
apply failure       -> recovering -> degraded after rollback
rollback start      -> recovering
rollback success    -> healthy
```

## GUI와 Package

제품 설치 책임은 `.pkg`에 둡니다. `.dmg`가 필요하면 installer 전달 매체로만 사용하고, DMG root에는
단일 `Install Tirosh VitalServer.pkg`를 둡니다. PKG가 Helper app/native shell과 host control components를 함께 설치하고,
Helper UI는 설치 이후 상태 확인과 운영 작업을 담당합니다. 장기적으로 이 UI는 Web/PWA primary implementation으로 이동하고 native app은 local runtime host/shell 역할에 집중합니다.

단일 PKG를 기본 배포물로 선택한 이유는 설치 대상이 self-contained app 하나가 아니기 때문입니다.
이 제품은 `/Applications`에 Helper app을 놓는 것 외에도 `/usr/local/bin` Updater/Supervisor/VM Driver tools,
`/Library/LaunchDaemons` system services, `/Library/Application Support/TiroshVitalServer` 아래의
VM Image/runtime asset, host nginx bundle, Docker image bundle을 설치하고 `postinstall`에서 VM disk,
cloud-init seed, component config, launchd 상태를 provision합니다. 이런 system-wide 설치는 macOS
Installer가 권한 상승, receipt, MDM/Jamf 배포, CLI 설치(`installer -pkg ... -target /`)를 다룰 수
있는 `.pkg`가 더 맞습니다.

`.app`만 제공하는 방식은 제품이 앱 bundle 하나로 닫혀 있고 사용자가 `/Applications`로 복사한 뒤 실행하면
충분할 때 적합합니다. 예를 들어 별도 LaunchDaemon, privileged helper, `/usr/local/bin` CLI, shared
runtime data, install-time provisioning이 없고, 최초 실행 시 사용자 권한으로 필요한 설정을 끝낼 수 있는
제품이면 drag-and-drop DMG나 zip/app 배포가 더 단순합니다. Tirosh VitalServer는 headless VM service와
host proxy를 부팅 시 자동 실행해야 하므로 `.app`만으로 배포하면 설치 책임이 Helper app에 과하게 섞이고,
깨진 설치/MDM 배포/제거 경로가 불명확해집니다.

```text
TiroshVitalServer.dmg
  -> Install Tirosh VitalServer.pkg
      -> /Applications/VitalServer Helper.app
      -> /Library/Application Support/TiroshVitalServer runtime data
      -> /usr/local/bin Updater/Supervisor/VM Driver tools
      -> LaunchDaemons
      -> postinstall runtime provisioning
```

| 설정 | 저장 위치 |
|---|---|
| VM CPU/RAM/kernel/disk/network/MAC | `runtime/vm-config.json` |
| cloud-init user/hostname/SSH key/bootstrap | `seed.iso` |
| VitalServer container/runtime 설정 | deploy `runtime-config.json` |
| 서비스 자동 실행 | LaunchDaemon plist |

Helper app은 설치 이후 상태 확인, 설정 변경, offline/online Product Update bundle 적용,
rollback, 로그 조회, 제거 진입점을 제공하는 UI로 봅니다. VM Image와 privileged provisioning은 installer pkg가 담당합니다.
설정 변경은 Helper app이 직접 JSON/plist를 수정하지 않고 `vitalserver-vm runtime configure ... --restart`를
administrator privilege로 호출합니다.

역할 경계는 아래처럼 고정합니다.

| 대상 | 책임 |
|---|---|
| `Install Tirosh VitalServer.pkg` | 파일 배치, 권한 설정, LaunchDaemon 설치, 최초 runtime provisioning |
| `VitalServer Helper.app` | 설치 후 Status/Settings/Update/Logs/About/Advanced/Danger Zone 진입점 |
| `/usr/local/bin/vitalserver-vm` | 현재 local control binary. Updater, Supervisor, VM Driver 명령을 제공 |
| `/usr/local/bin/tirosh-vitalserver-uninstall` | 제거 source of truth, Helper/Terminal/MDM 공통 backend |

현재 개발용 app bundle은 `make vm-app`으로 생성합니다.

```sh
make vm-app
open ".tmp/VitalServer Helper.app"
```

제품 DMG는 drag-and-drop app wrapper가 아니라 installer pkg를 전달합니다.
`make vm-pkg`는 Helper app을 `/Applications/VitalServer Helper.app` payload로 포함하고,
`make vm-dmg`는 DMG root에 `Install Tirosh VitalServer.pkg`만 배치합니다.

현재 배포 기준은 unsigned입니다. `.pkg`와 `.dmg`에 Developer ID 서명/notarization을 적용하지 않습니다. 단, nginx binary와 dylib는 `install_name_tool`로 load path를 수정하므로 실행 가능한 Mach-O 상태를 위해 ad-hoc signing(`codesign --sign -`)만 수행합니다.

## Runtime 계층과 통신 계약

설치된 target Mac에서 운영 중인 Helper product는 실행 관점에서 세 계층으로 봅니다.

```text
[MacRuntimeControlApp]
사용자 화면, 설정 입력, 버튼 액션
        |
        | CLI command
        | /usr/local/bin/vitalserver-vm ...
        v
[Local Control Components]
Updater, Supervisor, VM Driver, install/configure/update/rollback
        |
        | VirtioFS shared directory
        | JSON config/request, scripts, bundle files
        v
[Guest VM]
Linux guest bootstrap, Docker Compose stack, update/repair execution
```

상태와 결과는 반대 방향으로 올라옵니다.

```text
[Guest VM]
runtime-state.json, result JSON, guest logs
        |
        | VirtioFS shared directory
        v
[Local Control Components]
health/evaluator/waiter 판단, runtime-status.json 갱신
        |
        | status JSON, command/install/container logs
        v
[MacRuntimeControlApp]
Status/Settings/Update/Logs UI에 표시
```

`Contracts`와 `Core`는 별도 실행 계층이 아니라 `MacHostRuntimeAdapter`와 `HostCLI`이 import하는 공유 라이브러리입니다. `Contracts`는 JSON schema, enum, file name, guest request/result, update bundle manifest처럼 PWA/API/server/host runtime이 함께 알아야 하는 계약을 담습니다. `Core`는 그 계약 위의 evaluator, operation plan, recovery policy, port protocol을 담고, macOS process 실행이나 SwiftUI 화면 같은 adapter 책임은 갖지 않습니다.

현재 Helper app 경계는 아래처럼 둡니다. 이 구조는 전환기 SwiftUI app 안에서 ADR 0002의 `RuntimeControlClient` boundary를 구현한 모양입니다. 코드 배치도 같은 경계를 드러내도록 SwiftPM target을 나눕니다. `MacRuntimeControlApp`은 composition/presentation/native shell을 담고, `MacHostRuntimeAdapter`는 local file/process/CLI adapter를 담습니다. presentation/native shell은 adapter target을 import하지 않고, composition에서만 `MacHostRuntimeClient`를 조립합니다.

```text
[ContentView / MacRuntimeControlApplication]
SwiftUI 화면, binding, 버튼 액션
        |
        | user intent / view state binding
        v
[RuntimeViewModel]
UI 상태, capability guard, usecase orchestration, 화면 메시지 변환
        |
        +-- RuntimeControlClient protocol
        |     status/settings/log/backup/release read model
        |     install/configure/update/rollback/service command usecase
        |
        +-- RuntimeNativeShell
        |     directory/bundle/save panel, file/web open, relaunch/terminate
        |
        +-- RuntimeSettingsValidator
        |     settings apply precondition policy
        |
        +-- RuntimeBackupSelectionPolicy
        |     backup selection retention and managed-delete guard
        |
        +-- RuntimeProcessMessageFormatter
        |     RuntimeCommandResult to user-facing message contract
        |
        +-- RuntimePresentationFormatter
        |     confirmation text and UI filename formatting
        |
        +-- RuntimeHealthNotificationCoordinator
              health transition policy over HealthNotifying adapter

[Composition]
        |
        +-- MacHostRuntimeClient (MacHostRuntimeAdapter target)
              host file read, privileged CLI command, log export
```

`RuntimeViewModel`는 SwiftUI의 view model 역할을 맡지만, macOS API나 command 세부 구현을 직접 소유하지 않습니다. macOS native concern은 `RuntimeNativeShell` 뒤에 두고, local runtime operation은 `RuntimeControlClient` 뒤에 둡니다. 설정 적용 전 검증, backup 선택/삭제 guard, process result message formatting, confirmation/export name formatting, health notification 전이처럼 재사용 가능한 정책은 viewModel 밖의 작은 객체에 둡니다. UI에서 선택한 update bundle과 backup은 내부 계약에서 `URL`로 유지하고, 화면 표시가 필요할 때만 path string으로 변환합니다. Log source처럼 닫힌 선택지는 raw string 대신 enum 계약으로 유지합니다.

| 계층 | 역할 | 주요 코드 | 책임 |
|---|---|---|---|
| `MacRuntimeControlApp` | 운영 UI와 app composition | `Sources/MacRuntimeControlApp/{Composition,Presentation,NativeShell}/*` | SwiftUI 화면, view model 조립, native shell, RuntimeControl 구현 주입 |
| `RuntimeControl` | UI-usecase 입출력 계약 | `Sources/RuntimeControl/*` | `RuntimeControlClient` protocol, status/settings/backup/log/release DTO, command result와 닫힌 선택지 enum |
| `Contracts` | runtime schema 계약 | `Sources/Contracts/*` | status/progress/health/guest request-result/update bundle/file names, PWA/API/server/host runtime 공유 대상 |
| `MacHostRuntimeAdapter` | local runtime adapter | `Sources/MacHostRuntimeAdapter/*` | `RuntimeControl` 구현체, host file/log read, privileged command 실행, `vitalserver-vm` CLI command 조립 |
| `HostCLI` | local control backend | `Sources/HostCLI/*` | Updater/Supervisor/VM Driver 구현. VM 시작/중지, 설치/설정/업데이트/롤백, launchd/nginx/health 제어 |
| `Guest VM` | Linux 실행 환경 | `Support/Guest/*` | bootstrap, Docker image load, Compose stack 실행, update activation, datastore repair |
| `Core` | 공유 정책/workflow | `Sources/Core/*` | health/guest evaluator, operation plan, recovery policy, repository/clock/command/file port |

계층 간 통신 방식은 아래로 고정합니다.

| 방향 | 방식 | 입력 | 출력 |
|---|---|---|---|
| `MacRuntimeControlApp -> Local control` | CLI 실행 | `install`, `start`, `stop`, `runtime configure`, `apply-bundle`, `rollback` 명령과 CPU/RAM/disk/network/proxy/admin 설정 | command exit code, command log |
| `Local control -> MacRuntimeControlApp` | host file read | `runtime-status.json`, install/runtime/container logs, backup/update bundle metadata | UI status, progress, failure reason, log view |
| `Local control -> Guest VM` | shared directory file contract | `runtime-config.json`, cloud-init/bootstrap files, update/repair request JSON, deploy bundle files | guest 작업 시작 조건 |
| `Guest VM -> Local control` | shared directory file contract | `runtime-state.json`, bootstrap/update/repair result JSON, guest logs | health 판단, waiter completion, rollback/update result |

이 구조에서 파일 기반 계약은 모든 계층에 쓰는 범용 통신 방식이 아닙니다. Swift module 사이에서는 `public` API와 protocol을 import해서 호출하고, 파일 기반 JSON은 process/VM 경계를 넘는 계약에만 사용합니다. 특히 guest VM은 bootstrap 초기에 HTTP service가 아직 없을 수 있으므로, shared directory의 request/result JSON이 update와 repair의 안정적인 최소 계약입니다.

## Source 책임

초기 PoC는 Shell script가 대부분의 일을 직접 수행했습니다. 제품화 단계에서는 책임을 아래처럼 재배치합니다.

```text
Makefile
  -> target dependency와 개발자 인터페이스만 유지

Python build package
  -> build-machine 전용 artifact 생성
  -> Ubuntu/rootfs/cloud-init/nginx/Docker/update bundle 처리

Host-native runtime components
  -> target host 설치 후 운영 source of truth
  -> install/status/health/configure/update/rollback 처리
  -> macOS는 현재 Swift local control components가 담당

Shell
  -> installer, launchd, guest bootstrap의 얇은 entrypoint
```

이렇게 나누는 이유는 build-time과 installed product runtime의 실패 방식이 다르기 때문입니다. Build 단계는 네트워크, Docker registry, Ubuntu image, bundle 검증처럼 반복 가능한 artifact 생성 문제가 많고 Python으로 테스트하기 쉽습니다. 설치 후 운영 단계는 host filesystem, service manager, VM provider, backup/rollback, 관리자 권한이 얽히므로 설치된 host에서 platform-specific runtime component가 상태 전이를 책임지는 편이 안전합니다.

사용자-facing 책임과 version model은 Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, VM Image, VitalServer로 나눕니다. 현재 Swift `vitalserver-vm` binary가 여러 역할을 한 번에 담고 있더라도, 문서와 bundle manifest는 이 component 경계를 기준으로 변경 범위와 compatibility를 표현합니다.

제품 layer의 platform dependency와 책임은 아래처럼 둡니다. 이 표는 코드 배치보다 상위의 product contract입니다.

| Layer | Platform dependency | 책임 |
|---|---|---|
| VitalServer Helper | cross-platform product umbrella | 최상위 관리 제품/클라이언트 패키지, release/support 기준 |
| Helper UI | cross-platform Web/PWA primary | iPhone/Android/iPad/desktop browser와 native shell wrapper에서 쓰는 product UI |
| Native Shell | platform-specific | install/bootstrap/pairing/recovery/native picker/tray/menu |
| Runtime Control API | common API contract, platform-specific host implementation | auth/session/pairing, capability, status/log/update/settings/admin endpoint, progress/log streaming |
| Updater | host/platform-specific | bundle verify/apply/rollback, compatibility gate, migration 조율 |
| Supervisor | host/platform-aware | health/watchdog/recovery, service state loop, update 중 recovery suppression |
| VM Driver | platform-specific | VM provider별 lifecycle. macOS는 Apple Virtualization/launchd, Windows는 별도 provider |
| Service Stack | mostly guest/service-specific | guest deploy assets, compose, container image bundle, service activation |
| VM Image | guest OS/image-specific | Linux guest OS/base rootfs/kernel/initrd class artifact |
| VitalServer service | service-specific | VM 안에서 실행되는 VitalServer app/container |

현재 구현의 책임 경계는 아래처럼 둡니다. 이 표가 코드 배치의 기준입니다.

| 영역 | 주요 파일 | 책임 | 책임 밖 |
|---|---|---|---|
| build orchestration | `make/vm.mk`, `make/vm/config.mk` | target dependency, 중간/최종 산출물 경로, unsigned build 변수, install test wrapper | manifest 해석, disk/rootfs 세부 처리 |
| build config | `apps/vitalserver-macos-runtime/Support/Build/vm-build.toml` | Ubuntu/rootfs/Docker image/nginx bundle pinned input 값 | 설치 시 사용자 설정 |
| Python build package | `packages/vm-build/src/tirosh_vitalserver/vm_build/*.py` | Ubuntu asset 준비, cloud-init ISO 생성, rootfs 압축, nginx bundle, Docker image bundle, update bundle 생성/검증, plist/template rendering | 설치 후 runtime 상태 변경 |
| Local control entry | `Sources/HostCLI/CLI/Launcher.swift`, `Command.swift` | `vitalserver-vm` command routing, VM start/stop/status/network/runtime command 연결 | package staging, DMG 생성 |
| Local control lifecycle facade | `Sources/HostCLI/Runtime/RuntimeLifecycle.swift` | `runtime install/status/health/verify-bundle/stage-bundle/apply-bundle/rollback/repair-datastore/start-services/stop-services` command를 typed workflow와 runner로 연결 | workflow 내부 단계 구현, DMG/PKG 파일 생성 |
| Local control workflows | `RuntimeInstallWorkflow.swift`, `RuntimeBundleWorkflow.swift`, `RuntimeRollbackWorkflow.swift`, `RuntimeGuestActivationWorkflow.swift`, `RuntimeDatastoreRepairWorkflow.swift` | install/update/rollback/guest activation/datastore repair의 단계 조율, progress/status 기록 경계 | CLI argument parsing, Helper UI presentation |
| Local control contracts | `Sources/Contracts/*.swift`, `Sources/Core/Ports/*.swift` | runtime status/progress/health/guest request/result/update bundle/port 계약, 닫힌 상태값 enum | host filesystem이나 launchd 직접 호출 |
| Local control host services | `RuntimeServiceController.swift`, `RuntimeStorageMaintenance.swift`, `RuntimeStatusWriter.swift`, `RuntimeCommandExecutor.swift`, `RuntimeHealthChecker.swift` | launchd service 제어, free-space/file replacement/artifact pruning, status document 작성, shell command 실행, host/guest health snapshot 수집 | product update policy 결정 |
| Swift paths/constants | `LauncherPaths.swift`, `Constants.swift` | 설치/runtime 경로, artifact 이름, launchd/service 이름, command path | runtime 동작 정책 결정 |
| VM configuration | `VirtualMachine/VMRuntimeConfig.swift`, `VMConfigurationFactory.swift` | `vm-config.json` schema, Apple Virtualization configuration 생성 | install settings 파일 읽기 |
| Helper app | `Sources/MacRuntimeControlApp/*` | 설치 후 Status/Settings/Update/Logs/About/Advanced/Danger Zone UI, app composition, native shell | rootfs, VM disk, privileged provisioning 포함 |
| Helper runtime adapter | `Sources/MacHostRuntimeAdapter/*` | `RuntimeControlClient` local 구현, 상태/설정/log/backup file read, privileged command 조립/실행, log export | SwiftUI presentation, host runtime workflow 내부 단계 |
| PKG scripts | `Support/Packaging/preinstall`, `postinstall`, `proxy-run`, `uninstall` | installer/launchd/uninstall entrypoint wrapper | 복잡한 provisioning 로직 |
| guest bootstrap | `Support/Guest/bootstrap.sh`, `bin/*`, `systemd/*`, `prepare-airgap-rootfs.sh`, `compose.yaml` | Linux guest 내부 Docker/Compose 구성, edge nginx container, Docker image load, runtime state 기록 | macOS launchd/proxy 관리 |

Shell은 의도적으로 얇게 유지합니다. `postinstall`은 로그를 열고 `VITALSERVER_VM_HOME=/Library/Application Support/TiroshVitalServer/vm vitalserver-vm runtime install`만 호출합니다. 설치 정책은 Swift `RuntimeLifecycle`에 둡니다.

변경 판단 기준은 아래입니다.

| 변경 종류 | 위치 |
|---|---|
| Ubuntu image URL, rootfs 압축, cloud-init ISO, Docker image bundle, nginx bundle | Python `packages/vm-build` |
| PKG/DMG target dependency, 산출물 경로, 개발용 install wrapper | `make/vm/*.mk` |
| 설치 후 VM disk 생성, launchd load, runtime config, health, update/rollback | Swift `RuntimeLifecycle` facade와 `Runtime*Workflow`/runner |
| VM start/stop/network mode와 Apple Virtualization config | Swift `HostCLI` |
| Linux guest 내부 Docker Compose, edge nginx container, systemd entrypoint 구성 | `Support/Guest/*.sh`, guest config |
| installer/launchd가 호출하는 command 연결 | `Support/Packaging/*.sh` |
