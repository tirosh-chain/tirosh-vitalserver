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
vitalserver-vm clean
vitalserver-vm version
```

아직 제품 기능은 아닙니다.

- 완성형 `.pkg`
- GUI 앱
- codesign/notarization 제품화
- offline VM image build pipeline
- VM image 업데이트

## 참고 문서

- [VitalServer VM Launcher 문서](../../docs/vitalserver-vm-launcher.md)
- [macOS host proxy ADR](../../docs/adr/0001-macos-host-proxy-for-vrecorder-ip.md)
