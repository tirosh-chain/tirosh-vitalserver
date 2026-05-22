# ADR 0002: Helper Client Boundary for Local and Remote Runtime

## 상태

Accepted, implementation in progress

## 배경

VitalServer Helper는 macOS local VM launcher/helper로 시작했지만, 제품 방향은 여러 client가 같은 VitalServer management surface에 붙을 수 있어야 한다.

필요한 실행 형태는 두 가지다.

1. Local mode
   - macOS app이 local installed VitalServer appliance를 관리한다.
   - launchd, installed files, privileged commands, local logs, update bundle, VM image update bundle을 사용할 수 있다.

2. Remote mode
   - 같은 UI가 remote VitalServer control server에 연결된다.
   - iPadOS/macOS/Windows client는 macOS-only VM control code를 공유 UI에 직접 포함하면 안 된다.
   - 여러 client가 권한에 따라 같은 VitalServer appliance를 observe/control할 수 있어야 한다.

이 요구가 먼저 등장했기 때문에, UI와 local macOS implementation 사이에 명확한 boundary가 필요하다.

## 결정

Helper UI는 local files, launchd, privileged CLI, macOS-only API에 직접 의존하지 않는다. UI는 `RuntimeClient` boundary에 의존한다.

```text
Shared Helper UI
  Status / Settings / Update / Info / Logs / Advanced / Danger Zone
        |
        v
RuntimeClient
        |
        +-- LocalRuntimeClient
        |     macOS local adapter
        |     launchd, installed files, privileged commands, local logs
        |
        +-- RemoteRuntimeClient
              future HTTP/SSE adapter
              VitalServer control server
```

Local-only 기능은 암묵적으로 호출하지 않고 capability로 노출한다. 예시는 아래와 같다.

- apply product update bundle
- apply VM image update bundle
- rollback
- service start/stop
- log export
- open local files
- uninstall
- admin password reset
- VM resource settings

`NSOpenPanel`, `NSSavePanel`, `NSWorkspace` 같은 UI concern은 UI/controller code에 남긴다. 파일 복사, archive 생성, launchd, installed paths, privileged command execution은 local adapter/usecase 뒤에 둔다.

Remote mode는 local implementation을 공유하지 않고 같은 `RuntimeClient` contract를 HTTP/SSE adapter로 구현한다.

## 대안

| 대안 | 기각 이유 |
| --- | --- |
| Helper UI가 local filesystem/launchd/CLI를 직접 호출 | macOS local 전제에 묶여 iPadOS/remote client로 확장하기 어렵다 |
| macOS Helper와 remote client UI를 별도 codebase로 유지 | UI 동작과 상태 표현이 쉽게 갈라진다 |
| Remote API를 먼저 구현 | local boundary가 불명확한 상태에서 API를 만들면 local 구현 세부가 API로 새어 나간다 |
| 모든 기능을 항상 UI에서 노출하고 실패 시 에러 처리 | remote/restricted mode에서 불가능한 action을 사용자가 실행할 수 있다 |

## 결과

이 결정으로 얻는 것:

- UI는 local/remote VitalServer management surface를 같은 contract로 다룰 수 있다.
- local-only 기능은 capability로 제어된다.
- remote client/server 구조로 이동할 때 UI를 다시 쓰지 않아도 된다.
- local adapter 내부에서 macOS-specific implementation을 유지할 수 있다.

감수하는 것:

- `RuntimeClient` contract가 커질 수 있으므로 capability와 model 정리가 필요하다.
- local-only action을 UI disabled state와 controller guard 양쪽에서 관리해야 한다.
- Remote API는 local boundary가 충분히 정리된 뒤에 설계해야 한다.

## 관련 결정

- ADR 0003은 Helper product를 구성하는 layer와 component version vocabulary를 정의한다.
- ADR 0004는 현장 배포 후 update가 막히지 않도록 Product Update, VM Image Update, two-phase Product Update 계약을 정의한다.
