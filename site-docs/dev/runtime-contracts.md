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

| 상태 | 뜻 |
|---|---|
| `ok` | 확인 대상이 명시적으로 정상으로 확인됨 |
| `missing` | 필요한 상태, 파일, field가 없음 |
| `invalid` | 값이나 문서 모양이 약속과 맞지 않음 |
| `failed` | 읽기, 해석, 권한, 의존 service 호출이 실패함 |
| `stale` | 상태는 있지만 최신 상태로 보기 어려움 |
| `empty` | 정상적으로 읽었고 결과가 비어 있음 |

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

## 3. Recorder와 Bed 상태

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

## 4. `.vital` 파일 상태

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

## 5. 누가 상태를 말하나

상태는 소유자가 말해야 합니다. 다른 layer는 그 상태를 읽고 전달하거나 표시합니다.

| 영역 | 상태를 말하는 쪽 |
|---|---|
| Recorder/Bed 관측 | Recorder Observer / runtime 조회용 상태 |
| `.vital` file discovery | 지원 예정 file reader / testkit policy |
| runtime service health | Host runtime / watchdog |
| guest service state | guest tools |
| 화면 표시 | PWA / Helper app presentation |

화면 표시 layer는 상태를 생성하지 않습니다. 화면은 명시 상태를 포맷하고 표시합니다.

## 6. API가 맡는 일

API는 상태를 추측하는 곳이 아니라, 상태를 전달하는 통로입니다. 각 API는 자신이 맡은 범위의
request, response, failure state를 분명히 해야 합니다.

### 6-1. Runtime Control API

Runtime Control API는 UI와 Host runtime 사이의 기본 약속입니다.

PWA와 Helper app은 observer container나 Guest 내부를 직접 읽지 않습니다. Runtime Control API가
제공하는 runtime status, runtime events, recorder/bed activity를 읽고 표시합니다.

| 위치 | 역할 |
|---|---|
| `docs/runtime/macos/runtime-control.openapi.json` | PWA/Helper app과 Host runtime 사이의 API |

### 6-2. Recorder Observer API

Recorder Observer API는 Redis와 proxy/access log를 읽어 recorder observation snapshot을 만듭니다.
이 API는 내부 collector API입니다. 최종 product-facing 상태는 runtime 조회용 상태와
Runtime Control API를 통해 전달합니다.

| 위치 | 역할 |
|---|---|
| `docs/api/vitaldb-observer.openapi.yaml` | observer container 내부 API |

### 6-3. Audit Proxy API

Audit Proxy API는 VRecorder command 흐름과 audit event를 관측하기 위한 sidecar API입니다.

| 위치 | 역할 |
|---|---|
| `docs/api/audit-proxy.openapi.yaml` | command audit sidecar endpoint |

### 6-4. Vital Server API

Vital Server API 문서는 Vital Server integration surface를 기록하기 위한 reference입니다.

| 위치 | 역할 |
|---|---|
| `docs/api/vitalserver.openapi.yaml` | Vital Server integration surface reference |

## 7. 작성 규칙

- API 문서에는 request, response, failure state를 구분해서 적습니다.
- read failure를 empty success로 표현하지 않습니다.
- stale state와 missing state를 구분합니다.
- UI fallback은 display label 수준으로 제한합니다.
- 상태 단어를 바꿀 때는 관련 test와 release/dev 문서를 함께 확인합니다.
