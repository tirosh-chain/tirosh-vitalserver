# ADR 0004: Product Update and VM Image Update Contract

## 상태

Accepted, implementation in progress

## 배경

VitalServer Helper는 현장에 설치된 뒤에도 offline/online update bundle로 갱신되어야 한다. 이때 가장 큰 제약은 새 bundle을 적용하는 주체가 이미 현장에 배포된 Updater라는 점이다.

기존 Updater가 새 update bundle을 읽고 검증하고 적용할 수 있어야 한다. 새 bundle manifest, guest activation contract, rollback policy, rootfs 처리 방식이 기존 Updater가 모르는 형태로 바뀌면 사용자는 update bundle을 가지고 있어도 적용하지 못할 수 있다.

이 문제는 새 bundle 안에 새 Updater가 포함되어 있어도 해결되지 않는다. 새 Updater를 꺼내고 실행하기 전까지는 기존 Updater가 먼저 bundle을 열고, manifest를 해석하고, checksum/signature를 검증하고, 적용 순서와 rollback 범위를 결정해야 한다. 기존 Updater가 이 단계에서 새 형식이나 새 절차를 이해하지 못하면 새 Updater payload까지 도달할 수 없다.

대표적인 실패 사례는 아래와 같다.

- Manifest schema가 바뀌어 기존 Updater가 `bundleKind`, `components`, `schemaVersion` 같은 field의 의미를 모른다.
- Bundle packaging 방식이 폴더 layout에서 `tar.gz` archive로 바뀌거나 artifact 이름/checksum 위치가 바뀐다.
- Guest activation, service stop/start, rollback snapshot, status/result file 위치 같은 적용 절차가 바뀐다.
- Signature/checksum, required artifact, platform filtering 같은 검증 계약이 바뀐다.
- Product Update와 VM Image/rootfs 변경을 섞어서 기존 Updater가 mutable VM disk 보존 정책이나 base image 교체 정책을 판단하지 못한다.

따라서 update 가능 여부는 bundle 안의 새 코드가 아니라 현재 설치된 Updater가 판단한다. 현재 Updater가 새 Product Update를 직접 이해하지 못하면, 먼저 기존 Updater가 이해할 수 있는 bridge Product Update로 Updater 자체를 올리고, 그 다음 본 update를 적용해야 한다.

이 ADR은 “제품을 어떤 layer로 부를 것인가”보다 “현장 배포 후에도 update가 막히지 않게 하려면 update 흐름과 compatibility gate를 어떻게 고정할 것인가”를 다룬다. ADR 0003의 component vocabulary는 manifest 표현에 사용하지만, 이 결정의 출발점은 update 배포 안정성이다.

검토 중 아래 위험이 드러났다.

- `runtimeVersion` 하나로 Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, VM Image 변경을 모두 표현하면 어떤 변경이 update compatibility에 영향을 주는지 알 수 없다.
- rootfs/base OS 변경을 일반 update bundle에 섞으면 mutable `vm-disk.img`가 보존되는 기존 설치본에서 “rootfs가 바뀌었는데 왜 OS package가 안 바뀌는가” 같은 오해와 실패가 생긴다.
- Updater 자체가 바뀌는 update와 service/container만 바뀌는 update를 같은 위험도로 보면 bridge/two-phase update가 필요한 시점을 놓칠 수 있다.
- platform-specific VM provider 변경을 공통 update처럼 배포하면 macOS/Windows variant가 서로 다른 artifact를 잘못 적용할 수 있다.

따라서 update 계약은 설치본이 배포된 뒤에도 기존 Updater가 판단할 수 있는 최소 계약이어야 한다. 적용 가능성 판단에 필요한 field를 명확히 하고, 위험도가 다른 update를 UI와 bundle kind에서 분리해야 한다.

## 결정

Update compatibility의 source of truth는 Updater version이다.

- `schemaVersion`은 manifest 문법과 required field set의 version이다.
- `minUpdaterVersion`은 이 bundle을 직접 읽고 적용할 수 있는 최소 Updater version이다.
- `components.supervisor`, `components.vmDriver`, `components.serviceStack` 등은 변경 범위와 표시를 위한 version이지, update 적용 가능 여부의 직접 gate가 아니다.
- Updater가 새 manifest/result/status 계약을 이해하지 못하면, 먼저 Updater를 갱신하는 bridge/two-phase Product Update가 필요하다.

용어는 아래처럼 구분한다.

| 개념 | 의미 |
| --- | --- |
| Product Update | Helper UI/Native Shell/Runtime Control API/Updater/Supervisor/VM Driver/Service Stack/service 변경 |
| VM Image Update | Linux guest OS/rootfs/base image 변경 |
| Two-phase Update | 기존 Updater가 새 Product Update를 바로 이해하지 못할 때, Updater를 먼저 올리고 본 update를 나중에 적용 |

Update bundle kind는 두 개만 둔다.

| bundleKind | UI 위치 | 포함 범위 |
| --- | --- | --- |
| `product-update` | Update 탭 | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, 개별 service/container, host proxy, migrations |
| `vm-image-update` | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifact |

Hotfix, service-only update, updater bridge update는 새 bundle kind를 만들지 않고 `product-update`의 metadata로 표현한다. 예시는 `channel`, changed component versions, `requiresTwoPhaseUpdate`이다.

