# VitalServer Runtime Platform vNext 구현 계획

> 상태: **Foundation capability와 deterministic release composition 구현 완료. macOS Guest artifact productization은 C42 immutable ARM64 Linux source extraction, C43 explicit root-storage partition assembly, C41 source-to-C35 assembly, C35/C37–C40 bootstrap-volume contract까지 구현되었다. C42는 gzip source `vmlinuz`를 VZ가 직접 소비하는 uncompressed ARM64 `boot/Image`로 normalize한다. C32 `GuestRuntimeDiskProvisioning`은 immutable C34 root와 Host-persistent runtime workspace를 분리하며, local ad-hoc entitlement supervisor에서 receipt-guarded workspace creation, Ubuntu cloud-init, serial login prompt까지 diagnostic smoke를 통과했다. C47은 C41→C35→PKG→expanded-PKG verification을 one named release-build declaration/receipt로 연결한다. unsigned PKG + ad-hoc Supervisor의 local installation/reboot evidence는 별도 development journal로 수집할 수 있다. PKG composition/verification과 development journal은 immutable payload/local verification evidence일 뿐이다. Apple Developer ID PKG native installation, Guest Runtime readiness/transport, C24 clean-host proof는 여전히 별도 acceptance로 남아 있다.**
>
> 이 문서는 [vNext 설계 초안](vnext-runtime-platform-design.md)의 목표 구조를 실제 새 code root에서 구현하는 순서와 완료 기준을 정한다. 현재 Helper의 source를 정리·이식하는 계획이 아니라, 새 codebase를 만들고 기존 제품을 behavior oracle로만 사용하는 계획이다.

## 1. 결정 요약

### 1-1. 새 구현 root

새 product code의 유일한 root는 repository 최상위의 **`runtime-platform/`** 이다.

```text
tirosh-vitalserver/                  # legacy product, reference, release history
  apps/                              # 기존 구현 — vNext runtime dependency 금지
  packages/                          # 기존 구현 — vNext runtime dependency 금지
  docs/                              # 설계·reference 문서
  runtime-platform/                  # 새 product implementation root
```

`runtime-platform/`은 나중에 독립 repository로 추출할 수 있어야 한다. 따라서 parent root의 Python workspace, Node package, Swift package, Make target, runtime data path를 import하거나 전제하지 않는다.

기존 repository는 다음 용도로만 사용한다.

- Recorder wire protocol과 upstream behavior를 재현한 fixture의 출처
- existing product와의 integration/acceptance comparison harness
- 운영 시나리오, troubleshooting, package lifecycle에서 얻은 negative evidence

새 runtime은 기존 app source, legacy state DB, upstream Redis key, JSON status artifact를 직접 읽지 않는다. 필요한 legacy behavior는 아래처럼 vNext root 안의 frozen fixture로 고정한다.

```text
runtime-platform/acceptance/reference-fixtures/
  manifest.v1.json                   # source revision/locator, digest, sanitization, C1–C6 mapping
  recorder-socketio/                 # join_vr/send_data structural wire observations
  recorder-ingress/                  # durable spool and upstream-unavailable outcome observations
  vital-file-upload/                 # multipart library-upload observations, not export receipts
```

### 1-2. 첫 release의 경계

첫 release는 clean install을 대상으로 한다. 기존 Helper에서 vNext로의 in-place DB/data migration은 이 단계에 포함하지 않는다. 나중에 필요해지면 legacy data를 직접 공유하지 않고 `LegacyImportOperation`이라는 별도, 명시적, 되돌릴 수 있는 capability로 설계한다.

첫 production vertical slice의 target은 다음으로 제한한다.

```text
macOS Host
  → Host Platform Agent
  → Linux Guest Runtime
  → bundled VitalServer upstream
  ← Recorder Gateway ← Vital Recorder / TestKit
```

