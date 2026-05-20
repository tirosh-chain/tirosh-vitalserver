# VitalServer VM Launcher

`vitalserver-vm-launcher`는 Apple Virtualization Framework로 Linux VM을 직접 실행하는 PoC입니다.

이 PoC의 목적은 Mac mini에서 Linux VM을 운영 서버처럼 띄우고, 그 안에서 `systemd + nginx + Docker Compose`로 VitalServer를 24/7 운영할 수 있는지 검증하는 것입니다.

최종 배포 목표는 병원 Mac mini에 설치 가능한 self-contained `.pkg`입니다. 운영 환경은 air-gapped 환경까지 고려하므로, 설치 대상 Mac mini가 `brew`, Docker Desktop, OrbStack, 외부 apt repository, 외부 image registry에 의존하지 않는 형태가 목표입니다.

```text
Mac mini
  -> vitalserver-vm-launcher
      -> Linux VM
          -> nginx
          -> Docker Compose
              - vitalserver
              - redis
              - vitaldb-observer
```

## 왜 필요한가

macOS의 Docker Desktop/OrbStack container는 macOS kernel에서 직접 실행되지 않고 내부 Linux VM을 거칩니다.
그래서 Docker의 `network_mode: host`를 써도 Mac mini의 물리 NIC를 직접 공유하지 않습니다.

VRecorder 원본 IP를 안정적으로 보존하려면 다음 둘 중 하나가 필요합니다.

- macOS host에서 nginx proxy를 실행한다.
- Linux VM이 병원 LAN에서 독립 IP를 받고, VM 내부 nginx가 public edge가 된다.

이 launcher는 두 번째 방법을 제품화할 수 있는지 확인하기 위한 실험입니다.

## 현재 범위

지원하는 명령:

```sh
vitalserver-vm init
vitalserver-vm start
vitalserver-vm stop
vitalserver-vm status
vitalserver-vm interfaces
vitalserver-vm clean
vitalserver-vm version
```

아직 포함하지 않는 것:

- 완성형 `.pkg`
- GUI 앱
- codesign/notarization 제품화
- VM image 업데이트

중요: 현재 `make vm-download`와 Support/Guest `bootstrap.sh`는 **개발/PoC용**입니다. 최종 `.pkg`에는 이미 준비된 `Image`, `initrd.img`, `rootfs.raw`와 VM 내부 runtime이 포함되어야 합니다.

## 배포 모델

### 개발/빌드 환경

개발자 또는 CI가 Linux image를 준비합니다.

```text
download Ubuntu cloud image
  -> convert root disk to raw
  -> install docker/nginx/compose inside rootfs
  -> preload required container images
  -> install systemd units
  -> build signed/notarized macOS pkg
```

이 단계에서는 `qemu-img`, image customization 도구, 네트워크 접근이 필요할 수 있습니다.

### 설치 대상 Mac mini

병원 Mac mini는 `.pkg`만 설치합니다.

```text
TiroshVitalServer.pkg
  -> /usr/local/bin/vitalserver-vm
  -> /Library/Application Support/Tirosh/VitalServer/images/
       Image
       initrd.img
       rootfs.raw
  -> /Library/Application Support/Tirosh/VitalServer/data/
       vital-files/
       vr-release/
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist
```

설치 대상 Mac mini에는 다음 의존성이 없어야 합니다.

| 의존성 | 운영 Mac mini 필요 여부 |
|---|---|
| Homebrew | 필요 없음 |
| `qemu-img` | 필요 없음 |
| Docker Desktop | 필요 없음 |
| OrbStack | 필요 없음 |
| brew nginx | 필요 없음 |
| 외부 apt repository | 필요 없음 |
| 외부 container registry | 필요 없음 |

### GUI 설정

`.pkg` 자체는 풍부한 설정 UI를 제공하기에 적합하지 않습니다. 제품으로는 `.dmg` 안에 GUI 앱을 제공하고, 그 앱이 설정을 만든 뒤 privileged install 또는 bundled `.pkg` 설치를 실행하는 구조가 더 안전합니다.

권장 UX:

