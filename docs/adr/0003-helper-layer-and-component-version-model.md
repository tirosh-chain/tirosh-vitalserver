# ADR 0003: Helper Layer and Component Version Model

## 상태

Accepted, implementation in progress

## 배경

VitalServer Helper의 update 대상을 정의하고 각 대상에 version을 매기기 시작하면서 `runtime`이라는 이름이 애매해졌다. 어떤 문맥에서는 macOS helper CLI를 뜻하고, 어떤 문맥에서는 VM 실행 환경을 뜻하고, 또 다른 문맥에서는 guest service stack이나 watchdog/recovery까지 포함한다.

이 모호함은 코드에서도 드러나기 시작했다. `HostCLI` 안에는 update apply/rollback, watchdog/recovery, VM lifecycle, install/configure, service control, repair, log 관련 책임이 함께 들어 있다. 파일 단위 usecase runner는 분리되고 있지만, 이름과 version model은 아직 이 책임들을 하나의 runtime처럼 다루고 있다.

또한 platform별 구현이 다르다. Helper UI는 Web/PWA primary로 공통화할 수 있지만 native shell, Runtime Control API implementation, Updater, Supervisor, VM Driver는 macOS/Windows별로 달라질 수 있다. Service Stack과 VitalServer service는 guest/service 쪽 책임이다. Supervisor는 host/platform-aware 정책이고, VM Driver는 platform-specific provider다. 이 책임들을 한 단위로 설명하면 update target, support 진단, About UI, release metadata가 불명확해진다.

ADR 0002의 RuntimeControlClient boundary도 같은 vocabulary를 필요로 하지만, 이 ADR의 직접적인 출발점은 update 대상별 version을 정의하는 과정에서 드러난 `runtime` 책임 과다와 코드 구조의 모호함이다. Update 계약 자체는 별도 결정인 ADR 0004에서 다룬다.

## 결정

VitalServer Helper를 최상위 product/release train으로 보고, 아래 component layer를 명시한다.

| Layer | Platform dependency | 책임 | Version key |
| --- | --- | --- | --- |
| VitalServer Helper | cross-platform product umbrella | 최상위 관리 제품/클라이언트 패키지, release/support 기준 | `helperVersion` |
| Helper UI | cross-platform Web/PWA primary | iPhone/Android/iPad/desktop browser와 native shell wrapper에서 쓰는 product UI | `components.helperUI` |
| Native Shell | platform-specific | install/bootstrap/pairing/recovery/native picker/tray/menu | `components.nativeShell` |
| Runtime Control API | common API contract, platform-specific host implementation | auth/session/pairing, capability negotiation, status/log/update/settings/admin endpoint, progress/log streaming | `components.runtimeControl` |
| Updater | host/platform-specific | product update bundle verify/apply/rollback, manifest compatibility gate, migration/guest activation 조율 | `components.updater` |
| Supervisor | host/platform-aware | health/watchdog/recovery, service state loop, update/rollback 중 recovery suppression | `components.supervisor` |
| VM Driver | platform-specific | macOS Apple Virtualization, Windows provider 등 VM lifecycle provider | `components.vmDriver` |
| Service Stack | mostly guest/service-specific | guest deploy assets, compose, container image bundle, service activation 단위 | `components.serviceStack` |
| VM Image | guest OS/image-specific | Linux guest OS/base rootfs/kernel/initrd class artifact | `components.vmImage` |
| VitalServer service | service-specific | VM 안에서 실행되는 VitalServer app/container | `components.vitalServer` |

`runtimeVersion` 하나를 user-facing source of truth로 쓰지 않는다. 설치 상태, About UI, support log, release metadata는 `helperVersion`, platform/target information, `components` map을 기준으로 설명한다. Update manifest도 이 vocabulary를 재사용할 수 있지만, update compatibility와 bundle contract는 ADR 0004에서 정의한다.

예시:

```json
{
  "helperVersion": "0.2.0",
  "platform": "macos-arm64",
  "components": {
    "helperUI": "0.2.0+macos.1",
    "nativeShell": "0.2.0+macos.1",
    "runtimeControl": "0.2.0+macos.1",
    "updater": "0.2.0",
    "supervisor": "0.2.0",
    "vmDriver": "0.2.0+macos.1",
    "serviceStack": "2.3.4-stack.1",
    "vmImage": "0.2.0-image.1",
    "vitalServer": "2.3.4"
  }
}
```

`helperVersion`은 product release train version이다. Platform-specific artifact가 바뀌어 사용자가 받는 Helper product release가 달라지면 `helperVersion`을 올린다. Platform별 build 차이는 target platform 정보와 platform-specific component version build metadata로 구분한다.

공통 Service Stack이나 VM Image는 같은 Helper release 아래에서 platform 간 공유할 수 있다.

## 대안

| 대안 | 기각 이유 |
| --- | --- |
| `runtimeVersion` 하나만 유지 | 어떤 책임이 바뀌었는지 support/UI/release metadata에서 설명할 수 없다 |
| Helper version과 모든 component version을 항상 동일하게 유지 | UI-only, service-only, VM-driver-only 변경의 범위가 숨겨진다 |
| VM Image version을 Helper version과 항상 같이 올리기 | Service Stack이나 UI만 바뀌는 release도 VM Image 변경처럼 보인다. bundle 크기와 운영 위험도도 커진다 |
| platform 구분 없이 공통 component version만 사용 | native shell, Runtime Control API implementation, VM Driver는 platform-specific이므로 잘못된 artifact 적용 위험이 있다 |

## 결과

이 결정으로 얻는 것:

- About UI와 support log에서 실제 변경 layer를 설명할 수 있다.
- release note, support metadata, update bundle manifest가 같은 component vocabulary를 재사용할 수 있다.
- Native Shell/Runtime Control API/Updater/Supervisor/VM Driver/Service Stack/VM Image 책임이 문서와 코드 구조에서 일치하기 쉬워진다.
- platform-specific build와 common service artifact를 같은 Helper release 아래에서 구분할 수 있다.

감수하는 것:

- 설치 상태 문서와 UI label을 `runtimeVersion`에서 component version document로 전환해야 한다.
- generated release metadata가 component map을 관리해야 한다.
- 기존 flat version field와의 호환성은 현장 배포 전까지 정리한다.

## 관련 결정

- ADR 0002는 이 vocabulary가 UI와 local/remote implementation 사이에서 노출될 Helper client boundary를 정의한다.
- ADR 0004는 현장 배포 후 update compatibility 문제를 다루며, 이 ADR의 component vocabulary를 manifest 표현에 사용한다.
