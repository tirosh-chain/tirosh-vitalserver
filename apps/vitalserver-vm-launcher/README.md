# VitalServer VM Launcher

`vitalserver-vm-launcher`는 Apple Virtualization Framework로 Linux VM을 실행하는 PoC입니다.

목표는 Mac mini에서 Linux VM을 직접 띄우고, macOS host nginx를 통해 VM 내부 VitalServer를 운영할 수 있는지 검증하는 것입니다.

```text
Mac mini
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
| `make vm-airgap-rootfs` | 온라인 빌드 환경에서 rootfs에 Docker/nginx/Compose 설치 |
| `make vm-pkg` | VM runtime, boot asset, guest bundle, host proxy launcher를 `.pkg`로 묶기 |
| `make vm-app` | runtime `.pkg`를 포함한 macOS control app 생성 |
| `make vm-pkg-install` | 생성된 개발용 `.pkg`를 설치 |
| `make vm-pkg-uninstall-dev` | 개발용 설치물을 제거 |
| `make vm-installed-health` | 설치된 launchd VM/proxy 상태와 HTTP 확인 |

## Package

제품 목표는 Mac mini에 설치 가능한 `.pkg`입니다. 현재 `make vm-pkg`는 개발 검증용 package를 만듭니다.

```sh
make vm-pkg
```

생성물:

```text
.tmp/TiroshVitalServerVM-0.1.0.pkg
```

이 package는 아래 항목을 설치합니다.

| 항목 | 설치 위치 |
|---|---|
| VM launcher | `/usr/local/bin/vitalserver-vm` |
| host proxy runner | `/usr/local/bin/vitalserver-proxy-run` |
| uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| nginx bundle | `/Library/Application Support/TiroshVitalServer/nginx/` |
| Linux boot assets | `/Library/Application Support/TiroshVitalServer/vm/images/` |
| guest deployment bundle | `/Library/Application Support/TiroshVitalServer/vm/data/deploy/` |
| Docker image bundle | `/Library/Application Support/TiroshVitalServer/vm/data/deploy/docker-images/` |
| nginx config template | `/Library/Application Support/TiroshVitalServer/vm/Support/Proxy/` |
| LaunchDaemons | `/Library/LaunchDaemons/com.tirosh.vitalserver-*.plist` |

shared/NAT mode에서는 VM IP가 부팅 후에 결정되므로, `vitalserver-proxy-run`이 VM IP 파일을 기다린 뒤 host nginx config를 렌더링하고 proxy를 실행합니다.

`rootfs.raw`는 package에 그대로 넣지 않고 `rootfs.raw.gz`로 묶습니다. 설치 시 `postinstall`이 다시 `rootfs.raw`로 풀어 VM disk로 사용합니다.

`make vm-pkg`는 Docker registry 없이도 container를 시작할 수 있도록 `vitalserver`, `redis`, `redis-ui`, `swagger-ui` image를 `vitalserver-images.tar.gz`로 묶어 포함합니다. Guest bootstrap은 이 bundle을 먼저 `docker load`한 뒤 Compose를 실행합니다.

완전한 air-gapped 설치물을 만들려면 `.pkg` 생성 전에 온라인 빌드 환경에서 아래를 한 번 실행해 `rootfs.raw`에 Docker, Docker Compose, nginx, qemu-user-static을 미리 설치합니다.

```sh
VM_RECREATE_ROOTFS=true make vm-download
make vm-airgap-rootfs
make vm-pkg
```

기본 package용 rootfs는 8GB입니다. 설치 후에는 wizard의 Disk size 설정에 맞춰 VM disk 파일을 확장합니다. 설치된 VM은 부팅 시 필요한 guest package가 이미 있으면 `apt-get` 단계를 건너뜁니다.

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

설치된 Mac mini에서 사용자가 직접 제거할 때는:

```sh
sudo tirosh-vitalserver-uninstall
```

이 명령은 VM/proxy LaunchDaemon을 내리고, 설치된 runtime 파일을 제거합니다.

`make vm-nginx-bundle`은 nginx가 참조하는 Homebrew `pcre2`, `openssl` dylib를 package 내부 `nginx/lib`로 복사하고, nginx load path를 `@executable_path/../lib`로 바꿉니다. 운영 Mac mini에 Homebrew가 없어도 host proxy가 실행되는 방향입니다.

현재는 build machine의 nginx binary를 번들링합니다. 제품용으로는 nginx build version과 configure option을 고정한 release artifact로 관리해야 합니다.

## Control App

사용자용 진입점은 `.app`입니다.

```sh
make vm-app
open ".tmp/Tirosh VitalServer Manager.app"
```

개발용 app은 내부 Resources에 runtime `.pkg`와 uninstaller를 포함합니다.

```text
Tirosh VitalServer Manager.app
  Contents/MacOS/Tirosh VitalServer Manager
  Contents/Resources/TiroshVitalServerVM.pkg
  Contents/Resources/tirosh-vitalserver-uninstall
```

앱에서 제공하는 기능은 아래입니다.

| 기능 | 내부 동작 |
|---|---|
| Install Runtime | 설치 Wizard에서 CPU/RAM/disk/network/service 설정을 받고 bundled `.pkg`를 관리자 권한으로 설치 |
| Health Check | VM IP, guest HTTP, host proxy HTTP 확인 |
| Open VitalServer | `http://127.0.0.1/` 열기 |
| Uninstall | 설치된 uninstaller 또는 bundled uninstaller 실행 |

CPU는 VitalServer 내부 동작 조건 때문에 7 vCPU 이상만 허용하고, Mac mini 운영 기본값은 8 vCPU입니다.

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
vitalserver-vm clean
vitalserver-vm version
```

아직 제품 기능은 아닙니다.

- codesign/notarization 제품화
- offline VM image build pipeline
- nginx release artifact 고정
- VM image 업데이트

## 참고 문서

- [VitalServer VM Launcher 문서](../../docs/vitalserver-vm-launcher.md)
- [macOS host proxy ADR](../../docs/adr/0001-macos-host-proxy-for-vrecorder-ip.md)
