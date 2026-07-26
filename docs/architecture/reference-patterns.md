# VitalServer Runtime Platform vNext 참고 패턴과 적용 규칙

> 상태: **Draft — 설계 입력**
>
> 이 문서는 외부 프로젝트의 구현을 채택하는 문서가 아니다. VitalServer Runtime Platform vNext에서 반복될 설계 문제를 해결하기 위해, 검증된 패턴을 제품의 상태 owner·계약·운영 제약에 맞게 번역한 기준이다.

## 1. 목적과 적용 범위

vNext는 다음을 동시에 다뤄야 한다.

- macOS, Windows, Linux Host와 공통 Guest Runtime
- 번들 또는 외부 VitalServer/Redis upstream
- 장비 프로토콜, 대용량 packet ingress, `.vital` artifact
- 장기 operation, DB state migration, update/rollback
- logs, metrics, traces와 의료 데이터 보호

이를 모두 포괄하는 단일 레퍼런스 제품은 없다. 따라서 특정 framework나 microservice 구성을 복사하지 않고, 각 레퍼런스에서 **경계와 변화 관리에 필요한 규칙만** 가져온다.

| 공통 적용 규칙 | 의미 |
| --- | --- |
| 패턴은 구현체가 아니라 제약을 가져온다 | “Kubernetes처럼 만든다”가 아니라 `spec`과 `status`를 다른 사실로 유지한다. |
| 한 noun마다 process를 만들지 않는다 | 배포 단위는 privilege, traffic, availability 경계가 생길 때만 나눈다. |
| 외부 계약만 엄격히 version한다 | network, process, device, persisted-state 경계는 version한다. 같은 process 내부의 pure port는 typed contract와 test로 보호한다. |
| state owner가 migration도 소유한다 | 다른 component가 DB를 직접 고치거나 missing 값을 default로 채우지 않는다. |
| 기존 제품은 행동 oracle이다 | 기존 source, OpenAPI, fixture, `.feature`는 새 설계의 입력·출력·실패 검증 기준이지 새 domain model의 복사 대상이 아니다. |

## 2. 패턴 1: Resource와 observed state를 분리한다

### 출처

