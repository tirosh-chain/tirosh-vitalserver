# VitalServer VM Launcher

`vitalserver-vm-launcher`는 Apple Virtualization Framework로 Linux VM을 직접 실행하는 PoC입니다.

이 PoC의 목적은 Mac mini에서 Linux VM을 운영 서버처럼 띄우고, 그 안에서 `systemd + nginx + Docker Compose`로 VitalServer를 24/7 운영할 수 있는지 검증하는 것입니다.

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

- Linux image 다운로드/생성 자동화
- Docker Compose 자동 설치
- 완성형 `.pkg`
- GUI 앱
- codesign/notarization 제품화
- VM image 업데이트

## 요구사항

- macOS 13 이상
- Swift 6 이상
- Linux kernel, initramfs, writable root disk image
- shared/NAT boot: `com.apple.security.virtualization` entitlement
- bridged network: `com.apple.vm.networking` entitlement

`com.apple.vm.networking`은 bridged network에 필요합니다. ad-hoc signing으로는 macOS가 실행을 막을 수 있으므로, bridged 검증은 제품 signing profile에서 entitlement를 확보한 뒤 진행해야 합니다.

## 빌드

```sh
make vm-build
```

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

## 초기화

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
  "kernelCommandLine": "console=hvc0 root=/dev/vda rw",
  "kernelPath": "/Users/<user>/.tirosh/vitalserver-vm/images/vmlinuz",
  "memoryMiB": 4096,
  "network": {
    "bridgedInterface": null,
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

### shared

shared mode는 `VZNATNetworkDeviceAttachment`를 사용합니다.
Linux VM이 부팅되는지 확인하기 위한 첫 번째 단계입니다.

```json
"network": {
  "mode": "shared",
  "bridgedInterface": null
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
  "bridgedInterface": "en0"
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
make vm-start
make vm-status
make vm-stop
make vm-clean
```

boot asset이 없으면 `make vm-start`는 다음처럼 실패합니다.

```text
error: missing file: .../images/vmlinuz
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
