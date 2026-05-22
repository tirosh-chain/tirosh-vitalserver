# ADR 0002: Helper Client Boundary for Web/PWA and Local/Remote Runtime

## 상태

Accepted, implementation in progress

## 배경

VitalServer Helper는 macOS local VM launcher/helper로 시작했다. 초기 구현에서는 macOS app이 UI, local filesystem 접근, launchd 제어, privileged command 실행, update bundle 적용, log 조회를 모두 직접 다룬다.

제품 방향은 이 구조와 다르다. 같은 VitalServer appliance를 macOS 관리자뿐 아니라 iPhone, Android, iPad, Windows desktop, remote browser에서도 확인하고 제어할 수 있어야 한다. 특히 iPhone/Android 사용자는 단순 상태 확인이나 운영 작업을 위해 native app 설치를 강제하기 어렵다.

따라서 multi-platform UI의 primary path는 browser-based Web/PWA로 둔다. macOS native app은 계속 필요하지만, 장기적으로는 product UI의 유일한 소유자가 아니라 local runtime host, native shell, installer/recovery entrypoint 역할에 가까워진다.

Windows 지원을 고려하면 이 결론은 더 강해진다. Windows는 installer, service manager, tray shell, updater, supervisor, VM provider가 macOS와 다를 수밖에 없다. Windows host app이 별도 product UI를 소유하면 macOS, mobile browser, remote browser와 UI 동작이 갈라진다. 따라서 Windows에서도 host-native app은 shell/host 역할을 맡고, Web/PWA UI에는 같은 Runtime Control API contract를 제공해야 한다.

동시에 Web/PWA는 host operation을 직접 수행할 수 없다. Browser sandbox 안에서는 launchd 제어, VM start/stop, privileged file replacement, local log file 수집, update apply, rollback 실행을 할 수 없다. 이 작업은 host-native component가 수행해야 한다.

이 결정의 핵심 문제는 UI 기술 선택 자체가 아니다. 핵심은 product UI가 local macOS 구현에 직접 묶이지 않도록, UI와 host-specific runtime operation 사이의 boundary를 고정하는 것이다.

필요한 실행 형태는 세 가지다.

| 실행 형태 | 설명 | 주요 제약 |
| --- | --- | --- |
| Local native mode | macOS/Windows native shell이 local installed VitalServer appliance를 관리한다 | OS별 installer/service manager/native picker/recovery 구현이 다름 |
| Local web mode | Web/PWA UI가 local Runtime Control API에 연결된다 | browser는 host operation을 직접 실행하지 못하므로 local host service/native shell이 필요 |
| Remote mode | 같은 Web/PWA UI가 remote VitalServer control server에 연결된다 | auth, role/capability, network reachability, streaming 상태가 중요 |

이 구조에서는 Android/iPhone/iPad/desktop browser가 같은 product UI를 사용할 수 있고, macOS-only VM control code는 UI에 포함되지 않는다.

## 결정

Helper product UI는 local files, launchd, privileged CLI, macOS-only API에 직접 의존하지 않는다. UI는 `RuntimeClient` boundary에 의존한다.

```text
Web/PWA Helper UI
  Status / Settings / Update / Info / Logs / Advanced / Danger Zone
        |
        v
RuntimeClient
        |
        +-- LocalRuntimeClient
        |     in-process macOS adapter for current native app transition
        |     launchd, installed files, privileged commands, local logs
        |
        +-- HttpRuntimeClient
              HTTP/SSE adapter
              local Runtime Control API or remote VitalServer control server

macOS native shell
  - installs/starts/stops local runtime services
  - hosts or discovers local Runtime Control API
  - provides pairing URL/QR for mobile/browser access
  - provides native picker/save panel when required
  - provides local recovery/uninstall entrypoint
  - does not own product UI logic long term

Windows native shell
  - has the same shell/host responsibility
  - uses Windows-specific installer, service manager, tray, recovery flow
  - exposes the same Runtime Control API contract
  - does not own a separate product UI
```

Web/PWA UI는 product UI의 primary cross-platform implementation이다. macOS SwiftUI 화면은 전환 기간 동안 유지할 수 있지만, 새 product workflow는 `RuntimeClient` contract 뒤에 둔다. 같은 workflow를 Web/PWA, macOS shell, future native wrappers가 재사용할 수 있어야 한다.

책임 경계는 아래와 같다.

| Layer | 책임 | 하지 않는 것 |
| --- | --- | --- |
| Web/PWA Helper UI | 화면, user interaction, status/log/update/settings UX, API client, capability 기반 enable/disable | launchd 제어, VM 제어, privileged file operation, update apply 직접 실행 |
| RuntimeClient | UI가 사용하는 typed client contract, local/remote capability model, progress/log stream abstraction | 특정 OS API 호출 |
| HttpRuntimeClient | local/remote Runtime Control API 호출, SSE progress/log streaming, auth/session 처리 | host operation 직접 실행 |
| LocalRuntimeClient | 전환 기간 동안 macOS native app에서 local adapter 호출 | Web/PWA portability 보장 없이 UI workflow를 소유 |
| Runtime Control API | auth/session, pairing, capability negotiation, status/log/update/settings/admin operation endpoint | UI rendering |
| macOS native shell | macOS install/recovery/native picker/local host bootstrap | 장기 product UI logic 소유 |
| Windows native shell | Windows install/service/tray/recovery/local host bootstrap | 장기 product UI logic 소유 |
| Host-native runtime components | Updater, Supervisor, VM Driver, service control, log collector 실행 | browser에서 실행될 것을 전제 |

Platform-specific host runtime은 같은 API contract 뒤에 숨긴다.