Windows, Linux Host, external upstream, Lab replay, long-term archive, enterprise NTP profile은 같은 계약을 재사용하는 뒤 단계다. 첫 slice의 실패를 다른 profile로 자동 전환하지 않는다.

### 1-3. 실제 실행 단위와 product role

현재 제품 topology는 서로 다른 owner를 숨기지 않기 위해 다음 executable
product role을 구분한다.

| Unit | 실행 위치 | 주 책임 | 별도 unit인 이유 |
| --- | --- | --- | --- |
| **Host Agent** | Host OS service | install/update, provider lifecycle request, Host-owned operation/settings | Host privilege와 durable Host state 경계 |
| **Host Edge Proxy** | Host OS service | C36 public HTTP/WebSocket trust boundary와 configured-route forwarding | Recorder/Browser traffic trust boundary를 Host Agent control facade와 섞지 않음 |
| **Guest Product Process Supervisor** | Linux Guest systemd service | Guest Runtime과 Recorder Gateway라는 required child process lifetime | service-manager policy와 child lifetime policy를 child state owner와 섞지 않음 |
| **Guest Runtime** | Linux Guest child process | topology, operations, Lab, archive, Catalog의 workflow·read API | product control/data metadata owner |
| **Recorder Gateway** | Linux Guest child process | Socket.IO protocol, connection, durable spool/replay, ingress receipt | high-volume/untrusted device traffic와 backpressure 경계 |
| **Runtime PWA** | Host Agent가 serve하는 static artifact | owner read 표시와 command 요청 | presentation만 분리 |

macOS Virtualization Framework access는 Host Agent의 public API가 아니라 **macOS virtual machine supervisor**가 담당한다. supervisor는 Host Agent가 호출하는 OS-specific effect adapter이며 `VZVirtualMachine`의 process-lifetime owner다. Host operation state의 owner는 아니며 독립 product service로도 동작하지 않는다.

Guest Runtime 안에서는 `Topology`, `Operation`, `Lab`, `Archive Export`, `Observation Catalog`을 처음에는 module로 둔다. 이 중 하나를 별도 process로 옮기는 조건은 명확한 traffic, privilege, availability, independent release 요구가 생겼을 때뿐이다.

## 2. 새 root의 물리 구조

```text
runtime-platform/
  README.md                          # 범위, local quick start, legacy non-dependency rule
  Makefile                           # root-local build/test/acceptance entry points
  contracts/                         # language-neutral, versioned contract source
    json-schema/v1/                  # C1–C12와 이후 Clock/observation/telemetry JSON Schema
    openapi/control.v1.json          # public control-resource source
    catalog/v1.json                  # contract-to-owner map
    policies/v1/                     # cross-owner transition graph
    examples/v1/                     # positive/negative decode evidence
    compatibility/v1/                # frozen same-major compatibility baseline
    generated/                       # resolved OpenAPI bundle; no hand edits
  services/
    host-agent/                      # Go: Host control, SQLite owner, Linux/Windows adapters
    host-edge-proxy/                 # Go: C36 Host public HTTP/WebSocket trust boundary
    guest-product-process-supervisor/ # Go: Guest Runtime + Recorder Gateway child-process lifetime
    guest-runtime/                   # Go: operations, topology, Lab, archive, Catalog workflows
    recorder-gateway/                # TypeScript/Node: Socket.IO v2-compatible ingress and spool/replay
    runtime-pwa/                     # TypeScript/React: generated client, no owner logic
  providers/
    macos-virtualization/            # Swift: Apple Virtualization effect bridge only
  product/
    profiles/                        # bundled/external, time, telemetry declarations
    guest/                           # image, Compose, systemd, storage declarations
    packaging/                       # OS-specific artifact inputs; no application policy
  acceptance/
    features/                        # Gherkin user journeys
    reference-fixtures/              # frozen legacy behavior oracle
    harness/                         # real Host/Guest/upstream/device test runners
  tooling/
    *.py                             # boundary, fixture, contract generator and verifier
```

### 2-1. 언어와 build 경계