```text
TiroshVitalServer.dmg
  -> Tirosh VitalServer.app
      -> VM spec 설정
      -> network mode 설정
      -> bridged interface 선택
      -> DHCP reservation용 MAC 표시
      -> cloud-init user/SSH key/bootstrap 설정
      -> pkg install 또는 launchd service 등록
```

설정 결과물:

| 설정 | 저장 위치 |
|---|---|
| VM CPU/RAM/kernel/disk/network/MAC | `config.json` |
| cloud-init user/hostname/SSH key/bootstrap | `seed.iso` |
| VitalServer container 환경변수 | deploy `.env` |
| 서비스 자동 실행 | LaunchDaemon plist |

즉 GUI는 VM을 직접 “마법처럼” 만들기보다, 이 파일들을 안전하게 생성/수정하는 설정 도구가 됩니다.

### VM 내부

VM 내부에는 이미 다음이 준비되어 있어야 합니다.

| 항목 | 목적 |
|---|---|
| Linux kernel/initrd/rootfs | Apple Virtualization Framework boot |
| systemd service | 부팅 시 VitalServer stack 자동 실행 |
| nginx | VM port 80 edge proxy |
| Docker Engine 또는 호환 runtime | VitalServer/Redis container 실행 |
| Docker Compose plugin 또는 동등 실행 스크립트 | stack orchestration |
| VitalServer image | offline container 실행 |
| Redis image | offline container 실행 |
| guest deploy bundle | compose/nginx/config 파일 |

## 요구사항

- macOS 13 이상
- Swift 6 이상
- Linux kernel, initramfs, writable root disk image
- shared/NAT boot: `com.apple.security.virtualization` entitlement
- bridged network: `com.apple.vm.networking` entitlement

`com.apple.vm.networking`은 bridged network에 필요합니다. ad-hoc signing으로는 macOS가 실행을 막을 수 있으므로, bridged 검증은 제품 signing profile에서 entitlement를 확보한 뒤 진행해야 합니다.

## 폴더 구조

```text
apps/vitalserver-vm-launcher/
  Sources/                 Swift launcher source
  Support/
    Build/                 macOS 개발/빌드 머신에서 실행하는 image 준비 도구
    Guest/                 Linux guest 안에 배포되는 bootstrap/compose/nginx 파일
  launchd/                 macOS LaunchDaemon template
  Entitlements*.plist      signing entitlement
```

기준:

- `Sources/`는 macOS launcher 코드만 둡니다.
- `Support/Build/`는 `.pkg` 또는 VM image를 만들기 전 개발/CI 단계에서 쓰는 도구를 둡니다.
- `Support/Guest/`는 VM 내부 `/mnt/tirosh/deploy`로 stage되는 파일만 둡니다.
- 설치 대상 Mac mini에서 직접 실행하지 않을 도구는 `Support/Build/` 아래에 둡니다.

## PoC 실행 흐름

처음 검증할 때는 아래 흐름만 보면 됩니다.

```sh
make vm-prepare
make vm-start
```

한 번에 실행하고 싶다면:

```sh
make vm-up
```

VM이 부팅되면 cloud-init이 `/mnt/tirosh`를 mount하고 `deploy/bootstrap.sh`를 자동 실행합니다.

정지:

```sh
make vm-down
```

상태 확인:

```sh
make vm-status
```

`make vm-prepare`는 내부적으로 다음을 수행합니다.

1. `vitalserver-vm` 빌드
2. Ubuntu boot asset 다운로드
3. `rootfs.raw` 변환
4. cloud-init seed image 생성
5. VM runtime directory 초기화
6. guest deployment bundle staging

## 세부 명령

```sh
make vm-build
make vm-init
make vm-download
make vm-cloud-init
make vm-stage
```

위 명령들은 보통 직접 실행하지 않고 `make vm-prepare`가 호출합니다.

현재 일부 macOS Command Line Tools 환경에서 기본 SDK가 Swift toolchain과 맞지 않을 수 있어 `make/vm.mk`는 우선 `MacOSX15.4.sdk`를 사용하도록 잡아두었습니다.

## 서명

shared/NAT boot 테스트용:

```sh
make vm-sign
```

