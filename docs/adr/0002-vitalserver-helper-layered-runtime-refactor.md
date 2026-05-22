# ADR 0002: VitalServer Helper Layered Runtime Refactor

## 상태

Accepted

## 배경

VitalServer Helper는 처음에는 macOS local VM launcher/helper로 출발했지만, 제품 방향은 두 가지 실행 형태를 모두 지원해야 한다.

1. Local mode
   - macOS app이 local installed VitalServer appliance를 관리한다.
   - launchd, installed files, privileged CLI, local logs, product update bundle, VM image update bundle을 사용할 수 있다.

2. Remote mode
   - 같은 UI가 remote runtime-control server에 연결된다.
   - iPadOS/macOS client는 macOS-only VM control code를 공유 UI에 직접 들고 있으면 안 된다.
   - 여러 client가 권한에 따라 같은 runtime을 observe/control할 수 있어야 한다.

현재 코드는 `ManagerApp`, `RuntimeCore`, `RuntimeInfrastructure`, `RuntimeOrchestrator`라는 Swift target 구조를 가진다. 파일 단위로는 여러 usecase runner가 추출됐지만, `RuntimeOrchestrator`는 아직 Updater, Supervisor, VM Driver, installer, service control, repair, log 관련 책임을 함께 가진다.

또한 기존 user-facing 용어인 `runtime version`은 너무 많은 책임을 숨긴다. 업데이트 호환성, health/watchdog, VM provider, Service Stack, VM Image, 실제 VitalServer service version이 모두 한 라벨 아래에 섞이면 UI, manifest, release note, 장애 분석이 불명확해진다.

이 문제는 단순한 이름 정리가 아니다. Helper가 현장에 한 번 배포된 뒤에는 기존 updater가 새 update bundle을 읽고 검증하고 적용할 수 있어야 한다. 만약 새 bundle manifest, guest activation contract, rollback policy, rootfs 처리 방식이 기존 updater가 모르는 형태로 바뀌면, 사용자는 update bundle을 가지고 있어도 적용하지 못할 수 있다.

실제로 검토 중 아래 위험이 드러났다.

- `runtimeVersion` 하나로 Helper UI, updater, watchdog, VM provider, Service Stack, VM Image 변경을 모두 표현하면 어떤 변경이 update compatibility에 영향을 주는지 알 수 없다.
- rootfs/base OS 변경을 일반 update bundle에 섞으면 mutable `vm-disk.img`가 보존되는 기존 설치본에서는 “rootfs가 바뀌었는데 왜 OS package가 안 바뀌는가” 같은 오해와 실패가 생긴다.
- updater 자체가 바뀌는 update와 service/container만 바뀌는 update를 같은 위험도로 보면 bridge/two-phase update가 필요한 시점을 놓칠 수 있다.
- platform-specific VM provider 변경을 공통 update처럼 배포하면 macOS/Windows variant가 서로 다른 artifact를 잘못 적용할 수 있다.
- field를 literal/flat version으로 흩뿌리면 앞으로 어떤 component version을 기준으로 호환성을 판단해야 하는지 불명확해진다.

따라서 update 계약은 “설치본이 배포된 뒤에도 기존 updater가 판단할 수 있는 최소 계약”이어야 한다. 새 계약은 적용 가능성 판단에 필요한 field를 명확히 하고, 위험도가 다른 update를 UI와 bundle kind에서 분리해야 한다.

## 결정

VitalServer Helper를 최상위 product/release train으로 보고, 그 아래 layer를 명확히 나눈다.

| Layer | Platform dependency | 책임 | Manifest key |
| --- | --- | --- | --- |
| VitalServer Helper | cross-platform product umbrella | 최상위 관리 제품/클라이언트 패키지, release/support 기준 | `helperVersion` |
| Helper UI | platform-specific | macOS/iPadOS/Windows 등 사용자 인터페이스 | `components.helperUI` |
| Updater | host/platform-specific | product update bundle verify/apply/rollback, manifest compatibility gate, migration/guest activation 조율 | `components.updater`, `minUpdaterVersion` |
| Supervisor | host/platform-aware | health/watchdog/recovery, service state loop, update/rollback 중 recovery suppression | `components.supervisor` |
| VM Driver | platform-specific | macOS Apple Virtualization, Windows provider 등 VM lifecycle provider | `components.vmDriver` |
| Service Stack | mostly guest/service-specific | guest deploy assets, compose, container image bundle, service activation 단위 | `components.serviceStack` |
| VM Image | guest OS/image-specific | Linux guest OS/base rootfs/kernel/initrd class artifact | `components.vmImage` |
| VitalServer service | service-specific | VM 안에서 실행되는 VitalServer app/container | `components.vitalServer` |

