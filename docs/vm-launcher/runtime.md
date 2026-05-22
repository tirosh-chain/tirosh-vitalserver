# VitalServer VM Runtime

VM이 실제로 어떻게 준비되고 실행되는지 정리합니다. boot asset, cloud-init, guest bootstrap, network mode, host proxy, identity 정책을 다룹니다.

## 이 문서에서 바로 알아야 할 것

| 질문 | 답 |
|---|---|
| runtime source of truth는? | Swift CLI `vitalserver-vm` |
| 운영 상태 파일은? | `/Library/Application Support/TiroshVitalServer/status/runtime-status.json` |
| VM config는 어디 있나? | runtime directory의 `vm-config.json` |
| guest 초기화는 누가 하나? | cloud-init이 `Support/Guest/bootstrap.sh` 실행 |
| `.vital` 파일은 어디에 두나? | macOS shared directory |
| VM IP `192.168.64.x`는 정상인가? | shared/NAT mode에서는 정상 |

runtime 단계의 source of truth는 Swift CLI인 `vitalserver-vm`입니다. Shell script는 launchd나 installer가 호출하기 쉬운 wrapper로만 남기고, 설치 후 상태 전이와 복구 정책은 Swift `RuntimeLifecycle`에 둡니다.

| 책임 | 구현 |
|---|---|
| VM start/stop/status/network | Swift `Sources/HostRuntimeControl` |
| install/status/health/configure/update/rollback/watchdog | Swift `RuntimeLifecycle` |
| runtime 상태 파일 | `/Library/Application Support/TiroshVitalServer/status/runtime-status.json` |
| host proxy runner | `Support/Packaging/proxy-run`, nginx start/reload loop |
| Linux guest 내부 구성 | `Support/Guest/bootstrap.sh`, `prepare-airgap-rootfs.sh`, `compose.yaml` |

반대로 Ubuntu image 다운로드, cloud-init ISO 생성, Docker image bundle, nginx bundle 같은 build-machine 작업은 runtime 책임이 아니며 Python `packages/vm-build`가 담당합니다.

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
  "cpuCount": 8,
  "diskPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/vm-disk.img",
  "initialRamdiskPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/initrd.img",
  "cloudInitPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/seed.iso",
  "kernelCommandLine": "console=hvc0 root=/dev/vda1 rw",
  "kernelPath": "/Users/<user>/.tirosh/vitalserver-vm/runtime/Image",
  "memoryMiB": 8192,
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
| root disk target size | `4G` (4 GiB) |

root disk 크기를 바꾸려면:

```sh
VM_ROOTFS_SIZE=32G make vm-download
```

`VM_ROOTFS_SIZE`의 `G` suffix는 build tool 입력 형식이며 GiB 기준으로 해석합니다. 예를 들어 `32G`는 32 GiB root disk target size입니다.

`4G`는 packaging 효율을 위한 golden rootfs base 크기입니다. 설치 wizard에서 사용자가 고르는 runtime disk 크기와 다릅니다. 설치 시에는 `rootfs-base.raw.gz`를 `vm-disk.img`로 풀고, 기본 32 GiB 또는 사용자가 고른 크기로 sparse disk를 확장합니다. 설치 후 disk 크기는 증가만 허용합니다.

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

기본 password는 build-time seed 편의값입니다. 제품 설치에서는 Helper app wizard 또는 install settings JSON이 설치 대상별 admin password를 runtime config에 전달합니다.

## Guest Bootstrap

`make vm-stage`는 VM에서 실행할 deployment bundle을 공유 디렉터리에 복사합니다.

```sh
make vm-stage
```

| 항목 | 용도 |
|---|---|
| `bootstrap.sh` | Linux guest 초기 entrypoint. mount/package 확인 후 `bin/`, `systemd/`, Compose stack 연결 |
| `bin/*` | runtime env export, runtime state 기록, Compose start/stop, health, diagnostics, Redis backup 명령 |
| `systemd/*` | runtime state writer, Compose stack, Redis backup timer unit |
| `compose.yaml` | VM 내부 VitalServer/Redis/UI/edge nginx Compose stack |
| `nginx/vitalserver.conf` | Compose edge nginx container 설정 |
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
2. air-gapped rootfs에 Docker/Compose/avahi/growpart 등 guest 필수 package가 준비됐는지 확인
3. 준비물이 없으면 `apt-get`을 시도하지 않고 실패 처리
4. `Support/Guest/bin`, `Support/Guest/systemd` 파일을 guest OS에 설치
5. bundled Docker image를 load하고 dangling image cleanup 수행
6. bundled Docker image를 load한 뒤 `docker compose up -d`로 VitalServer/Redis/UI/edge nginx 실행
7. runtime state에 VM IP와 guest HTTP readiness 기록

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

bridged mode는 향후 host nginx 제거, 네트워크 구조 단순화, 또는 직접 LAN 노출이 필요한 경우의 옵션으로 둡니다. 현재 제품 GUI에서는 `shared/NAT`만 선택 가능하게 두고, bridged는 entitlement와 병원망 조건을 만족하는 release에서만 열어야 합니다.

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

`make vm-up`은 VM을 background로 시작하고, guest가 shared directory에 기록한 runtime state와 guest HTTP readiness를 기다린 뒤 host nginx upstream을 `<vm-ip>:80`으로 설정합니다.

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

## Health Endpoints

runtime health는 사용자 화면, watchdog, update wait가 같이 사용하는 계약입니다. 제품 runtime은 liveness와 readiness를 분리합니다.

| endpoint | 의미 | 사용처 |
|---|---|---|
| `/health` | proxy/nginx process가 살아 있고 요청을 받을 수 있음 | liveness 확인, proxy 자체 장애 판단 |
| `/ready` | VitalServer stack이 사용자 요청을 처리할 준비가 됨 | watchdog recovery 판단, update health wait, Helper status |

단일 Mac runtime이라 Kubernetes처럼 traffic routing이나 scale-out을 하지는 않지만, `/health`와 `/ready`를 분리해야 장애 판단이 안정적입니다.

```text
/health failure
  -> 해당 process가 죽었거나 listen하지 않음
  -> proxy restart 대상

/ready failure
  -> process는 살아 있지만 upstream/app/guest가 아직 준비되지 않음
  -> update 중이면 대기
  -> 일반 운영 중이면 watchdog recovery 대상
```

guest runtime state writer도 VitalServer 상태를 `/ready` 기준으로 기록합니다. `/`는 VitalServer app이 정상이어도 login 또는 UI route로 `302` redirect를 반환할 수 있으므로 readiness source가 아닙니다.

watchdog auto-recovery는 update/rollback과 동시에 실행되면 안 됩니다. `runtime-status.json`이 `apply-bundle`, `activate-guest-update`, `rollback` 진행 중임을 나타내면 watchdog은 recovery를 건너뜁니다. 상태가 오래 갱신되지 않아 stale로 판단되면 watchdog은 다시 일반 recovery 정책으로 돌아갑니다.

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
