# Health Check Contract

Health Check contract는 Vital Server Helper가 확인한 상태의 의미를 고정합니다.

상태는 추측하지 않습니다. 상태 소유자가 제공한 명시적인 state, event, document,
command result만 사용합니다.

## 상태 의미

| 상태 | 의미 |
|---|---|
| `ok` | 검사 대상이 명시적으로 정상으로 확인됨 |
| `missing` | 필요한 상태, 파일, contract field가 없음 |
| `invalid` | 값, 파일명, document shape이 계약과 맞지 않음 |
| `failed` | read, decode, permission, dependency 호출이 실패함 |
| `stale` | 상태는 있으나 최신 상태로 보기 어려움 |
| `empty` | 정상적으로 읽은 결과가 비어 있음 |

`missing`, `invalid`, `failed`, `stale`, `empty`는 서로 변환하지 않습니다.

## VR/VRecorder 상태

| 상태 | 의미 |
|---|---|
| observed | recorder identity와 최근 activity가 명시적으로 관측됨 |
| missing | expected recorder가 관측되지 않음 |
| stale | 최근 activity가 threshold를 넘김 |
| read-failed | observer/runtime state를 읽지 못함 |
| invalid | recorder document shape이 계약과 맞지 않음 |

Host는 Guest 내부 상태를 추측하지 않습니다. Guest 또는 runtime read model이 제공한
관측 결과만 표시합니다.

## `.vital` file 상태

| 상태 | 의미 |
|---|---|
| found | `.vital` 파일을 명시적으로 발견 |
| empty | 파일 탐색이 성공했고 결과가 비어 있음 |
| invalid-filename | 파일명이 upload policy와 맞지 않음 |
| zero-size | 파일이 0 byte |
| read-failed | 파일 또는 directory 읽기 실패 |
| permission-failed | 권한 문제로 접근 실패 |
| decode-failed | 파일 내용을 해석하지 못함 |

파일 탐색 실패는 empty가 아닙니다. 권한 실패는 파일 없음이 아닙니다. decode 실패는
invalid filename과 다릅니다.

## Contract owner

| 영역 | Owner |
|---|---|
| VRecorder observed state | VitalDB Observer / runtime read model |
| `.vital` discovery | explicit file reader / testkit policy |
| runtime service health | Host runtime / watchdog |
| guest service state | guest tools |
| UI display | PWA / Helper presentation |

UI는 상태를 생성하지 않습니다. UI는 명시 상태를 포맷하고 표시합니다.
