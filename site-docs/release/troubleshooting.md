# Troubleshooting

이 문서는 Vital Server Helper 현장 장애를 기록하고 분류하는 원칙을 설명합니다.

장애 대응 문서는 항상 증상, 원인, 확인 방법, 조치 방향, 예방 원칙을 함께 적습니다.

## Principles

- 상태를 추측하지 않습니다.
- missing, invalid, failed, stale, empty를 구분합니다.
- 권한 실패와 빈 결과를 섞지 않습니다.
- decode 실패와 파일 없음은 다른 상태로 기록합니다.
- cloud 모드 장애는 병원 내 기본 모드 장애와 분리합니다.

## Common Symptoms

| 증상 | 먼저 확인할 것 |
|---|---|
| Vital Server URL 접근 불가 | Status, proxy 상태, network 설정 |
| VRecorder 미연결 | VRecorder IP, 병원 내부망 연결, 최근 데이터 전송 시각 |
| `.vital` 파일 없음 | 저장 directory, 권한, 실제 업로드 여부 |
| `.vital` sanity check 실패 | 파일명, 파일 크기, decode/read 실패 여부 |
| Health Check stale | 마지막 관측 시각, runtime 상태, observer 상태 |
| update 실패 | bundle 검증 결과, 적용 로그, rollback 여부 |

## Record Format

```text
Symptom:
Cause:
How to check:
Fix direction:
Prevention:
```

현장 장애가 반복되면 dev troubleshooting 문서에 원인과 예방 원칙을 추가합니다.

## When To Convert To A GitHub Issue

아래 조건을 만족하면 GitHub issue로 전환할 수 있습니다.

- 재현 절차가 있음
- 기대 상태와 실제 상태가 구분됨
- Health Check, Status, Logs 중 어떤 명시 상태가 문제인지 확인됨
- 환자 정보, 병원 내부 IP, 비밀번호, 토큰, 개인식별정보를 제거함

GitHub issue에는 현장 추측보다 명시 상태와 재현 절차를 적습니다.
