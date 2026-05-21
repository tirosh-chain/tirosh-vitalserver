# VitalServer VM Launcher

이 문서는 `apps/vitalserver-vm-launcher`의 설계와 운영 판단 기준을 정리합니다.

앱 README는 빠른 실행만 다루고, 배포 모델/네트워크/identity/cloud-init/rootfs 정책은 이 문서에서 관리합니다.

## 목표

Mac mini 또는 Mac Studio에서 Linux VM을 직접 실행하고, VM 내부에서 VitalServer stack을 운영합니다.

v1 기본 구조는 `shared/NAT VM + macOS host nginx`입니다.

```text
shared/NAT mode

VRecorder / Browser
  -> target Mac LAN IP :80
      -> host nginx
          -> Linux VM shared/NAT IP
              -> Docker Compose
                  - vitalserver
                  - redis
                  - vitaldb-observer
```

bridged mode는 Apple 승인이 필요한 향후 옵션입니다.

```text
bridged mode

VRecorder / Browser
  -> Linux VM LAN IP :80
      -> guest nginx
          -> Docker Compose
              - vitalserver
              - redis
              - vitaldb-observer
```

두 구조를 비교하면 아래와 같습니다.

| 항목 | shared/NAT mode | bridged mode |
|---|---|---|
| 제품 v1 기본값 | 예 | 아니오 |
| VRecorder 접속 대상 | target Mac LAN IP | Linux VM LAN IP |
| edge proxy 위치 | macOS host nginx | Linux VM 내부 nginx |
| VM IP 부여 | macOS Virtualization NAT DHCP | 병원 LAN DHCP |
| 원 IP 보존 | host nginx 경유로 보존 | VM이 LAN에서 직접 수신 |
| Apple `com.apple.vm.networking` 승인 | 필요 없음 | 필요 |
| 주요 리스크 | host nginx package/launchd 관리 | Apple 승인, 병원망 bridged 허용 여부 |

최종 v1 목표:

```text
Mac mini / Mac Studio
  -> host nginx :80
      -> vitalserver-vm
          -> Linux VM shared/NAT
              -> Docker Compose
                  - vitalserver
                  - redis
                  - vitaldb-observer
```

v1 제품 구조는 `shared/NAT VM + macOS host nginx`입니다. VRecorder는 target Mac의 LAN IP로 접속하고, host nginx가 요청을 VM 내부 VitalServer로 전달합니다.

이 구조는 macOS Docker Desktop/OrbStack 의존성을 제거하면서도, 이미 검증한 host nginx 경유 원 IP 보존 방식을 제품화하기 위한 것입니다.

bridged mode는 host nginx 없이 VM이 병원 LAN에 직접 붙는 선택지로 남깁니다. 다만 `com.apple.vm.networking` restricted entitlement 승인이 필요하므로 v1 제품 blocker로 두지 않습니다.

## 배포 모델

최종 목표는 병원 Mac mini/Mac Studio에 설치 가능한 self-contained package입니다. 운영 target Mac은 air-gapped 환경까지 고려합니다.

### Build Machine

개발자 또는 CI가 VM image를 준비합니다.

```text
download Ubuntu cloud image
  -> convert root disk to raw
  -> expand rootfs
  -> install docker/nginx/compose inside rootfs
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
  -> /usr/local/tirosh/nginx/sbin/nginx
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist
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
| VM IP 변경 대응 | `vitalserver-proxy-run`이 `vm/data/run/vm-ip`를 감시하고 nginx config reload |
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
5. Manager app은 `/Library/Application Support/TiroshVitalServer/status/runtime-status.json`을 읽어 정상/복구중/장애/업데이트중 상태를 표시한다.
6. install/update는 free-space preflight를 수행하고, installer/runtime log는 size 기반 rotation을 수행한다.
7. guest bootstrap은 bundled image load 후 Docker dangling image cleanup을 수행한다.

### Runtime Status 계약

운영 상태의 source of truth는 아래 JSON 파일입니다.

```text
/Library/Application Support/TiroshVitalServer/status/runtime-status.json
```

이 파일은 `vitalserver-vm runtime install`, `health`, `watchdog`, `apply-bundle`, `rollback`이 갱신합니다. Manager app, watchdog, 운영 CLI는 같은 파일을 읽어 상태를 판단합니다.

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
  "runtimeVersion": "0.1.0",
  "vmService": "loaded",
  "proxyService": "loaded",
  "watchdogService": "loaded",
  "vmIP": "192.168.64.2",
  "proxyPort": 80,
  "hostProxyHTTP": "200",
  "guestHTTP": "200",
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
단일 `Install Tirosh VitalServer.pkg`를 둡니다. PKG가 Manager app과 runtime을 함께 설치하고,
Manager app은 설치 이후 상태 확인과 운영 작업을 담당합니다.

단일 PKG를 기본 배포물로 선택한 이유는 설치 대상이 self-contained app 하나가 아니기 때문입니다.
이 제품은 `/Applications`에 Manager app을 놓는 것 외에도 `/usr/local/bin` runtime tools,
`/Library/LaunchDaemons` system services, `/Library/Application Support/TiroshVitalServer` 아래의
VM/runtime asset, host nginx bundle, Docker image bundle을 설치하고 `postinstall`에서 VM disk,
cloud-init seed, runtime config, launchd 상태를 provision합니다. 이런 system-wide 설치는 macOS
Installer가 권한 상승, receipt, MDM/Jamf 배포, CLI 설치(`installer -pkg ... -target /`)를 다룰 수
있는 `.pkg`가 더 맞습니다.

`.app`만 제공하는 방식은 제품이 앱 bundle 하나로 닫혀 있고 사용자가 `/Applications`로 복사한 뒤 실행하면
충분할 때 적합합니다. 예를 들어 별도 LaunchDaemon, privileged helper, `/usr/local/bin` CLI, shared
runtime data, install-time provisioning이 없고, 최초 실행 시 사용자 권한으로 필요한 설정을 끝낼 수 있는
제품이면 drag-and-drop DMG나 zip/app 배포가 더 단순합니다. Tirosh VitalServer는 headless VM service와
host proxy를 부팅 시 자동 실행해야 하므로 `.app`만으로 배포하면 설치 책임이 Manager app에 과하게 섞이고,
깨진 설치/MDM 배포/제거 경로가 불명확해집니다.

```text
TiroshVitalServer.dmg
  -> Install Tirosh VitalServer.pkg
      -> /Applications/Tirosh VitalServer Manager.app
      -> /Library/Application Support/TiroshVitalServer runtime
      -> /usr/local/bin runtime tools
      -> LaunchDaemons
      -> postinstall runtime provisioning
