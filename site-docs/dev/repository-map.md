# Repository Map

이 repository는 Vital Server Helper를 구성하는 여러 app, package, 문서를 함께 담는 monorepo입니다.

이 문서는 “어떤 일을 하려면 어디를 보면 되는가”를 빠르게 찾기 위한 지도입니다. 모든 폴더를 외우는 것이 목적이 아니라, 변경하려는 일이 어느 책임에 속하는지 먼저 구분하는 것이 목적입니다.

## 1. 먼저 볼 곳

처음 코드를 볼 때는 아래 순서가 좋습니다.

1. 전체 제품 구조는 [Architecture](architecture.md)를 먼저 봅니다.
2. 상태 단어와 API 의미는 [Runtime Contracts](runtime-contracts.md)를 봅니다.
3. 실제 코드 위치는 이 문서의 “작업별 입구”에서 찾습니다.
4. 검증 방법은 [Delivery & Validation](delivery-validation.md)을 봅니다.

### 1-1. 작업별 입구

| 하고 싶은 일                       | 먼저 볼 곳                                                                                           |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Helper app 화면 수정               | `apps/vitalserver-macos-runtime/Sources/Adapters/Inbound/MacControlPanel/Presentation`               |
| PWA 화면 수정                      | `apps/vitalserver-runtime-pwa/src/pages`                                                             |
| Runtime Control API 수정           | `apps/vitalserver-macos-runtime/Sources/Adapters/Inbound/RuntimeControlAPI`                          |
| runtime status 의미 수정           | `apps/vitalserver-macos-runtime/Sources/Contracts`와 `apps/vitalserver-macos-runtime/Sources/Domain` |
| recorder/bed 관측 수정             | `apps/vitaldb-observer`와 macOS runtime의 observability reader                                       |
| update/recovery 흐름 수정          | `apps/vitalserver-macos-runtime/Sources/Workflow`와 `Sources/Hosts/CLI`                              |
| packaging 또는 release bundle 수정 | `packages/vitalserver-devtools`, `apps/vitalserver-macos-runtime/Support`, `Makefile`                |
| testkit 수정                       | `packages/vitalserver-testkit`와 runtime TestKit API                                                 |
| 문서 수정                          | `site-docs/`와 `docs/`                                                                               |

### 1-2. 헷갈리기 쉬운 기준

| 질문                                      | 기준                                                        |
| ----------------------------------------- | ----------------------------------------------------------- |
| UI에서 상태를 만들어도 되는가?            | 안 됩니다. UI는 받은 상태를 표시합니다.                     |
| Host가 Guest 내부 상태를 추측해도 되는가? | 안 됩니다. Guest가 만든 문서나 API 응답을 읽습니다.         |
| 실패를 빈 결과로 바꿔도 되는가?           | 안 됩니다. 실패와 empty는 다릅니다.                         |
| 새 기능은 어디에 넣는가?                  | 상태를 말하는 곳, 판단하는 곳, 실행하는 곳을 먼저 나눕니다. |

## 2. 큰 폴더

Repository root에서는 먼저 두 가지만 구분하면 됩니다.

`apps/`는 실제로 실행되는 것들이 모인 곳입니다. Helper app, PWA, observer, recorder ingress처럼 제품을 이루는 app과 service가 여기에 있습니다.

`packages/`는 그 app들을 만들고 검증하고 운영하는 데 쓰는 도구가 모인 곳입니다. testkit, devtools, guest tools처럼 여러 위치에서 재사용되는 package가 여기에 있습니다.

그 밖의 폴더는 설정, 문서, script, infrastructure를 보조합니다.

| 경로         | 무엇이 들어 있나                               |
| ------------ | ---------------------------------------------- |
| `apps/`      | 제품으로 실행되는 app과 service                |
| `packages/`  | build, 검증, guest 운영에 쓰는 재사용 도구     |
| `infra/`     | proxy, Swagger UI, 배포 보조 파일              |
| `config/`    | build, packaging, testkit 설정                 |
| `scripts/`   | repository 전체에서 쓰는 보조 script           |
| `vendor/`    | Vital Server source reference                  |
| `docs/`      | runtime/API/ADR/troubleshooting 같은 상세 문서 |
| `site-docs/` | 공개 site로 빌드되는 문서                      |