bridged network 테스트용:

```sh
make vm-sign-bridged
```

`make vm-sign-bridged` 후 실행 파일이 즉시 종료된다면 현재 signing identity가 `com.apple.vm.networking`을 사용할 수 없는 상태입니다. 그 경우 shared mode로 먼저 boot PoC를 진행합니다.

### 초기화

```sh
make vm-init
```

기본 runtime directory:

```text
~/.tirosh/vitalserver-vm/
  config.json
  images/
  data/
    vital-files/
    vr-release/
  logs/
  run/
```

repo 안에서만 테스트하고 싶다면:

```sh
VITALSERVER_VM_HOME="$PWD/.tmp/vitalserver-vm" make vm-init
```

생성되는 기본 config:

```json
{
  "cpuCount": 4,
  "diskPath": "/Users/<user>/.tirosh/vitalserver-vm/images/rootfs.raw",
  "initialRamdiskPath": "/Users/<user>/.tirosh/vitalserver-vm/images/initrd.img",
  "cloudInitPath": "/Users/<user>/.tirosh/vitalserver-vm/images/seed.iso",
  "kernelCommandLine": "console=hvc0 root=/dev/vda1 rw",
  "kernelPath": "/Users/<user>/.tirosh/vitalserver-vm/images/Image",
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

### Linux boot asset 다운로드

Git에는 Linux image를 넣지 않습니다. `make vm-download`는 개발/PoC용으로 로컬 VM runtime directory에만 다운로드합니다. 최종 `.pkg`에서는 이 다운로드가 설치 대상 Mac mini에서 실행되면 안 됩니다.

```sh
make vm-download
```

다운로드 설정은 아래 파일에서 관리합니다.

```text
apps/vitalserver-vm-launcher/Support/Build/ubuntu-cloud-image.env
```

기본값:

| 항목 | 값 |
|---|---|
| 배포판 | Ubuntu Server 24.04 LTS Noble cloud image |
| 설정 파일 | `apps/vitalserver-vm-launcher/Support/Build/ubuntu-cloud-image.env` |
| 다운로드 경로 | `~/.tirosh/vitalserver-vm/images/downloads/` |
| 실행 경로 | `~/.tirosh/vitalserver-vm/images/` |
| architecture | macOS host architecture 기준 자동 선택 |

생성되는 실행 파일:

```text
~/.tirosh/vitalserver-vm/images/
  Image
  initrd.img
  rootfs.raw