```

| 설정 | 저장 위치 |
|---|---|
| VM CPU/RAM/kernel/disk/network/MAC | `runtime/vm-config.json` |
| cloud-init user/hostname/SSH key/bootstrap | `seed.iso` |
| VitalServer container/runtime 설정 | deploy `runtime-config.json` |
| 서비스 자동 실행 | LaunchDaemon plist |

Manager app은 설치 이후 상태 확인, health check, runtime 설정 저장, offline update bundle 적용,
rollback, uninstall 진입점을 제공하는 UI로 봅니다. VM runtime artifact와 privileged provisioning은 installer pkg가 담당합니다.
설정 변경은 Manager가 직접 JSON/plist를 수정하지 않고 `vitalserver-vm runtime configure ... --restart`를
administrator privilege로 호출합니다.

역할 경계는 아래처럼 고정합니다.

| 대상 | 책임 |
|---|---|
| `Install Tirosh VitalServer.pkg` | 파일 배치, 권한 설정, LaunchDaemon 설치, 최초 runtime provisioning |
| `Tirosh VitalServer Manager.app` | 설치 후 상태/설정/업데이트/롤백/로그/제거 진입점 |
| `/usr/local/bin/vitalserver-vm` | VM lifecycle, health, configure, update, rollback backend |
| `/usr/local/bin/tirosh-vitalserver-uninstall` | 제거 source of truth, Manager/Terminal/MDM 공통 backend |

현재 개발용 app bundle은 `make vm-app`으로 생성합니다.

```sh
make vm-app
open ".tmp/Tirosh VitalServer Manager.app"
```

제품 DMG는 drag-and-drop app wrapper가 아니라 installer pkg를 전달합니다.
`make vm-pkg`는 Manager app을 `/Applications/Tirosh VitalServer Manager.app` payload로 포함하고,
`make vm-dmg`는 DMG root에 `Install Tirosh VitalServer.pkg`만 배치합니다.

현재 배포 기준은 unsigned입니다. `.pkg`와 `.dmg`에 Developer ID 서명/notarization을 적용하지 않습니다. 단, nginx binary와 dylib는 `install_name_tool`로 load path를 수정하므로 실행 가능한 Mach-O 상태를 위해 ad-hoc signing(`codesign --sign -`)만 수행합니다.

## Package 구성

현재 repository의 `make vm-pkg`는 `.pkg`까지 가기 위한 개발 검증용 packaging target입니다.
최종 배포 산출물은 `dist/`에 두고, `.tmp/`는 중간 작업물 전용으로 사용합니다.

```sh
make vm-pkg
make vm-pkg-install
make vm-installed-health
make vm-pkg-uninstall-dev
```

`make vm-pkg` 생성물:

```text
dist/TiroshVitalServerVM-0.1.0.pkg
```

전달용 DMG가 필요하면 `make vm-dmg`를 실행합니다. DMG에는 단일 PKG만 들어갑니다.

```text
dist/TiroshVitalServer-0.1.0.dmg
```

설치 후 구조:

```text
/Applications/Tirosh VitalServer Manager.app
/usr/local/bin/vitalserver-vm
/usr/local/bin/vitalserver-proxy-run
/usr/local/bin/tirosh-vitalserver-uninstall
/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist
/Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
/Library/LaunchDaemons/com.tirosh.vitalserver-watchdog.plist
/Library/Application Support/TiroshVitalServer/
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
  -> com.tirosh.vitalserver-watchdog
      -> vitalserver-vm runtime watchdog
      -> health snapshot 확인
      -> 필요 시 VM/proxy launchd kickstart
      -> runtime-status.json 갱신

launchd
  -> com.tirosh.vitalserver-vm
      -> vitalserver-vm start
      -> VM이 /mnt/tirosh/run/vm-ip 기록

launchd
  -> com.tirosh.vitalserver-proxy
      -> vitalserver-proxy-run
      -> vm-ip 대기
      -> nginx config 렌더링
      -> nginx start/reload
      -> vm-ip 변경 감시