| 영역 | 초기 구현 선택 | 이유 | 공유 방식 |
| --- | --- | --- | --- |
| Host Agent, Guest Runtime | Go | long-running service, static distribution, Windows/Linux OS service integration | 서로 다른 module; HTTP/JSON contract만 공유 |
| macOS virtual machine supervisor | Swift | Apple Virtualization Framework와 signing/runtime integration | Host Agent가 retained local process protocol로 호출 |
| Recorder Gateway | TypeScript/Node | Socket.IO v2, binary frame, WebSocket 호환성을 먼저 실제 device fixture로 증명 | versioned event schema와 ingress receipt |
| PWA | TypeScript/React | OpenAPI-generated client와 operator UI | public Control API만 호출 |
| Test/fixture/dev tooling | Python 또는 각 service test runner | existing TestKit과 protocol evidence 재사용 | production runtime dependency 금지 |

Go 또는 TypeScript shared “domain package”를 모든 service가 import하게 만들지 않는다. 공유되는 것은 `contracts/`의 schema와 generated transport types뿐이다. Contract kernel capability는 resolved OpenAPI bundle을 생성·검증하며, 실제 Go/TypeScript client emission은 consumer module이 생길 때 추가한다. 순수 domain policy가 한 service 안에서만 쓰이면 그 service의 `internal/<bounded-context>domain`에 둔다. 예를 들어 `hostagentdomain`, `guestruntimedomain`, `guestproductprocesssupervisordomain`처럼 owner와 bounded context가 import path에 남아야 한다.

Recorder Gateway의 Node 선택은 영구적인 선결정이 아니다. **protocol compatibility spike**에서 실제 Engine.IO v3 / Socket.IO protocol-v4(Recorder Socket.IO v2) handshake, binary frame, reconnect, command dispatch fixture를 통과해야만 확정한다. 통과하지 못하면 Gateway runtime 선택을 다시 ADR로 결정하며, Guest Runtime과 public contracts는 바꾸지 않는다.

### 2-2. 의존성 규칙

1. `services/*`는 sibling source, database table, local file을 import/read하지 않는다.
2. `contracts/`는 I/O·DB·fallback 없이 schema, enum, error/receipt type만 가진다.
3. Host Agent는 Guest 내부 filesystem/container/process를 읽지 않고 Guest Control API result만 소비한다.
4. Guest Runtime은 Host filesystem/service/VM state를 읽지 않고 Platform Control contract만 소비한다.
5. Recorder Gateway는 upstream Redis schema를 product API로 노출하지 않는다.
6. `product/` manifest는 deployment declaration이며 state transition policy를 구현하지 않는다.
7. `acceptance/reference-fixtures`의 update는 provenance와 contract assertion 변경을 함께 review한다.

## 3. 먼저 고정할 계약

endpoint 목록을 먼저 늘리지 않는다. 아래 여섯 resource/event document를 먼저 정의하고 code generation·negative decode test를 붙인다.

| 순서 | 계약 | owner | 첫 구현에서 필요한 최소 내용 |
| --- | --- | --- | --- |
| C1 | `ReadResult<T>` | 각 read owner | `available/missing/invalid/unavailable/failed/stale/empty/unsupported`, value 또는 typed issue |
| C2 | `Operation` | Host Agent 또는 Guest Runtime | ID, kind, target, requested revision, state, failure, evidence reference, timestamps |
| C3 | `RuntimeTopology` | Guest Runtime | bundled/external `spec`, connection/capability `status`, revision, secret reference |
| C4 | `CapabilityDocument` | Provider adapter result를 Guest Runtime이 보존 | provider identity, revision, supported command/read, explicit `unsupported` |
| C5 | `IngressReceipt` | Recorder Gateway | connection/session, durable spool handoff, delivery request/result correlation |
| C6 | `ArtifactManifest`/`ExportReceipt` | Archive Export module | source finalization, immutable artifact identity, upload/index receipt |