```

root disk는 Ubuntu cloud image의 `.img`를 받은 뒤 `qemu-img`로 raw image로 변환합니다. macOS에서 `qemu-img`가 없으면 먼저 설치합니다.

```sh
brew install qemu
```

다운로드 URL을 바꾸고 싶다면:

```sh
VM_UBUNTU_CONFIG=/path/to/ubuntu-cloud-image.env make vm-download
```

다운로드 출력 경로를 바꾸고 싶다면:

```sh
VM_IMAGE_DIR=/path/to/images make vm-download
```

root disk 크기를 바꾸고 싶다면:

```sh
VM_ROOTFS_SIZE=32G make vm-download
```

기본값은 `16G`입니다. Docker, nginx, qemu-user-static, VitalServer image build까지 PoC guest 안에서 실행하므로 Ubuntu cloud image의 기본 root disk 크기만으로는 부족합니다.

주의: `make vm-download`는 runtime `config.json`을 만들지 않습니다. 다운로드/변환은 빌드 단계 작업이고, `config.json`과 VM MAC address는 설치 대상 또는 PoC runtime에서 `make vm-init`이 생성해야 합니다.

### cloud-init seed 생성

PoC cloud image에 로그인할 수 있도록 NoCloud seed image를 만듭니다.

```sh
make vm-cloud-init
```

기본값:

| 항목 | 값 |
|---|---|
| seed image | `~/.tirosh/vitalserver-vm/images/seed.iso` |
| hostname | `tirosh-vitalserver` |
| instance-id | 자동 생성 |
| user | `ubuntu` |
| password | `ubuntu` |
| SSH public key | `~/.ssh/id_ed25519.pub`가 있으면 자동 포함 |
| bootstrap | `/mnt/tirosh/deploy/bootstrap.sh` 자동 실행 |

값을 바꾸고 싶다면:

```sh
VM_CLOUD_INIT_HOSTNAME=tirosh-vitalserver \
VM_CLOUD_INIT_INSTANCE_ID=tirosh-site-a-001 \
VM_CLOUD_INIT_USER=ubuntu \
VM_CLOUD_INIT_PASSWORD=change-me \
VM_CLOUD_INIT_SSH_KEY=~/.ssh/id_ed25519.pub \
make vm-cloud-init
```

bootstrap 자동 실행을 끄고 cloud-init seed만 만들고 싶다면:

```sh
VM_CLOUD_INIT_RUN_BOOTSTRAP=false make vm-cloud-init
```

주의: 기본 password는 PoC 편의용입니다. 제품 `.pkg`에서는 GUI 또는 first-run flow가 설치 대상별 credential을 생성해야 합니다.

### Linux guest 배포 준비

VM 안에서 VitalServer container를 실행하려면 macOS에서 먼저 배포 번들을 공유 디렉터리에 준비합니다. 이 흐름도 개발/PoC용입니다. air-gapped `.pkg`에서는 rootfs 안에 systemd service와 runtime dependency가 미리 들어 있어야 합니다.

```sh
make vm-stage
```

`make vm-stage`는 다음 내용을 `~/.tirosh/vitalserver-vm/data/deploy/` 아래로 복사합니다.

| 항목 | 용도 |
|---|---|
| `bootstrap.sh` | Linux guest에서 Docker/nginx 설치 후 Compose 실행 |
| `compose.yaml` | VM 내부 VitalServer/Redis Compose stack |
| `nginx/vitalserver.conf` | VM 내부 nginx edge proxy 설정 |
| `.env` | VitalServer container 환경변수 |
| `apps/vitalserver/docker` | VitalServer image build Dockerfile |
| `apps/vitalserver/runtime` | VitalServer runtime preload |
| `vendor/vitalserver/vitalserver-old` | upstream VitalServer source |

`make vm-prepare`로 cloud-init seed를 만든 경우 Linux guest 첫 부팅 때 아래 명령이 자동으로 실행됩니다.

```sh
sudo /mnt/tirosh/deploy/bootstrap.sh
```

이 스크립트는 다음 순서로 동작합니다.

1. VirtioFS 공유 디렉터리를 `/mnt/tirosh`에 mount
2. `docker.io`, `docker-compose-plugin`, `nginx` 설치
3. Apple Silicon Linux guest에서 `linux/amd64` container 실행을 위해 `qemu-user-static`, `binfmt-support` 설치
4. nginx를 port 80 edge proxy로 설정
5. `docker compose up -d --build`로 VitalServer/Redis 실행

목표 구조:

```text
VRecorder
  -> Linux VM:80
      -> nginx
          -> 127.0.0.1:18080
              -> VitalServer container:80
```

nginx는 `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`를 VitalServer container로 전달합니다. VitalServer container는 `VITALSERVER_TRUST_PROXY=1`로 실행됩니다.

## macOS 데이터 공유

Redis 데이터는 VM 내부 Docker volume에 두는 것이 좋습니다. 반면 VitalServer가 저장하는 `.vital` 파일은 macOS에서도 확인/백업할 수 있어야 하므로 host shared directory로 분리합니다.

기본 공유 경로:

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

`vitalserver-vm`은 Apple Virtualization Framework의 VirtioFS 장치를 사용해 `sharedDirectory.hostPath`를 guest에 노출합니다. guest 안에서는 아래처럼 mount합니다.

```sh
sudo mkdir -p /mnt/tirosh
sudo mount -t virtiofs tirosh /mnt/tirosh
```

Linux VM 내부 Compose에서는 named volume 대신 bind mount를 사용합니다.

```yaml
services:
  app:
    volumes:
      - type: bind
        source: /mnt/tirosh/vital-files
        target: /opt/vitalserver/vital_files
      - type: bind
        source: /mnt/tirosh/vr-release
        target: /opt/vitalserver/service/vr_release
      - type: volume
        source: vital-tmp-files
        target: /opt/vitalserver/service/tmp_files