- [Kubernetes Objects — spec과 status](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
- [Kubernetes API concepts](https://kubernetes.io/docs/reference/using-api/api-concepts/)
- [Kubernetes API deprecation policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/)

### 가져올 규칙

하나의 resource에는 운영자가 요청한 사실과 owner가 관측한 사실이 섞이면 안 된다.

- `spec`: 운영자가 선언하거나 command가 바꾸는 **원하는 구성**
- `status`: resource owner가 explicit provider/adapter result로 기록한 **관측 결과**
- `resourceRevision`: resource가 바뀐 순서를 나타내는 revision
- `schemaVersion`: 저장 문서의 구조 버전

`status`는 `spec`을 성공으로 바꾸는 증거가 아니며, 연결이 된다는 사실만으로 delivery, archive indexing, clock synchronization 같은 다른 사실을 만들지 않는다.

### VitalServer 적용

| Resource | `spec` owner | `status`를 쓰는 owner | status의 입력 |
| --- | --- | --- | --- |
| `RuntimeTopology` | Runtime Controller의 topology workflow | Runtime Controller | `VitalServerUpstreamPort`의 connection/capability 결과 |
| `PlatformInstallation` | Host Platform Control | Host Platform Control | Platform Provider/OS의 explicit live result |
| `LabSession` | Lab service | Lab service | virtual recorder lifecycle과 Gateway/Archive의 명시 receipt |
| `ArtifactExport` | Archive Export workflow | Archive Export | finalization, upload, indexing receipt |
| `ClockQuality` | Time Authority configuration workflow | 해당 node의 Time Authority | NTP service와 clock-quality source result |

`Operation`은 resource의 `status` 한 필드로 축소하지 않고 별도의 durable resource로 둔다. 그래야 재시도, 원인, proof, 요청 당시 resource revision을 잃지 않는다.

`OutboundRelayTarget`은 `RuntimeTopology`의 세 번째 profile이 아니다. upstream primary state의 owner와 relay consumer의 owner는 다르므로, 독립 integration resource로 모델링하고 그 결과를 upstream capability나 delivery receipt로 합치지 않는다.

### 가져오지 않을 것

- Kubernetes cluster, CRD, controller loop, eventual reconciliation을 제품 기본 구조로 도입하지 않는다.
- 모든 상태를 eventual consistency로 취급하지 않는다. VitalServer의 command, archive, update는 owner의 terminal receipt가 필요하다.

## 3. 패턴 2: 호환성은 field 모양뿐 아니라 의미까지 보장한다

### 출처

- [Google AIP-180 — Backwards compatibility](https://google.aip.dev/180)
- [Google AIP-151 — Long-running operations](https://google.aip.dev/151)

### 가져올 규칙

동일 API major에서 지켜야 할 호환성은 세 가지다.

1. **source compatibility**: client가 새 client library/contract로 컴파일·실행 가능한가.
2. **wire compatibility**: request/response/event가 기존 decoder와 통신 가능한가.
3. **semantic compatibility**: 기존 consumer가 합리적으로 기대한 의미가 유지되는가.

추가 optional field는 같은 API major에서 가능하다. 그러나 field 삭제, 이름·type 변경, enum의 의미 변경, 기존 optional field의 필수화, error의 success 전환은 breaking change다. 새 major 또는 새 resource를 만든다.

오래 걸리는 작업은 request를 붙잡고 있지 않고 `Operation` resource를 반환한다. 입력 자체가 잘못되어 시작할 수 없으면 command 요청이 즉시 실패한다. 실행 중 실패는 `Operation.state=failed`와 typed failure로 남긴다.

### VitalServer 적용

| Contract | 안정성·버전 단위 | 필수 식별자 |
| --- | --- | --- |
| Operator/Browser Control API | `apiVersion` major | resource ID, `operationId`, request/correlation ID |
| Host ↔ Guest Control API | `apiVersion` major | target resource revision, `operationId` |
| Recorder Socket.IO / self-observation | `protocolVersion` | `recorderId` 또는 `vrcode`, boot ID, sequence |
| Upstream Provider port | contract package version + capability revision | provider ID, request ID, receipt ID |
| Persisted resource document | `schemaVersion` | resource ID, resource revision |

이 문서의 “version”은 product release version과 다르다. 예를 들어 product `2.5.0`은 Control API `v1`, `RuntimeTopology.schemaVersion=3`, external provider capability revision `17`을 동시에 가질 수 있다.

### 가져오지 않을 것

- Google의 URI, resource-name, RPC naming 규칙을 기계적으로 복사하지 않는다.
- internal pure function까지 외부 HTTP API처럼 major version으로 묶지 않는다.

## 4. 패턴 3: 저장 state 변화에는 명시적 upgrader가 필요하다

### 출처

- [Terraform Plugin Framework — State upgrade](https://developer.hashicorp.com/terraform/plugin/framework/resources/state-upgrade)

### 가져올 규칙

저장된 state는 code release보다 오래 남는다. owner는 현재 schema뿐 아니라 지원하는 과거 `schemaVersion`과 각 버전에서 현재 schema로 가는 explicit upgrader를 제공해야 한다.

업그레이드는 다음 순서를 따른다.

1. owner repository가 저장 문서의 `schemaVersion`과 현재 schema를 읽고 검증한다.
2. 지원되는 이전 version이면 owner-owned upgrader가 완전한 새 문서를 만든다.
3. 새 문서를 다시 validation한 뒤 atomic하게 저장하고, 이전/이후 version과 migration result를 operation evidence에 남긴다.
4. decode, permission, invariant, migration 어느 단계든 실패하면 `failed` 또는 `invalid`를 그대로 보고한다. 빈 document나 default success를 만들지 않는다.

### VitalServer 적용

- Host Platform Control SQLite, Guest control ledger, Catalog PostgreSQL, Gateway durability metadata는 각각의 owner가 migration을 제공한다.
- upstream VitalServer Redis와 external provider DB는 Helper가 migration하지 않는다. Provider adapter는 지원 capability와 receipt만 소비한다.
- migration fixture는 지원하는 모든 이전 schema 문서, malformed document, permission failure, interrupted migration을 포함한다.
- 새 schema는 identity를 재발급하지 않는다. 기존 resource ID와 audit trail은 유지한다.

### 가져오지 않을 것

- Terraform plan/HCL/remote state 모델을 제품에 넣지 않는다.
- generic migration script가 모든 owner의 DB를 직접 변경하지 않는다.

## 5. 패턴 4: 외부·legacy 의미는 Anti-Corruption Layer로 격리하고, 기능 단위로 전환한다

### 출처

- [Anti-Corruption Layer pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer)
- [Strangler Fig pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig)

### 가져올 규칙

서로 다른 의미 체계를 가진 시스템 사이에는 번역 계층을 둔다. 이 계층은 protocol, DTO, error, retryability, capability를 번역할 뿐, 새 domain의 policy나 상태 owner가 되지 않는다.

기존 시스템의 교체는 제품 전체를 한 번에 바꾸지 않고 capability별로 한다.

1. 기존 동작을 fixture·integration test·BDD acceptance로 기록한다.
2. 새 adapter/flow를 같은 contract fixture로 검증한다.
3. 명시적인 cutover 대상으로 한 capability만 새 owner에 넘긴다.
4. 성공 증거와 rollback 조건을 확인한 뒤 legacy flow를 제거한다.

### VitalServer 적용

| 경계 | Anti-Corruption Layer | 번역해야 하는 것 | 새 domain에 누출하면 안 되는 것 |
| --- | --- | --- | --- |
| Helper ↔ VitalServer | `VitalServerUpstreamPort` adapter | HTTP/Socket.IO/upload response → capability·receipt | upstream Redis key, route의 우연한 동작, log text |
| Recorder ↔ Gateway | Recorder protocol adapter | device packet/self-observation → versioned envelope·ingress receipt | payload가 없다는 사실로 만든 device health |
| Host ↔ Guest | Platform/Runtime control adapter | OS/VM/provider result → typed platform contract | launchd, Hyper-V, KVM 내부 형식 |
| legacy Helper ↔ vNext | temporary migration facade | legacy request/fixture → new capability contract | legacy state table을 새 app이 직접 읽는 의존성 |

waveform·patient data는 두 authoritative store에 무기한 dual-write하지 않는다. 비교가 필요하면 bounded fixture replay 또는 별도로 승인된 non-production shadow 검증을 사용한다. production cutover 후에는 capability마다 단 하나의 owner가 write한다.

### 가져오지 않을 것

- ACL을 business orchestration, domain policy, hidden fallback의 장소로 만들지 않는다.
- legacy compatibility branch나 proxy를 영구적으로 유지하지 않는다. 각 bridge에는 제거 release와 acceptance proof가 있어야 한다.

## 6. 패턴 5: 장비 protocol은 adapter에서 흡수하고, 공통 domain envelope는 별도로 둔다

### 출처

- [EdgeX Foundry Device Service](https://docs.edgexfoundry.org/3.1/microservices/device/DeviceService/)
- [Vital Recorder integration contract](../recorder/vital-recorder-integration.md)

### 가져올 규칙

장비가 사용하는 native protocol과 product가 사용하는 domain contract는 다르다. protocol adapter는 장비 protocol을 decode/validate하고, versioned common envelope로 바꾼다. device가 말한 자기 상태와 Gateway가 관측한 transport 사실은 같은 field에 합치지 않는다.

### VitalServer 적용

- Vital Recorder 호환 adapter는 `join_vr`, `send_data`, `vrcode` 같은 기존 wire semantics를 보존하거나 명시적으로 version 변환한다.
- Gateway는 socket session, packet receipt, queue/replay receipt를 owner로서 제공한다.
- Recorder self-observation은 `protocolVersion`, `bootId`, sequence, capture time, device-reported health/clock quality를 가진 별도 envelope다.
- Observation Catalog는 source envelope와 Gateway receipt를 조회용 projection으로 보존하지만, device state를 새로 만들지 않는다.

### 가져오지 않을 것

- EdgeX처럼 protocol마다 독립 microservice와 범용 message bus를 기본 배포 구조로 만들지 않는다.
- Gateway가 device health, bed business state, upstream delivery success를 packet receipt에서 추정하지 않는다.

## 7. 패턴 6: Observability pipeline은 product state와 분리한다

### 출처

- [OpenTelemetry Collector architecture](https://opentelemetry.io/docs/collector/architecture/)

### 가져올 규칙

Collector는 receiver → processor → exporter pipeline으로 logs, metrics, traces를 수집·redact·sample·전달한다. product operation과 telemetry export는 별도 사실이다.

### VitalServer 적용

- Host와 Guest Collector는 OTLP, structured log, permitted metrics를 받아 allowlist/redaction/cardinality 정책을 적용한다.
- Collector/exporter의 unavailable, drop, sampling result는 telemetry pipeline health로 노출한다.
- telemetry backend가 정상이라는 사실은 packet delivery, artifact indexing, NTP quality, update 성공의 근거가 될 수 없다.

### 가져오지 않을 것

- raw waveform, packet, patient identifier, secret을 기본 telemetry attribute로 넣지 않는다.
- Collector를 product state repository나 recovery fallback으로 사용하지 않는다.

## 8. vNext에 적용할 계약 카탈로그

| 우선순위 | 계약 | 적용 패턴 | 첫 acceptance proof |
| --- | --- | --- | --- |
| P0 | `RuntimeTopology` + `CapabilityDocument` | Resource/status, compatibility, state upgrade, ACL | bundled/external profile 각각에서 explicit capability와 failure를 표시 |
| P0 | `Operation` | long-running operation, resource lifecycle | start/stop/update/reconfigure가 terminal receipt와 evidence를 남김 |
| P0 | persisted state envelope | state upgrade | 구 schema, malformed schema, interrupted migration이 typed result를 냄 |
| P1 | `IngressReceipt` + Recorder observation envelope | device adapter, compatibility | reconnect/replay/self-observation source를 서로 합치지 않음 |
| P1 | `ArtifactManifest` + export receipt | operation, single writer | Lab stop과 artifact upload/indexing failure가 분리되어 보임 |
| P1 | `ClockQuality` | resource/status | Host·Guest·Recorder clock source가 각각 명시됨 |
| P2 | telemetry pipeline profile | OTel pipeline | backend failure가 product success를 바꾸지 않음 |

## 9. 변경 검토 체크리스트

새 API, event, provider, stored state를 바꾸는 change는 아래 질문에 모두 답해야 한다.

1. resource 또는 사실의 owner는 누구인가?
2. 이 변경은 public/cross-process/device/persisted/internal 중 어느 경계인가?
3. version 범위는 `apiVersion`, `protocolVersion`, `schemaVersion`, capability revision 중 무엇인가?
4. 기존 consumer의 source, wire, semantic 의미가 유지되는가? 아니라면 새 major 또는 explicit migration인가?
5. missing, invalid, unavailable, failed, stale, empty, unsupported를 어떤 typed result로 구분하는가?
6. 장기 작업이라면 command의 즉시 결과와 `Operation` terminal result가 분리되는가?
7. 저장 state가 바뀌면 owner-owned migration, old-schema fixture, interrupted/failure test가 있는가?
8. external/legacy 의미를 새 domain model에 직접 누출하지 않았는가?
9. cutover 후 authoritative writer가 하나인지, legacy bridge의 제거 조건·release가 정해졌는가?
10. user-visible 변화라면 scenario catalog, `.feature`, contract fixture가 함께 갱신되었는가?

## 10. 관련 문서

- [VitalServer Runtime Platform vNext 설계 초안](vnext-runtime-platform-design.md)
- [제품 사용 시나리오 카탈로그](../product/user-scenarios.md)
- [현재 Runtime contract와 상태 규칙](../../site-docs/dev/runtime-contracts.md)
- [Vital Recorder integration contract](../recorder/vital-recorder-integration.md)
- [Recorder ingress audit contract](../recorder/ingress-audit-contract.md)