Host/Guest control capability는 아래 C7–C12를 추가했다. Recorder delivery capability는 C13 `DeliveryReceipt`로 ingress durability와 one-upstream-attempt outcome을 분리한다. `ClockQuality`와 Recorder self-observation envelope는 이 kernel이 안정된 뒤 추가한다. 단, 모든 service는 처음부터 `operation.id`, `request.id`, `service.version`을 structured log/trace correlation으로 낸다.

| 순서 | 계약 | owner | Host/Guest control 최소 내용 |
| --- | --- | --- | --- |
| C7 | `PlatformInstallation` | Host Agent | Host release와 data directory의 explicit resource |
| C8 | `GuestRuntimeControlEndpoint` | Host Agent | configured Runtime Control HTTP target과 Platform Provider/transport observation의 분리 |
| C9 | `GuestLifecycleCommand` | Host Agent | request ID와 expected resource revision을 가진 lifecycle command |
| C10 | `ProviderLifecycleRequest` / `ProviderLifecycleResult` | macOS provider | OS/VM effect와 actual observed result |
| C11 | `FacadeForwardingFailure` | Host Agent | Guest command forward 후 delivery existence가 unknown인 결과 |
| C12 | `CommandAdmissionFailure` | Host Agent 또는 Guest Runtime | durable operation admission 자체가 unknown인 결과 |
| C13 | `DeliveryReceipt` | Recorder Gateway | ingress receipt와 분리된 one-upstream-attempt outcome 및 retry disposition |

Update foundation capability는 C25–C29로 installer/update compatibility boundary를 추가했다. C25는
현재 updater가 검증하는 immutable bootstrap envelope이고, C26은 staged next
updater만 해석하는 evolving layer plan이다. C27/C28/C29는 각각 Host admission·
bootstrap/completion command, per-layer execution evidence, Host SQLite journal을
분리한다. 상세는 [Installation and Update Foundation](installation-update-foundation.md)을 따른다.

## 4. Capability delivery sequence

### Foundation workspace — boundary를 code로 강제하는 빈 workspace

**목적:** 새 root를 만들되, 아직 legacy 기능을 복사하지 않는다.

1. `runtime-platform/README.md`, root-local `Makefile`, `.gitignore`, license/dependency inventory를 만든다.
2. `contracts/`, 네 service, macOS provider, `product/`, `acceptance/`의 빈 module과 각 책임 README를 만든다.
3. CI에 `runtime-platform/*` 전용 lint/test/contract-generation lane을 추가한다. parent Python workspace와 legacy package build를 요구하지 않는다.
4. architecture test로 sibling source import, parent `../apps`/`../packages` runtime import, cross-service database access를 금지한다.
5. frozen reference fixture의 provenance format과 capture command를 만든다.

**완료 조건:** 새 root만 checkout해도 root-local unit/contract test가 실행되고, legacy source import를 시도하면 CI가 실패한다.

### Contract kernel — compatibility harness

**목적:** 가장 먼저 바뀌기 어려운 의미를 executable specification으로 만든다.

1. C1–C6 JSON Schema와 Control API `v1` OpenAPI source를 작성한다.
2. canonical `Operation` transition graph를 executable policy로 고정한다. 각 owner service가 생기면 이 graph에 conform하는 pure policy를 해당 service 안에 구현한다.
3. command input failure와 operation execution failure를 다르게 model/test한다.
4. `schemaVersion` envelope와 owner-owned migration rule을 고정한다. migration implementation은 persistent owner와 실제 이전 schema가 생길 때만 추가한다.
5. current Recorder `join_vr`/`send_data`, VitalServer delivery/upload의 positive·negative fixture를 reference source에서 고정한다.
6. schema compatibility test는 optional add, removed/renamed field, enum semantic change, invalid/missing document를 검증한다.

**완료 조건:** 아직 VM이나 upstream 없이도 모든 C1–C6 document의 encode/decode, version, invalid/unsupported result, operation terminal state가 자동 검증된다.