Update bundle kind는 두 개만 둔다.

| bundleKind | UI 위치 | 포함 범위 |
| --- | --- | --- |
| `product-update` | Update 탭 | Helper UI, Updater, Supervisor, VM Driver, Service Stack, 개별 service/container, host proxy, migrations |
| `vm-image-update` | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifact |

Hotfix, service-only update, updater bridge update는 새 bundle kind를 만들지 않고 `product-update`의 metadata로 표현한다. 예시는 `channel`, changed component versions, `requiresTwoPhaseUpdate`이다.

Bundle manifest는 flat `runtimeVersion` 중심이 아니라 아래 형태를 기준으로 한다.

```json
{
  "bundleKind": "product-update",
  "helperVersion": "0.2.0",
  "targetPlatforms": ["macos-arm64"],
  "minUpdaterVersion": "0.1.6",
  "components": {
    "helperUI": "0.2.0+macos.1",
    "updater": "0.2.0",
    "supervisor": "0.2.0",
    "vmDriver": "0.2.0+macos.1",
    "serviceStack": "2.3.4-stack.1",
    "vitalServer": "2.3.4"
  }
}
```

아직 현장 배포 전이므로 기존 update manifest와의 하위 호환성은 보장하지 않는다. 새 manifest contract를 기준으로 release automation과 Swift reader를 맞춘다.

## Update 계약 결정

Update compatibility의 source of truth는 Updater version이다.

- `minUpdaterVersion`은 이 bundle을 직접 읽고 적용할 수 있는 최소 Updater version이다.
- `components.supervisor`, `components.vmDriver`, `components.serviceStack` 등은 변경 범위와 표시를 위한 version이지, update 적용 가능 여부의 직접 gate가 아니다.
- updater가 새 manifest/result/status 계약을 이해하지 못하면, 먼저 updater를 갱신하는 bridge/two-phase Product Update가 필요하다.

용어는 아래처럼 구분한다.

| 개념 | 의미 |
| --- | --- |
| Product Update | Helper/Updater/Supervisor/VM Driver/Service Stack/service 변경 |
| VM Image Update | Linux guest OS/rootfs/base image 변경 |
| Two-phase Update | 기존 Updater가 새 Product Update를 바로 이해하지 못할 때, Updater를 먼저 올리고 본 update를 나중에 적용 |

여기서 말하는 two-phase update는 VM Image Update와 Product Update를 같이 묶는다는 뜻이 아니다. Two-phase는 Product Update 내부에서 updater compatibility를 먼저 올린 뒤 본 update를 적용하는 절차다.

```text
Phase 1: 기존 설치본이 이해할 수 있는 형식으로 Updater compatibility layer 갱신
Phase 2: 새 Updater가 실제 Product Update payload 적용
```

VM Image/rootfs/base OS 변경은 별도의 `vm-image-update` 흐름이며 Danger Zone에 둔다. Product Update와 VM Image Update를 같은 release에서 함께 제공해야 할 수는 있지만, 그 경우도 two-phase update라고 부르지 않는다. 필요한 경우에는 paired product/image release 또는 coordinated Product + VM Image update로 표현한다.

Update 흐름은 위험도에 따라 나눈다.

| 흐름 | UI | 주요 artifact | Compatibility 기준 |
| --- | --- | --- | --- |
| Product Update | Update 탭 | Helper UI, Updater, Supervisor, VM Driver, Service Stack, service/container, host proxy, migrations | `bundleKind=product-update`, `minUpdaterVersion`, `targetPlatforms`, optional `requiresTwoPhaseUpdate` |
| VM Image Update | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifact | `bundleKind=vm-image-update`, 별도 운영 데이터 보존/재생성 정책 |