### 2-1. apps

`apps/`는 제품을 이루는 실행 단위입니다. 화면, host runtime, observer, proxy처럼 각각 독립적인 책임을 가진 app이나 service가 들어 있습니다.

| 경로                             | 역할                                                       |
| -------------------------------- | ---------------------------------------------------------- |
| `apps/vitalserver`               | Vital Server를 Helper runtime 안에서 실행하기 위한 wrapper |
| `apps/vitalserver-macos-runtime` | macOS Helper app, host runtime, VM 관리, packaging         |
| `apps/vitalserver-runtime-pwa`   | browser에서 여는 Runtime Control UI                        |
| `apps/vitaldb-observer`          | Redis/proxy를 읽어 recorder/bed 상태를 정리                |
| `apps/vitalserver-recorder-ingress`   | VRecorder command와 audit event를 관측                     |
| `apps/vitalserver-recorder-recovery`  | recorder ingress raw archive를 `.vital`로 복구하는 service |

### 2-2. packages

`packages/`는 제품 자체라기보다 제품을 만들고 검증하고 운영하는 도구입니다. 실제 현장 기능과 연결되지만, app처럼 독립 화면이나 service entrypoint를 갖는 것과는 구분합니다.

| 경로                               | 역할                                                        |
| ---------------------------------- | ----------------------------------------------------------- |
| `packages/vitalserver-testkit`     | 가상 recorder와 smoke/load 검증 도구                        |
| `packages/vitalserver-devtools`    | packaging, VM image, update bundle을 만드는 도구            |
| `packages/vitalserver-guest-tools` | Linux guest 안에서 상태, update, logs, repair를 다루는 도구 |

## 3. macOS runtime 구조

`apps/vitalserver-macos-runtime/Sources`는 Helper app과 host runtime의 핵심 코드입니다. 폴더 이름은 책임을 드러내야 합니다.

### 3-1. Source layout

```text
Sources/
  Contracts/
  Domain/
  Application/
  Workflow/
  Adapters/
  Hosts/
  Bootstrap/
  Errors/
```

### 3-2. 각 폴더의 역할

| 폴더          | 쉬운 설명                                            |
| ------------- | ---------------------------------------------------- |
| `Contracts`   | 주고받는 문서와 API 모델                             |
| `Domain`      | 상태 판단 규칙과 전이 규칙                           |
| `Application` | 명령을 실행하기 전 필요한 결정                       |
| `Workflow`    | install, update, repair, uninstall 같은 긴 작업 순서 |
| `Adapters`    | 외부 연결 코드. API, UI, 파일, process, network 연결 |
| `Hosts`       | CLI와 Mac app 실행 경계                              |
| `Bootstrap`   | 앱 시작 시 필요한 설정, 경로, 구현 연결              |
| `Errors`      | 실패 의미와 설명                                     |

`Contracts`, `Domain`, `Application`, `Workflow`, `Bootstrap`, `Hosts`, `Errors`의 책임 기준은 [Architecture](architecture.md)의 `코드 경계`와 [Delivery & Validation](delivery-validation.md)의 test rule에서 더 자세히 설명합니다. 이 문서의 다음 절은 그중에서도 파일 위치를 자주 찾아야 하는 외부 연결 코드를 조금 더 풀어 설명합니다.

### 3-3. TestKit과 Dev Console

Dev 배포판의 QA 기능은 단순 test support가 아니라 제품 검증 기능입니다. Production source에서 `Testing`이라는 포괄 이름을 쓰기보다, 기능 이름인 `TestKit` 또는 `DevConsole`로 드러냅니다.

```text
Contracts/RuntimeControl/TestKit/
Adapters/Inbound/RuntimeControlAPI/DevConsole/
Adapters/Inbound/RuntimeControlAPI/TestKit/
Adapters/Inbound/MacControlPanel/Presentation/TestKit/
Adapters/Outbound/MacRuntimeControlClient/TestKit/
```

## 4. 자주 들어가는 외부 연결 코드

Helper를 고칠 때 외부와 연결되는 코드 중 자주 들어가는 곳은 세 군데입니다. API를 고칠 때, Mac Helper 화면을 고칠 때, Mac에서 파일이나 process를 읽고 쓰는 기능을 고칠 때입니다.