### Host/Guest control slice — macOS

**목적:** 제품이 설치된 Host와 Guest 사이의 ownership을 실제로 증명한다.

1. Go Host Agent는 Host SQLite에 `PlatformInstallation`, Host operation, Guest endpoint resource를 저장한다.
2. Swift macOS virtual machine supervisor는 Apple Virtualization effect만 실행하고 typed live result를 Host Agent에 반환한다.
3. Go Guest Runtime은 `GET /runtime/capabilities`, `GET /runtime/topology`, `GET /runtime/operations/{id}`와 topology apply command를 제공한다.
4. Host Agent는 유일한 public facade로서 `/platform/*`을 직접 소유하고 allowlisted `/runtime/*`을 Guest로 forward한다. Host state와 Guest response를 합성하지 않는다.
5. PWA product UI는 이 control slice의 구현 범위가 아니다. 이후 PWA는 generated client로 topology/read/operation만 표시하며, Lab·recorder·settings owner logic을 갖지 않는다.
6. Host start/stop/reboot와 Guest endpoint unavailable/transport failure를 distinct result로 검증한다.

**완료 조건:** real Host Agent와 real Guest Runtime process가 서로 다른 SQLite state를 소유한 상태에서, public HTTP만 사용해 start → topology read → stop/reboot → typed recovery read를 자동 검증한다. provider outcome/admission/outcome-persistence failure가 success 또는 empty로 바뀌지 않는 unit/HTTP test가 있어야 한다. 실제 VM image, signed installer, clean macOS install/reboot proof는 release gate다. 상세는 [Host/Guest Control Slice](host-guest-control-boundary.md)를 따른다.

### Recorder data path — bundled upstream

**목적:** 첫 실제 device data vertical slice를 만든다.

1. Guest Runtime은 `bundled-upstream` `RuntimeTopology`를 apply하고 provider capability를 저장한다.
2. Recorder Gateway protocol spike에서 Socket.IO v2 handshake, `join_vr`, `send_data`, binary frame, reconnect fixture를 실제 upstream과 통과시킨다. legacy command wire shape는 parsing/explicit unsupported acknowledgement까지만 증명하며 command execution을 몰래 재도입하지 않는다.
3. Gateway는 packet을 durable spool에 먼저 기록하고 `IngressReceipt`를 만든다. upstream delivery worker는 receipt correlation을 유지한다.
4. Upstream adapter는 HTTP/socket success가 아니라 `DeliveryReceipt`로 delivery result를 반환한다.
5. Gateway connection/packet receipt, upstream delivery receipt, upstream observation read를 하나의 `online` 값으로 합치지 않는다.
6. bounded replay, backpressure, spool unavailable, upstream unavailable, duplicate/retry scenario를 integration test로 추가한다.

**완료 조건:** 실제 TestKit 또는 certified Recorder fixture가 packet을 보내고, Gateway durable receipt와 upstream delivery receipt를 각자 조회할 수 있다. upstream 장애가 `empty` recorder 목록으로 보이지 않는다. 상세 state owner와 non-proof는 [Recorder Gateway Data Path](recorder-gateway-data-path.md)를 따른다.

### Lab and archive lifecycle — deletion boundary

**목적:** 이번 제품에서 반복된 stop/upload/delete 문제를 새 owner model로 해결한다.

1. Guest Runtime 내부 module로 `LabSession`, virtual recorder resource, start/stop `Operation`을 추가한다.
2. `ArtifactExport`는 Lab session stop과 독립된 resource/operation으로 만든다.
3. source finalization → immutable manifest → upload → index verification을 receipt로 연결한다.
4. hide, detach, delete를 별도 command/state machine으로 만들고 delete guard와 cascade policy를 문서화한다.
5. delete 성공 후 session, read model, spool, raw source, artifact manifest의 잔존 여부를 acceptance로 증명한다.

