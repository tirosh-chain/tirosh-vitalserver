# 문서 지도

이 디렉터리는 VitalServer 제품화 작업에서 확인한 사실, 결정, 운영 기준을 정리합니다. 처음 보는 사람은 root [README](https://github.com/tirosh-chain/tirosh-vitalserver#readme)를 먼저 읽고, 아래 지도에서 필요한 문서군으로 이동합니다.

## 빠른 경로

| 목적 | 먼저 볼 문서 |
|---|---|
| 제품 전체 맥락을 잡기 | [VitalServer 제품화 전략](product/productization.md) |
| 다음 세대 재구축의 목표 구조를 검토하기 | [VitalServer Runtime Platform vNext 설계 초안](architecture/vnext-runtime-platform-design.md) |
| 새 코드의 이름만 보고 owner·경계·역할을 읽는 기준 확인하기 | [도메인 언어와 모듈 명명 기준](architecture/domain-language-and-module-naming.md) |
| 현재 구현된 Host/Guest control 경계와 proof 한계를 확인하기 | [Host/Guest Control Slice](architecture/host-guest-control-boundary.md) |
| Console/CLI가 C52 local socket·named pipe를 통해 Host control에 붙는 경계 보기 | [Host Local Administration Transport Boundary](architecture/host-local-administration-transport-boundary.md) |
| external VitalServer archive credential의 local-only 수명주기 보기 | [Guest Archive Credential-Material Boundary](architecture/guest-secret-material-boundary.md) |
| Guest image compiler·C34·macOS PKG가 나뉘는 이유 확인하기 | [Guest Artifact Build Boundary](architecture/guest-artifact-build-boundary.md) |
| QCOW2를 raw Guest disk로 바꾸는 owner와 receipt 확인하기 | [Guest Linux Source Disk Materialization Boundary](architecture/guest-linux-source-disk-materialization-boundary.md) |
| 명시된 Linux image에서 kernel/initrd/root storage를 추출하는 owner 확인하기 | [Guest Linux Boot Artifact Extraction Boundary](architecture/guest-linux-boot-artifact-extraction-boundary.md) |
| whole-disk ext4를 explicit `/dev/vda1` C39 base로 조립하는 owner 확인하기 | [Guest Root Storage Partition Assembly Boundary](architecture/guest-root-storage-partition-assembly-boundary.md) |
| release source가 C35 input root·identity로 조립되는 경계 확인하기 | [Guest Artifact Compilation Input Assembly Boundary](architecture/guest-artifact-compilation-input-assembly-boundary.md) |
| Host release build와 Guest-owned first-boot installation 경계 확인하기 | [Guest Product Bootstrap Volume Boundary](architecture/guest-product-bootstrap-volume-boundary.md) |
| Guest Runtime·Recorder Gateway의 Guest-local process owner와 deployment input 확인하기 | [Guest Product Process Supervisor Boundary](architecture/guest-product-process-supervisor-boundary.md) |
| Linux Guest systemd unit·Supervisor·child process owner가 분리되는 이유 확인하기 | [Guest Product Service Manager Boundary](architecture/guest-product-service-manager-boundary.md) |
| public listener와 explicit route·client identity 경계 확인하기 | [Host Edge Proxy Boundary](architecture/host-edge-proxy-boundary.md) |
| macOS VM이 왜 long-lived supervisor를 필요로 하는지 확인하기 | [macOS Virtual Machine Supervisor Boundary](architecture/macos-virtual-machine-supervisor-boundary.md) |
| Apple 배포 서명 전 local PKG 설치와 entitlement를 검증하는 경계 확인하기 | [macOS Development Installation Evidence Boundary](architecture/macos-development-installation-evidence-boundary.md) |
| C24 evidence fragment를 검토해 immutable release candidate로 반영하는 경계 보기 | [Release Delivery Proof Attachment Boundary](architecture/release-delivery-proof-attachment-boundary.md) |
| Windows MSI/SCM clean-host C24 evidence의 owner와 실행 경계 보기 | [Windows Clean-Host Release Evidence Boundary](architecture/windows-clean-host-release-evidence-boundary.md) |
| Linux DEB/systemd clean-host C24 evidence의 owner와 실행 경계 보기 | [Linux Clean-Host Release Evidence Boundary](architecture/linux-clean-host-release-evidence-boundary.md) |
| Recorder packet·spool·upstream delivery가 분리되는 경계 보기 | [Recorder Gateway Data Path](architecture/recorder-gateway-data-path.md) |
| Lab stop, `.vital` export, hide/detach/delete의 분리된 owner와 receipt 보기 | [Lab, Artifact Export, and Deletion Lifecycle](architecture/lab-archive-deletion-lifecycle.md) |
| external upstream, NTP, Recorder self-observation, OpenTelemetry 경계 보기 | [External Upstream, Time, and Observability](architecture/external-time-observability.md) |
| Windows/Linux provider, service lifecycle, release proof의 실제/미증명 경계 보기 | [Cross-platform Provider and Delivery](architecture/cross-platform-delivery.md) |
| installer/update compatibility, Host journal, updater handoff의 실제/미증명 경계 보기 | [Installation and Update Foundation](architecture/installation-update-foundation.md) |
| release composition, signed bootstrap, staged handoff의 현재 책임 경계 보기 | [Product Composition and Staged Update](architecture/product-composition-and-staged-update.md) |
| vNext에 적용할 외부 레퍼런스 패턴과 변화 관리 기준 보기 | [vNext 참고 패턴과 적용 규칙](architecture/reference-patterns.md) |
| 새 `runtime-platform/` root의 실제 구현 순서와 완료 기준 보기 | [vNext 구현 계획](architecture/vnext-implementation-plan.md) |
| 제품 사용 여정과 acceptance evidence 보기 | [제품 사용 시나리오 카탈로그](product/user-scenarios.md) |
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
| [VitalServer Runtime Platform vNext 설계 초안](architecture/vnext-runtime-platform-design.md) | 현재 구현과 분리한 재구축 목표: cross-platform Host, bundled/external upstream, Recorder/NTP, logs·metrics·traces 경계 |
| [도메인 언어와 모듈 명명 기준](architecture/domain-language-and-module-naming.md) | owner·boundary·role이 드러나는 DDD 명명 규칙과 신규 코드 체크리스트 |
| [Host/Guest Control Slice](architecture/host-guest-control-boundary.md) | 실제 구현된 Host/Guest SQLite owner, provider bridge, facade forwarding, recovery semantics와 executable evidence |
| [Host Local Administration Transport Boundary](architecture/host-local-administration-transport-boundary.md) | C33 local authorization policy, C52 descriptor, Console/CLI transport, OS proof gap의 분리 |
| [Guest Archive Credential-Material Boundary](architecture/guest-secret-material-boundary.md) | C51 private owner, C60 non-secret projection, local-only credential lifecycle와 archive failure boundary |
| [Guest Artifact Build Boundary](architecture/guest-artifact-build-boundary.md) | Guest image compiler output, C34 identity, macOS PKG composition, boot/install proof의 분리된 책임 |
| [Guest Linux Source Disk Materialization Boundary](architecture/guest-linux-source-disk-materialization-boundary.md) | C73 QCOW2→raw disk conversion, source/raw identity receipt, C42 source binding의 분리 |
| [Guest Linux Boot Artifact Extraction Boundary](architecture/guest-linux-boot-artifact-extraction-boundary.md) | C42 raw Linux source/explicit partition, filesystem-or-external boot resource extraction receipt, C43 layout conversion의 분리 |
| [Guest Root Storage Partition Assembly Boundary](architecture/guest-root-storage-partition-assembly-boundary.md) | C43 C42 receipt correlation, MBR `/dev/vda1` storage assembly receipt, C39 base identity의 분리 |
| [Guest Artifact Compilation Input Assembly Boundary](architecture/guest-artifact-compilation-input-assembly-boundary.md) | C41 release source selection, immutable C35 input root/receipt, build-machine path 격리 |
| [Guest Product Bootstrap Volume Boundary](architecture/guest-product-bootstrap-volume-boundary.md) | C39 bootstrap intent, C40 NoCloud delivery volume, Guest-owned cloud-init installation과 boot proof의 분리 |
| [Guest Product Process Supervisor Boundary](architecture/guest-product-process-supervisor-boundary.md) | C37 Guest process deployment, Guest Runtime/Recorder Gateway process-lifetime owner, explicit upstream/replay input과 artifact/boot proof의 분리 |
| [Guest Product Service Manager Boundary](architecture/guest-product-service-manager-boundary.md) | C38 systemd service-manager deployment, Supervisor invocation/restart policy, Guest image/systemd proof의 분리 |
| [Guest Product Release Activation Boundary](architecture/guest-product-release-activation-boundary.md) | C61 fixed C55 executor, C32 direct bridge, C59 Guest release activation/rollback owner의 분리 |
| [Host Edge Proxy Boundary](architecture/host-edge-proxy-boundary.md) | C36 explicit public route, client identity trust boundary, Host proxy package/clean-host proof의 분리 |
| [macOS Virtual Machine Supervisor Boundary](architecture/macos-virtual-machine-supervisor-boundary.md) | `VZVirtualMachine` process-lifetime owner, Host Agent/supervisor C21-C10 boundary, current invocation CLI의 한계 |
| [macOS Development Installation Evidence Boundary](architecture/macos-development-installation-evidence-boundary.md) | unsigned PKG, ad-hoc Virtualization-entitled Supervisor, local install/reboot evidence와 C24 release proof의 분리 |
| [Release Delivery Proof Attachment Boundary](architecture/release-delivery-proof-attachment-boundary.md) | C74 review, source C24 template 보호, exact evidence SHA-256 검증, immutable proof-set candidate 발행 |
| [Windows Clean-Host Release Evidence Boundary](architecture/windows-clean-host-release-evidence-boundary.md) | C23-selected MSI, ProductCode, SCM registration, reboot C24 evidence의 owner와 failure semantics |
| [Linux Clean-Host Release Evidence Boundary](architecture/linux-clean-host-release-evidence-boundary.md) | C23-selected DEB, dpkg receipt, systemd registration, retained root, reboot C24 evidence의 owner와 failure semantics |
| [Recorder Gateway Data Path](architecture/recorder-gateway-data-path.md) | Recorder Gateway protocol adapter, durable ingress/spool, delivery receipt, bundled upstream capability의 owner·proof 경계 |
| [Lab, Artifact Export, and Deletion Lifecycle](architecture/lab-archive-deletion-lifecycle.md) | Lab resource lifecycle, artifact export receipt, explicit deletion/cascade·retention boundary |
| [External Upstream, Time, and Observability](architecture/external-time-observability.md) | external provider/relay, Host·Guest time quality, Recorder self-observation Catalog, OTel pipeline boundary |
| [Cross-platform Provider and Delivery](architecture/cross-platform-delivery.md) | selected OS provider bridge, C21–C24 delivery gate, source-inventory SBOM와 clean-host proof boundary |
| [Installation and Update Foundation](architecture/installation-update-foundation.md) | C25–C31 immutable bootstrap envelope, Host update journal/recovery, next-updater handoff boundary |
| [Product Composition and Staged Update](architecture/product-composition-and-staged-update.md) | C25–C31 release composition, Host signature/staging, C30/C31 path ownership, next-updater planning boundary |
| [vNext 참고 패턴과 적용 규칙](architecture/reference-patterns.md) | Kubernetes·Google AIP·Terraform·ACL/Strangler·EdgeX·OpenTelemetry에서 가져올 경계, version, migration, 전환 규칙 |
| [vNext 구현 계획](architecture/vnext-implementation-plan.md) | `runtime-platform/` 독립 root, 실제 deployable unit, contract-first 단계, acceptance/release gate |
| [제품 사용 시나리오 카탈로그](product/user-scenarios.md) | 설치, 운영, Recorder, Product Lab, update, recovery, uninstall 사용자 여정과 Gherkin/evidence 연결 |
| [Vital Server Helper Release Overview](../site-docs/release/index.md) | 공개 배포 독자를 위한 Vital Server Helper 소개, 설치, 운영 문서군 진입점 |
| [Vital Server Helper Dev Overview](../site-docs/dev/index.md) | 오픈소스 contributor와 repository 유지보수자를 위한 서비스 경계, package 책임, build/release/test 문서군 진입점 |
| [Vital Server Helper Release/Dev Documentation Plan](product/release-dev-documentation-plan.md) | Vital Server Helper 공개/배포를 위한 release/dev 독자 구분, 작성 대상 문서, MkDocs nav 기준 |
| [ADR 0001](adr/0001-macos-host-proxy-for-vrecorder-ip.md) | macOS host proxy로 VRecorder 원 IP를 보존하기로 한 결정 |
| [ADR 0002](adr/0002-helper-client-boundary-for-local-and-remote-runtime.md) | Web/PWA primary UI와 local/remote RuntimeControlClient boundary 결정 |
| [ADR 0003](adr/0003-helper-layer-and-component-version-model.md) | VitalServer Helper layer와 component version model 결정 |
| [ADR 0004](adr/0004-product-update-and-vm-image-update-contract.md) | Product Update와 VM Image Update 계약 결정 |
| [ADR 0005](adr/0005-vital-file-versioned-compatibility-and-canonical-model.md) | Vital File v1/v2/v3 입력 호환성과 canonical 최신 writer 결정 |
| [ADR 0006](adr/0006-recovery-artifact-origin-and-publish-boundary.md) | cold-path recovery artifact origin, receipt, export와 publish 책임 분리 결정 |
| [PostgreSQL schema lifecycle](architecture/postgresql-schema-lifecycle.md) | 중앙 Alembic migrator, bounded-context schema, clean database 전환과 Runtime 기동 gate |

### VRecorder와 데이터

| 문서 | 역할 |
|---|---|
| [Vital Recorder integration contract](recorder/vital-recorder-integration.md) | Socket.IO 접속 흐름, VRecorder 식별 기준, Web Monitoring 상태 표시 기준 |
| [Recorder ingress audit contract](recorder/ingress-audit-contract.md) | recorder ingress 기반 `join_vr`, `send_data`, `req_cmd`, dispatch event 계약 |
| [Recorder ingress send_data flow control contract](recorder/send-data-flow-control.md) | upstream 수정 없이 `send_data` 유입을 제어하고 저장, 재생, backpressure 상태를 노출하는 계약 |
| [Recorder observability 호환성과 배포 순서](recorder/observability-compatibility-and-rollout.md) | Helper 0.2.1과 Recorder 0.2.6 후보의 contract matrix, incident UI, canary와 rollback 기준 |
| [Recorder observability persistence and API implementation plan](recorder/observability-persistence-and-api-plan.md) | Recorder 관측 JSONB admission, profile, PostgreSQL projection, read API와 단계별 구현 계획 |
| [Recorder observability Guest compose proof](recorder/observability-compose-proof.md) | certified NDJSON → Guest compose PostgreSQL → recorder-ingress direct query GET 증명의 범위, 상태, unique VRCODE, 운영자 승인 경계 |
| [Installed Recorder observability proof](recorder/observability-installed-proof.md) | 설치된 admission edge + Guest Control `/runtime/vitaldb`를 명시 endpoint로 검증하는 증명. Compose를 기동하지 않고 operator confirmation `YES`가 필수 |
| [Recorder observability API and database handoff](recorder/observability-recorder-handoff.md) | Recorder 팀과 합의한 초기 POST/profile/PostgreSQL 설계 기록. 현재 배포 기준은 호환성 문서 사용 |
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
| [ADR 0005](adr/0005-vital-file-versioned-compatibility-and-canonical-model.md) | Vital File version reader, canonical model, v3 writer, upload/replay streaming 경계 |

### 개발 운영

| 문서 | 역할 |
|---|---|
| [Branch 운영 기준](repository/branching.md) | main/develop/feature branch와 package tag 운영 방식 |

## 읽는 순서

처음 보는 개발자는 아래 순서로 읽습니다.

1. root [README](https://github.com/tirosh-chain/tirosh-vitalserver#readme)
2. [VitalServer 제품화 전략](product/productization.md)
3. [VitalServer Runtime Platform vNext 설계 초안](architecture/vnext-runtime-platform-design.md) (재구축 설계를 검토할 때)
4. [도메인 언어와 모듈 명명 기준](architecture/domain-language-and-module-naming.md) (owner·context·boundary·role을 이름에서 읽는 기준)
5. [Host/Guest Control Slice](architecture/host-guest-control-boundary.md) (현재 code와 acceptance가 실제로 증명한 범위)
6. [Host Local Administration Transport Boundary](architecture/host-local-administration-transport-boundary.md) (C52 descriptor, Console/CLI local transport와 OS authorization boundary를 구현·검토할 때)
7. [Guest Artifact Build Boundary](architecture/guest-artifact-build-boundary.md) (Guest artifact와 PKG의 책임을 구현·검토할 때)
8. [Guest Linux Source Disk Materialization Boundary](architecture/guest-linux-source-disk-materialization-boundary.md) (C73 QCOW2→raw source identity를 구현·검토할 때)
9. [Guest Linux Boot Artifact Extraction Boundary](architecture/guest-linux-boot-artifact-extraction-boundary.md) (C42 source layout과 kernel/initrd/root source extraction을 구현·검토할 때)
10. [Guest Root Storage Partition Assembly Boundary](architecture/guest-root-storage-partition-assembly-boundary.md) (C43 MBR `/dev/vda1` layout과 C42 receipt correlation을 구현·검토할 때)
11. [Guest Artifact Compilation Input Assembly Boundary](architecture/guest-artifact-compilation-input-assembly-boundary.md) (C41 source selection과 C35 identity를 구현·검토할 때)
12. [Guest Product Bootstrap Volume Boundary](architecture/guest-product-bootstrap-volume-boundary.md) (C39 bootstrap intent와 C40 Guest-owned first-boot installation을 구현·검토할 때)
13. [Guest Product Process Supervisor Boundary](architecture/guest-product-process-supervisor-boundary.md) (Guest-local product process와 deployment input을 구현·검토할 때)
14. [Guest Product Service Manager Boundary](architecture/guest-product-service-manager-boundary.md) (systemd unit과 Supervisor boundary를 구현·검토할 때)
15. [Host Edge Proxy Boundary](architecture/host-edge-proxy-boundary.md) (public route와 trust boundary를 구현·검토할 때)
16. [macOS Development Installation Evidence Boundary](architecture/macos-development-installation-evidence-boundary.md) (unsigned PKG/ad-hoc Supervisor local verification과 C24 release proof를 구분할 때)
17. [Release Delivery Proof Attachment Boundary](architecture/release-delivery-proof-attachment-boundary.md) (C24 fragment/evidence review와 immutable candidate를 검토할 때)
18. [Recorder Gateway Data Path](architecture/recorder-gateway-data-path.md) (data plane과 receipt 분리를 구현·검토할 때)
19. [Lab, Artifact Export, and Deletion Lifecycle](architecture/lab-archive-deletion-lifecycle.md) (Lab stop/export/delete lifecycle을 구현·검토할 때)
20. [External Upstream, Time, and Observability](architecture/external-time-observability.md) (external dependency, time, telemetry boundary를 구현·검토할 때)
21. [Cross-platform Provider and Delivery](architecture/cross-platform-delivery.md) (provider selection과 release proof를 검토할 때)
22. [Installation and Update Foundation](architecture/installation-update-foundation.md) (update compatibility와 Host recovery boundary를 검토할 때)
23. [Product Composition and Staged Update](architecture/product-composition-and-staged-update.md) (release bundle, Host staging, updater handoff를 구현·검토할 때)
24. [vNext 참고 패턴과 적용 규칙](architecture/reference-patterns.md) (API/상태/마이그레이션 경계를 설계할 때)
25. [vNext 구현 계획](architecture/vnext-implementation-plan.md) (새 root의 단계별 구현을 시작할 때)
26. [Vital Recorder integration contract](recorder/vital-recorder-integration.md)
27. [Testkit 사용법](testkit/usage.md)
28. [VitalServer recorder Redis key model](recorder/redis-key-model.md)
28. [VitalServer macOS Runtime](runtime/macos/index.md)
29. [Branch 운영 기준](repository/branching.md)

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