Two-phase update는 VM Image Update와 Product Update를 같이 묶는다는 뜻이 아니다. Two-phase는 `product-update`의 특수 적용 절차다. Product Update 내부에서 Updater compatibility를 먼저 올린 뒤 본 update를 적용한다.

```text
Phase 1: 기존 Updater가 이해할 수 있는 bridge Product Update로 Updater 갱신
Phase 2: 새 Updater가 실제 Product Update payload 적용
```

VM Image/rootfs/base OS 변경은 별도의 `vm-image-update` 흐름이며 Danger Zone에 둔다. Product Update와 VM Image Update를 같은 release campaign에서 함께 제공해야 할 수는 있지만, 그 경우도 two-phase update라고 부르지 않는다. 필요한 경우에는 paired product/image release 또는 coordinated Product + VM Image update로 표현한다. 이 경우에도 두 bundle은 독립적으로 검증, 승인, 적용, rollback 상태를 가진다.

Bundle manifest는 ADR 0003의 component vocabulary를 재사용한다.

```json
{
  "schemaVersion": 1,
  "bundleKind": "product-update",
  "helperVersion": "0.2.0",
  "targetPlatforms": ["macos-arm64"],
  "minUpdaterVersion": "0.1.6",
  "components": {
    "helperUI": "0.2.0+macos.1",
    "nativeShell": "0.2.0+macos.1",
    "runtimeControl": "0.2.0+macos.1",
    "updater": "0.2.0",
    "supervisor": "0.2.0",
    "vmDriver": "0.2.0+macos.1",
    "serviceStack": "2.3.4-stack.1",
    "vitalServer": "2.3.4"
  }
}
```

Manifest compatibility rule은 아래와 같이 고정한다.

- `schemaVersion`, `bundleKind`, `helperVersion`, `targetPlatforms`, `minUpdaterVersion`, artifact checksum은 required contract field다.
- Updater가 `bundleKind`를 모르면 reject한다.
- `targetPlatforms`에 현재 platform이 없으면 reject한다.
- 현재 Updater version이 `minUpdaterVersion`보다 낮으면 직접 적용하지 않고 bridge/two-phase Product Update가 필요하다고 판단한다.
- 알 수 없는 optional metadata는 ignore할 수 있어야 한다.
- 알 수 없는 required field, required capability, schema major version은 reject한다.
- checksum, artifact name, bundle kind, target platform, `minUpdaterVersion`을 검증하기 전에는 payload를 적용하지 않는다.

Product Update는 mutable VM disk를 암묵적으로 교체하지 않는다. Service Stack, compose, container image bundle, guest deploy 변경은 guest activation으로 반영한다. VM Image/rootfs/base OS 변경은 별도 VM Image Update로 취급한다.

아직 현장 배포 전이므로 기존 update manifest와의 하위 호환성은 보장하지 않는다. 새 manifest contract를 기준으로 release automation과 Swift reader를 맞춘다. 현장 배포가 시작된 뒤에는 이 계약을 깨는 변경을 일반 Product Update로 배포하지 않는다. 필요하면 새 Updater를 먼저 배포하는 bridge/two-phase update를 사용한다.

## 대안

| 대안 | 기각 이유 |
| --- | --- |
| 모든 artifact를 하나의 일반 update bundle에 계속 포함 | rootfs/base OS와 service/app 변경의 위험도가 달라 rollback, UI, 운영 데이터 보존 정책이 흐려진다 |
| bundle kind를 hotfix, service-stack, updater-bridge 등으로 많이 나누기 | kind가 늘수록 updater가 알아야 할 분기가 늘어난다. 대부분은 `product-update` metadata로 표현 가능하다 |
| `runtimeVersion` 하나로 update compatibility 판단 | 어떤 component 변경이 compatibility gate인지 알 수 없다 |
| VM Image Update를 Update 탭에서 처리 | OS image급 변경은 운영 데이터 보존/재생성 정책이 필요하므로 일반 Product Update와 같은 UX로 다루면 위험하다 |
| platform 구분 없이 공통 bundle만 사용 | Native Shell, Runtime Control API implementation, VM Driver는 platform-specific이므로 잘못된 artifact 적용 위험이 있다 |

## 결과

이 결정으로 얻는 것:

- 현장 배포 이후 update contract를 깨는 변경을 식별할 수 있다.
- Product Update와 VM Image Update의 위험도가 UI와 manifest에서 분리된다.
- Updater compatibility gate가 명확해진다.
- Manifest reader가 reject/ignore해야 할 조건이 명확해진다.
- Service Stack/service-only 변경을 VM Image 변경처럼 과대 취급하지 않는다.

감수하는 것:

- VM Image Update UX와 운영 데이터 보존/재생성 정책은 Product Update와 별도로 설계해야 한다.
- Bridge/two-phase Product Update를 지원하는 release automation이 필요하다.
- Bundle manifest field를 확장할 때 기존 Updater가 읽을 수 있는지 먼저 판단해야 한다.

## 관련 결정

- ADR 0002는 Product Update와 VM Image Update를 실행할 client boundary를 정의한다.
- ADR 0003은 update manifest가 참조하는 component vocabulary와 version model을 정의한다.