**완료 조건:** Lab stop은 export 실패와 별개로 정확한 terminal state를 갖고, delete는 orphan를 남기지 않거나 남긴 resource를 explicit retained 상태로 보고한다.

### External upstream, time, and observability — capability profile

**목적:** 외부 dependency와 운영 사실을 새 domain을 오염시키지 않고 추가한다.

1. `external-upstream` provider adapter와 certified capability fixture matrix를 구현한다.
2. external upstream에서는 lifecycle/update/backup을 노출하지 않고 지원 capability만 command/read로 공개한다.
3. `OutboundRelayTarget`을 `RuntimeTopology`와 독립된 integration resource로 추가한다.
4. Host/Guest Time Authority와 `ClockQuality` contract, enterprise NTP profile을 구현한다. device self-observation은 별도 source로 Catalog에 기록한다.
5. Host/Guest OTel Collector profile을 추가한다. redaction, bounded cardinality, pipeline unavailable/drop status를 acceptance로 검증한다.

**완료 조건:** bundled/external profile이 같은 UI/API에 보이더라도 unsupported capability와 failure reason이 명시적으로 다르고, telemetry/NTP 결과가 delivery success로 승격되지 않는다.

### Windows/Linux provider and delivery hardening

> 상태: **구현 및 portable acceptance 완료. OS별 clean-host release proof는 C24에서 pending으로 보존한다.**

**목적:** OS 차이를 product core 밖으로 격리한 채 platform support를 넓힌다.

1. Go Host Agent는 one-of-three provider selection을 검증하고 C21 invocation으로 C10 lifecycle request, request ID, expected endpoint revision을 selected bridge에 전달한다.
2. Windows Hyper-V/SCM와 Linux KVM/libvirt/systemd bridge는 C10 result와 C22 component evidence를 반환하며 다른 provider/native profile로 fallback하지 않는다.
3. C23 plan과 C24 proof set은 OS별 installer/package, service registration, clean uninstall, reboot, update/rollback, SBOM/notices stage를 모두 선언한다.
4. release artifact는 clean-host install → reboot → update → rollback → uninstall/reinstall proof를 모두 가져야 하며, proof가 없으면 `pending`/`failed`로 남긴다.

**완료 조건:** 특정 OS provider가 실패해도 다른 OS/native profile로 fallback하지 않고, 해당 provider의 typed failure와 evidence만 보고한다. portable suite는 Host composition/contract/cross compile을 검증한다. 실제 OS install/reboot/update/rollback/uninstall은 matching clean-host runner의 C24 evidence 없이는 완료 또는 release success로 주장하지 않는다. 상세는 [Cross-platform Provider and Delivery](cross-platform-delivery.md)를 따른다.

### Immutable bootstrap update foundation

> 상태: **구현 및 portable acceptance 완료. native bootstrap/package effect와 C24 clean-host proof는 subsequent delivery capability에 남는다.**

1. C25 signed bootstrap envelope과 C26 next-updater-only product specification을 분리한다. C25에는 `minimumUpdaterVersion` gate가 없으며, 현재 Host updater가 C26을 해석하지 않는다.
2. Host Agent는 C27 request ID/installation revision을 확인하고 C29 journal을 Host SQLite에 durable하게 저장한다. `handoff-pending`은 native handoff effect 전에 commit한다.
3. separate `host-updater` module은 C26 layer order/dependency/rollback plan을 parse하며 Host platform layer가 마지막인지 확인한다. 선택된 layer effect executor가 남긴 explicit C28 evidence를 C30/C26와 대조한 뒤 C27 Host-local completion으로 제출할 수 있지만, effect 자체를 추측하거나 성공으로 만들지는 않는다.
4. C28 layer/rollback evidence가 모든 declared layer의 성공을 명시할 때만 Host가 C7 installed release revision을 전진시킨다. failed/unavailable/unsupported evidence, invalid trust, persistence ambiguity는 success/fallback이 아니다.
5. restart recovery는 `bootstrap-staged`/`handoff-pending` journal의 idempotent handoff만 반복한다. `applying` next updater의 내부 상태는 Host가 추측하지 않는다.