세 곳을 나눠 두는 이유는 단순합니다. 화면이 할 일, API가 할 일, host에서 실제로 실행할 일을 섞지 않기 위해서입니다. 이 구분이 무너지면 상태 의미가 흐려지고, 테스트도 어려워집니다.

### 4-1. Runtime Control API

화면과 host runtime 사이에 오가는 API를 고칠 때 보는 곳입니다. PWA나 Helper app은 이 API를 통해 status, event, recorder/bed activity를 읽고, start/update/repair 같은 명령을 요청합니다.

```text
Adapters/Inbound/RuntimeControlAPI/
  Boundary/
  Transport/
  DevConsole/
  TestKit/
```

이 폴더 안에서도 역할을 나눕니다. HTTP 요청/응답을 다루는 코드, API route를 고르는 코드, 개발용 확인 화면, TestKit endpoint가 서로 섞이지 않게 합니다.

| 수정하려는 것       | 먼저 볼 곳                                        |
| ------------------- | ------------------------------------------------- |
| API route 추가/변경 | `Boundary/`와 endpoint catalog                    |
| HTTP 요청/응답 처리 | `Transport/`                                      |
| 개발용 확인 화면    | `DevConsole/`                                     |
| testkit endpoint    | `TestKit/`                                        |
| OpenAPI 문서        | `docs/runtime/macos/runtime-control.openapi.json` |

주의할 점은 API가 상태를 새로 만들면 안 된다는 것입니다. API는 이미 읽은 runtime 상태, event, recorder/bed activity를 response로 전달합니다.

### 4-2. Mac Control Panel

Mac Helper app 화면을 고칠 때 보는 곳입니다. 버튼 문구, 상태 색상, 화면 배치, ViewModel 연결이 여기에 있습니다.

```text
Adapters/Inbound/MacControlPanel/
  Configuration/
  Generated/
  Presentation/
    Copy/
    Formatting/
    Policies/
    TestKit/
    ViewModels/
    Views/
```

화면 코드는 다시 작은 역할로 나눕니다. 문구는 Copy, 시간/byte 같은 표시는 Formatting, 상태를 어떤 색과 문구로 보여줄지는 Policies, 화면 상태와 명령 연결은 ViewModels, 실제 SwiftUI 화면은 Views에 둡니다.

| 수정하려는 것                       | 먼저 볼 곳                 |
| ----------------------------------- | -------------------------- |
| 버튼/라벨 문구                      | `Presentation/Copy/`       |
| 시간, byte, URL 같은 표시 형식      | `Presentation/Formatting/` |
| 상태를 어떤 문구/색/행동으로 보일지 | `Presentation/Policies/`   |
| 화면 상태와 command 연결            | `Presentation/ViewModels/` |
| SwiftUI 화면                        | `Presentation/Views/`      |
| release version/generated 값        | `Generated/`               |
| host 설정 한계값                    | `Configuration/`           |

주의할 점은 화면이 상태를 직접 만들면 안 된다는 것입니다. 화면은 ViewModel이 가진 명시 상태를 읽고, 사람이 이해할 수 있는 문구와 action으로 바꿉니다.

### 4-3. Mac Runtime Control Client

Mac에서 실제로 파일을 읽거나, command를 실행하거나, log를 모으거나, settings를 저장하는 기능을 고칠 때 보는 곳입니다. 화면이나 API보다 바깥 세계에 더 가까운 코드입니다.

```text
Adapters/Outbound/MacRuntimeControlClient/
  Backups/
  Client/
  Commands/
  Environment/
  Logs/
  Reads/
  Settings/
  TestKit/
```

이 영역은 실패를 가장 조심해야 합니다. 파일이 없으면 missing, 권한 문제가 있으면 failed, 정상적으로 읽었는데 결과가 없으면 empty로 전달해야 합니다.

| 수정하려는 것                  | 먼저 볼 곳     |
| ------------------------------ | -------------- |
| backup 목록/생성/삭제          | `Backups/`     |
| runtime command 실행           | `Commands/`    |
| host 환경과 URL 계산           | `Environment/` |
| log 읽기/export                | `Logs/`        |
| status, diagnostics, file read | `Reads/`       |
| settings 읽기/쓰기             | `Settings/`    |
| testkit control                | `TestKit/`     |

## 5. 문서 노출 기준