Product Update는 mutable VM disk를 암묵적으로 교체하지 않는다. Service Stack, compose, container image bundle, guest deploy 변경은 guest activation으로 반영한다. VM Image/rootfs/base OS 변경은 별도 VM Image Update로 취급한다.

고민했던 대안과 기각 이유:

| 대안 | 기각 이유 |
| --- | --- |
| 모든 artifact를 하나의 일반 update bundle에 계속 포함 | rootfs/base OS와 service/app 변경의 위험도가 달라 rollback, UI, 운영 데이터 보존 정책이 흐려진다 |
| bundle kind를 hotfix, service-stack, updater-bridge 등으로 많이 나누기 | kind가 늘수록 updater가 알아야 할 분기가 늘어난다. 대부분은 `product-update` metadata로 표현 가능하다 |
| `runtimeVersion` 하나만 유지 | 어떤 component 변경이 compatibility gate인지 알 수 없다 |
| VM Image version을 Helper version과 항상 같이 올리기 | Service Stack이나 UI만 바뀌는 release도 VM Image 변경처럼 보인다. bundle 크기와 운영 위험도도 커진다 |
| platform 구분 없이 공통 bundle만 사용 | VM Driver와 Helper UI는 platform-specific이므로 잘못된 artifact 적용 위험이 있다 |

앞으로 현장 배포가 시작된 뒤에는 이 계약을 깨는 변경을 일반 Product Update로 배포하지 않는다. 필요하면 새 Updater를 먼저 배포하는 bridge/two-phase update를 사용한다.

## 리팩터링 순서

모듈 구조를 바로 크게 나누지 않는다. 진행 중인 usecase extraction을 먼저 마무리하고, 그 다음 product layer 구조에 맞춰 폴더/namespace/target 분리를 진행한다.

### 1. 진행 중인 RuntimeLifecycle extraction 마무리

`RuntimeLifecycle`는 assembler/router 역할로 줄이고 low-level workflow implementation을 밖으로 옮긴다.

이미 추출된 주요 usecase:

- `RuntimeInstallRunner`
- `RuntimeInstallStepExecutor`
- `RuntimeApplyBundleRunner`
- `RuntimeApplyBundlePreflightRunner`
- `RuntimeApplyBundleStepExecutor`
- `RuntimeRollbackRunner`
- `RuntimeRollbackPreflightRunner`
- `RuntimeRollbackStepExecutor`
- `RuntimeWatchdogRunner`
- `RuntimeServiceControlRunner`
- `RuntimeDatastoreRepairRunner`
- `RuntimeConfigureRunner`
- `RuntimeBackupStore`
- `RuntimeMigrationRunner`
- `RuntimeHealthChecker`
- `RuntimeStatusReporter`
- `RuntimeManagedOperationGuard`
- `RuntimeInstallDirectoryPreparer`
- `RuntimeGuestConfigWriter`

남은 extraction 후보:

- `RuntimeInstallDiskProvisioner`
- `RuntimeInstallCloudInitWriter`
- `RuntimeInstallPermissionConfigurer`
- `RuntimeInstallVMConfigWriter`

이 단계에서는 binary/Swift target 분리보다 testable collaborator extraction을 우선한다.

### 2. RuntimeClient boundary 정리

UI는 local file, launchd, privileged CLI, macOS-only API에 직접 의존하지 않는다. `RuntimeClient`를 UI boundary로 유지하고, local-only capability를 명시한다.

현재 방향:

- `ManagerApp`은 UI concern을 가진다.
- `LocalRuntimeClient`는 local filesystem/CLI/launchd adapter를 호출한다.
- Remote mode는 나중에 같은 protocol을 HTTP/SSE adapter로 구현한다.
- `NSOpenPanel`, `NSSavePanel`, `NSWorkspace`는 UI/controller code에 남긴다.
- log export, release metadata, service control, rollback, uninstall, admin password reset은 capability로 노출한다.

### 3. Update/backup/version contract 정리

Updater 책임을 명확히 한다.

- `product-update`와 `vm-image-update`를 manifest/UI/release automation에서 구분한다.
- rootfs/base OS 변경은 일반 Update 탭이 아니라 VM Image Update 흐름으로 둔다.
- `minUpdaterVersion`은 compatibility gate다.
- Supervisor/VM Driver version은 표시와 변경 범위 설명에 사용하되, update 적용 가능 여부를 그 label에서 추론하지 않는다.
- `runtime-version.json`과 About UI는 `runtimeVersion` 한 줄이 아니라 component version document로 전환한다.