**완료 조건:** portable acceptance가 C25→C29 handoff, request/report idempotency, restart recovery, C26 ordering, unavailable bootstrap, invalid C28 report가 release를 전진시키지 않는 것을 public contract로 증명한다. macOS native signature/file staging/PKG activation, three layer actual replacement, update/rollback clean-host evidence는 아직 완료가 아니다.

## 5. 첫 12개 구현 change

각 change는 독립 review·revert가 가능해야 한다.

1. `chore(runtime-platform): create isolated root and CI lane`
2. `docs(runtime-platform): record ownership and legacy-fixture policy`
3. `feat(contracts): add read-result and operation v1 schemas`
4. `feat(contracts): add topology and capability v1 schemas`
5. `test(contracts): add compatibility and negative-decode harness`
6. `feat(host-agent): persist platform installation and operation resources`
7. `feat(guest-runtime): expose capabilities, topology, and operation reads`
8. `feat(control): add authenticated facade and allowlisted runtime forwarding`
9. `feat(macos-provider): add typed VM lifecycle effect bridge`
10. `test(acceptance): prove Host/Guest ownership, lifecycle, stop/reboot, and typed recovery`
11. `spike(recorder-gateway): prove Socket.IO v2/binary-frame compatibility`
12. `feat(recorder-gateway): add durable ingress receipt and bundled delivery worker`

11번이 실패하면 Gateway runtime technology decision을 다시 연다. 12번 이후에만 Lab, external upstream, Windows/Linux 작업을 병렬화한다.

## 6. Scope-based verification and release gate

| 범위 | 자동 검증 | 실제 환경 검증 | 다음 capability guard |
| --- | --- | --- | --- |
| contracts | schema, codegen, compatibility, negative decode | consumer fixture replay | unsupported/invalid을 success로 바꾸지 않음 |
| Host/Guest | state machine, repository, HTTP contract | real process/SQLite public-HTTP ownership acceptance | Host가 Guest file/log를 읽지 않음 |
| Gateway | protocol parser, spool/replay policy | real Socket.IO/Recorder fixture | ingress receipt와 delivery receipt 분리 |
| archive | transition/migration unit test | upstream upload/indexing | stop과 export terminal result 분리 |
| external upstream | adapter fixture matrix | certified external endpoint | capability를 version/header로 추정하지 않음 |
| NTP/OTel | policy/redaction test | supported network/collector profile | telemetry/time을 product success로 사용하지 않음 |
| Guest artifact compilation | C35 input/builder identity, declared output/C34/receipt atomic-publication test | release-approved ARM64 Linux builder and boot smoke | legacy cache/download/default base를 Guest state로 사용하지 않음 |
| OS delivery | package unit/inventory test | clean-host lifecycle runner | package build와 installed success를 혼동하지 않음 |
| update foundation | C25–C29 schema, Host journal/state-machine, next-updater plan, portable handoff acceptance | native bootstrap/staging, package activation, clean-host update/rollback runner | current updater가 C26을 parse하거나 missing trust를 success로 바꾸지 않음 |

## 7. 구현 중 지켜야 할 운영 규칙

- production data의 dual-write, shared legacy DB, direct upstream Redis read는 금지한다.
- `Operation` 없이 long-running side effect를 성공으로 반환하지 않는다.
- API compatibility bridge는 deprecation release와 제거 acceptance가 있을 때만 만든다.
- 새 schema migration은 owner별로 작은 change로 작성하고 old-schema fixture를 같은 change에 넣는다.
- PWA는 API contract generated type만 사용한다. UI state는 product state owner가 아니다.
- 모든 production service는 structured logs를 처음부터 내지만, OTel backend 도입 전에도 log text를 domain state로 파싱하지 않는다.
- external VitalServer 및 Redis credential은 `credentialReference`로만 전달하며 API, trace, support export에 원문을 남기지 않는다.

