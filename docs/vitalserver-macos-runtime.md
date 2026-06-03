# VitalServer macOS Runtime

`apps/vitalserver-macos-runtime`의 설계, 빌드, 설치, 운영 문서 진입점입니다.

앱 README는 실제 사용자가 자주 접하는 시나리오와 핵심 명령을 먼저 다룹니다. 제품 구조, 패키징 계약, VM runtime, troubleshooting은 아래 문서로 나누어 관리합니다.

## 빠른 지도

| 문서 | 언제 보나 |
|---|---|
| [macOS Runtime Overview](macos-runtime/overview.md) | VM runtime 문서군 전체 지도와 사용자 시나리오 |
| [Architecture](macos-runtime/architecture.md) | 제품 구조, shared/NAT + host nginx 선택 이유, 단일 노드 가용성 범위, 책임 경계 확인 |
| [State Machine Traceability](macos-runtime/state-machine-traceability.md) | install/update/recovery/recorder/log 흐름의 상태 전이, invariant, 검증 증거 기준 확인 |
| [ADR 0002](adr/0002-helper-client-boundary-for-local-and-remote-runtime.md) | Web/PWA Helper UI, macOS native shell, local/remote RuntimeControlClient boundary 확인 |
| [ADR 0003](adr/0003-helper-layer-and-component-version-model.md) | Helper layer와 component version model 확인 |
| [ADR 0004](adr/0004-product-update-and-vm-image-update-contract.md) | Product Update, VM Image Update, two-phase Product Update 계약 확인 |
| [Packaging and Update](macos-runtime/packaging.md) | `make vm-pkg`, `make vm-dmg`, PKG 설치 흐름, install settings, update bundle 계약 확인 |
| [Update](macos-runtime/update.md) | update bundle 적용 과정, 보존/변경 범위, guest-side activation, rollback 계약 확인 |
| [Runtime](macos-runtime/runtime.md) | VM boot asset, cloud-init, guest bootstrap, data sharing, network mode, identity/signing 정책 확인 |
| [Troubleshooting](troubleshooting.md) | 502, cloud-init 재실행, disk full, update 실패, bridged entitlement, stale pid 같은 문제 확인 |

## 핵심 구조

v1 제품 구조는 `shared/NAT VM + macOS host nginx`입니다. VRecorder와 browser는 target Mac의 LAN IP로 접속하고, macOS host nginx가 Linux VM 내부 VitalServer로 요청을 전달합니다.

```text
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

bridged mode는 Apple `com.apple.vm.networking` restricted entitlement 승인이 필요한 향후 옵션입니다. v1에서는 host nginx를 통해 VRecorder 원 IP 보존을 제품화합니다.

## 주요 명령어

설치 파일을 만들 때:

```sh
make vm-dmg
```

이미 설치된 현장에 Product Update bundle을 제공할 때:

```sh
make vm-update-bundle
make vm-update-bundle-verify
```

VM Image/rootfs 자체를 교체하는 특수 bundle이 필요할 때:

```sh
make vm-rootfs-update-bundle
make vm-rootfs-update-bundle-verify
```

개발용 설치 테스트:

```sh
make vm-pkg
make vm-pkg-install
make vm-installed-health
make vm-pkg-uninstall-dev
```

개발용 VM을 직접 띄워 확인할 때는 아래를 사용합니다.

```sh
make vm-up
make vm-health
make vm-down
```

## Source of Truth

| 영역 | 기준 문서 |
|---|---|
| 문서군 전체 지도 | [macOS Runtime Overview](macos-runtime/overview.md) |
| 제품 구조와 책임 분리 | [Architecture](macos-runtime/architecture.md) |
| 상태 전이와 검증 기준 | [State Machine Traceability](macos-runtime/state-machine-traceability.md) |
| 패키지 산출물과 설치/update 계약 | [Packaging and Update](macos-runtime/packaging.md) |
| update 적용과 rollback 계약 | [Update](macos-runtime/update.md) |
| VM runtime 동작과 네트워크 정책 | [Runtime](macos-runtime/runtime.md) |
| 장애 증상과 조치 | [Troubleshooting](troubleshooting.md) |
