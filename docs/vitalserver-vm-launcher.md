# VitalServer VM Launcher

이 문서는 `apps/vitalserver-vm-launcher`의 설계와 운영 판단 기준을 정리합니다.

앱 README는 빠른 실행만 다루고, 배포 모델/네트워크/identity/cloud-init/rootfs 정책은 이 문서에서 관리합니다.

## 목표

Mac mini에서 Linux VM을 직접 실행하고, VM 내부에서 VitalServer stack을 운영합니다.

v1 기본 구조는 `shared/NAT VM + macOS host nginx`입니다.

```text
shared/NAT mode

VRecorder / Browser
  -> Mac mini LAN IP :80
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
| VRecorder 접속 대상 | Mac mini LAN IP | Linux VM LAN IP |
| edge proxy 위치 | macOS host nginx | Linux VM 내부 nginx |
| VM IP 부여 | macOS Virtualization NAT DHCP | 병원 LAN DHCP |
| 원 IP 보존 | host nginx 경유로 보존 | VM이 LAN에서 직접 수신 |
| Apple `com.apple.vm.networking` 승인 | 필요 없음 | 필요 |
| 주요 리스크 | host nginx package/launchd 관리 | Apple 승인, 병원망 bridged 허용 여부 |

최종 v1 목표:

```text
Mac mini
  -> host nginx :80
      -> vitalserver-vm
          -> Linux VM shared/NAT
              -> Docker Compose
                  - vitalserver
                  - redis
                  - vitaldb-observer
```

v1 제품 구조는 `shared/NAT VM + macOS host nginx`입니다. VRecorder는 Mac mini의 LAN IP로 접속하고, host nginx가 요청을 VM 내부 VitalServer로 전달합니다.

이 구조는 macOS Docker Desktop/OrbStack 의존성을 제거하면서도, 이미 검증한 host nginx 경유 원 IP 보존 방식을 제품화하기 위한 것입니다.

bridged mode는 host nginx 없이 VM이 병원 LAN에 직접 붙는 선택지로 남깁니다. 다만 `com.apple.vm.networking` restricted entitlement 승인이 필요하므로 v1 제품 blocker로 두지 않습니다.

## 배포 모델

최종 목표는 병원 Mac mini에 설치 가능한 self-contained package입니다. 운영 Mac mini는 air-gapped 환경까지 고려합니다.

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

### Target Mac Mini

병원 Mac mini는 설치 파일만 받습니다.

```text
TiroshVitalServer.pkg
  -> /usr/local/bin/vitalserver-vm
  -> /usr/local/tirosh/nginx/sbin/nginx
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
  -> /Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist
  -> /Library/Application Support/Tirosh/VitalServer/images/
       Image
       initrd.img
       rootfs.raw
  -> /Library/Application Support/Tirosh/VitalServer/data/
       vital-files/
       vr-release/
```

운영 Mac mini에는 아래 의존성이 없어야 합니다.

| 의존성 | 운영 Mac mini 필요 여부 |
|---|---|
| Homebrew | 필요 없음 |
| `qemu-img` | 필요 없음 |
| Docker Desktop | 필요 없음 |
| OrbStack | 필요 없음 |
| brew nginx | 필요 없음, package에 포함 |
| 외부 apt repository | 필요 없음 |
| 외부 container registry | 필요 없음 |

## GUI와 Package

`.pkg` 자체는 풍부한 설정 UI에 적합하지 않습니다. 제품으로는 `.dmg` 안에 GUI 앱을 제공하고, GUI가 설정을 만든 뒤 privileged install 또는 bundled `.pkg` 설치를 실행하는 구조가 좋습니다.

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

| 설정 | 저장 위치 |
|---|---|
| VM CPU/RAM/kernel/disk/network/MAC | `config.json` |
| cloud-init user/hostname/SSH key/bootstrap | `seed.iso` |
| VitalServer container 환경변수 | deploy `.env` |
| 서비스 자동 실행 | LaunchDaemon plist |

GUI는 VM을 직접 만드는 도구라기보다, 이 파일들을 안전하게 생성/수정하는 설정 도구로 봅니다.

## Runtime Directory

PoC 기본 runtime directory는 아래입니다.

```text
~/.tirosh/vitalserver-vm/
  config.json
  images/
    Image
    initrd.img
    rootfs.raw
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

## Linux Boot Assets

PoC에서는 Git에 Linux image를 넣지 않습니다.

```sh
make vm-download
```

설정 파일:

```text
apps/vitalserver-vm-launcher/Support/Build/ubuntu-cloud-image.env
```

| 항목 | 기본값 |
|---|---|
| 배포판 | Ubuntu Server 24.04 LTS Noble cloud image |
| architecture | macOS host architecture 기준 자동 선택 |
| 다운로드 경로 | `~/.tirosh/vitalserver-vm/images/downloads/` |
| 실행 경로 | `~/.tirosh/vitalserver-vm/images/` |
| root disk target size | `16G` |

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
| seed image | `~/.tirosh/vitalserver-vm/images/seed.iso` |
| hostname | `tirosh-vitalserver` |
| instance-id | 자동 생성 |
| user | `ubuntu` |
| password | `ubuntu` |
| SSH public key | `~/.ssh/id_ed25519.pub`가 있으면 자동 포함 |
| bootstrap | `/mnt/tirosh/deploy/bootstrap.sh` 자동 실행 |

값을 바꾸려면:

```sh
VM_CLOUD_INIT_HOSTNAME=tirosh-vitalserver \
VM_CLOUD_INIT_INSTANCE_ID=tirosh-site-a-001 \
VM_CLOUD_INIT_USER=ubuntu \
VM_CLOUD_INIT_PASSWORD=change-me \
VM_CLOUD_INIT_SSH_KEY=~/.ssh/id_ed25519.pub \
make vm-cloud-init
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
| `.env` | VitalServer container 환경변수 |
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
6. `docker compose up -d --build`로 VitalServer/Redis 실행

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
  -> Mac mini host nginx :80
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

v1 운영에서는 사용자가 VM IP로 접속하지 않습니다. 사용자는 Mac mini의 LAN IP 또는 host nginx가 노출하는 이름으로 접속합니다.

bridged mode가 활성화되면 VM은 병원 LAN DHCP에서 `172.x`, `10.x`, `192.168.x` 대역의 IP를 직접 받을 수 있습니다.

## Host Proxy

v1에서는 host nginx가 제품의 public edge입니다. VM은 shared/NAT 뒤에 있고, host nginx가 VM endpoint로 proxy합니다.

```text
public:
  http://<Mac mini LAN IP>:80

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

`make vm-init`은 `config.json`에 VM MAC address를 생성해 저장합니다. 이 값은 제품 설치 후 유지되어야 합니다.

## VM Identity

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
- host nginx가 Mac mini port 80에서 요청을 받는다.
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
error: missing file: .../images/Image
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

v1 구조에서는 정상입니다. 사용자는 이 VM IP로 직접 접속하지 않고, Mac mini host nginx로 접속합니다.

```text
VRecorder
  -> http://<Mac mini LAN IP>/
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

`make vm-download`는 rootfs를 기본 `16G`로 확장합니다. 더 크게 만들려면:

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
VM_CLOUD_INIT_INSTANCE_ID=tirosh-site-a-001 make vm-cloud-init
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
