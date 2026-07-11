# 문서 지도

이 디렉터리는 VitalServer 제품화 작업에서 확인한 사실, 결정, 운영 기준을 정리합니다. 처음 보는 사람은 root [README](https://github.com/tirosh-chain/tirosh-vitalserver#readme)를 먼저 읽고, 아래 지도에서 필요한 문서군으로 이동합니다.

## 빠른 경로

| 목적 | 먼저 볼 문서 |
|---|---|
| 제품 전체 맥락을 잡기 | [VitalServer 제품화 전략](product/productization.md) |
| Vital Server Helper 공개/운영 문서 보기 | [Release Overview](../site-docs/release/index.md) |
| Vital Server Helper 오픈소스 개발 문서 보기 | [Dev Overview](../site-docs/dev/index.md) |
| Vital Server Helper release/dev 문서 작성 기준 보기 | [Vital Server Helper Release/Dev Documentation Plan](product/release-dev-documentation-plan.md) |
| VRecorder가 VitalServer에 어떻게 붙는지 보기 | [Vital Recorder integration contract](recorder/vital-recorder-integration.md) |
| command audit event 계약 확인하기 | [Recorder ingress audit contract](recorder/ingress-audit-contract.md) |
| recorder `send_data` flow control 계약 확인하기 | [Recorder ingress send_data flow control contract](recorder/send-data-flow-control.md) |
| testkit으로 검증 실행하기 | [Testkit 사용법](testkit/usage.md) |
| Redis key와 relay 근거 보기 | [VitalServer recorder Redis key model](recorder/redis-key-model.md) |
| Mac mini VM runtime/package 이해하기 | [VitalServer macOS Runtime](runtime/macos/index.md) |
| runtime operation 상태 전이 검증 기준 보기 | [Runtime State Machine Traceability](runtime/macos/state-machine-traceability.md) |
| Runtime Control PWA 구현 기준 보기 | [Runtime Control PWA](pwa/index.md) |
| runtime status/event/log/index 수집 책임 보기 | [Runtime observability model](runtime/macos/observability.md) |
| branch와 tag 운영 기준 보기 | [Branch 운영 기준](repository/branching.md) |

## 문서군

### 제품화 기준

| 문서 | 역할 |
|---|---|
| [VitalServer 제품화 전략](product/productization.md) | 저장소의 목표, upstream 동작, 제품화 기준, 아직 비어 있는 영역 |
| [Vital Server Helper Release Overview](../site-docs/release/index.md) | 공개 배포 독자를 위한 Vital Server Helper 소개, 설치, 운영 문서군 진입점 |
| [Vital Server Helper Dev Overview](../site-docs/dev/index.md) | 오픈소스 contributor와 repository 유지보수자를 위한 서비스 경계, package 책임, build/release/test 문서군 진입점 |
| [Vital Server Helper Release/Dev Documentation Plan](product/release-dev-documentation-plan.md) | Vital Server Helper 공개/배포를 위한 release/dev 독자 구분, 작성 대상 문서, MkDocs nav 기준 |
| [ADR 0001](adr/0001-macos-host-proxy-for-vrecorder-ip.md) | macOS host proxy로 VRecorder 원 IP를 보존하기로 한 결정 |
| [ADR 0002](adr/0002-helper-client-boundary-for-local-and-remote-runtime.md) | Web/PWA primary UI와 local/remote RuntimeControlClient boundary 결정 |
| [ADR 0003](adr/0003-helper-layer-and-component-version-model.md) | VitalServer Helper layer와 component version model 결정 |
| [ADR 0004](adr/0004-product-update-and-vm-image-update-contract.md) | Product Update와 VM Image Update 계약 결정 |

### VRecorder와 데이터

| 문서 | 역할 |
|---|---|
| [Vital Recorder integration contract](recorder/vital-recorder-integration.md) | Socket.IO 접속 흐름, VRecorder 식별 기준, Web Monitoring 상태 표시 기준 |
| [Recorder ingress audit contract](recorder/ingress-audit-contract.md) | recorder ingress 기반 `join_vr`, `send_data`, `req_cmd`, dispatch event 계약 |
| [Recorder ingress send_data flow control contract](recorder/send-data-flow-control.md) | upstream 수정 없이 `send_data` 유입을 제어하고 저장, 재생, backpressure 상태를 노출하는 계약 |
| [VitalServer recorder Redis key model](recorder/redis-key-model.md) | VitalServer가 Redis에 저장하는 key 구조와 relay 설계 메모 |
| [OpenAPI 문서](api/vitalserver.openapi.yaml) | upstream VitalServer route에서 추출한 Swagger/OpenAPI spec |
| [Recorder Ingress OpenAPI](api/recorder-ingress.openapi.yaml) | recorder ingress sidecar 운영 endpoint spec |

### Testkit

| 문서 | 역할 |
|---|---|
| [Testkit 사용법](testkit/usage.md) | `vitalserver-testkit` CLI와 검증 시나리오 실행 방법 |

### Runtime Control PWA

| 문서 | 역할 |
|---|---|
| [Runtime Control PWA](pwa/index.md) | PWA 문서군 진입점과 목표/비목표 |
| [PWA Architecture](pwa/architecture.md) | PWA 레이어, source of truth, Runtime Control API boundary |
| [PWA Design system](pwa/design-system.md) | Tailwind token, shared UI component, styling ownership |
| [PWA Responsive layout](pwa/responsive-layout.md) | 24/32인치, iPad, iPhone 대응 기준 |
| [PWA Swift UI parity](pwa/parity.md) | Swift UI와 PWA 기능 parity, host affordance gap |
| [PWA Deployment](pwa/deployment.md) | air-gapped 배포, Helper resource 포함, update bundle 영향 |
| [PWA Testing](pwa/testing.md) | PWA test scope, 검증 명령, responsive smoke test 기준 |

### Mac mini VM Runtime

VM runtime 문서는 [VitalServer macOS Runtime](runtime/macos/index.md)를 진입점으로 봅니다.

| 문서 | 역할 |
|---|---|
| [Runtime v2 Cross-platform Conformance](runtime/runtime-v2-conformance.md) | macOS, Windows, Linux가 공유하는 Platform/Runtime API proof와 설치 acceptance matrix |
| [VitalServer macOS Runtime](runtime/macos/index.md) | VM runtime 문서군의 빠른 지도 |
| [macOS Runtime Overview](runtime/macos/overview.md) | VM runtime 세부 문서의 한눈에 보기와 사용자 시나리오 |
| [Architecture](runtime/macos/architecture.md) | 제품 구조, 단일 노드 가용성, Web/PWA UI/native shell/host runtime 책임 경계 |
| [State Machine Traceability](runtime/macos/state-machine-traceability.md) | install/update/recovery/recorder/log 흐름의 상태, 이벤트, guard, invariant, 검증 기준 |
| [Runtime Control API](runtime/macos/runtime-control-api.md) | PWA 직전 Runtime Control API 계약, OpenAPI, local read-only server 경계 |
| [Runtime observability model](runtime/macos/observability.md) | runtime status/event/log/index 수집 책임, watchdog 중심 정규화와 SQLite read model 기준 |
| [Packaging and Update](runtime/macos/packaging.md) | PKG/DMG 빌드, 설치 흐름, install settings, update bundle 계약 |
| [Update](runtime/macos/update.md) | update bundle 적용 과정, 보존/변경 범위, guest-side activation, rollback 계약 |
| [Runtime](runtime/macos/runtime.md) | boot asset, cloud-init, guest bootstrap, network/identity/signing 정책 |
| [Troubleshooting](troubleshooting/index.md) | PoC와 패키징 중 확인한 증상과 조치 |
| [ADR 0002](adr/0002-helper-client-boundary-for-local-and-remote-runtime.md) | Web/PWA Helper UI, macOS native shell, local/remote RuntimeControlClient boundary |
| [ADR 0003](adr/0003-helper-layer-and-component-version-model.md) | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, VM Image layer와 version model |
| [ADR 0004](adr/0004-product-update-and-vm-image-update-contract.md) | Product Update, VM Image Update, two-phase Product Update 구분 |

### 개발 운영

| 문서 | 역할 |
|---|---|
| [Branch 운영 기준](repository/branching.md) | main/develop/feature branch와 package tag 운영 방식 |

## 읽는 순서

처음 보는 개발자는 아래 순서로 읽습니다.

1. root [README](https://github.com/tirosh-chain/tirosh-vitalserver#readme)
2. [VitalServer 제품화 전략](product/productization.md)
3. [Vital Recorder integration contract](recorder/vital-recorder-integration.md)
4. [Testkit 사용법](testkit/usage.md)
5. [VitalServer recorder Redis key model](recorder/redis-key-model.md)
6. [VitalServer macOS Runtime](runtime/macos/index.md)
7. [Branch 운영 기준](repository/branching.md)

Swagger UI로 API를 확인할 때는 root에서 아래 명령을 실행합니다.

```sh
make swagger/up
```

이후 `http://localhost:8082`에서 Swagger UI를 열면 VitalServer, Runtime Control API, Recorder Ingress API spec을 선택해서 볼 수 있습니다. VitalServer spec은 [OpenAPI 문서](api/vitalserver.openapi.yaml)로 관리합니다.

## 작성 기준

- 문서는 가능한 한 한글로 작성합니다.
- CLI, API, Socket.IO, Redis, Docker, Compose처럼 개발자에게 익숙한 용어는 원어를 유지합니다.
- 실행 방법은 사용법 문서에 모으고, 전략 문서에는 판단 기준과 결정 배경을 남깁니다.
- Redis key와 relay처럼 구현의 근거가 되는 사실은 [VitalServer recorder Redis key model](recorder/redis-key-model.md)에 모읍니다.
- VM package/runtime 세부 사항은 `docs/runtime/macos/` 문서군에 모읍니다.