```

권장 분리:

| 데이터 | 위치 |
|---|---|
| Redis `/data` | VM 내부 Docker volume |
| Vital 파일 | macOS shared directory |
| VR release 파일 | macOS shared directory |
| tmp upload 파일 | VM 내부 Docker volume |

## 네트워크 모드

운영 기본값은 다음 방향으로 가져갑니다.

| 항목 | 기본 정책 |
|---|---|
| network mode | bridged 권장, shared/NAT는 fallback |
| VM IP | VM 내부 DHCP |
| IP 고정 | 병원/공유기 DHCP reservation 권장 |
| VM MAC address | `config.json`에 생성 후 영구 저장 |
| 사용자 접근 | VM IP 표시 + mDNS/Bonjour 보조 |
| static IP | advanced option으로만 제공 |

핵심은 static IP를 기본값으로 두지 않는 것입니다. 병원/회사망은 `192.168.0.x`, `192.168.1.x`, `10.x.x.x`, `172.x.x.x`처럼 subnet이 제각각이고, 임의 static IP는 충돌을 만들 수 있습니다. 대신 VM의 MAC address를 고정하고 네트워크 장비에서 DHCP reservation을 설정하는 방식이 운영상 가장 안전합니다.

### 고정 MAC address

`make vm-init`은 `config.json`에 VM MAC address를 생성해 저장합니다.

```json
"network": {
  "mode": "bridged",
  "bridgedInterface": "en0",
  "macAddress": "52:12:34:56:78:9a"
}
```

이 값은 DHCP reservation의 기준이므로 제품 설치 후 유지되어야 합니다.

```text
52:12:34:56:78:9a -> 192.168.0.50
```

주의:

- `vm-clean`은 PoC용이라 `config.json`을 삭제합니다.
- 제품 `.pkg`에서는 config와 MAC address 보존 정책을 별도로 가져가야 합니다.
- VM을 새로 만들더라도 같은 `macAddress`를 유지해야 DHCP reservation이 깨지지 않습니다.

### VM identity

Golden image는 여러 병원과 여러 Mac mini에 복제될 수 있으므로, 장비마다 달라야 하는 값은 image에 고정해서 넣지 않습니다.

| Identity | 언제 결정하나 | 어디에 보존하나 | 정책 |
|---|---|---|---|
| MAC address | 설치/초기화 시 | `config.json` | 장비마다 다르게, 재설치 후에도 유지 |
| hostname | 설치/초기화 시 | `seed.iso` 또는 guest config | 사이트/장비를 구분할 수 있게 고유화 |
| cloud-init instance-id | `seed.iso` 생성 시 | `seed.iso` | VM마다 다르게 생성 |
| machine-id | guest 첫 부팅 시 | guest `/etc/machine-id` | golden image에서는 비워둠 |
| SSH host keys | guest 첫 부팅 시 | guest `/etc/ssh/` | golden image에서는 삭제 |
| TLS/cert identity | 설치 또는 등록 시 | host/guest secure storage | 장비별로 발급 |
| site/device id | 설치 또는 등록 시 | observer/app config | 관제 기준 식별자로 유지 |

공통으로 배포해도 되는 값은 OS, kernel, initrd, base rootfs, container image, compose/nginx template입니다. Redis data, Vital 파일, bed/VR mapping 같은 runtime state는 image에 넣지 않고 운영 volume에만 저장합니다.

### DHCP reservation

운영 설치에서는 VM 내부는 DHCP로 두고, 병원 네트워크 장비에서 예약 IP를 설정하는 방식을 권장합니다.

```text
VM MAC address
  -> 병원 DHCP server reservation
      -> 고정된 VM LAN IP
