# Runtime Contracts

Runtime contract는 Helper와 UI가 상태를 같은 뜻으로 이해하기 위한 약속입니다.

이 문서는 API 형식 자체보다 “상태를 어떻게 말할 것인가”를 먼저 설명합니다. Helper는 상태를
추측하지 않습니다. 상태를 아는 쪽이 명시적으로 말하고, 다른 쪽은 그 상태를 읽고 표시합니다.

## 1. 왜 필요한가

운영 화면에서 가장 위험한 것은 모르는 상태를 정상처럼 보이게 만드는 것입니다. 파일을 읽지
못한 상황, 값이 없는 상황, 오래된 상황, 실제로 비어 있는 상황은 모두 다르게 다뤄야 합니다.

### 1-1. 같은 단어를 같은 뜻으로 쓰기

Runtime Control API, Helper app, PWA, test, 문서는 같은 상태 단어를 같은 뜻으로 써야 합니다.
예를 들어 `missing`은 필요한 정보가 없다는 뜻이고, `failed`는 읽거나 확인하는 과정이 실패했다는
뜻입니다. 둘은 서로 바꿀 수 없습니다.

### 1-2. UI가 상태를 만들지 않기

UI는 상태를 보여주는 곳입니다. UI가 “값이 없으니 정상일 것이다” 또는 “읽지 못했지만 비어
있을 것이다”라고 판단하지 않습니다. UI는 API가 준 상태를 사람에게 읽기 좋게 표시합니다.

## 2. 상태 단어

아래 단어는 Helper 전반에서 같은 뜻으로 사용합니다.

| 상태 | 뜻 | 예시 |
|---|---|---|
| `ok` | 확인 대상이 명시적으로 정상으로 확인됨 | runtime status를 읽었고 service가 healthy로 보고됨 |
| `missing` | 필요한 상태, 파일, field가 없음 | `runtime-status.json` 파일이 아직 생성되지 않음 |
| `invalid` | 값이나 문서 모양이 약속과 맞지 않음 | JSON은 있지만 필수 field 타입이 맞지 않음 |
| `failed` | 읽기, 해석, 권한, 의존 service 호출이 실패함 | 파일 권한 문제로 status를 읽지 못함 |
| `stale` | 상태는 있지만 최신 상태로 보기 어려움 | 마지막 recorder activity가 기준 시간을 넘김 |
| `empty` | 정상적으로 읽었고 결과가 비어 있음 | recorder 목록을 정상적으로 읽었지만 항목이 없음 |

### 2-1. 섞으면 안 되는 상태

| 구분 | 이유 |
|---|---|
| `missing`과 `empty` | 없음과 “읽었는데 비어 있음”은 다름 |
| `failed`와 `empty` | 읽기 실패를 빈 결과로 처리하면 장애가 숨겨짐 |
| `stale`과 `ok` | 오래된 정상은 현재 정상과 다름 |
| `invalid`와 `missing` | 값이 잘못된 것과 값이 없는 것은 조치가 다름 |

### 2-2. 문서에 남겨야 하는 것

상태를 만들거나 읽는 코드는 실패 이유를 가능한 한 보존해야 합니다. 권한 문제, decode 실패,
의존 service 실패, 파일 없음은 서로 다른 조치가 필요합니다.

| 상황 | 남겨야 하는 정보 |
|---|---|
| 파일 없음 | 어떤 파일이나 상태가 없었는지 |
| 권한 실패 | 어떤 경로에서 어떤 권한 문제가 있었는지 |
| decode 실패 | 어떤 문서가 어떤 이유로 해석되지 않았는지 |
| 의존 service 실패 | 어떤 service나 endpoint 호출이 실패했는지 |
| 오래된 상태 | 마지막으로 관측된 시간이 언제인지 |

### 2-3. 운영자가 보게 되는 차이

상태 단어가 다르면 안내도 달라져야 합니다.

| 상태 | 화면에서의 방향 |
|---|---|
| `missing` | 아직 생성되지 않았거나 설치/초기화가 끝나지 않았을 수 있음을 알림 |
| `failed` | 로그 export나 권한/연결 문제 확인을 안내 |
| `stale` | 마지막 관측 시간과 recorder/network 확인을 안내 |
| `empty` | 정상적으로 읽었지만 현재 항목이 없음을 안내 |
| `invalid` | Helper와 runtime contract version 또는 문서 손상을 확인하도록 안내 |

## 3. Host와 Guest operation 계약

Host는 runtime/process/filesystem state를 소유하고, Guest는 Host가 제공한 explicit contract만
소비합니다. Guest 내부 상태를 Host가 로그나 파일 부재로 추정하지 않습니다.

### 3-1. Host time