Release 문서는 운영자가 바로 판단해야 하는 내용을 다룹니다. Dev 문서는 그 판단 뒤의 구조와 계약을 설명합니다.

| 항목                 | 노출 위치 | 설명                                        |
| -------------------- | --------- | ------------------------------------------- |
| Vital Server Helper  | release   | release 문서의 최상위 서비스명              |
| Health Check         | release   | Vital Server Helper가 제공하는 기능         |
| Runtime Control API  | dev 중심  | UI와 host runtime 사이의 API                |
| Linux VM guest stack | dev 중심  | 같은 service 묶음을 실행하는 guest 환경     |
| wrapper/preload      | dev 중심  | Vital Server를 guest에서 실행하기 위한 입력 |
| devtools             | dev 중심  | packaging/build machine tooling             |

### 5-1. Release 문서에 쓰는 것

Release 문서는 “사용자가 지금 무엇을 해야 하는가”를 설명합니다.

| 예시                                | 이유                               |
| ----------------------------------- | ---------------------------------- |
| 설치, 실행, update, clean uninstall | 운영자가 직접 수행하는 절차        |
| Health Check 상태 의미              | 운영자가 화면에서 바로 판단해야 함 |
| 지원 범위와 제한                    | 도입 전 판단에 필요                |
| runtime status reference            | 화면에서 보이는 상태를 해석해야 함 |

### 5-2. Dev 문서에 쓰는 것

Dev 문서는 “왜 그렇게 만들었고, 어디를 고쳐야 하는가”를 설명합니다.

| 예시                  | 이유                           |
| --------------------- | ------------------------------ |
| Host/Guest/PWA 구조   | 구현 판단과 platform 확장 기준 |
| Runtime Contract      | 상태 단어와 API 의미를 고정    |
| Repository Map        | 코드 위치와 책임 경계 안내     |
| Delivery & Validation | 변경별 검증 기준               |

### 5-3. docs와 site-docs 구분

`site-docs/`는 읽기 쉬운 공개 site 문서입니다. `docs/`는 상세 설계, API, ADR, troubleshooting처럼 더 깊은 reference를 담습니다.

같은 내용을 두 곳에 반복하지 않습니다. release/dev site 문서에서는 판단과 흐름을 설명하고, 세부 파일명, API spec, ADR, 긴 장애 기록은 `docs/`로 연결합니다.

## 6. 변경할 때 지킬 것

변경 전에 먼저 “이 변경은 상태를 말하는가, 판단하는가, 실행하는가, 표시하는가”를 나눕니다.

### 6-1. 공통 기준

| 기준        | 확인할 것                                                       |
| ----------- | --------------------------------------------------------------- |
| 상태 소유자 | 이 상태를 누가 명시적으로 제공하는가                            |
| 실패 의미   | missing, failed, invalid, stale, empty가 섞이지 않는가          |
| 위치        | UI, contract, domain, workflow, 외부 연결 코드 중 어디 책임인가 |
| 테스트      | 정상 흐름뿐 아니라 실패/부재/오래됨을 확인했는가                |
| 문서        | 운영 rule이나 contract 의미가 바뀌면 문서도 바뀌었는가          |

### 6-2. 변경 유형별 기준

| 변경                        | 지킬 것                                                      |
| --------------------------- | ------------------------------------------------------------ |
| UI 표시 변경                | UI는 상태를 만들지 않고, 받은 상태를 표시                    |
| API 변경                    | OpenAPI, schema, PWA/Swift client, contract test를 함께 확인 |
| status/read 변경            | read failure를 empty success로 바꾸지 않음                   |
| update/recovery/repair 변경 | Workflow에 순서와 진행 상태를 두고 실패 event를 남김         |
| packaging 변경              | release artifact, install/update/uninstall 문서를 함께 확인  |
| testkit 변경                | 검증 기능이 product-facing QA 기능이라는 점을 유지           |

### 6-3. 피해야 할 것

- UI에서 domain state를 만들어내기
- Host가 Guest 내부 상태를 로그나 파일명으로 추측하기
- permission failure나 decode failure를 빈 결과로 바꾸기
- 모든 책임을 하나의 router, view model, lifecycle 파일에 몰아넣기
- unreleased behavior를 compatibility라는 이름으로 오래 끌고 가기
