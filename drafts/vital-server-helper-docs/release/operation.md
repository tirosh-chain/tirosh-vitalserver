# Operation

이 문서는 Vital Server Helper를 설치한 뒤 일상적으로 확인하는 운영 흐름을 설명합니다.

## 기본 확인 순서

1. Helper app을 엽니다.
2. Status에서 전체 health를 확인합니다.
3. Health Check 결과를 확인합니다.
4. VR/VRecorder 연결 상태를 확인합니다.
5. `.vital` 저장 데이터 상태를 확인합니다.
6. 문제가 있으면 Logs에서 관련 로그를 확인합니다.

## 주요 확인 지점

| 확인 지점 | 용도 |
|---|---|
| Status | VitalServer URL, 저장 위치, 전체 health, 주요 service 상태 확인 |
| Logs | Helper, runtime, service, VM/container log 확인 |
| Update | update bundle 검증과 적용 |
| Health result | VR/VRecorder 동작 유무와 `.vital` 저장 데이터 sanity check 결과 확인 |

## Health Check 결과 해석

Health Check가 실패하면 먼저 실패 의미를 구분합니다.

| 결과 | 운영자가 볼 의미 |
|---|---|
| `missing` | 필요한 파일, 상태, recorder 정보가 없음 |
| `invalid` | 값 또는 파일 형식이 맞지 않음 |
| `failed` | 검사, 읽기, dependency 호출이 실패함 |
| `stale` | 상태가 오래되어 현재 상태로 보기 어려움 |
| `empty` | 정상적으로 읽었지만 결과가 비어 있음 |

운영자는 실패 상태를 정상 빈 값으로 해석하지 않습니다. 같은 증상이 반복되면
troubleshooting 문서의 증상, 원인, 확인 방법 순서로 확인합니다.

## Update 운영

offline update bundle은 Update 화면에서 선택해 검증한 뒤 적용합니다.

update 적용 전에는 현재 상태와 저장 데이터 위치를 확인합니다. update 적용 후에는
Status와 Health Check를 다시 확인합니다.