Guest clock은 Host-owned `host-time.json` contract에서 동기화합니다. Guest는 boot 초기에
`tirosh-vitalserver-sync-host-time.service`로 이 값을 적용한 뒤 Docker, runtime-state,
observability, compose service를 시작합니다.

| 상태 | 의미 |
|---|---|
| host time contract missing | Host가 Guest boot input을 제공하지 못함 |
| host time contract invalid | Guest가 contract를 해석할 수 없음 |
| host time sync failed | Guest가 명시 시각 적용에 실패함 |

UI나 observer는 timestamp를 현재 시간으로 보정하지 않습니다. 시간이 틀리면 Host/Guest time contract
문제로 보고 failure reason과 logs를 확인합니다.

### 3-2. Guest shutdown result

Update나 VM restart가 Guest shutdown preparation을 요구하면 Host는 request를 쓰고 Guest의 typed result를
기다립니다. request가 남아 있거나 log가 없다는 사실만으로 pending/success를 추정하지 않습니다.

| 상태 | 의미 |
|---|---|
| request missing | Host가 아직 operation을 요청하지 않았거나 cleanup이 끝남 |
| result missing | Guest worker가 실행되지 않았거나 result를 쓰기 전에 실패함 |
| result failed | Guest가 실패 reason과 details를 명시적으로 보고함 |
| result stale | requestId 또는 updatedAt이 현재 operation과 맞지 않음 |
| result ready | Guest가 shutdown preparation과 poweroff request를 완료함 |

`prepare-update-shutdown-result.json`의 failure details에는 실패 service, 남은 service 목록,
service state snapshot, snapshot path가 포함될 수 있습니다. Host와 UI는 이 details를 표시하거나
전달하고, 로그를 해석해서 다른 상태로 바꾸지 않습니다.

## 4. Recorder와 Bed 상태

Recorder와 Bed 상태는 관측 결과를 기반으로 표시합니다. Host나 UI가 임의로 만들지 않습니다.

| 상태 | 뜻 |
|---|---|
| observed | recorder identity와 최근 activity가 명시적으로 관측됨 |
| missing | 기대한 recorder가 관측되지 않음 |
| stale | 최근 activity가 기준 시간을 넘김 |
| read-failed | observer나 runtime 상태를 읽지 못함 |
| invalid | recorder 문서 모양이 약속과 맞지 않음 |

Recorder/bed activity는 runtime status와 같은 줄에서 만들어지는 상태가 아닙니다. Observer와
조회용 상태가 제공한 관측 결과를 Runtime Control API가 읽고 화면에 전달합니다.

### 4-1. 예시

| 상황 | 표시해야 하는 상태 |
|---|---|
| Recorder activity가 최근 기준 안에 들어옴 | observed |
| 기대한 recorder가 최신 관측에 없음 | missing |
| 마지막 activity가 기준 시간을 넘김 | stale |
| observer 저장소를 읽지 못함 | read-failed |
| recorder 문서에 필요한 값이 없거나 타입이 맞지 않음 | invalid |

Recorder가 보이지 않는다고 해서 곧바로 missing으로 만들지 않습니다. 관측 자료를 정상적으로
읽었는지 먼저 구분해야 합니다. 관측 자료 자체를 읽지 못했다면 missing이 아니라 read-failed입니다.

## 5. `.vital` 파일 상태

`.vital` file sanity check는 지원 예정 기능입니다. 아래 상태는 향후 file check를 추가할 때
현재 runtime model과 같은 실패 의미를 유지하기 위한 기준입니다.

| 상태 | 뜻 |
|---|---|
| found | `.vital` 파일을 명시적으로 발견 |
| empty | 파일 탐색이 성공했고 결과가 비어 있음 |
| invalid-filename | 파일명이 upload 규칙과 맞지 않음 |
| zero-size | 파일이 0 byte |
| read-failed | 파일 또는 directory 읽기 실패 |
| permission-failed | 권한 문제로 접근 실패 |
| decode-failed | 파일 내용을 해석하지 못함 |

파일 탐색 실패는 empty가 아닙니다. 권한 실패는 파일 없음이 아닙니다. decode 실패는
invalid filename과 다릅니다.

## 6. 누가 상태를 말하나

상태는 소유자가 말해야 합니다. 다른 layer는 그 상태를 읽고 전달하거나 표시합니다.

| 영역 | 상태를 말하는 쪽 |
|---|---|
| Recorder/Bed 관측 | Recorder Observer / runtime 조회용 상태 |
| `.vital` file discovery | 지원 예정 file reader / testkit policy |
| runtime service health | Host runtime / watchdog |
| guest service state | guest tools |
| 화면 표시 | PWA / Helper app presentation |

화면 표시 layer는 상태를 생성하지 않습니다. 화면은 명시 상태를 포맷하고 표시합니다.