```

장점:

- subnet이 바뀌어도 VM 설정을 바꿀 필요가 적음
- IP 충돌 가능성이 낮음
- 병원/회사 네트워크 정책과 맞추기 쉬움

단점:

- 병원 네트워크 관리자 또는 공유기 설정 권한이 필요함

### mDNS/Bonjour

PoC guest bootstrap은 `avahi-daemon`을 설치하고 hostname을 기본 `tirosh-vitalserver`로 설정합니다. 네트워크에서 mDNS가 허용되면 아래 이름으로 접근할 수 있습니다.

```text
tirosh-vitalserver.local
```

mDNS는 사용자가 IP를 외우지 않아도 되는 편의 기능입니다. 다만 병원/회사망에서는 mDNS가 차단될 수 있으므로, 항상 DHCP reservation과 VM IP 표시를 기본 운영 경로로 봐야 합니다.

### Static IP

VM 내부 static IP는 advanced option으로만 다룹니다. 제품 기본값으로 넣지 않습니다.

잘못된 static IP는 다음 문제를 만들 수 있습니다.

- IP 충돌
- 잘못된 gateway
- DNS 장애
- 네트워크 변경 시 접속 불가

static IP를 지원하더라도 UI/설정에서 subnet, gateway, DNS를 명시적으로 검증해야 합니다.

### shared

shared mode는 `VZNATNetworkDeviceAttachment`를 사용합니다.
Linux VM이 부팅되는지 확인하기 위한 첫 번째 단계입니다.

```json
"network": {
  "mode": "shared",
  "bridgedInterface": null,
  "macAddress": "52:12:34:56:78:9a"
}
```

주의: shared mode는 VRecorder 원본 IP 보존 검증에는 충분하지 않습니다.

### bridged

bridged mode가 최종 운영 가설입니다.
Linux VM이 병원 LAN에서 독립 IP를 받고, VRecorder는 Mac mini IP가 아니라 Linux VM IP로 접속해야 합니다.

bridged interface 확인:

```sh
make vm-interfaces
```

config 예시:

```json
"network": {
  "mode": "bridged",
  "bridgedInterface": "en0",
  "macAddress": "52:12:34:56:78:9a"
}
```

성공 시 목표 구조:

```text
VRecorder
  -> Linux VM IP:80
      -> nginx
      -> VitalServer container
```

이때 VM 내부 nginx의 `$remote_addr`가 실제 VRecorder IP여야 합니다.

## 실행

```sh
make vm-up
```

또는 prepare/start를 분리해서 실행합니다.

```sh
make vm-prepare
make vm-start
make vm-status
make vm-down
make vm-clean
```

boot asset이 없으면 `make vm-start`는 다음처럼 실패합니다.

```text
error: missing file: .../images/Image
```

이 실패는 정상입니다. 먼저 `images/` 아래에 Linux boot asset을 준비해야 합니다.

## 정리

```sh
make vm-clean
```

`vm-clean`은 disposable runtime state를 삭제하지만 macOS에 bind되는 데이터 디렉터리는 보존합니다.

삭제:

- `config.json`
- `images/`
- `logs/`
- `run/`

보존:

- `data/`
- `data/vital-files/`
- `data/vr-release/`

## PoC 체크리스트

- shared mode에서 VM이 boot된다.
- guest console log를 볼 수 있다.
- VM 안에서 network가 동작한다.
- `make vm-interfaces`로 bridged 후보 interface가 보인다.
- bridged mode에서 VM이 boot된다.
- VM이 DHCP로 병원 LAN IP를 받는다.
- 다른 장비에서 VM IP로 접속할 수 있다.
- VM 내부 nginx가 실제 client IP를 `$remote_addr`로 본다.

## 코드 구조

```text
Sources/VitalServerVMLauncher/
  main.swift                    # process entrypoint

  CLI/
    Command.swift               # command names and aliases
    Launcher.swift              # CLI command dispatch
    LauncherError.swift

  Runtime/
    Constants.swift             # public contracts and defaults
    LauncherPaths.swift         # runtime path resolution
    ProcessState.swift          # pid/status/stop handling

  VirtualMachine/
    VMRuntimeConfig.swift       # config model
    VMConfigurationFactory.swift # Virtualization.framework config
    VirtualMachineDelegate.swift
```

## 참고

- Apple Developer: Running Linux in a Virtual Machine
- Apple Developer: `VZVirtualMachineConfiguration`
- Apple Developer: `VZBridgedNetworkDeviceAttachment`