## 8. 착수 전 확인할 결정

아래는 implementation을 시작하기 전에 확정해야 하는 범위 결정이다.

| 결정 | 제안 | 확정이 필요한 이유 |
| --- | --- | --- |
| 새 root 이름 | `runtime-platform/` | 새 product와 legacy source의 import boundary를 CI로 강제하기 위해 |
| 첫 Host | macOS | Apple Virtualization 경험과 현재 package acceptance를 가장 빨리 재사용하기 위해 |
| 첫 topology | `bundled-upstream` | external capability 조합을 data path가 증명된 뒤 열기 위해 |
| legacy install migration | 첫 release 제외 | shared state/dual-write 없이 새 owner model을 검증하기 위해 |
| Gateway technology | Node/TypeScript provisional, protocol compatibility spike로 확정 | Socket.IO v2/binary frame real compatibility가 product risk이기 때문에 |
| public API | Host Agent single facade, Guest `/runtime/*` forward | UI와 Host/Guest owner state를 분리하기 위해 |

Foundation부터 update capability까지의 구현은 이 dependency order를 따른다. `ReleaseBundleComposition`은 signed C25 bundle을 만들고, Host는 C30 staged invocation과 C31 durable handoff를 atomically publish하며, separate next updater는 C26을 계획하고 C28/C27 completion을 제출한다. macOS Guest artifact productization은 C42 `GuestLinuxBootArtifactExtractionDeclaration`/receipt로 one immutable ARM64 Linux image에서 kernel/initrd/whole-disk ext4 source를 추출하고, C43 `GuestRootStoragePartitionAssemblyDeclaration`/receipt로 그 source를 declared MBR `/dev/vda1` raw root base로 조립한다. C41 `GuestArtifactCompilationInputAssemblyDeclaration`/receipt는 named outputs와 service artifacts의 build-machine source selection을 C35 밖에 격리한다. C35 `GuestArtifactCompilationCommand`와 `GuestArtifactCompiler`는 explicit input/builder/C34 receipt를 관리한다. Selected `GuestProductBootstrapArtifactComposer`와 C40 `GuestProductBootstrapVolumeCompositionPlan`/`GuestProductBootstrapVolumeComposer`는 C37 `GuestProductProcessDeploymentConfiguration`/Supervisor, C38 `GuestProductServiceManagerDeploymentConfiguration`/deterministic systemd unit, C39 `GuestProductBootstrapConfiguration`을 Host-attachable RAW storage image 안의 Guest-visible ISO9660 `CIDATA` bootstrap partition으로 전달한다. C41→C35 release-candidate composition은 실제로 실행되어 C34/C35 artifact identity를 만들었다. 2026-07-18에는 ad-hoc entitlement를 가진 Supervisor가 C32 `GuestRuntimeDiskProvisioning`으로 immutable release root와 별도 `GuestRuntimeDiskWorkspace`를 만들고, C21 `start=running`, cloud-init, `multi-user.target`, `serial-getty@hvc0`, Ubuntu login prompt까지 local diagnostic smoke에서 관측했다. immutable source digest와 Guest-written runtime disk digest도 서로 달라 ownership split을 확인했다. unsigned PKG와 ad-hoc-entitled Supervisor를 사용하는 local installation/reboot path는 별도 `MacOSDevelopmentInstallationEvidenceJournal`에 기록하며 C24 release proof를 만들지 않는다. 이 사실은 local VZ boot/development installation evidence일 뿐 Apple Developer ID PKG installation, Host Agent→Guest Runtime transport/readiness, update migration, 또는 C24 clean-host proof는 아니다. 다음 work는 Developer ID Supervisor/PKG와 clean Host에서 이 separate evidence chain을 수집하고, 두 C23 Host service registration, explicit C9 Guest start, Guest Runtime Control transport, update/rollback/uninstall 증거를 C24에 기록하는 것이다.