| Layer | macOS 구현 | Windows 구현 | 공통 계약 |
| --- | --- | --- | --- |
| Runtime Control API | local macOS service | local Windows service | HTTP/SSE API, auth/session, capability, result/reason model |
| Native shell | menu bar app, pkg/recovery, native panels | tray app, installer/recovery, native dialogs | bootstrap, pairing, recovery entrypoint |
| Updater | macOS file/service/update flow | Windows file/service/update flow | ADR 0004 manifest/update contract |
| Supervisor | launchd/process/network health | Windows Service/process/network health | health/status/recovery model |
| VM Driver | Apple Virtualization provider | Hyper-V, WSL2, VirtualBox, or other Windows provider | VM lifecycle capability model |
| Service Stack | Linux guest compose/container assets | Linux guest compose/container assets | guest activation and service stack contract |

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

`NSOpenPanel`, `NSSavePanel`, `NSWorkspace` 같은 native UI concern은 macOS shell/controller code에 남긴다. 파일 복사, archive 생성, launchd, installed paths, privileged command execution은 local adapter/usecase 뒤에 둔다.

현재 SwiftUI 전환기 구현에서는 이 경계를 다음 코드 계약으로 맞춘다.

| 코드 계약 | 책임 |
| --- | --- |
| `RuntimeController` | UI 상태, capability guard, usecase orchestration, 화면 메시지 변환 |
| `RuntimeClient` | UI가 호출하는 local/remote runtime operation contract. status/settings/log/backup/release read model과 install/configure/update/rollback/service command를 제공 |
| `LocalRuntimeClient` | macOS local adapter. file reader, settings/status reader, privileged command runner, action environment를 조합 |
| `RuntimeNativeShell` | macOS native picker/save panel, file/web open, helper relaunch/terminate 같은 shell concern |

이 구현에서 `RuntimeController`는 `AppKit`을 직접 import하지 않는다. update bundle, log export destination, backup 선택값처럼 local file을 가리키는 값은 내부 계약에서 `URL`로 전달하고, CLI argument나 화면 표시가 필요한 boundary에서만 path string으로 변환한다. Log source처럼 닫힌 선택지는 raw string이 아니라 enum 계약으로 다룬다.

Local web mode와 Remote mode는 같은 `RuntimeClient` contract를 HTTP/SSE adapter로 구현한다. Runtime Control API는 최소한 아래 contract를 가져야 한다.

- auth/session 또는 pairing token
- capability negotiation
- status/settings/release/component version read model
- product update와 VM image update endpoint
- progress/log streaming
- dangerous operation confirmation
- audit/debug에 필요한 result and reason model

Local web mode에서 mobile browser가 local host에 접근하는 방식은 배포 환경별로 다를 수 있다. Same LAN, QR/pairing token, reverse tunnel, remote management server 중 하나를 사용할 수 있지만, UI는 그 transport 세부에 의존하지 않는다.

## 대안

| 대안 | 기각 이유 |
| --- | --- |
| Helper UI가 local filesystem/launchd/CLI를 직접 호출 | macOS local 전제에 묶여 iPhone/Android/iPad/remote browser로 확장하기 어렵다 |
| macOS Helper와 remote/mobile UI를 별도 codebase로 유지 | UI 동작, 상태 표현, update UX, 권한 처리가 쉽게 갈라진다 |
| Windows host app이 별도 product UI를 소유 | Windows service/tray/VM provider 구현 차이가 UI 차이로 번지고 cross-platform UX가 갈라진다 |
| iPhone/Android를 native app으로만 제공 | 현장 사용자가 단순 상태 확인/운영을 위해 app 설치를 강제받는다 |
| Web/PWA가 host operation을 직접 수행 | browser sandbox 때문에 launchd, VM control, privileged file operation을 수행할 수 없다 |
| Remote API를 먼저 구현 | local boundary가 불명확한 상태에서 API를 만들면 local 구현 세부가 API로 새어 나간다 |
| 모든 기능을 항상 UI에서 노출하고 실패 시 에러 처리 | remote/restricted mode에서 불가능한 action을 사용자가 실행할 수 있다 |

## 결과

이 결정으로 얻는 것:

- Android/iPhone/iPad/desktop browser는 설치 강제 없이 같은 product UI를 사용할 수 있다.
- UI는 local/remote VitalServer management surface를 같은 contract로 다룰 수 있다.
- local-only 기능은 capability로 제어된다.
- macOS/Windows native app은 local runtime host/native shell 역할로 축소할 수 있다.
- remote client/server 구조로 이동할 때 UI workflow를 다시 쓰지 않아도 된다.
- macOS/Windows-specific implementation은 Runtime Control API와 host-native runtime component 내부에 격리된다.

감수하는 것:

- `RuntimeClient` contract가 커질 수 있으므로 capability와 model 정리가 필요하다.
- Runtime Control API는 auth, pairing, capability, dangerous operation confirmation을 포함해야 한다.
- Local web mode는 network reachability, local TLS, pairing UX를 별도로 설계해야 한다.
- 전환 기간에는 SwiftUI UI와 Web/PWA UI가 일부 공존할 수 있다.
- Web/PWA를 도입해도 Updater, Supervisor, VM Driver 같은 host operation은 platform-specific native implementation으로 남는다.
- Windows VM provider는 별도 결정이 필요하다. ADR 0002는 provider 선택이 아니라 provider 차이를 UI/API 뒤에 숨기는 boundary를 결정한다.

## 관련 결정

- ADR 0003은 Helper product를 구성하는 layer와 component version vocabulary를 정의한다.
- ADR 0004는 현장 배포 후 update가 막히지 않도록 Product Update, VM Image Update, two-phase Product Update 계약을 정의한다.