### 4. Supervisor/VM Driver 책임 분리

Watchdog은 VM Driver가 아니라 Supervisor 책임이다.

- Supervisor: health evaluation, endpoint readiness, launchd/service state, auto-recovery policy, update/rollback 중 recovery suppression.
- VM Driver: platform-specific VM lifecycle, provisioning input handoff, start/stop, disk/config/cloud-init provider error.

VM boot/storage/network failure reason은 Supervisor가 사람이 이해할 수 있는 상태로 끌어올린다.

### 5. 폴더/namespace를 product layer에 맞춰 재배치

위 extraction이 충분히 끝난 뒤 `RuntimeOrchestrator` 내부를 아래 구조로 재배치한다.

```text
Sources/RuntimeOrchestrator/
  Runtime/
    RuntimeLifecycle.swift        # composition/facade/router
    Constants.swift
    LauncherPaths.swift
  Installer/
  Updater/
  Supervisor/
  VMDriver/
  ServiceControl/
  Repair/
  Logs/
```

Swift Package target 또는 binary 분리는 이 재배치 이후에 판단한다. 당장 target을 쪼개면 import cycle과 test churn이 커질 수 있으므로, 먼저 physical file ownership과 dependency direction을 맞춘다.

### 6. Remote Runtime API 초안

Remote networking은 local boundary가 깨끗해진 뒤 진행한다. API 초안은 아래 resource를 기준으로 한다.

- `GET /runtime/status`
- `GET /runtime/health`
- `GET /runtime/settings`
- `PUT /runtime/settings`
- `GET /runtime/release`
- `GET /runtime/components`
- `GET /runtime/logs`
- `POST /runtime/logs/collect`
- `GET /runtime/logs/export`
- `POST /runtime/product-updates`
- `POST /runtime/product-updates/{id}/apply`
- `GET /runtime/product-updates/progress`
- `POST /runtime/vm-image-updates`
- `POST /runtime/vm-image-updates/{id}/apply`
- `GET /runtime/vm-image-updates/progress`
- `GET /runtime/backups`
- `POST /runtime/rollback`
- `POST /runtime/admin/repair-datastore`
- `POST /runtime/services/start`
- `POST /runtime/services/stop`
- `GET /runtime/service-links`

Streaming은 logs/progress에 SSE를 우선한다. WebSocket은 bidirectional interaction이 필요해질 때만 도입한다.

## 결과

이 결정으로 얻는 것:

- UI와 local macOS runtime control code가 분리된다.
- release/version label이 실제 책임 경계를 드러낸다.
- product update와 VM image update의 위험도가 UI와 manifest에서 분리된다.
- Updater/Supervisor/VM Driver의 책임이 문서와 코드 구조에서 일치한다.
- Remote client/server 구조로 이동할 때 UI를 다시 쓰지 않아도 된다.

감수하는 것:

- 당장은 `vitalserver-vm` binary 하나가 여러 layer의 command를 담을 수 있다.
- `RuntimeOrchestrator` target 이름은 즉시 바꾸지 않는다.
- 기존 manifest 하위 호환성은 포기한다. 아직 현장 배포 전이라는 전제를 둔다.
- component version document와 UI label 정리는 별도 follow-up으로 남는다.

## Guardrails

- `VERSION` 파일을 source of truth로 되살리지 않는다. `release.json`과 generated files를 사용한다.
- 새 bundle kind를 쉽게 늘리지 않는다. 먼저 `product-update` metadata로 표현 가능한지 확인한다.
- Product Update에서 mutable `vm-disk.img`를 암묵적으로 교체하지 않는다.
- VM Image/rootfs/base OS 변경은 Danger Zone 흐름으로 둔다.
- `RuntimeLifecycle`에 새 workflow logic을 계속 추가하지 않는다. 새 usecase는 collaborator로 추출한다.
- Local filesystem, `ditto`, launchd, local CLI, installed paths는 local adapter/usecase 뒤에 둔다.
- Swift code 변경은 `apps/vitalserver-vm-launcher`에서 `swift test`로 검증한다.