### 6-1. 상태 소유권 예시

| 질문 | 답해야 하는 쪽 |
|---|---|
| VM이 실행 중인가? | Host runtime |
| guest service가 healthy인가? | guest tools가 만든 상태와 Host runtime |
| recorder가 최근 데이터를 보냈는가? | Recorder Observer / 조회용 상태 |
| update가 실패했는가? | update workflow와 runtime event |
| 화면에 어떤 색으로 보일 것인가? | PWA / Helper app presentation |

화면은 마지막 질문만 답합니다. 앞의 상태 질문을 화면이 직접 판단하기 시작하면 같은 runtime을
PWA와 Helper app에서 다르게 해석할 위험이 생깁니다.

## 7. API가 맡는 일

API는 상태를 추측하는 곳이 아니라, 상태를 전달하는 통로입니다. 각 API는 자신이 맡은 범위의
request, response, failure state를 분명히 해야 합니다.

### 7-1. Swagger UI로 확인하기

API 문서는 OpenAPI 파일로 관리하고, 개발 중에는 Swagger UI로 확인할 수 있습니다.

```sh
make swagger/up
```

이후 `http://localhost:8082`에서 Swagger UI를 열면 Vital Server, Runtime Control API,
Audit Proxy API spec을 선택해서 볼 수 있습니다.

설치된 runtime에서는 Helper app의 Swagger UI 항목 또는 `http://127.0.0.1:<proxy-port>/swagger/`
경로로 guest에서 제공하는 Swagger UI를 확인합니다.

### 7-2. Runtime Control API

Runtime Control API는 UI와 Host runtime 사이의 기본 약속입니다.

PWA와 Helper app은 observer container나 Guest 내부를 직접 읽지 않습니다. Runtime Control API가
제공하는 runtime status, runtime events, recorder/bed activity를 읽고 표시합니다.

| 문서 파일 | 역할 |
|---|---|
| `docs/runtime/macos/runtime-control.openapi.json` | PWA/Helper app과 Host runtime 사이의 API |

### 7-3. Recorder Observer API

Recorder Observer API는 Redis와 proxy/access log를 읽어 recorder observation snapshot을 만듭니다.
이 API는 내부 collector API입니다. 최종 product-facing 상태는 runtime 조회용 상태와
Runtime Control API를 통해 전달합니다.

| 문서 파일 | 역할 |
|---|---|
| `docs/api/vitaldb-observer.openapi.yaml` | observer container 내부 API |

외부 PC 또는 Kubernetes로 numeric/trend 및 waveform 데이터를 relay할 때도 VitalServer raw Redis port는
외부에 직접 노출하지 않습니다. 실시간/대용량 relay는 observer API가 아니라 별도 Redis relay container가
source Redis 3.2를 내부 network에서 읽고, Helper Advanced 설정의 target Redis 8.x endpoint로 publish합니다.
Observer API는 recorder observation snapshot만 제공하며 Redis data export API를 제공하지 않습니다.

Helper Advanced Redis relay 설정은 UI checkbox/preset 값을 runtime file contract로 변환합니다.
Regex allowlist는 UI가 만들지 않고 relay code의 policy가 소유합니다. Helper가 생성하는 파일은 다음과
같습니다.

| Host/guest shared path | Container path | 내용 |
|---|---|---|
| `/mnt/tirosh/deploy/redis-relay-config/redis-relay.toml` | `/run/tirosh/config/redis-relay.toml` | relay enable, target endpoint, preset |
| `/mnt/tirosh/deploy/redis-relay-secrets/redis-relay-target-password` | `/run/tirosh/secrets/redis-relay-target-password` | target Redis password |

Password 원문은 Runtime Control settings/read model과 TOML에 저장하지 않습니다. Helper read model은
저장 여부만 `passwordConfigured`로 노출합니다.

### 7-4. Audit Proxy API

Audit Proxy API는 VRecorder command 흐름과 audit event를 관측하기 위한 sidecar API입니다.

| 문서 파일 | 역할 |
|---|---|
| `docs/api/audit-proxy.openapi.yaml` | command audit sidecar endpoint |

### 7-5. Vital Server API

Vital Server API 문서는 Vital Server integration surface를 기록하기 위한 reference입니다.

| 문서 파일 | 역할 |
|---|---|
| `docs/api/vitalserver.openapi.yaml` | Vital Server integration surface reference |

## 8. 작성 규칙

- API 문서에는 request, response, failure state를 구분해서 적습니다.
- read failure를 empty success로 표현하지 않습니다.
- stale state와 missing state를 구분합니다.
- UI fallback은 display label 수준으로 제한합니다.
- 상태 단어를 바꿀 때는 관련 test와 release/dev 문서를 함께 확인합니다.