```

이 구조에서 운영자가 `VITALSERVER_PROXY_UPSTREAM`을 직접 설정할 필요는 없습니다.

`vm-disk.img`는 sparse disk라 package payload에 그대로 넣으면 `pkgbuild`가 실패할 수 있습니다. 따라서 package에는 immutable base artifact인 `rootfs-base.raw.gz`를 넣고, 설치 시 `postinstall`에서 `vm-disk.img`를 생성합니다.

## Source 책임

현재 구현의 책임 경계는 아래처럼 둡니다. 이 표가 코드 배치의 기준입니다.

| 영역 | 주요 파일 | 책임 | 책임 밖 |
|---|---|---|---|
| build orchestration | `make/vm.mk`, `make/vm/config.mk` | target dependency, 중간/최종 산출물 경로, unsigned build 변수, install test wrapper | manifest 해석, disk/rootfs 세부 처리 |
| build config | `apps/vitalserver-vm-launcher/Support/Build/vm-build.toml` | Ubuntu/rootfs/Docker/nginx pinned input 값 | 설치 시 사용자 설정 |
| Python build package | `packages/vm-build/src/tirosh_vitalserver/vm_build/*.py` | Ubuntu asset 준비, cloud-init ISO 생성, rootfs 압축, nginx bundle, Docker image bundle, update bundle 생성/검증, plist/template rendering | 설치 후 runtime 상태 변경 |
| Swift CLI entry | `Sources/VitalServerVMLauncher/CLI/Launcher.swift`, `Command.swift` | `vitalserver-vm` command routing, VM start/stop/status/network/runtime command 연결 | package staging, DMG 생성 |
| Swift runtime lifecycle | `Sources/VitalServerVMLauncher/Runtime/RuntimeLifecycle.swift` | `runtime install/status/health/verify-bundle/stage-bundle/apply-bundle/rollback`, install settings 적용, VM disk 생성, launchd load, backup/rollback | DMG/PKG 파일 생성 |
| Swift runtime paths/constants | `LauncherPaths.swift`, `Constants.swift` | 설치/runtime 경로, artifact 이름, launchd/service 이름, command path | runtime 동작 정책 결정 |
| VM configuration | `VirtualMachine/VMRuntimeConfig.swift`, `VMConfigurationFactory.swift` | `vm-config.json` schema, Apple Virtualization configuration 생성 | install settings 파일 읽기 |
| Manager app | `Sources/TiroshVitalServerApp/*` | 설치 후 상태/health/open/update/uninstall 진입 UI | rootfs, VM disk, privileged provisioning 포함 |
| PKG scripts | `Support/Packaging/preinstall`, `postinstall`, `proxy-run`, `uninstall` | installer/launchd/uninstall entrypoint wrapper | 복잡한 provisioning 로직 |
| guest bootstrap | `Support/Guest/bootstrap.sh`, `prepare-airgap-rootfs.sh`, `compose.yaml` | Linux guest 내부 Docker/nginx/Compose 구성, Docker image load, VM IP marker 기록 | macOS launchd/proxy 관리 |

Shell은 의도적으로 얇게 유지합니다. `postinstall`은 로그를 열고 `VITALSERVER_VM_HOME=/Library/Application Support/TiroshVitalServer/vm vitalserver-vm runtime install`만 호출합니다. 설치 정책은 Swift `RuntimeLifecycle`에 둡니다.

## DMG Build 흐름

`make vm-dmg`는 최종 전달 매체를 만들지만, 실제로는 아래 dependency chain을 실행합니다.

```text
make vm-dmg
  -> make vm-pkg
    -> make vm-pkg-stage
      -> make vm-sign              # unsigned 기준: ad-hoc sign
      -> make vm-app               # Manager.app 생성
      -> make vm-golden-rootfs     # clean VM disk -> rootfs-base.raw.gz
      -> make vm-nginx-bundle      # pinned nginx -> self-contained bundle
      -> make vm-docker-images     # air-gapped Docker image tar.gz
    -> pkgbuild                    # dist/TiroshVitalServerVM-<version>.pkg
  -> hdiutil create                # dist/TiroshVitalServer-<version>.dmg
```

중간 파일과 최종 파일은 아래 위치를 사용합니다.

| 단계 | 경로 | 의미 |
|---|---|---|
| nginx artifact cache | `.artifacts/nginx/macos/bin/nginx` | repository에 commit하지 않는 pinned build input |
| package work dir | `.tmp/vitalserver-vm-pkg/` | PKG staging, rootfs cache, nginx bundle, Docker bundle |
| package root | `.tmp/vitalserver-vm-pkg/root/` | `pkgbuild --root` 입력 |
| app bundle staging | `.tmp/Tirosh VitalServer Manager.app` | `/Applications` payload로 들어갈 app |
| golden VM home | `.tmp/vitalserver-vm-golden/` | package용 clean rootfs를 만들기 위한 임시 VM home |
| DMG staging | `.tmp/vitalserver-vm-dmg/` | DMG root에 들어갈 파일 배치 |
| PKG output | `dist/TiroshVitalServerVM-<version>.pkg` | installer payload |
| DMG output | `dist/TiroshVitalServer-<version>.dmg` | 사용자 전달 매체 |

DMG root에는 `Install Tirosh VitalServer.pkg`만 둡니다. 사용자는 pkg를 열어 macOS Installer로 설치합니다.

## DMG 설치 흐름

사용자 관점의 설치 순서는 아래입니다.

```text
1. TiroshVitalServer-<version>.dmg mount
2. Install Tirosh VitalServer.pkg 실행
3. macOS Installer가 payload 복사
4. PKG postinstall 실행
5. Swift runtime install이 runtime instance provision
6. launchd VM/proxy/watchdog service 등록 및 정책 적용
7. Manager.app 또는 CLI로 status/health 확인
```

실제 코드 호출은 아래처럼 이어집니다.

```text
Install Tirosh VitalServer.pkg
  -> payload copy
    -> /Applications/Tirosh VitalServer Manager.app
    -> /usr/local/bin/vitalserver-vm
    -> /usr/local/bin/vitalserver-proxy-run
    -> /Library/Application Support/TiroshVitalServer/vm/runtime/rootfs-base.raw.gz
    -> /Library/Application Support/TiroshVitalServer/vm/data/deploy/*
    -> /Library/Application Support/TiroshVitalServer/nginx/*
    -> /Library/LaunchDaemons/com.tirosh.vitalserver-*.plist
  -> Support/Packaging/postinstall
    -> vitalserver-vm runtime install
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

VM service가 시작되면 `vitalserver-vm start`가 `vm-config.json`을 읽어 Apple Virtualization VM을 띄웁니다. guest cloud-init은 `seed.iso`의 `runcmd`로 `/mnt/tirosh/deploy/bootstrap.sh`를 실행합니다. guest bootstrap은 Docker image bundle을 load하고 Compose stack과 guest nginx를 구성한 뒤 `/mnt/tirosh/run/vm-ip`를 기록합니다. proxy service의 `vitalserver-proxy-run`은 이 VM IP 파일을 기다렸다가 host nginx config를 렌더링하고 nginx를 시작 또는 reload합니다.

설치 시 설정값은 MDM 또는 고급 설치 wrapper가 `installer` 실행 전에 `/private/tmp/tirosh-vitalserver-install.json`에 쓸 수 있습니다. 이 파일은 partial JSON이며 `postinstall` 이후 삭제됩니다. 일반 사용자 설치는 기본값으로 진행하고, 설치 후 Manager app의 Settings에서 runtime 설정을 변경합니다.

Uninstall 로직은 Manager app에 중복 구현하지 않고, 설치된
`/usr/local/bin/tirosh-vitalserver-uninstall`을 관리자 권한으로 호출합니다. Manager app을 열 수 없는 깨진 설치 상태에서는 같은 command를 Terminal 또는 MDM/Jamf에서 root로 실행합니다.

```text
Tirosh VitalServer Manager.app
  운영 중:
    Status
    Settings
    Update
    Rollback
    Logs
    Uninstall

Fallback:
  sudo /usr/local/bin/tirosh-vitalserver-uninstall
```

## 인터페이스 계약

현재 제품화 흐름은 여러 실행 환경을 건너므로, 각 경계의 입력과 출력 계약을 분리해서 관리합니다.

| 경계 | 호출자 | 피호출자 | 입력 계약 | 출력/부작용 |
|---|---|---|---|---|
| build orchestration | `make/vm.mk` | `vitalserver-vm-build` | `vm-build.toml`, source tree, optional Make overrides | `.tmp/vitalserver-vm-pkg/*`, `dist/*` |
| Ubuntu/rootfs build | `make vm-golden-rootfs` | Python `ubuntu`, `cloud-init`, Swift launcher | Ubuntu cloud image, deploy bundle, bootstrap script | clean `vm-disk.img`, compressed `rootfs-base.raw.gz` |
| nginx bundle | `make vm-nginx-bundle` | Python `nginx-bundle` | pinned macOS nginx binary, expected version | self-contained `nginx/sbin`, `nginx/lib` bundle |
| Docker image bundle | `make vm-docker-images` | Python `docker-images` | Dockerfile, image list, build platform | `vitalserver-images.tar.gz` |
| PKG staging | `make vm-pkg-stage` | macOS filesystem tools | app bundle, rootfs base, nginx bundle, Docker bundle, templates | package root under `.tmp/vitalserver-vm-pkg/root` |
| install provisioning | PKG `postinstall` | `vitalserver-vm runtime install` | installed payload, optional `/private/tmp/tirosh-vitalserver-install.json` | `vm-disk.img`, `vm-config.json`, `seed.iso`, permissions, launchd services |
| runtime status | RuntimeLifecycle | `runtime-status.json` | health/install/update/rollback result | Manager/watchdog-readable status |
| VM launch | launchd | `vitalserver-vm start` | `VITALSERVER_VM_HOME`, `VITALSERVER_VM_DETACHED=1`, `runtime/vm-config.json` | Virtualization.framework VM process |
| watchdog | launchd | `vitalserver-vm runtime watchdog` | runtime files, launchd state, VM IP, HTTP health | runtime status update, VM/proxy kickstart |
| host proxy | launchd | `vitalserver-proxy-run` | `vm/data/run/vm-ip`, proxy template, nginx binary | rendered host nginx config, nginx process |
| guest bootstrap | cloud-init | `bootstrap.sh` | VirtioFS mounts, `runtime-config.json`, Docker bundle | guest nginx, Docker Compose stack, `vm-ip` marker |
| update verification | operator/Manager | `vitalserver-vm runtime verify-bundle` | bundle directory | manifest/checksum validation |
| update apply | operator/Manager | `vitalserver-vm runtime apply-bundle` | verified bundle directory | staged bundle, backup, rootfs-base replacement, migrations, health check |

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
| `memoryGiB` | 8 | 4-64, 4 단위 |
| `diskGiB` | 64 | 32-512, 16 단위 |
| `networkMode` | `shared` | `shared` 또는 `bridged` |
| `proxyPort` | 80 | 1-65535, LaunchDaemon plist에 저장하고 Runtime CLI/Manager가 해당 값을 읽음 |
| `vitalFilesDirectory` | `/Library/Application Support/TiroshVitalServer/vm/data/vital-files` | absolute path |
| `adminPassword` | `admin` | admin 계정 reset 값. empty가 아니면 guest runtime에 적용 |
| `vmHostname` | `tirosh-vitalserver` | hostname-safe 문자열 |
| `publicHost` | empty | single-line 문자열 |
| `publicPort` | 80 | 1-65535 |
| `startAfterInstall` | true | bool |
| `startOnBoot` | true | bool |

현재 settings JSON은 partial override 계약입니다. 파일을 제공하는 installer UI, MDM, 또는 설치 wrapper는 바꾸고 싶은 필드만 쓰면 됩니다. 누락된 필드는 기본값을 사용하고, 범위를 벗어난 값은 무시합니다.

예시:

```json
{
  "cpuCount": 8,
  "memoryGiB": 16,
  "diskGiB": 128,
  "proxyPort": 8080,
  "vitalFilesDirectory": "/Users/Shared/TiroshVitalFiles",
  "adminPassword": "change-me",
  "publicHost": "vitalserver.local",
  "publicPort": 8080,
  "startAfterInstall": true,
  "startOnBoot": true
}
```

설치 wrapper는 `installer` 실행 전에 이 파일을 씁니다.

```sh
sudo install -m 0600 /path/to/install-settings.json /private/tmp/tirosh-vitalserver-install.json
sudo installer -pkg dist/TiroshVitalServerVM-0.1.0.pkg -target /
```

개발용 Make target은 같은 계약을 `VM_INSTALL_SETTINGS`로 감쌉니다.

```sh
VM_INSTALL_SETTINGS=/path/to/install-settings.json make vm-pkg-install
```

`postinstall`이 설정을 읽어 runtime provisioning에 반영한 뒤 settings 파일을 삭제합니다.

### Proxy Port 계약

v1 기본 proxy port는 80입니다.

```text
external client
  -> target Mac host nginx :80
  -> Linux VM nginx :80
  -> VitalServer container :18080
```

`proxyPort`는 설치 설정과 LaunchDaemon environment로 전달됩니다. Runtime CLI와 Manager app은 설치된 proxy LaunchDaemon plist에서 `VITALSERVER_PROXY_PORT`를 읽어 health/open URL에 반영합니다.

```text
install settings JSON
  -> postinstall
  -> proxy LaunchDaemon EnvironmentVariables:VITALSERVER_PROXY_PORT
  -> vitalserver-proxy-run
  -> RuntimeLifecycle status/health
  -> Manager app health/open URL
```

### Update Bundle 계약

`make vm-update-bundle`은 현재 아래 artifact를 만들 수 있습니다.

| artifact type | 생성 여부 | Swift verify | Swift apply |
|---|---:|---:|---:|
| `rootfs-base` | 항상 포함 | 예 | `rootfs-base.raw.gz` 교체 |
| `migration` | optional | 예 | executable이면 순차 실행 |

따라서 현재 update apply의 실제 효과는 아래로 제한됩니다.

```text
verify bundle
stage bundle
backup rootfs-base/runtime-version
stop services
replace rootfs-base.raw.gz
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

update에서 rootfs base를 교체해도 기존 `vm-disk.img` 내부 OS와 application runtime은 자동으로 교체되지 않습니다. 이미 설치된 VM 내부를 바꾸는 작업은 migration 또는 별도 guest update artifact로 정의해야 합니다. `.pkg` 재설치나 app/runtime tools 교체는 아직 update bundle 계약에 포함하지 않습니다.

설치 테스트는 실제 시스템 경로를 사용합니다.

| 경로 | 내용 |
|---|---|
| `/usr/local/bin` | VM launcher/runtime lifecycle CLI, proxy runner |
| `/Library/LaunchDaemons` | VM/proxy 자동 실행 plist |
| `/Library/Application Support/TiroshVitalServer` | VM image, deploy bundle, nginx runtime |
| `/Library/Application Support/TiroshVitalServer/logs/install.log` | installer provisioning log, 10 MiB 기준 rotation |
| `/Library/Application Support/TiroshVitalServer/status/runtime-status.json` | Manager/watchdog용 runtime 상태 |

설치 후 `make vm-installed-health`로 launchd load 상태, VM IP, guest HTTP, host proxy HTTP를 확인합니다.

개발 중 설치/제거를 반복할 때는 `make vm-pkg-uninstall-dev`를 사용합니다. 이 target은 `/Library/Application Support/TiroshVitalServer`, 관련 LaunchDaemon plist, `/usr/local/bin/vitalserver-*`를 제거하므로 운영 환경에서는 사용하지 않습니다.

설치된 Mac mini/Mac Studio에서 사용자가 CLI로 제거할 때는 아래 명령을 사용합니다.

```sh
sudo tirosh-vitalserver-uninstall
```

이 명령은 VM/proxy LaunchDaemon을 unload하고, package가 설치한 runtime 파일을 제거합니다. GUI 제품에서는 Manager app의 “Uninstall” 버튼이 같은 command를 호출합니다.

### nginx release artifact

`make vm-nginx-bundle`은 `apps/vitalserver-vm-launcher/Support/Build/vm-build.toml`의 `[nginx]`에 선언된 release artifact를 사용합니다. 기본 경로는 아래입니다.

```text
.artifacts/nginx/macos/bin/nginx
```

이 파일은 repository에 commit하지 않는 build-machine 입력 cache입니다. 로컬 unsigned build에서는 Homebrew nginx를 한 번 복사해 release artifact를 만듭니다.

```sh
make vm-nginx-artifact
```

기본 source binary는 `/opt/homebrew/opt/nginx/bin/nginx`입니다. 다른 위치를 쓰려면 artifact 생성 단계에서만 명시적으로 지정합니다.

```sh
VM_NGINX_SOURCE_BIN=/path/to/nginx make vm-nginx-artifact
```

build tooling은 이 binary의 `nginx -v` 출력이 pinned `expected_version`과 맞는지 확인한 뒤, 실행 파일과 비시스템 dylib를 package 내부로 복사합니다. 현재 pinned version은 `nginx/1.31.0`입니다.

```text
nginx/sbin/nginx
  -> @executable_path/../lib/libpcre2-8.0.dylib
  -> @executable_path/../lib/libssl.3.dylib
  -> @executable_path/../lib/libcrypto.3.dylib
  -> /usr/lib/libz.1.dylib
  -> /usr/lib/libSystem.B.dylib
```

즉 운영 target Mac에 Homebrew가 없어도 host proxy가 뜰 수 있는 구조입니다. 임시로 다른 binary를 bundle 입력으로 직접 쓰려면 명시적으로 override합니다.

```sh
VM_NGINX_BIN=/path/to/nginx \
VM_NGINX_EXPECTED_VERSION=nginx/1.31.0 \
make vm-nginx-bundle
```

air-gapped 제품 package는 외부 Docker registry 없이 container를 시작할 수 있어야 합니다. 현재 package flow는 `make vm-docker-images`로 아래 image를 하나의 bundle로 만들고, 설치 후 guest bootstrap에서 `docker load`를 먼저 수행합니다.

```text
vitalserver:2.3.4
redis:3.2.12-alpine
rediscommander/redis-commander:latest
swaggerapi/swagger-ui:v5.17.14
```

생성/설치 경로는 아래와 같습니다.

```text
.tmp/vitalserver-vm-pkg/docker-images/vitalserver-images.tar.gz
/Library/Application Support/TiroshVitalServer/vm/data/deploy/docker-images/vitalserver-images.tar.gz
```

Docker image만으로는 충분하지 않습니다. Guest VM이 처음 부팅될 때 `docker.io`, Docker Compose, nginx, qemu-user-static을 apt로 설치해야 한다면 air-gapped 환경에서 실패합니다. 그래서 제품용 package는 개발용 VM disk가 아니라 별도 golden VM home에서 만든 clean rootfs base를 사용합니다.

```sh
make vm-golden-rootfs
make vm-pkg
```

기본 package용 rootfs는 8GB입니다. `make vm-golden-rootfs`는 `.tmp/vitalserver-vm-golden` 아래에서 VM을 임시로 띄우고 `prepare-airgap-rootfs.sh`만 실행한 뒤 `.tmp/vitalserver-vm-pkg/rootfs-base.raw.gz`를 생성합니다. 이 스크립트는 OS package를 설치하고 `/mnt/tirosh/run/rootfs-ready` marker를 기록한 뒤 종료됩니다. Container는 시작하지 않기 때문에 운영 데이터나 Redis volume을 golden rootfs에 섞지 않습니다.

기본값은 매번 golden disk를 새로 만듭니다. 반복 개발 중 재사용하려면:

```sh
VM_RECREATE_GOLDEN_ROOTFS=false make vm-golden-rootfs
```

## Update Bundle

온라인/오프라인 업데이트는 같은 bundle directory를 입력으로 사용합니다.

```sh
make vm-update-bundle
make vm-update-bundle-verify
```

`make vm-update-artifacts`는 package staging root를 기준으로 `app-bundle.tar.gz`,
`runtime-tools.tar.gz`, `nginx-bundle.tar.gz`, `guest-deploy.tar.gz`를 자동 생성합니다.
`make vm-update-bundle`은 이 artifact들을 기본 포함하므로 Manager app, runtime tools, host nginx,
guest deploy bundle까지 같은 online/offline bundle 계약으로 배포할 수 있습니다.

마이그레이션 실행 파일을 bundle에 포함하려면:

```sh
VM_UPDATE_MIGRATIONS="release/migrations/001-example" make vm-update-bundle
```

생성물:

```text
dist/update-bundles/update-bundle-0.1.0/
  manifest.json
  checksums.txt
  signature
  rootfs-base.raw.gz
  app-bundle.tar.gz
  runtime-tools.tar.gz
  nginx-bundle.tar.gz
  guest-deploy.tar.gz
  migrations/
```

`manifest.json`은 `schemaVersion: 2`를 사용합니다. `artifacts`와 `migrations`는 모두
`checksums.txt`와 manifest 자체의 sha256/size 값으로 검증됩니다.

현재 `signature`는 `unsigned` placeholder입니다. 이 파일은 호환 레이어가 아니라 bundle 계약의 고정 자리이며, release hardening 단계에서 실제 signature 검증으로 교체합니다.

설치된 Mac mini/Mac Studio에서는 Swift runtime lifecycle command가 bundle을 검증하고 적용합니다.

```sh
vitalserver-vm runtime verify-bundle /path/to/update-bundle-0.1.0
sudo vitalserver-vm runtime stage-bundle /path/to/update-bundle-0.1.0
sudo vitalserver-vm runtime apply-bundle /path/to/update-bundle-0.1.0
sudo vitalserver-vm runtime rollback
```

`apply-bundle`은 mutable `vm-disk.img`를 보존하고, replaceable artifact만 backup/rollback 대상으로 삼습니다. 적용 전 backup을 만들고 VM/proxy를 중지한 뒤 artifact를 교체하고 executable migration을 순서대로 실행합니다. 기존에 서비스가 실행 중이었다면 재시작 후 health check를 통과해야 성공 처리합니다. migration 또는 health check 실패 시 `rollback`으로 직전 backup을 복원합니다.

지원 artifact type:

| type | artifact name | 적용 대상 |
|---|---|---|
| `rootfs-base` | `rootfs-base.raw.gz` | 이후 provisioning 기준 rootfs base |
| `app-bundle` | `app-bundle.tar.gz` | `/Applications/Tirosh VitalServer Manager.app` |
| `runtime-tools` | `runtime-tools.tar.gz` | `/usr/local/bin` runtime tools |
| `nginx-bundle` | `nginx-bundle.tar.gz` | host nginx bundle |
| `guest-deploy` | `guest-deploy.tar.gz` | VM shared deploy bundle |

설치 후 runtime 설정 변경은 아래 command가 source of truth입니다.

```sh
sudo vitalserver-vm runtime configure \
  --cpu 8 \
  --memory-gib 8 \
  --network shared \
  --bridged-interface "<interface-id-if-bridged>" \
  --proxy-port 80 \
  --vital-files-dir "/Library/Application Support/TiroshVitalServer/vm/data/vital-files" \
  --public-host "" \
  --public-port 80 \
  --start-on-boot true \
  --admin-password "<password>" \
  --restart
```

이 command는 `vm-config.json`, deploy `runtime-config.json`, proxy LaunchDaemon plist, launchd enable/disable 정책을 갱신하고 `--restart`가 있으면 VM/proxy/watchdog을 kickstart합니다. Manager app의 Settings tab도 이 command를 호출합니다. Manager app의 admin password 입력은 기존 값을 표시하지 않고, 운영자용 admin password reset을 선택했을 때만 `--admin-password`를 전달합니다.

admin password reset은 VitalServer 본체의 사용자 계정 기능을 확장하거나 수정하는 기능이 아닙니다. VitalServer UI의 비밀번호 변경은 현재 비밀번호를 아는 사용자가 본인 계정을 변경하는 흐름이고, Manager의 reset은 설치/운영 관리자가 `admin` 계정을 복구하거나 초기화하기 위한 패키징 레벨의 유지보수 기능입니다. 위험도가 높은 설정이므로 향후 운영 정책에 따라 Manager UI에서 제거하고 CLI 또는 recovery flow로만 남길 수 있습니다.

설치 후 Manager에서 바로 변경하는 범위와 별도 기능으로 분리해야 하는 범위는 아래처럼 구분합니다.

| 범위 | 처리 |
|---|---|
| CPU, memory, network, bridged interface | `vm-config.json` 갱신 후 restart |
| proxy port | proxy LaunchDaemon environment 갱신 후 restart |
| Vital files directory | VM shared directory와 guest runtime config 갱신 후 restart |
| public host/port, admin password reset | guest `runtime-config.json` 갱신 후 restart |
| start on boot | `launchctl enable/disable system/<label>`로 VM/proxy/watchdog 정책 갱신 |
| disk size | 별도 resize/migration flow 필요 |
| VM hostname | `seed.iso`/guest hostname 재생성 또는 guest migration flow 필요 |

rootfs base 교체는 이후 install/provisioning 기준 artifact를 바꾸는 동작입니다. 이미 생성된 `vm-disk.img` 내부에 새 rootfs를 자동 전개하지 않습니다.

Shell은 installer/launchd wrapper로만 남깁니다. Bundle manifest parsing, checksum 검증, backup, rollback 정책은 Swift runtime lifecycle command가 담당합니다.

남은 제품화 항목은 아래입니다.

| 항목 | 필요한 이유 |
|---|---|
| Developer ID signing | launchd/Virtualization binary 배포 신뢰성 확보 |
| notarization | Gatekeeper 환경에서 설치 마찰 감소 |

## Runtime Directory

PoC 기본 runtime directory는 아래입니다.

```text
~/.tirosh/vitalserver-vm/
  runtime/
    Image
    initrd.img
    vm-disk.img
    vm-config.json
    seed.iso
  data/
    deploy/
    vital-files/
    vr-release/
  logs/
  run/
```

repo 안에서만 테스트하려면:

```sh
VITALSERVER_VM_HOME="$PWD/.tmp/vitalserver-vm" make vm-init
```

## VM Config

기본 config 예시:

```json
{
  "cpuCount": 4,
  "diskPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/vm-disk.img",
  "initialRamdiskPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/initrd.img",
  "cloudInitPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/seed.iso",
  "kernelCommandLine": "console=hvc0 root=/dev/vda1 rw",
  "kernelPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/Image",
  "memoryMiB": 4096,
  "network": {
    "bridgedInterface": null,
    "macAddress": "52:12:34:56:78:9a",
    "mode": "shared"
  },
  "sharedDirectory": {
    "guestMountPath": "/mnt/tirosh",
    "hostPath": "/Users/<user>/.tirosh/vitalserver-vm/data",
    "readOnly": false,
    "tag": "tirosh"
  }
}
```

## Linux Boot Assets

PoC에서는 Git에 Linux image를 넣지 않습니다.

```sh
make vm-download
```

설정 파일:

```text
apps/vitalserver-vm-launcher/Support/Build/vm-build.toml
```

`make vm-download`는 build-machine 전용 Python package인
`packages/vm-build`의 `vitalserver-vm-build ubuntu` CLI를 호출합니다.

| 항목 | 기본값 |
|---|---|
| 배포판 | Ubuntu Server 24.04 LTS Noble cloud image |
| architecture | macOS host architecture 기준 자동 선택 |
| 다운로드 경로 | `~/.tirosh/vitalserver-vm/runtime/downloads/` |
| 실행 경로 | `~/.tirosh/vitalserver-vm/runtime/` |
| root disk target size | `8G` |

root disk 크기를 바꾸려면:

```sh
VM_ROOTFS_SIZE=32G make vm-download
```

Docker, nginx, qemu-user-static, VitalServer image build까지 PoC guest 안에서 실행하므로 Ubuntu cloud image의 기본 root disk 크기만으로는 부족합니다.

## Cloud-Init

NoCloud seed image를 생성합니다.

```sh
make vm-cloud-init
```

| 항목 | 기본값 |
|---|---|
| seed image | `~/.tirosh/vitalserver-vm/runtime/seed.iso` |
| hostname | `tirosh-vitalserver` |
| instance-id | 자동 생성 |
| user | `ubuntu` |
| password | `ubuntu` |
| SSH public key | `~/.ssh/id_ed25519.pub`가 있으면 자동 포함 |
| bootstrap | `/mnt/tirosh/deploy/bootstrap.sh` 자동 실행 |

기본값은 `apps/vitalserver-vm-launcher/Support/Build/vm-build.toml`의 `[cloud_init]`에서 관리합니다.
일회성 값을 바꾸려면 build CLI를 직접 호출합니다.

```sh
uv run --project packages/vm-build vitalserver-vm-build \
  --config apps/vitalserver-vm-launcher/Support/Build/vm-build.toml \
  cloud-init \
  --runtime-dir ~/.tirosh/vitalserver-vm/runtime \
  --hostname tirosh-vitalserver \
  --instance-id tirosh-site-a-001 \
  --username ubuntu \
  --password change-me \
  --ssh-key ~/.ssh/id_ed25519.pub
```

기본 password는 PoC 편의용입니다. 제품에서는 GUI 또는 first-run flow가 설치 대상별 credential을 생성해야 합니다.

## Guest Bootstrap

`make vm-stage`는 VM에서 실행할 deployment bundle을 공유 디렉터리에 복사합니다.

```sh
make vm-stage
```

| 항목 | 용도 |
|---|---|
| `bootstrap.sh` | Linux guest에서 Docker/nginx 설치 후 Compose 실행 |
| `compose.yaml` | VM 내부 VitalServer/Redis Compose stack |
| `nginx/vitalserver.conf` | VM 내부 nginx edge proxy 설정 |
| `runtime-config.json` | VitalServer container/runtime 설정 |
| `apps/vitalserver/docker` | VitalServer image build Dockerfile |
| `apps/vitalserver/runtime` | VitalServer runtime preload |
| `vendor/vitalserver/vitalserver-old` | upstream VitalServer source |

cloud-init은 첫 부팅 때 아래 명령을 자동 실행합니다.

```sh
sudo /mnt/tirosh/deploy/bootstrap.sh
```

bootstrap 순서:

1. VirtioFS 공유 디렉터리를 `/mnt/tirosh`에 mount
2. network time sync 대기
3. `docker.io`, `docker-compose-plugin`, `nginx` 설치
4. Apple Silicon Linux guest에서 `linux/amd64` container 실행을 위해 `qemu-user-static`, `binfmt-support` 설치
5. nginx를 port 80 edge proxy로 설정
6. bundled Docker image를 load하고 dangling image cleanup 수행
7. `docker compose up -d --build`로 VitalServer/Redis 실행
8. `tirosh-vitalserver-compose.service`를 등록해 VM 재부팅 후 Compose stack을 다시 적용
9. `tirosh-vitalserver-health`, `tirosh-vitalserver-diagnostics`, Redis backup timer를 설치

## macOS Data Sharing

Redis data는 VM 내부 Docker volume에 둡니다. VitalServer가 저장하는 `.vital` 파일은 macOS에서도 확인/백업할 수 있어야 하므로 host shared directory로 분리합니다.

```text
macOS:
  ~/.tirosh/vitalserver-vm/data/
    vital-files/
    vr-release/

Linux guest:
  /mnt/tirosh/
    vital-files/
    vr-release/
```

| 데이터 | 위치 |
|---|---|
| Redis `/data` | VM 내부 Docker volume |
| Vital 파일 | macOS shared directory |
| VR release 파일 | macOS shared directory |
| tmp upload 파일 | VM 내부 Docker volume |

## Network Mode

| 모드 | IP를 주는 곳 | 장점 | 한계 |
|---|---|---|---|
| `shared` | macOS Virtualization NAT DHCP | Apple restricted entitlement 없이 배포 가능, v1 기본값 | VM 자체는 병원 LAN IP를 받지 않음 |
| `bridged` | 병원 LAN DHCP | host nginx 없이 VM이 LAN에 직접 노출됨 | Apple 승인과 병원 네트워크 정책에 의존 |

v1 기본값은 `shared/NAT`입니다.

```text
VRecorder
  -> target Mac host nginx :80
      -> Linux VM shared/NAT
          -> VitalServer
```

host nginx 경유 시 VRecorder 원 IP 보존은 확인되었습니다. 따라서 v1에서는 VM이 병원 LAN IP를 직접 받을 필요가 없습니다.

bridged mode는 향후 host nginx 제거, 네트워크 구조 단순화, 또는 직접 LAN 노출이 필요한 경우의 옵션으로 둡니다. 제품 GUI에서는 `shared/NAT`를 기본값으로 두고, bridged는 entitlement와 병원망 조건을 만족할 때만 선택하게 하는 것이 안전합니다.

CLI에서 모드를 바꾸려면:

```sh
make vm-network-shared

make vm-interfaces
VM_BRIDGED_INTERFACE=en0 make vm-network-bridged
```

bridged mode 실행은 macOS가 제한하는 network entitlement가 필요합니다. 개발 중에는 shared/NAT mode는 ad-hoc signing으로 실행할 수 있지만, bridged mode는 실제 codesign identity와 entitlement가 준비되어야 합니다.

```sh
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

shared/NAT mode에서 보이는 `192.168.64.x` IP는 macOS Virtualization NAT DHCP가 부여한 IP입니다. 병원 LAN에서 VRecorder가 접근해야 하는 운영 IP가 아닙니다.

v1 운영에서는 사용자가 VM IP로 접속하지 않습니다. 사용자는 target Mac의 LAN IP 또는 host nginx가 노출하는 이름으로 접속합니다.

bridged mode가 활성화되면 VM은 병원 LAN DHCP에서 `172.x`, `10.x`, `192.168.x` 대역의 IP를 직접 받을 수 있습니다.

## Host Proxy

v1에서는 host nginx가 제품의 public edge입니다. VM은 shared/NAT 뒤에 있고, host nginx가 VM endpoint로 proxy합니다.

```text
public:
  http://<target Mac LAN IP>:80

upstream:
  http://<VM shared/NAT IP>:80
```

PoC에서는 VM IP를 확인한 뒤 아래처럼 host proxy upstream을 지정합니다.

```sh
make vm-up
```

`make vm-up`은 VM을 background로 시작하고, guest가 shared directory에 기록한 VM IP와 guest HTTP readiness를 기다린 뒤 host nginx upstream을 `<vm-ip>:80`으로 설정합니다.

VM IP만 확인하거나 proxy를 다시 붙이고 싶을 때는 아래 target을 사용합니다.

```sh
make vm-health
make vm-ip
make vm-proxy-start
```

`make vm-health`는 VM process, guest가 기록한 IP, VM 내부 HTTP, macOS host proxy HTTP를 한 번에 확인합니다. `502 Bad Gateway`처럼 경로 중간에서 막힐 때 가장 먼저 실행합니다.

기존 Docker Compose 개발 경로의 host proxy는 기본 upstream을 그대로 사용합니다.

```text
127.0.0.1:${VITALSERVER_HTTP_PORT}
```

host nginx는 trust boundary입니다. client가 보낸 forwarding header를 신뢰하지 않고, `$remote_addr`를 기준으로 `X-Forwarded-For`, `X-Real-IP`, `X-Client-IP`, `Forwarded`를 다시 설정합니다.

## DHCP Reservation

static IP를 기본값으로 두지 않습니다. 병원/회사망은 subnet이 제각각이고, 임의 static IP는 충돌을 만들 수 있습니다.

대신 VM MAC address를 고정하고 네트워크 장비에서 DHCP reservation을 설정하는 방식을 권장합니다.

```text
VM MAC address
  -> 병원 DHCP server reservation
      -> 고정된 VM LAN IP
```

`make vm-init`은 `runtime/vm-config.json`에 VM MAC address를 생성해 저장합니다. 이 값은 제품 설치 후 유지되어야 합니다.

## VM Identity

Golden image는 여러 병원과 여러 Mac mini/Mac Studio에 복제될 수 있으므로, 장비마다 달라야 하는 값은 image에 고정해서 넣지 않습니다.

| Identity | 언제 결정하나 | 어디에 보존하나 | 정책 |
|---|---|---|---|
| MAC address | 설치/초기화 시 | `runtime/vm-config.json` | 장비마다 다르게, 재설치 후에도 유지 |
| hostname | 설치/초기화 시 | `seed.iso` 또는 guest config | 사이트/장비를 구분할 수 있게 고유화 |
| cloud-init instance-id | `seed.iso` 생성 시 | `seed.iso` | VM마다 다르게 생성 |
| machine-id | guest 첫 부팅 시 | guest `/etc/machine-id` | golden image에서는 비워둠 |
| SSH host keys | guest 첫 부팅 시 | guest `/etc/ssh/` | golden image에서는 삭제 |
| TLS/cert identity | 설치 또는 등록 시 | host/guest secure storage | 장비별로 발급 |
| site/device id | 설치 또는 등록 시 | observer/app config | 관제 기준 식별자로 유지 |

공통으로 배포해도 되는 값은 OS, kernel, initrd, base rootfs, container image, compose/nginx template입니다.

Redis data, Vital 파일, bed/VR mapping 같은 runtime state는 image에 넣지 않고 운영 volume에만 저장합니다.

## Signing

v1 기본 구조인 `shared/NAT VM + host nginx`는 bridged networking entitlement 없이 진행합니다.

shared/NAT boot 테스트:

```sh
make vm-sign
```

bridged network 테스트는 별도 승인 이후에만 진행합니다.

```sh
make vm-sign-bridged
```

### Apple 승인 필요 항목

| 항목 | 용도 | v1 필수 여부 |
|---|---|---:|
| Apple Developer Program | Developer ID signing/notarization | 필요 |
| Developer ID Application certificate | `.pkg`/`.dmg` 배포용 signing | 필요 |
| `com.apple.security.virtualization` | Virtualization Framework로 VM 실행 | 필요 |
| notarization | 외부 배포 시 Gatekeeper 통과 | 필요 |
| `com.apple.vm.networking` | bridged networking | v1 필수 아님 |

`com.apple.vm.networking`은 Apple의 restricted entitlement입니다. Apple 문서상 virtualization software 개발자에게 제한되며, Apple representative를 통해 요청해야 합니다.

이 승인이 없으면 bridged mode는 제품 기능으로 제공하지 않습니다. v1은 host nginx로 VRecorder 원 IP를 보존하므로 bridged entitlement 승인을 기다리지 않고 패키징을 진행할 수 있습니다.

## PoC Checklist

- shared mode에서 VM이 boot된다.
- cloud-init이 seed를 인식한다.
- guest bootstrap이 자동 실행된다.
- VitalServer/Redis container가 healthy가 된다.
- host nginx가 target Mac port 80에서 요청을 받는다.
- host nginx가 VM 내부 VitalServer로 proxy한다.
- guest가 VM IP를 shared directory에 기록한다.
- `make vm-up`이 VM IP를 기다린 뒤 host proxy upstream을 VM으로 설정한다.
- host nginx 경유 요청에서 VRecorder 원 IP가 보존된다.
- Redis `ip_<vrcode>`에 실제 VRecorder IP가 저장된다.
- Network Settings가 실제 VRecorder IP로 열린다.
- `make vm-bridged-preflight`가 bridged signing 조건을 설명한다.

bridged mode는 별도 승인 이후 체크합니다.

- `make vm-interfaces`로 bridged 후보 interface가 보인다.
- bridged mode에서 VM이 boot된다.
- VM이 DHCP로 병원 LAN IP를 받는다.
- 다른 장비에서 VM IP로 접속할 수 있다.

## Troubleshooting

이번 PoC를 진행하면서 확인한 문제와 조치입니다.

### `make vm-start`가 boot asset 없음으로 실패

증상:

```text
error: missing file: .../runtime/Image
```

원인:

`vitalserver-vm start`는 VM만 실행합니다. Linux kernel, initrd, root disk, cloud-init seed가 없으면 시작할 수 없습니다.

조치:

```sh
make vm-prepare
make vm-start
```

또는 한 번에:

```sh
make vm-up
```

### VM IP가 `192.168.64.x`로 보임

증상:

cloud-init log에 아래처럼 표시됩니다.

```text
Address 192.168.64.3
Gateway 192.168.64.1
```

원인:

shared/NAT mode에서는 macOS Virtualization NAT DHCP가 VM IP를 부여합니다. 이 IP는 병원 LAN DHCP에서 받은 IP가 아닙니다.

조치:

v1 구조에서는 정상입니다. 사용자는 이 VM IP로 직접 접속하지 않고, target Mac host nginx로 접속합니다.

```text
VRecorder
  -> http://<target Mac LAN IP>/
      -> host nginx
      -> VM shared/NAT IP
```

host nginx를 경유하면 VRecorder 원 IP 보존이 가능합니다.

VM이 병원 LAN IP를 직접 받는 구조를 검증하려면 bridged mode를 사용합니다.

```sh
make vm-interfaces
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

### bridged mode가 `Killed: 9`로 종료됨

증상:

```text
VITALSERVER_VM_HOME=... vitalserver-vm network bridged "en0"
make: *** [vm-network-bridged] Killed: 9
```

원인:

`com.apple.vm.networking` entitlement가 들어간 바이너리를 ad-hoc signing으로 실행하면 macOS가 프로세스를 시작 직후 종료할 수 있습니다. 이 entitlement는 shared/NAT boot smoke test용 `com.apple.security.virtualization`보다 더 제한적입니다.

확인:

```sh
security find-identity -v -p codesigning
codesign -d --entitlements - apps/vitalserver-vm-launcher/.build/release/vitalserver-vm
```

현재 개발 PC에 유효한 codesign identity가 없으면 bridged mode까지 진행할 수 없습니다.

조치:

```sh
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

`make vm-bridged-preflight`는 이 조건을 먼저 확인합니다. codesign identity가 없는 환경에서는 `Killed: 9` 대신 설명 가능한 오류로 중단합니다.

### `docker.io` 설치 중 `No space left on device`

증상:

```text
cannot copy extracted data ... failed to write (No space left on device)
```

원인:

Ubuntu cloud image의 기본 root disk는 Docker, nginx, qemu-user-static, VitalServer image build까지 수행하기에 작습니다.

조치:

`make vm-download`는 VM disk를 기본 `8G`로 확장합니다. 더 크게 만들려면:

```sh
VM_ROOTFS_SIZE=32G make vm-download
```

이미 디스크 부족으로 망가진 PoC runtime은 재생성합니다.

```sh
make vm-clean
make vm-prepare
```

### `apt-get update`가 Release file 시간 오류로 실패

증상:

```text
Release file ... is not valid yet
```

원인:

VM 첫 부팅 직후 guest 시간이 실제 시간보다 과거일 수 있습니다. cloud-init final 단계가 package install을 먼저 시작하면 apt repository metadata 시간이 미래처럼 보입니다.

조치:

`Support/Guest/bootstrap.sh`는 `apt-get update` 전에 `systemd-timesyncd`를 재시작하고 NTP 동기화를 기다립니다.

수동 확인:

```sh
timedatectl
timedatectl show -p NTPSynchronized --value
```

### cloud-init이 bootstrap을 다시 실행하지 않음

증상:

`seed.iso`를 다시 만들어도 `/mnt/tirosh/deploy/bootstrap.sh`가 실행되지 않습니다.

원인:

cloud-init은 `instance-id`를 기준으로 이미 처리한 instance인지 판단합니다. 같은 instance-id를 재사용하면 초기화 스크립트를 다시 실행하지 않을 수 있습니다.

조치:

`make vm-cloud-init`은 기본적으로 새 instance-id를 생성합니다. 수동으로 지정하려면:

```sh
uv run --project packages/vm-build vitalserver-vm-build \
  --config apps/vitalserver-vm-launcher/Support/Build/vm-build.toml \
  cloud-init \
  --runtime-dir ~/.tirosh/vitalserver-vm/runtime \
  --instance-id tirosh-site-a-001
```

### nginx가 `502 Bad Gateway`를 반환

증상:

```sh
curl -I http://<vm-ip>/
```

결과가 `502 Bad Gateway`입니다.

원인:

VM 내부 nginx는 `127.0.0.1:18080`의 VitalServer container로 proxy합니다. app container가 아직 healthy가 아니거나 HTTP worker가 뜨지 않으면 502가 납니다.

확인:

```sh
ssh ubuntu@<vm-ip> 'sudo docker ps'
ssh ubuntu@<vm-ip> 'sudo docker logs --tail 120 vitalserver-app-1'
ssh ubuntu@<vm-ip> 'curl -I http://127.0.0.1:18080/'
```

이번 PoC에서는 `VITALSERVER_MIN_CPUS=6` 때문에 upstream VitalServer가 worker를 0개만 만들었습니다.

```js
numCPUs = os.cpus().length - 6
```

worker가 없으면 master process만 살아 있고 HTTP listener가 없어 nginx가 502를 냅니다.

조치:

`VITALSERVER_MIN_CPUS` 기본값을 `8`로 두어 최소 worker 2개가 뜨게 했습니다.

정상 로그:

```text
worker:1 is forked
worker:2 is forked
worker:1 is listening
worker:2 is listening
```

정상 응답:

```text
HTTP/1.1 302 Found
Location: /check
```

### app container가 오래 `health: starting` 상태

증상:

```text
vitalserver-app-1   Up ... (health: starting)
```

### Ubuntu arm64 cloud image에서 `flash-kernel`이 실패

증상:

```text
Unsupported platform ''.
dpkg: error processing package flash-kernel (--configure)
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

원인:

Ubuntu arm64 cloud image에는 `flash-kernel`이 포함될 수 있습니다. 하지만 이 VM은 Apple Virtualization launcher가 macOS에서 kernel/initrd를 직접 지정해 부팅하므로 guest 안의 `flash-kernel`이 필요하지 않습니다. 해당 hook이 실행되면 현재 VM platform을 인식하지 못하고 apt/dpkg 흐름을 막을 수 있습니다.

조치:

guest `bootstrap.sh`에서 `flash-kernel` hook을 비활성화하고 `flash-kernel` 패키지를 제거한 뒤 `dpkg --configure -a`로 package state를 복구합니다.

원인:

Apple Silicon Linux guest에서 VitalServer는 `linux/amd64` Node 12 image를 qemu-user-static으로 실행합니다. 첫 build/pull 직후에는 시작이 느릴 수 있습니다.

확인:

```sh
ssh ubuntu@<vm-ip> 'sudo docker inspect -f "{{json .State.Health}}" vitalserver-app-1'
ssh ubuntu@<vm-ip> 'sudo docker logs --tail 120 vitalserver-app-1'
```

worker가 `listening` 상태까지 갔는지 확인합니다.

### `make vm-status`가 stale pid file을 표시

증상:

```text
stale pid file: .../run/vitalserver-vm.pid
```

원인:

VM process가 이미 종료되었지만 pid file이 남아 있습니다. sandbox 안에서 실행하면 `~/.tirosh` 아래 pid file 삭제가 막혀 stale이 계속 보일 수 있습니다.

조치:

일반 shell에서 다시 실행하면 stale pid file이 정리됩니다.

```sh
make vm-status
make vm-status
```

첫 번째 호출에서 stale을 감지하고, 두 번째 호출에서 `stopped`가 보여야 합니다.

## Code Structure

```text
Sources/VitalServerVMLauncher/
  main.swift

  CLI/
    Command.swift
    Launcher.swift
    LauncherError.swift

  Runtime/
    Constants.swift
    LauncherPaths.swift
    ProcessState.swift

  VirtualMachine/
    VMRuntimeConfig.swift
    VMConfigurationFactory.swift
    VirtualMachineDelegate.swift
```

## References

- Apple Developer: Running Linux in a Virtual Machine
- Apple Developer: `VZVirtualMachineConfiguration`
- Apple Developer: `VZBridgedNetworkDeviceAttachment`
