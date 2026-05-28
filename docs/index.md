# 문서 지도

이 디렉터리는 VitalServer 제품화 작업에서 확인한 사실, 결정, 운영 기준을 정리합니다.
처음 보는 사람은 root [README](../README.md)를 먼저 읽고, 아래 지도에서 필요한 문서군으로 이동합니다.

## 빠른 경로

| 목적 | 먼저 볼 문서 |
|---|---|
| 제품 전체 맥락을 잡기 | [VitalServer 제품화 전략](vitalserver-productization.md) |
| VRecorder가 VitalServer에 어떻게 붙는지 보기 | [Vital Recorder](vrecorder.md) |
| command audit event 계약 확인하기 | [VitalServer command audit](vitalserver-command-audit.md) |
| testkit으로 검증 실행하기 | [Testkit 사용법](testkit-usage.md) |
| Redis key와 relay 근거 보기 | [Redis 데이터 구조](redis-data-model.md) |
| Mac mini VM runtime/package 이해하기 | [VitalServer macOS Runtime](vitalserver-macos-runtime.md) |
| Runtime Control PWA 구현 기준 보기 | [Runtime Control PWA](pwa.md) |
| runtime status/event/log/index 수집 책임 보기 | [Runtime observability model](macos-runtime/observability.md) |
| branch와 tag 운영 기준 보기 | [Branch 운영 기준](branching.md) |

## 문서군

### 제품화 기준

| 문서 | 역할 |
|---|---|
| [VitalServer 제품화 전략](vitalserver-productization.md) | 저장소의 목표, upstream 동작, 제품화 기준, 아직 비어 있는 영역 |
| [ADR 0001](adr/0001-macos-host-proxy-for-vrecorder-ip.md) | macOS host proxy로 VRecorder 원 IP를 보존하기로 한 결정 |
| [ADR 0002](adr/0002-helper-client-boundary-for-local-and-remote-runtime.md) | Web/PWA primary UI와 local/remote RuntimeControlClient boundary 결정 |
| [ADR 0003](adr/0003-helper-layer-and-component-version-model.md) | VitalServer Helper layer와 component version model 결정 |
| [ADR 0004](adr/0004-product-update-and-vm-image-update-contract.md) | Product Update와 VM Image Update 계약 결정 |

### VRecorder와 데이터

| 문서 | 역할 |
|---|---|
| [Vital Recorder](vrecorder.md) | Socket.IO 접속 흐름, VRecorder 식별 기준, Web Monitoring 상태 표시 기준 |
| [VitalServer command audit](vitalserver-command-audit.md) | audit proxy 기반 `join_vr`, `send_data`, `req_cmd`, dispatch event 계약 |
| [Redis 데이터 구조](redis-data-model.md) | VitalServer가 Redis에 저장하는 key 구조와 relay 설계 메모 |
| [OpenAPI 문서](openapi.yaml) | upstream VitalServer route에서 추출한 Swagger/OpenAPI spec |
| [Audit Proxy OpenAPI](openapi/audit-proxy.openapi.yaml) | audit proxy sidecar 운영 endpoint spec |

### Testkit

| 문서 | 역할 |
|---|---|
| [Testkit 사용법](testkit-usage.md) | `vitalserver-testkit` CLI와 검증 시나리오 실행 방법 |

### Runtime Control PWA

| 문서 | 역할 |
|---|---|
| [Runtime Control PWA](pwa.md) | PWA 문서군 진입점과 목표/비목표 |
| [PWA Architecture](pwa/architecture.md) | PWA 레이어, source of truth, Runtime Control API boundary |
| [PWA Design system](pwa/design-system.md) | Tailwind token, shared UI component, styling ownership |
| [PWA Responsive layout](pwa/responsive-layout.md) | 24/32인치, iPad, iPhone 대응 기준 |

### Mac mini VM Runtime

VM runtime 문서는 [VitalServer macOS Runtime](vitalserver-macos-runtime.md)를 진입점으로 봅니다.

| 문서 | 역할 |
|---|---|
| [VitalServer macOS Runtime](vitalserver-macos-runtime.md) | VM runtime 문서군의 빠른 지도 |
| [macOS Runtime Overview](macos-runtime/overview.md) | VM runtime 세부 문서의 한눈에 보기와 사용자 시나리오 |
| [Architecture](macos-runtime/architecture.md) | 제품 구조, 단일 노드 가용성, Web/PWA UI/native shell/host runtime 책임 경계 |
| [Runtime Control API](macos-runtime/runtime-control-api.md) | PWA 직전 Runtime Control API 계약, OpenAPI, local read-only server 경계 |
| [Runtime observability model](macos-runtime/observability.md) | runtime status/event/log/index 수집 책임, watchdog 중심 정규화와 SQLite read model 기준 |
| [Packaging and Update](macos-runtime/packaging.md) | PKG/DMG 빌드, 설치 흐름, install settings, update bundle 계약 |
| [Update](macos-runtime/update.md) | update bundle 적용 과정, 보존/변경 범위, guest-side activation, rollback 계약 |
| [Runtime](macos-runtime/runtime.md) | boot asset, cloud-init, guest bootstrap, network/identity/signing 정책 |
| [Troubleshooting](troubleshooting.md) | PoC와 패키징 중 확인한 증상과 조치 |
| [ADR 0002](adr/0002-helper-client-boundary-for-local-and-remote-runtime.md) | Web/PWA Helper UI, macOS native shell, local/remote RuntimeControlClient boundary |
| [ADR 0003](adr/0003-helper-layer-and-component-version-model.md) | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, VM Image layer와 version model |
| [ADR 0004](adr/0004-product-update-and-vm-image-update-contract.md) | Product Update, VM Image Update, two-phase Product Update 구분 |

### 개발 운영

| 문서 | 역할 |
|---|---|
| [Branch 운영 기준](branching.md) | main/develop/feature branch와 package tag 운영 방식 |

## 읽는 순서

처음 보는 개발자는 아래 순서로 읽습니다.

1. root [README](../README.md)
2. [VitalServer 제품화 전략](vitalserver-productization.md)
3. [Vital Recorder](vrecorder.md)
4. [Testkit 사용법](testkit-usage.md)
5. [Redis 데이터 구조](redis-data-model.md)
6. [VitalServer macOS Runtime](vitalserver-macos-runtime.md)
7. [Branch 운영 기준](branching.md)

Swagger UI로 API를 확인할 때는 root에서 아래 명령을 실행합니다.

```sh
make swagger
```

이후 `http://localhost:8082`에서 Swagger UI를 열면 VitalServer, Runtime Control API, Audit Proxy API
spec을 선택해서 볼 수 있습니다. 기존 단일 문서 경로인 [OpenAPI 문서](openapi.yaml)도 유지합니다.

## 작성 기준

- 문서는 가능한 한 한글로 작성합니다.
- CLI, API, Socket.IO, Redis, Docker, Compose처럼 개발자에게 익숙한 용어는 원어를 유지합니다.
- 실행 방법은 사용법 문서에 모으고, 전략 문서에는 판단 기준과 결정 배경을 남깁니다.
- Redis key와 relay처럼 구현의 근거가 되는 사실은 [Redis 데이터 구조](redis-data-model.md)에 모읍니다.
- VM package/runtime 세부 사항은 `docs/macos-runtime/` 문서군에 모읍니다.
