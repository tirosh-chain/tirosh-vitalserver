# Health Check Service

Vital Server Helper의 Health Check 서비스는 병원 현장에서 VitalServer 운영 상태,
VR/VRecorder 동작 유무, 저장 데이터 상태를 확인하기 위한 기능입니다.

Health Check는 상태를 추측하지 않습니다. 상태 소유자가 제공한 명시적인 상태와
검사 결과만 표시합니다.

## 확인 대상

| 대상 | 확인 내용 |
|---|---|
| VitalServer service | 서비스가 실행 중인지, 병원 내부망에서 접근 가능한지 확인 |
| VR/VRecorder | 연결, 최근 데이터 전송, stale 여부 확인 |
| 저장 데이터 | `.vital` 파일 존재, 파일명 형식, 크기, 읽기 가능성, sanity check 결과 확인 |
| 운영 상태 | proxy, observer, runtime status, log 상태 확인 |

## 결과 상태

Health Check 결과는 서로 다른 의미를 섞지 않습니다.

| 상태 | 의미 |
|---|---|
| `ok` | 검사 대상이 명시적으로 정상으로 확인됨 |
| `missing` | 필요한 상태나 파일이 없음 |
| `invalid` | 값이나 파일 형식이 계약과 맞지 않음 |
| `failed` | 검사 또는 dependency 호출이 실패함 |
| `stale` | 상태는 있으나 최신 상태로 보기 어려움 |
| `empty` | 정상적으로 읽은 결과가 비어 있음 |

`missing`, `invalid`, `failed`, `stale`, `empty`는 서로 다른 의미입니다. 예를 들어
파일 읽기 실패는 빈 파일 목록으로 표시하지 않습니다.

## `.vital` 저장 데이터 sanity check

저장 데이터 검사는 `.vital` 파일을 기준으로 합니다. 요구 원문에 있는 `*.vatal`
표기는 이 문서군에서 사용하지 않습니다.

초기 sanity check 범위는 아래와 같습니다.

| 검사 | 설명 |
|---|---|
| 파일 발견 | 지정된 저장 위치에서 `.vital` 파일을 찾음 |
| 파일명 형식 | VitalDB upload 규칙에 맞는 파일명인지 확인 |
| 크기 | 0 byte 또는 비정상적으로 작은 파일을 구분 |
| 읽기 가능성 | 권한 문제와 decode 문제를 구분 |
| 저장 흐름 | 파일이 예상 directory 구조에 저장되는지 확인 |

## 확장 가능성

Health Check는 향후 아래 방향으로 확장할 수 있습니다.

- 병원별 VRecorder 목록과 expected recorder 상태 비교
- 저장 데이터의 시간 범위, 누락 구간, 업로드 지연 확인
- cloud 연계 모드에서 전송 성공/실패 상태 확인
- 장기 trend 기반 anomaly 확인

확장 시에도 상태 의미는 유지합니다. dependency failure를 빈 결과나 정상 상태로
변환하지 않습니다.
